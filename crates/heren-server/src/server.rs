//! HerenServer â€” FlojoMCP server con las tools MCP v4 (paridad con bridge Python).
//!
//! Fase 4 enfoque paridad: cada tool reenvÃ­a al EditorPlugin v4 via
//! EditorRegistry (el bridge Python es el benchmark de comportamiento).

use flojo_mcp::prelude::*;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use tracing::info;

use crate::editor::normalize_project_path;
use crate::pure::{args, normalize_scene_path, unwrap_result};
use crate::registry::EditorRegistry;
use crate::scene_tool::schemas::ScenePlan;

/// Contexto de escena por proyecto (fix problema sistemÃ¡tico 2026-08-04):
/// el "edited scene root" del editor cambia con la pestaÃ±a activa. Este mapa
/// recuerda el Ãºltimo scene_path por proyecto: la primera llamada con
/// scene_path fija el contexto, las siguientes se inyectan automÃ¡ticamente.
fn scene_ctx_store() -> &'static Mutex<HashMap<String, String>> {
    static CTX: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    CTX.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Registra el scene_path de referencia para un proyecto (sin inyectar).
fn remember_scene_context(proj: &str, scene_path: &str) {
    if !scene_path.is_empty() {
        scene_ctx_store()
            .lock()
            .unwrap()
            .insert(proj.to_string(), scene_path.to_string());
    }
}

/// AsÃ­ las ops de nodo operan SIEMPRE contra la escena objetivo, no contra
/// la pestaÃ±a que estÃ© activa en ese momento.
fn apply_scene_context(proj: &str, mut a: Value) -> Value {
    let mut g = scene_ctx_store().lock().unwrap();
    if let Some(obj) = a.as_object_mut() {
        if let Some(s) = obj.get("scene_path").and_then(|v| v.as_str()) {
            if !s.is_empty() {
                g.insert(proj.to_string(), s.to_string());
                return a;
            }
        }
        if let Some(s) = g.get(proj) {
            if !obj.contains_key("scene_path") {
                obj.insert("scene_path".into(), Value::String(s.clone()));
            }
        }
    }
    a
}

fn last_project_store() -> &'static std::sync::Mutex<Option<String>> {
    static LAST: std::sync::OnceLock<std::sync::Mutex<Option<String>>> = std::sync::OnceLock::new();
    LAST.get_or_init(|| std::sync::Mutex::new(None))
}
fn set_last_project(proj: &str) {
    *last_project_store().lock().unwrap() = Some(proj.to_string());
}
fn get_last_project() -> Option<String> {
    last_project_store().lock().unwrap().clone()
}

/// Server FlojoMCP: struct marcado con #[flojo_mcp].
#[flojo_mcp(name = "heren-server", version = "4.1.0")]
pub struct Heren;

/// Resuelve el project_path: el editor conectado ES la sesión (ADR-004).
/// Sin tool de session: el primer tool call con project_path paga el auto-launch
/// (ensure_editor_connected). Fallback: explicit → last_project → único conectado → error.
async fn resolve_project(project_path: Option<&str>) -> Result<String, ToolError> {
    // 1. Parámetro explícito
    if let Some(p) = project_path {
        if !p.trim().is_empty() {
            let norm = normalize_project_path(p);
            set_last_project(&norm);
            return Ok(norm);
        }
    }
    // 2. Último proyecto usado en este proceso (entre tool calls)
    if let Some(last) = get_last_project() {
        return Ok(last);
    }
    // 3. Un solo proyecto conectado → usarlo
    let projects = crate::registry::EditorRegistry::global().connected_projects().await;
    if projects.len() == 1 {
        let sole = projects[0].clone();
        set_last_project(&sole);
        return Ok(sole);
    }
    // 4. Múltiples o ninguno → error con diagnóstico
    let editors = crate::registry::EditorRegistry::global().connected_editors().await;
    let detail = if editors.is_empty() {
        "ningún editor conectado".to_string()
    } else {
        format!("proyectos conectados: {}", editors.iter().map(|(p, _, _)| p.clone()).collect::<Vec<_>>().join(", "))
    };
    Err(ToolError::invalid_params(format!(
        "project_path required — {detail}. Pasa project_path explícito o abre Godot con el plugin y vuelve a llamar."
    )))
}

/// Garantiza que hay un editor conectado para `project_path`.
/// Si no hay editor Y `HEREN_AUTO_LAUNCH != 0`, lanza uno y espera conexión (timeout
/// desde `constants::EDITOR_CONNECT_TIMEOUT_MS`). Si no hay editor Y auto_launch=0,
/// retorna error claro: el usuario abre Godot con el plugin o habilita auto_launch.
///
/// Es la versión "sin sesión" del antiguo `session/open`: no hay tool de sesión;
/// el primer tool call con project_path paga el coste de launch (3-10s), los
/// siguientes son ~20ms.
///
/// Auto-reload del plugin (§0.13 W4-c, fix 2026-09-10): en CADA tool call
/// sincronizamos `addons/heren/` source → proyecto (content-aware, barato si
/// nada cambió). Si el editor YA está conectado pero el plugin cambió en
/// disco, lo matamos para forzar recarga del código nuevo (Godot no tiene
/// hot-reload de plugins — issue #11612). Esto evita que el agente trabaje
/// con un plugin stale que no conoce las tools/acciones recién añadidas.
async fn ensure_editor_connected(
    project_path: &str,
    godot_path: Option<&str>,
    registry: &EditorRegistry,
) -> Result<(), ToolError> {
    // Discovery (fix 2026-09-18): escribir `.heren/server_port.json` EN EL PROYECTO
    // (no en CWD) para que el editor sepa reconectar al server correcto.
    // Solo se ejecuta cuando hay un project_path real (primer tool call con proyecto).
    let port = ws_port();
    crate::discovery::write_discovery(&std::path::PathBuf::from(project_path), port);

    // 1. SIEMPRE sync source → proyecto (content-aware, barato si no cambió).
    let (plugin_changed, _sync_msg) = crate::launcher::ensure_plugin_installed(project_path);

    // 2. Si editor conectado y plugin al día → fast path (~0ms).
    if registry.has_editor(project_path).await {
        if !plugin_changed {
            return Ok(());
        }
        // Plugin stale: matar editor para que el path de launch siguiente
        // arranque con el código nuevo. El registry también debe olvidarlo.
        info!(
            project_path,
            "plugin changed on disk; killing running editor to reload new code (Godot #11612)"
        );
        crate::launcher::close_editor(project_path);
        // Esperar kill real (taskkill es async en Windows).
        let kill_deadline = std::time::Instant::now()
            + std::time::Duration::from_millis(crate::constants::EDITOR_KILL_WAIT_MS * 2);
        while std::time::Instant::now() < kill_deadline {
            if !crate::launcher::is_editor_running(project_path) {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
        // El registry olvida al editor cuando el WS se cierra (ver
        // ws_plugin_server); aquí solo esperamos el timeout natural o el
        // próximo has_editor lo verá como false.
        // ⚠️ Nota: si la escena tiene cambios sin guardar (dirty), el agente
        // los PIERDE al matar el editor. Para uso personal es aceptable; para
        // producción habría que chequear dirty_set del registry y warnear.
    }

    // 3. Si llegamos aquí sin editor → lanzar.
    let auto_launch = std::env::var("HEREN_AUTO_LAUNCH")
        .map(|v| v != "0" && v.to_lowercase() != "false")
        .unwrap_or(true);
    if !auto_launch {
        return Err(ToolError::internal(format!(
            "no_editor_connected: {project_path} y HEREN_AUTO_LAUNCH=0. \
             Abre Godot con el plugin o habilita auto_launch."
        )));
    }
    let port = ws_port();
    let outcome = crate::launcher::launch_editor(project_path, port, godot_path, false);
    if !outcome.launched {
        return Err(ToolError::internal(format!(
            "launch_failed: {} (proyecto={})",
            outcome.msg, project_path
        )));
    }
    let deadline = std::time::Instant::now()
        + std::time::Duration::from_millis(crate::constants::EDITOR_CONNECT_TIMEOUT_MS);
    let mut wait_ms = 0u64;
    while std::time::Instant::now() < deadline {
        tokio::time::sleep(std::time::Duration::from_millis(
            crate::constants::EDITOR_CONNECT_POLL_MS,
        ))
        .await;
        wait_ms += crate::constants::EDITOR_CONNECT_POLL_MS;
        if registry.has_editor(project_path).await {
            return Ok(());
        }
    }
    Err(ToolError::internal(format!(
        "editor lanzado pero NO conecto al WS server en {wait_ms}ms. \
         Posibles causas: crash al arrancar, plugin con SCRIPT ERROR, puerto WS ocupado. \
         Usa health (diagnose=true) para el debugger unificado."
    )))
}

/// Reenvía tools/call al editor y devuelve el resultado desenvuelto.
/// Sin role routing (la tool session que lo gestionaba ya no existe):
/// el primer editor conectado para el proyecto recibe la tool.
async fn forward(
    registry: &EditorRegistry,
    project_path: &str,
    tool_name: &str,
    args: Value,
) -> Result<Value, ToolError> {
    ensure_editor_connected(project_path, None, registry).await?;
    let raw = registry.call_tool(tool_name, args, project_path).await
        .map_err(ToolError::internal)?;
    Ok(unwrap_result(&raw))
}

/// ReenvÃ­a una MUTACIÃ“N (tool que modifica el Ã¡rbol del editor) y marca la
/// escena como dirty. RediseÃ±o persistencia 2026-08-07: el server recuerda
/// quÃ© escenas tienen cambios sin guardar â†’ scene/save limpia el dirty.
async fn forward_mutating(
    registry: &EditorRegistry,
    project_path: &str,
    tool_name: &str,
    args: Value,
    scene_path: &str,
) -> Result<Value, ToolError> {
    ensure_editor_connected(project_path, None, registry).await?;
    let result = forward(registry, project_path, tool_name, args).await?;
    // Marcar dirty solo si la mutaciÃ³n tuvo Ã©xito (ok=true) y hay scene_path.
    if !scene_path.is_empty() {
        let ok = result
            .get("ok")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false);
        if ok {
            registry.mark_dirty(project_path, scene_path).await;
        }
    }
    Ok(result)
}

/// Lee el puerto WS (default 9099). SIEMPRE cacheado con OnceLock.
/// Discovery (fix 2026-09-03): el caller escribe `.heren/server_port.json`
/// para que el editor sepa reconectar al server correcto.
fn ws_port() -> u16 {
    static PORT: OnceLock<u16> = OnceLock::new();
    *PORT.get_or_init(|| {
        let base = std::env::var("HEREN_WS_ADDR")
            .ok()
            .and_then(|a| a.rsplit(':').next().map(std::string::ToString::to_string))
            .and_then(|p| p.parse().ok())
            .unwrap_or(crate::constants::WS_PORT_BASE);
        // HEREN_WS_ADDR explícito → respetar sin buscar (el usuario lo fijó).
        if std::env::var("HEREN_WS_ADDR").is_ok() {
            return base;
        }
        // Buscar puerto libre partiendo de 9099 (otra sesión puede tenerlo).
        for port in base..base + 20 {
            if std::net::TcpListener::bind(("127.0.0.1", port)).is_ok() {
                return port;
            }
        }
        base // todos ocupados: improbable; el bind fallará con error claro
    })
}

// ============================================================
// HEALTH — reemplaza la antigua tool session. Sin lifecycle (Fennara-style):
// el primer tool call con project_path paga el auto-launch; los siguientes ~20ms.
// HEREN_AUTO_LAUNCH=0 deshabilita el auto-launch (el usuario abre Godot manualmente).
// ============================================================

#[tool(
    description = "Health check del server y de los editores conectados. Con diagnose=true ejecuta el debugger unificado (integridad plugin + grafo headless en sandbox). Sin project_path: estado global (versiones, conexiones, env vars). Con project_path: detalle de ese proyecto (conexión, versiones, dirty, unexpected_close). La conexión de editores es AUTO-MANAGIDA: no hay tool session — el server lanza el editor si hace falta."
)]
#[allow(clippy::too_many_arguments)]
async fn health(
    project_path: Option<String>,
    godot_path: Option<String>,
    diagnose: Option<bool>,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let source = crate::launcher::source_plugin_version();
    let editors = registry.connected_editors().await;
    let connected_projects: Vec<String> = editors.iter().map(|(p, _, _)| p.clone()).collect();

    // Plugins stale (editor con version != source).
    let mut stale: Vec<Value> = Vec::new();
    for (proj, _, live_ver) in &editors {
        if let (Some(live), Some(src)) = (live_ver.as_ref(), source.as_ref()) {
            if live != src {
                stale.push(json!({
                    "project_path": proj,
                    "plugin_version_editor": live,
                    "plugin_version_source": src,
                    "remedy": "cierra y reabre Godot para recargar el plugin con el codigo nuevo",
                }));
            }
        }
    }

    // Config: env vars que afectan el comportamiento.
    let auto_launch = std::env::var("HEREN_AUTO_LAUNCH")
        .map(|v| v != "0" && v.to_lowercase() != "false")
        .unwrap_or(true);
    let default_project_env = std::env::var("HEREN_DEFAULT_PROJECT").ok();
    let last_project = get_last_project();

    let mut result = json!({
        "ok": true,
        "server": "heren-server (Rust)",
        "version": env!("CARGO_PKG_VERSION"),
        "connected_projects": connected_projects,
        "editor_count": editors.len(),
        "plugin_source_version": source,
        "stale_editors": stale,
        "auto_launch": auto_launch,
        "default_project_env": default_project_env,
        "last_project": last_project,
    });

    // Detalle por proyecto si se pidió.
    if let Some(p) = project_path.as_deref() {
        let proj = resolve_project(Some(p)).await?;
        if !registry.has_editor(&proj).await {
            ensure_editor_connected(&proj, godot_path.as_deref(), registry).await?;
        }
        let connected = registry.has_editor(&proj).await;
        let installed = crate::launcher::read_plugin_version(&proj);
        let live = registry.editor_plugin_version(&proj).await;
        let is_stale = matches!((&live, &source), (Some(l), Some(s)) if l != s);
        let dirty = registry.dirty_scenes(&proj).await;
        let unexpected = registry.unexpected_close(&proj).await;
        let stale_msg = if is_stale {
            "El editor corre una version ANTIGUA del plugin. Cierra y reabre Godot para recargar el codigo nuevo."
        } else {
            ""
        };
        result["project"] = json!({
            "project_path": proj,
            "connected": connected,
            "plugin_version_source": source,
            "plugin_version_installed": installed,
            "plugin_version_editor": live,
            "plugin_stale": is_stale,
            "plugin_stale_remedy": stale_msg,
            "dirty_scenes": dirty,
            "unexpected_close": unexpected.is_some(),
            "unexpected_close_dirty": unexpected.unwrap_or_default(),
        });
    }

    // Diagnose opcional: valida el plugin del proyecto en sandbox headless.
    if diagnose.unwrap_or(false) {
        let proj = match project_path.as_deref() {
            Some(p) => resolve_project(Some(p)).await?,
            None => match get_last_project() {
                Some(p) if std::path::Path::new(&p).join("project.godot").exists() => p,
                _ => String::new(),
            },
        };
        if proj.is_empty() {
            result["diagnose"] = json!({
                "skipped": "no project_path and no resolvable last_project"
            });
        } else {
            let diag = crate::launcher::validate_plugin_graph(&proj, godot_path.as_deref());
            result["diagnose"] = json!({
                "project_path": proj,
                "ok": diag.ok,
                "errors": diag.errors,
                "output_tail": diag.output_tail,
            });
        }
    }
    Ok(result)
}

// ============================================================
// SCENE
// ============================================================
// SCENE
// ============================================================

// allow: los parámetros los dicta el schema MCP de la tool unificada.
#[allow(clippy::too_many_arguments)]
#[tool(
    description = "Escenas: get_open_scenes|get_edited_scene_root|open|save|create|unload|plan|orchestrate|validate|commit|status|list. Flujo planning: el state (plan, qa, lock, mode) vive en el plugin-registry (single source of truth) — el server NO mantiene estado paralelo. plan_file (path JSON) escribe el ScenePlan; orchestrate ejecuta el batch vía coder pure-logic; validate hace QA dual-engine; commit guarda+unlock. open con mode={isolated,attached,modify} opcional adquiere lock."
)]
async fn scene(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    output_path: Option<String>,
    root_type: Option<String>,
    root_name: Option<String>,
    // Planning/Orchestration args. mode válido: isolated|attached|modify.
    mode: Option<String>,
    // Mantenido en signatura para compat. Solo usado por planning (open acquire_lock).
    #[allow(dead_code)]
    agent_id: Option<String>,
    save: Option<bool>,
    // create instanciado: path explícito o pestaña activa del editor
    instance_scene: Option<String>,
    instance_current: Option<bool>,
    // Plan como ARCHIVO JSON: el agente escribe el .json con sus tools de
    // archivo y pasa el path. Evita los límites de serialización/schema de
    // dicts anidados vía tool args. Acepta path absoluto o relativo al
    // proyecto (res:// incluido). Sin plan_file, action="plan" devuelve un
    // ejemplo canónico auto-documentado.
    plan_file: Option<String>,
    // Orchestrate preview sin ejecutar (devuelve los calls que ejecutaría).
    dry_run: Option<bool>,
    // engine filter para validate — "a"=solo estructura, "b"=solo visual, "all"=ambos
    engine: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();

    // Fase 1 (2026-09-03): SINGLE SOURCE OF TRUTH.
    // Bifurcación eliminada. Las actions de planning (plan|orchestrate|validate|
    // commit|status|list) se procesan server-side con state cargado del plugin.
    // El plugin es source-of-truth para: árbol, plan JSON, qa_report, lock.
    match action.as_str() {
        "plan" => return scene_plan_action(&proj, scene_path.as_deref(), plan_file.as_deref(), agent_id.as_deref()).await,
        "orchestrate" => return scene_orchestrate_action(&proj, scene_path.as_deref(), agent_id.as_deref(), dry_run.unwrap_or(false)).await,
        "validate" => return scene_validate_action(&proj, scene_path.as_deref(), agent_id.as_deref(), engine.as_deref()).await,
        "commit" => return scene_commit_action(&proj, scene_path.as_deref(), agent_id.as_deref(), save.unwrap_or(true)).await,
        "status" => return scene_status_action(&proj, scene_path.as_deref()).await,
        "list" => return scene_list_action(&proj).await,
        _ => {}
    }

    // Actions legacy: low-level (open, save, create, unload, get_*).
    let explicit_path = scene_path
        .clone()
        .map(|p| normalize_scene_path(&p))
        .unwrap_or_default();
    let scene_path = scene_path.as_deref().map(normalize_scene_path);
    let a = args(&[
        (
            "scene_path",
            scene_path.as_deref().map(|s| Value::String(s.to_string())),
        ),
        (
            "output_path",
            output_path
                .map(|p| normalize_scene_path(&p))
                .map(Value::String),
        ),
        ("root_type", root_type.map(Value::String)),
        ("root_name", root_name.map(Value::String)),
        // create instanciado: nueva escena conteniendo otra como instancia ExtResource.
        (
            "instance_scene",
            instance_scene
                .as_deref()
                .map(normalize_scene_path)
                .map(Value::String),
        ),
        ("instance_current", instance_current.map(Value::Bool)),
        // open del planning (Fase 1): mode/agent_id opcionales se forwardean al plugin
        // para que acquire_lock pueda usarlos. Si no vienen, plugin usa defaults.
        ("mode", mode.clone().map(Value::String)),
        ("agent_id", agent_id.clone().map(Value::String)),
    ]);
    // Contexto de escena: save/open sin scene_path usan el último conocido.
    let a = if action == "save" || action == "open" {
        apply_scene_context(&proj, a)
    } else {
        remember_scene_context(&proj, &explicit_path);
        a
    };
    // Regla 1: Antes de destruir un árbol dirty → guardar.
    if action == "open" {
        if let Some(p) = scene_path.as_deref() {
            let dirty = registry.dirty_scenes(&proj).await;
            if dirty.iter().any(|d| d == p) {
                let saved = forward(registry, &proj, "scene/save", json!({"scene_path": p})).await;
                if let Ok(v) = &saved {
                    if v.get("ok")
                        .and_then(serde_json::Value::as_bool)
                        .unwrap_or(false)
                    {
                        registry.clean_dirty(&proj, p).await;
                    }
                }
            }
        }
    }
    let result = forward(registry, &proj, &format!("scene/{action}"), a).await?;
    match action.as_str() {
        "save" => {
            if let Some(p) = scene_path.as_deref() {
                if result
                    .get("ok")
                    .and_then(serde_json::Value::as_bool)
                    .unwrap_or(false)
                {
                    registry.clean_dirty(&proj, p).await;
                }
            }
        }
        "create" => {
            remember_scene_context(&proj, &explicit_path);
        }
        _ => {}
    }
    Ok(result)
}

// ============================================================
// SCENE — sub-comandos Planning (Fase 1 §0.8: single source of truth)
// ============================================================
// Helpers INTERNOS invocados desde la tool `scene`. NO son tools MCP propias.
// State (plan, qa, lock) vive en HerenSceneRegistry (plugin). El server solo
// ejecuta la lógica pure (coder, validator) y coordina forward al plugin.

// scene/plan: lee plan_file, lo envía al plugin (state source-of-truth).
async fn scene_plan_action(
    proj: &str,
    scene_path: Option<&str>,
    plan_file: Option<&str>,
    _agent_id: Option<&str>,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    // Sin plan_file → devolver ejemplo canónico auto-documentado.
    let Some(file) = plan_file else {
        return Ok(serde_json::json!({
            "ok": true,
            "hint": "escribe este JSON (ajustándolo) a un archivo y llama scene(action=\"plan\", plan_file=\"<path>\")",
            "example": crate::scene_tool::schemas::example_plan(),
            "notes": {
                "steps_action": "add_node|set_transform|add_resource|connect_signal|instantiate_template|remove_node|duplicate_node",
                "generic_step": "Para animación/esqueleto/shaders/tilemaps: {id, tool, action, args} — el agente conoce las tools de tools/list",
                "verification_kind": "node_count|bbox_max|bbox_min|script_attached|resource_exists|signal_connected|node_exists|property_value",
                "tolerance": "OBLIGATORIO en cada verification target",
                "workplane": "XZ (3D mundo) | XY (UI/pantalla)",
                "local_pos": "coords de MUNDO directas + workplane_offset; sin swaps",
                "properties": "cualquier prop del inspector: colores {r,g,b,a}, vectores {x,y,z}, arrays, paths res:// (recursos por PATH, nunca inline)",
                "precedence": "properties explícitas SOBREESCRIBEN local_pos/local_rot/local_scale/resource_path derivados"
            }
        }));
    };
    let path = resolve_plan_file_path(proj, file);
    let text = std::fs::read_to_string(&path).map_err(|e| {
        ToolError::invalid_params(format!("no se pudo leer plan_file '{path}': {e}"))
    })?;
    let plan: ScenePlan = serde_json::from_str(&text).map_err(|e| {
        ToolError::invalid_params(format!(
            "plan_file '{path}' no es un ScenePlan válido: {e}"
        ))
    })?;
    let plan_scene_path = plan.scene_path.clone();
    let steps = plan.steps.len();
    let verifications = plan.verification.len();
    // Validar contra scene_path explícito si viene (protección: agente no
    // puede escribir plan de otra escena).
    if let Some(req_p) = scene_path {
        if req_p != plan_scene_path {
            return Err(ToolError::invalid_params(format!(
                "scene_path '{req_p}' no coincide con plan.scene_path '{plan_scene_path}'"
            )));
        }
    }
    // Forward al plugin: el plugin persiste el plan en su registry + disco.
    let response = forward(registry, proj, "scene/plan", json!({
        "scene_path": plan_scene_path,
        "plan": serde_json::to_value(&plan)?,
    })).await?;
    Ok(serde_json::json!({
        "ok": response.get("ok").and_then(Value::as_bool).unwrap_or(false),
        "warnings": response.get("warnings").cloned().unwrap_or(json!([])),
        "scene_path": plan_scene_path,
        "steps_count": steps,
        "verification_count": verifications,
        "next": "scene(action=\"orchestrate\") ejecuta el batch; luego validate y commit"
    }))
}

// scene/orchestrate: lee plan del plugin, ejecuta coder pure-logic, forwardea calls.
async fn scene_orchestrate_action(
    proj: &str,
    scene_path: Option<&str>,
    agent_id: Option<&str>,
    dry_run: bool,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    // 1. Resolver scene_path: usar el explícito, o el del primer lock activo.
    let resolved_scene_path = resolve_planning_scene_path(proj, scene_path).await?;
    // 2. Forward: leer plan del plugin.
    let plan_resp = forward(registry, proj, "scene/get_plan", json!({
        "scene_path": resolved_scene_path,
    })).await?;
    let plan_json: serde_json::Value = plan_resp.get("plan").cloned().unwrap_or(json!({}));
    if plan_json.is_null() || plan_json.as_object().is_none_or(serde_json::Map::is_empty) {
        return Err(ToolError::invalid_params(format!(
            "no hay plan escrito para '{resolved_scene_path}' — llama scene(action=\"plan\", plan_file=\"...\") primero"
        )));
    }
    let plan: ScenePlan = serde_json::from_value(plan_json).map_err(|e| {
        ToolError::internal(format!("plan del plugin corrupto: {e}"))
    })?;
    // 3. Cargar contexto (necesario para el coder).
    let context = load_scene_context_from_plugin(proj, &resolved_scene_path).await?;
    // 4. Coder pure-logic: traduce plan → calls.
    let calls = crate::scene_tool::coder::SceneCoder::plan_to_mcp_calls(&plan, &context);
    let executed_steps: Vec<String> = calls.iter().map(|c| c.description.clone()).collect();
    let coords: Vec<Value> = calls.iter().map(|c| serde_json::to_value(&c.args).unwrap_or(Value::Null)).collect();
    // 5. dry_run: devolver preview sin mutar.
    if dry_run {
        return Ok(json!({
            "ok": true,
            "dry_run": true,
            "executed_steps": executed_steps,
            "coords": coords,
            "warnings": ["dry_run: NINGÚN step fue ejecutado"],
        }));
    }
    // 6. Ejecutar calls vía forward al plugin (continue-on-error, P-B9).
    // Cada call exitosa se sigue de un get_info del node afectado para que
    // el agente reciba coords POST-APPLY en JSON estructurado.
    let mut warnings: Vec<String> = Vec::new();
    let mut applied = 0usize;
    let mut per_step_state: Vec<Value> = Vec::with_capacity(calls.len());
    let total = calls.len();
    let _ = agent_id; // (mantenido para signatura)
    for call in calls {
        // Extraer campos ANTES de forward (call.args se mueve).
        let node_path: Option<String> = call.args.get("node_path")
            .and_then(|v| v.as_str())
            .map(String::from);
        let parent_path: Option<String> = call.args.get("parent_path")
            .and_then(|v| v.as_str())
            .map(String::from);
        let node_name: Option<String> = call.args.get("node_name")
            .and_then(|v| v.as_str())
            .map(String::from);
        let action: Option<String> = call.args.get("action")
            .and_then(|v| v.as_str())
            .map(String::from);
        let post_position: Option<Value> = call.args.get("properties")
            .and_then(|p| p.get("position"))
            .cloned();

        let apply_result = forward(registry, proj, &call.tool, call.args).await;
        match apply_result {
            Ok(_) => applied += 1,
            Err(e) => {
                warnings.push(format!(
                    "step '{}' falló ({}): {} — los steps previos SÍ se aplicaron",
                    call.step_id, call.description, e
                ));
                per_step_state.push(json!({
                    "step_id": call.step_id,
                    "applied": false,
                    "error": e.to_string(),
                }));
                continue;
            }
        }
        // Para AddNode el nodo todavía no existe — coords post = posición asignada.
        if call.tool == "node" && action.as_deref() == Some("add") {
            per_step_state.push(json!({
                "step_id": call.step_id,
                "applied": true,
                "node_path": format!("{}/{}", parent_path.as_deref().unwrap_or("."), node_name.as_deref().unwrap_or("?")),
                "coords": {"position": post_position.unwrap_or(json!(null))},
            }));
            continue;
        }
        // Para el resto de calls que afectan geometría, leer coords reales.
        let lookup_path = node_path.clone()
            .or_else(|| parent_path.as_ref().zip(node_name.as_ref()).map(|(p, n)| {
                if p == "." { n.clone() } else { format!("{p}/{n}") }
            }));
        if let Some(path) = lookup_path {
            // get_info devuelve coords via node_query/get_info.
            let info = forward(registry, proj, "node_query/get_info", json!({
                "scene_path": resolved_scene_path,
                "node_path": path,
            })).await;
            let coords = info.ok()
                .and_then(|v| v.get("coords").cloned())
                .unwrap_or(json!(null));
            per_step_state.push(json!({
                "step_id": call.step_id,
                "applied": true,
                "node_path": path,
                "coords": coords,
            }));
        } else {
            per_step_state.push(json!({
                "step_id": call.step_id,
                "applied": true,
            }));
        }
    }
    if applied > 0 {
        registry.mark_dirty(proj, &resolved_scene_path).await;
    } else {
        warnings.push(format!(
            "P-B9: 0/{total} calls pasaron — escena NO marcada como dirty"
        ));
    }
    Ok(json!({
        "ok": true,
        "applied": applied,
        "total": total,
        "executed_steps": executed_steps,
        "coords": coords,
        "applied_state": per_step_state,
        "warnings": warnings,
    }))
}

// scene/validate: refresca contexto, ejecuta validator pure-logic, persiste QA report.
async fn scene_validate_action(
    proj: &str,
    scene_path: Option<&str>,
    _agent_id: Option<&str>,
    engine: Option<&str>,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let resolved_scene_path = resolve_planning_scene_path(proj, scene_path).await?;
    let engine_filter = engine.unwrap_or("all");
    // Cargar plan del plugin.
    let plan_resp = forward(registry, proj, "scene/get_plan", json!({
        "scene_path": resolved_scene_path,
    })).await?;
    let plan_json: serde_json::Value = plan_resp.get("plan").cloned().unwrap_or(json!({}));
    if plan_json.as_object().is_none_or(serde_json::Map::is_empty) {
        return Err(ToolError::invalid_params(format!(
            "no hay plan para '{resolved_scene_path}' — llama scene(action=\"plan\", ...) primero"
        )));
    }
    let plan: ScenePlan = serde_json::from_value(plan_json).map_err(|e| {
        ToolError::internal(format!("plan corrupto: {e}"))
    })?;
    // Refrescar contexto desde el editor vivo (P0b).
    let context = load_scene_context_from_plugin(proj, &resolved_scene_path).await?;
    // Validator pure-logic.
    let mut qa_report = crate::scene_tool::validator::SceneValidator::validate_scene(
        &plan, &context, &ValidatorClientAdapter { project_path: proj.to_string() }
    ).await;
    // Engine filter (P-M7).
    if engine_filter == "a" {
        qa_report.engine_b = crate::scene_tool::schemas::EngineReport {
            engine_name: "skipped (engine=a)".to_string(),
            results: vec![],
            summary: "Skipped by engine filter".to_string(),
            warnings: vec![],
            errors: vec![],
        };
    } else if engine_filter == "b" {
        qa_report.engine_a = crate::scene_tool::schemas::EngineReport {
            engine_name: "skipped (engine=b)".to_string(),
            results: vec![],
            summary: "Skipped by engine filter".to_string(),
            warnings: vec![],
            errors: vec![],
        };
    }
    // Fase 5: validar GenericSteps contra schema del plugin.
    let tool_schemas = fetch_tool_schemas().await;
    let generic_details = crate::scene_tool::validator::SceneValidator
        ::validate_generic_steps(&plan, &tool_schemas);
    if !generic_details.is_empty() {
        qa_report.engine_a.results.extend(generic_details.iter().cloned());
        let any_fail = generic_details.iter().any(|d| !d.passed);
        if any_fail {
            qa_report.error_type = crate::scene_tool::schemas::ErrorType::Topology;
            qa_report.passed = false;
        }
    }
    // Persistir QA report en plugin (single source of truth).
    let _ = forward(registry, proj, "scene/set_qa_report", json!({
        "scene_path": resolved_scene_path,
        "qa_report": serde_json::to_value(&qa_report)?,
    })).await;
    Ok(serde_json::to_value(&crate::scene_tool::schemas::SceneValidateResponse { qa_report })?)
}

// scene/commit: forward al plugin (que guarda + libera lock en su registry).
async fn scene_commit_action(
    proj: &str,
    scene_path: Option<&str>,
    _agent_id: Option<&str>,
    save: bool,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let resolved_scene_path = resolve_planning_scene_path(proj, scene_path).await?;
    // F2: descartar cambios sin aviso = pérdida silenciosa.
    if !save {
        let st_resp = forward(registry, proj, "scene/status", json!({
            "scene_path": resolved_scene_path,
        })).await?;
        let dirty = st_resp.get("status").and_then(|s| s.get("dirty")).and_then(Value::as_bool).unwrap_or(false);
        if dirty {
            return Err(ToolError::invalid_params(
                "la escena tiene cambios SIN guardar (dirty:true) — pasa save=true para persistirlos, o scene(action=\"open\") de nuevo para descartarlos conscientemente",
            ));
        }
    }
    let response = forward(registry, proj, "scene/commit", json!({
        "scene_path": resolved_scene_path,
        "save": save,
    })).await?;
    // Limpiar dirty en el registry server-side si save OK.
    if save && response.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        registry.clean_dirty(proj, &resolved_scene_path).await;
    }
    Ok(response)
}

// scene/status: forward al plugin (single source of truth).
async fn scene_status_action(
    proj: &str,
    scene_path: Option<&str>,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let Some(p) = scene_path else {
        // Sin scene_path → forward list (alias).
        return forward(registry, proj, "scene/list", json!({})).await;
    };
    forward(registry, proj, "scene/status", json!({
        "scene_path": p,
    })).await
}

// scene/list: forward al plugin.
async fn scene_list_action(
    proj: &str,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    forward(registry, proj, "scene/list", json!({})).await
}

// Resuelve la escena objetivo: explícita si viene, si no la única con lock activo.
// Pide al plugin vía scene/list y devuelve la primera; si no hay ninguna, error.
async fn resolve_planning_scene_path(
    proj: &str,
    scene_path: Option<&str>,
) -> Result<String, ToolError> {
    if let Some(p) = scene_path {
        return Ok(p.to_string());
    }
    let registry = EditorRegistry::global();
    let list_resp = forward(registry, proj, "scene/list", json!({})).await?;
    let scenes = list_resp.get("scenes").and_then(Value::as_array).cloned().unwrap_or_default();
    let first = scenes.first()
        .and_then(|s| s.get("scene_path").and_then(Value::as_str))
        .ok_or_else(|| {
            ToolError::invalid_params(
                "No active scene in plugin-registry — llama scene(action=\"open\", scene_path=...) antes de planificar"
            )
        })?;
    Ok(first.to_string())
}

// Carga el SceneContext desde el plugin (forward a scene/get_edited_scene_root + node/get_children).
async fn load_scene_context_from_plugin(
    proj: &str,
    scene_path: &str,
) -> Result<crate::scene_tool::schemas::SceneContext, ToolError> {
    let registry = EditorRegistry::global();
    // Forward scene/open primero (asegura pestaña activa).
    let _ = forward(registry, proj, "scene/open", json!({
        "scene_path": scene_path,
    })).await;
    let root = forward(registry, proj, "scene/get_edited_scene_root", json!({})).await?;
    let nodes_result = forward(registry, proj, "node/get_children", json!({
        "node_path": ".",
        "recursive": true,
        "scene_path": scene_path,
    })).await?;
    Ok(build_scene_context(scene_path, &root, &nodes_result))
}

/// Fase 5: obtiene los schemas de todas las tools del plugin vía FlojoTester.
/// Retorna HashMap<tool_name, schema_json>. Cacheada en estático.
async fn fetch_tool_schemas() -> std::collections::HashMap<String, Value> {
    use flojo_mcp::prelude::FlojoTester;
    let tester = FlojoTester::with_context(Heren::new(), Context::default());
    let tools = tester.list_tools().await.unwrap_or_default();
    let mut map = std::collections::HashMap::new();
    for tool in tools {
        let name = tool.name.to_string();
        let schema = serde_json::to_value(&tool.input_schema).unwrap_or(Value::Null);
        map.insert(name, schema);
    }
    map
}

/// Resuelve el path de un plan_file: absoluto tal cual; `res://...` o ruta
/// relativa se anclan al directorio del proyecto activo.
fn resolve_plan_file_path(proj: &str, file: &str) -> String {
    let normalized = file.replace('\\', "/");
    if std::path::Path::new(&normalized).is_absolute() {
        normalized
    } else {
        let relative = normalized
            .strip_prefix("res://")
            .unwrap_or(&normalized)
            .trim_start_matches('/');
        format!("{proj}/{relative}")
    }
}

/// Resuelve la escena objetivo: usa la versión async `resolve_planning_scene_path`
/// definida en el cuerpo de `scene`. Esta función sync queda como alias
/// deprecated (no se invoca desde ningún path nuevo).
#[allow(dead_code)]
fn _resolve_planning_scene_deprecated(_scene_path: Option<&str>, _action: &str) -> Result<String, ToolError> {
    Err(ToolError::invalid_params("deprecated — use resolve_planning_scene_path (async)"))
}

/// Adapter for validator client using forward()
struct ValidatorClientAdapter {
    project_path: String,
}

#[async_trait::async_trait]
impl crate::scene_tool::validator::SceneValidatorClient for ValidatorClientAdapter {
    async fn validate_scene(&self, scene_path: &str) -> Result<serde_json::Value, String> {
        let registry = EditorRegistry::global();
        forward(registry, &self.project_path, "validate/scene", serde_json::json!({
            "scene_path": scene_path,
        })).await.map_err(|e| e.to_string())
    }

    async fn visual_summary(&self, scene_path: &str) -> Result<serde_json::Value, String> {
        let registry = EditorRegistry::global();
        forward(registry, &self.project_path, "visual/scene_summary", serde_json::json!({
            "scene_path": scene_path,
        })).await.map_err(|e| e.to_string())
    }

    async fn list_signals(&self, scene_path: &str) -> Result<serde_json::Value, String> {
        let registry = EditorRegistry::global();
        forward(registry, &self.project_path, "signal/list", serde_json::json!({
            "scene_path": scene_path,
        })).await.map_err(|e| e.to_string())
    }

    // P-M3: lectura real de propiedad vía node_query/get_prop.
    async fn get_prop(&self, scene_path: &str, node_path: &str, property: &str) -> Result<serde_json::Value, String> {
        let registry = EditorRegistry::global();
        forward(registry, &self.project_path, "node_query/get_prop", serde_json::json!({
            "scene_path": scene_path,
            "node_path": node_path,
            "property_name": property,
        })).await.map_err(|e| e.to_string())
    }
}

/// Build SceneContext from Godot query results
fn build_scene_context(scene_path: &str, root: &serde_json::Value, nodes_result: &serde_json::Value) -> crate::scene_tool::schemas::SceneContext {
    let mut nodes = Vec::new();
    
    // Parse nodes from node_query/get_children result
    if let Some(children) = nodes_result.get("children").and_then(|v| v.as_array()) {
        for child in children {
            if let Some(node_info) = parse_node_info(child) {
                nodes.push(node_info);
            }
        }
    }
    
    // Calculate bbox from nodes
    let mut bbox = crate::scene_tool::schemas::AABB::default();
    for node in &nodes {
        if let Some(pos) = &node.position {
            bbox.position.x = bbox.position.x.min(pos.x);
            bbox.position.y = bbox.position.y.min(pos.y);
            bbox.position.z = bbox.position.z.min(pos.z);
            bbox.size.x = bbox.size.x.max(pos.x);
            bbox.size.y = bbox.size.y.max(pos.y);
            bbox.size.z = bbox.size.z.max(pos.z);
        }
    }
    
    crate::scene_tool::schemas::SceneContext {
        scene_path: scene_path.to_string(),
        root_name: root.get("name").and_then(|v| v.as_str()).unwrap_or("Main").to_string(),
        root_type: root.get("type").and_then(|v| v.as_str()).unwrap_or("Node3D").to_string(),
        workplane: crate::scene_tool::schemas::Workplane::XZ,
        workplane_offset: crate::scene_tool::schemas::Vector3::default(),
        bbox,
        nodes,
        resources: Vec::new(),
        scripts: Vec::new(),
        plan_schema: crate::scene_tool::schemas::generate_plan_schema(),
    }
}

// allow: Godot usa f32 para coords; JSON llega como f64 — la conversión es intencional.
#[allow(clippy::cast_possible_truncation)]
fn parse_node_info(value: &serde_json::Value) -> Option<crate::scene_tool::schemas::NodeInfo> {
    Some(crate::scene_tool::schemas::NodeInfo {
        path: value.get("path").and_then(|v| v.as_str())?.to_string(),
        name: value.get("name").and_then(|v| v.as_str())?.to_string(),
        node_type: value.get("type").and_then(|v| v.as_str())?.to_string(),
        parent: value.get("parent").and_then(|v| v.as_str()).map(std::string::ToString::to_string),
        position: value.get("position").and_then(|v| {
            Some(crate::scene_tool::schemas::Vector3 {
                x: v.get("x").and_then(serde_json::Value::as_f64)? as f32,
                y: v.get("y").and_then(serde_json::Value::as_f64)? as f32,
                z: v.get("z").and_then(serde_json::Value::as_f64)? as f32,
            })
        }),
        script_path: value.get("script_path").and_then(|v| v.as_str()).map(std::string::ToString::to_string),
        children: value.get("children").and_then(|v| v.as_array()).map(|arr| {
            arr.iter().filter_map(|c| c.get("path").and_then(|p| p.as_str()).map(std::string::ToString::to_string)).collect()
        }).unwrap_or_default(),
        ..Default::default()
    })
}

// ============================================================
// NODE
// ============================================================
// NODE
// ============================================================

#[tool(
    description = "Nodos: mutaciones estructurales. add|instantiate|remove|duplicate|rename. template usa el registry transversal en vez de instance_path. move/set_owner/reorder archivados (§0.12 W4) — usar scene_script. Lecturas → node_query, props → node_props."
)]
#[allow(clippy::too_many_arguments)]
async fn node(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    node_path: Option<String>,
    node_type: Option<String>,
    node_name: Option<String>,
    instance_path: Option<String>,
    properties: Option<GodotDict>,
    new_name: Option<String>,
    parent_path: Option<String>,
    template: Option<String>,
    script: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("node_path", node_path.map(Value::String)),
            ("node_type", node_type.map(Value::String)),
            ("node_name", node_name.map(Value::String)),
            ("instance_path", instance_path.map(Value::String)),
            ("properties", properties.map(Into::into)),
            ("new_name", new_name.map(Value::String)),
            ("parent_path", parent_path.map(Value::String)),
            ("template", template.map(Value::String)),
            ("script", script.map(Value::String)),
        ]),
    );
    forward_mutating(registry, &proj, &format!("node/{action}"), a, &scene_path).await
}

#[tool(
    description = "Nodos: lecturas sin mutación. get_info|get_children|get_prop|find|class_info|props_diff. find acepta query (texto) o by=tipo. class_info = API real de una clase vía ClassDB (métodos/props/señales/enums; filter=substring; úsalo ANTES de llamar APIs que no conoces). props_diff = props del nodo que difieren del default de su clase."
)]
#[allow(clippy::too_many_arguments)]
async fn node_query(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    node_path: Option<String>,
    property_name: Option<String>,
    recursive: Option<bool>,
    query: Option<String>,
    class_name: Option<String>,
    filter: Option<String>,
    include_inherited: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("node_path", node_path.map(Value::String)),
            ("property_name", property_name.map(Value::String)),
            ("recursive", recursive.map(|v| json!(v))),
            ("query", query.map(Value::String)),
            ("class_name", class_name.map(Value::String)),
            ("filter", filter.map(Value::String)),
            ("include_inherited", include_inherited.map(Value::Bool)),
        ]),
    );
    forward(registry, &proj, &format!("node/{action}"), a).await
}

#[tool(
    description = "Nodos: propiedades. set_prop|set_props|array_append|array_remove. Recursos por PATH (res://) para ext_resource; dict inline emite warning."
)]
#[allow(clippy::too_many_arguments)]
async fn node_props(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    node_path: Option<String>,
    property_name: Option<String>,
    value: Option<GodotVariant>,
    properties: Option<GodotDict>,
    index: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("node_path", node_path.map(Value::String)),
            ("property_name", property_name.map(Value::String)),
            ("value", value.map(Into::into)),
            ("properties", properties.map(Into::into)),
            ("index", index.map(|i| json!(i))),
        ]),
    );
    let mutating = matches!(
        action.as_str(),
        "set_prop" | "set_props" | "array_append" | "array_remove"
    );
    if mutating {
        forward_mutating(registry, &proj, &format!("node/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("node/{action}"), a).await
    }
}

// ============================================================
// UI (Fase UI-2) — tool `ui` modular para UI 2D sobre viewports.
// El sistema de templates es transversal (template_registry.gd); esta tool
// delega en él. theme se añade AL FINAL de UI-2 (tras validar las otras 5).
// ============================================================

#[tool(
    description = "UI 2D: create|canvas_layer|templates|get_info. create: Control desde template o desde cero. canvas_layer: CanvasLayer para HUD. templates: lista con params del registry transversal."
)]
#[allow(clippy::too_many_arguments)]
async fn ui(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    node_path: Option<String>,
    node_type: Option<String>,
    node_name: Option<String>,
    template: Option<String>,
    properties: Option<GodotDict>,
    parent_path: Option<String>,
    layer: Option<i64>,
    follow_viewport: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("node_path", node_path.map(Value::String)),
            ("node_type", node_type.map(Value::String)),
            ("node_name", node_name.map(Value::String)),
            ("template", template.map(Value::String)),
            ("properties", properties.map(Into::into)),
            ("parent_path", parent_path.map(Value::String)),
            ("layer", layer.map(|i| json!(i))),
            ("follow_viewport", follow_viewport.map(|v| json!(v))),
        ]),
    );
    let mutating = matches!(
        action.as_str(),
        "create" | "canvas_layer"
    );
    if mutating {
        forward_mutating(registry, &proj, &format!("ui/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("ui/{action}"), a).await
    }
}

// ============================================================
// RESOURCE
// ============================================================

#[tool(
    description = "Recursos .tres y scripts .gd: create|read|update|delete|list|create_script|read_script|edit_script. Defaults en el plugin para todos los args salvo action."
)]
#[allow(clippy::too_many_arguments)]
async fn resource(
    action: String,
    project_path: Option<String>,
    resource_path: Option<String>,
    resource_type: Option<String>,
    properties: Option<GodotDict>,
    directory: Option<String>,
    extension: Option<String>,
    recursive: Option<bool>,
    script_path: Option<String>,
    content: Option<String>,
    append: Option<bool>,
    template: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("resource_path", resource_path.map(Value::String)),
        ("resource_type", resource_type.map(Value::String)),
        ("properties", properties.map(Into::into)),
        ("directory", directory.map(Value::String)),
        ("extension", extension.map(Value::String)),
        ("recursive", recursive.map(|v| json!(v))),
        ("script_path", script_path.map(Value::String)),
        ("content", content.map(Value::String)),
        ("append", append.map(|v| json!(v))),
        ("template", template.map(Value::String)),
    ]);
    forward(registry, &proj, &format!("resource/{action}"), a).await
}

// ============================================================
// PROJECT
// ============================================================

#[tool(
    description = "Config proyecto: create|setup_plugin|setting(op=get/set/list/delete/set_multi)|autoload|remove_autoload|input_map(type=add/get/list/add_event/set_events/remove_event/set_deadzone/set_event/remove)|shader_global"
)]
#[allow(clippy::too_many_arguments)]
async fn project(
    action: String,
    project_path: Option<String>,
    op: Option<String>,
    setting_name: Option<String>,
    value: Option<GodotVariant>,
    values: Option<GodotDict>,
    prefix: Option<String>,
    autoload_name: Option<String>,
    script_path: Option<String>,
    global_name: Option<String>,
    r#type: Option<String>,
    action_name: Option<String>,
    event: Option<GodotVariant>,
    events: Option<GodotVariant>,
    deadzone: Option<f64>,
    index: Option<i64>,
    project_name: Option<String>,
    main_scene: Option<String>,
    root_type: Option<String>,
    root_name: Option<String>,
    viewport_width: Option<i64>,
    viewport_height: Option<i64>,
    stretch_mode: Option<String>,
) -> Result<Value, ToolError> {
    // `create` y `setup_plugin` NO requieren editor conectado: escriben en
    // disco directamente (migraciÃ³n v3: project("create") hacÃ­a lo mismo).
    if action == "create" {
        return create_project(
            project_path.as_deref(),
            project_name.as_deref(),
            r#type.as_deref(),
            main_scene.as_deref(),
            root_type.as_deref(),
            root_name.as_deref(),
            viewport_width.unwrap_or(1280),
            viewport_height.unwrap_or(720),
            stretch_mode.as_deref(),
        );
    }
    if action == "setup_plugin" {
        return setup_plugin(project_path.as_deref());
    }

    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("op", op.map(Value::String)),
        ("setting_name", setting_name.map(Value::String)),
        ("value", value.map(Into::into)),
        ("values", values.map(Into::into)),
        ("prefix", prefix.map(Value::String)),
        ("autoload_name", autoload_name.map(Value::String)),
        ("script_path", script_path.map(Value::String)),
        ("global_name", global_name.map(Value::String)),
        ("type", r#type.map(Value::String)),
        ("action_name", action_name.map(Value::String)),
        ("event", event.map(Into::into)),
        ("events", events.map(Into::into)),
        ("deadzone", deadzone.map(|d| json!(d))),
        ("index", index.map(|i| json!(i))),
    ]);
    forward(registry, &proj, &format!("project/{action}"), a).await
}

/// Instala el plugin v4 en un proyecto (sin editor): copia addons/heren/ +
/// normaliza [editor_plugins]. El agente la llama para preparar un proyecto.
fn setup_plugin(project_path: Option<&str>) -> Result<Value, ToolError> {
    let proj = match project_path {
        Some(p) if !p.trim().is_empty() => normalize_project_path(p),
        _ => {
            return Err(ToolError::invalid_params(
                "project_path required â€” proyecto donde instalar el plugin",
            ));
        }
    };
    if !std::path::Path::new(&proj).join("project.godot").exists() {
        return Err(ToolError::invalid_params(format!(
            "not a Godot project (no project.godot): {proj} â€” usa project/create primero"
        )));
    }
    let (installed, install_msg) = crate::launcher::ensure_plugin_installed(&proj);
    // Ok(true)=normalizado, Ok(false)=ya correcto (Ã©xito), Err=fallo real.
    let enabled = match crate::launcher::enable_plugin_in_project(&proj) {
        Ok(v) => v,
        Err(e) => {
            return Err(ToolError::internal(format!(
                "enable_plugin_in_project failed: {e}"
            )));
        }
    };
    Ok(json!({
        "ok": true,
        "project_path": proj,
        "installed": installed,
        "install_msg": install_msg,
        "enabled": enabled,
        "guidelines": "res://addons/heren/ai/guidelines.md",
        "message": format!(
            "plugin: {install_msg}; [editor_plugins]: {}; guía para agentes en res://addons/heren/ai/guidelines.md",
            if enabled { "normalizado/habilitado" } else { "ya correcto" }
        ),
    }))
}

/// Crea un proyecto Godot completo en `project_path` (sin editor) y genera
/// automÃ¡ticamente una escena main (`res://main.tscn` por defecto) con su
/// root conectado a `run/main_scene`. Paridad con `project("create")` v3 +
/// configurabilidad profunda para el agente.
#[allow(clippy::too_many_arguments)]
fn create_project(
    project_path: Option<&str>,
    project_name: Option<&str>,
    renderer: Option<&str>,
    main_scene: Option<&str>,
    root_type: Option<&str>,
    root_name: Option<&str>,
    viewport_width: i64,
    viewport_height: i64,
    stretch_mode: Option<&str>,
) -> Result<Value, ToolError> {
    let proj = match project_path {
        Some(p) if !p.trim().is_empty() => normalize_project_path(p),
        _ => {
            return Err(ToolError::invalid_params(
                "project_path required â€” dÃ³nde crear el proyecto",
            ));
        }
    };
    let dir = std::path::Path::new(&proj);
    let pg = dir.join("project.godot");
    if pg.exists() {
        return Ok(json!({
            "ok": true,
            "project_path": proj,
            "daemon_setup": "skipped",
            "message": "project.godot ya existe â€” plugin instalado por session/open",
        }));
    }
    let _ = std::fs::create_dir_all(dir);

    let name = project_name.unwrap_or("Heren Project");
    let renderer = renderer.unwrap_or("forward_plus");
    let scene = main_scene.unwrap_or("res://main.tscn");
    let root_type = root_type.unwrap_or("Node2D");
    let root_name = root_name.unwrap_or("Main");
    let stretch = stretch_mode.unwrap_or("2d");
    let viewport_width = viewport_width.clamp(320, 7680);
    let viewport_height = viewport_height.clamp(180, 4320);

    // project.godot â€” config completa.
    let body = format!(
        "; Engine configuration file.\n\
         ; Godot version: 4.7.1\n\
         ; Format: 2\n\
         \n\
         [application]\n\
         config/name=\"{name}\"\n\
         config/features=PackedStringArray(\"4.7\")\n\
         run/main_scene=\"{scene}\"\n\
         \n\
         [display]\n\
         window/size/viewport_width={viewport_width}\n\
         window/size/viewport_height={viewport_height}\n\
         window/stretch/mode=\"{stretch}\"\n\
         window/stretch/aspect=\"ignore\"\n\
         \n\
         [rendering]\n\
         renderer/rendering_method=\"{renderer}\"\n"
    );

    // Escena main â€” generada y conectada al proyecto.
    let scene_path = scene.trim_start_matches("res://");
    let scene_file = dir.join(scene_path);
    if let Some(parent) = scene_file.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let tscn = format!("[gd_scene format=3]\n\n[node name=\"{root_name}\" type=\"{root_type}\"]\n");
    let scene_created = std::fs::write(&scene_file, tscn).is_ok();

    match std::fs::write(&pg, body) {
        Ok(()) => Ok(json!({
            "ok": true,
            "project_path": proj,
            "daemon_setup": "success",
            "project_name": name,
            "renderer": renderer,
            "main_scene": scene,
            "root_type": root_type,
            "root_name": root_name,
            "main_scene_created": scene_created,
            "message": "proyecto creado con escena main â€” usa project/setup_plugin o session/open para instalar el plugin",
        })),
        Err(e) => Err(ToolError::internal(format!(
            "create project.godot failed: {e}"
        ))),
    }
}

// ============================================================
// SHADER
// ============================================================

#[tool(
    description = "Shaders: create|edit|get|inspect|validate. Defaults en el plugin para todos los args. material/uniform/apply archivados (§0.12 W4) — usar scene_script."
)]
#[allow(clippy::too_many_arguments)]
async fn shader(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    shader_path: Option<String>,
    shader_type: Option<String>,
    code: Option<String>,
    append: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("shader_path", shader_path.map(Value::String)),
            ("shader_type", shader_type.map(Value::String)),
            ("code", code.map(Value::String)),
            ("append", append.map(|v| json!(v))),
        ]),
    );
    // Shader: las acciones que ESCRIBEN (create/edit) marcan dirty;
    // las de lectura (get/inspect/validate) no.
    let mutating = matches!(action.as_str(), "create" | "edit");
    if mutating {
        forward_mutating(registry, &proj, &format!("shader/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("shader/{action}"), a).await
    }
}

// ============================================================
// ANIMATION
// ============================================================

#[tool(
    description = "Animaciones: create_player|create|add_track|add_key|state_machine|play|stop|seek|speed|get_*|remove_*|update_*|one_shot|tween|record|from_path|loop_pose|preview|curve|duplicate|delete|rename|reverse. Defaults en el plugin. tree_*/capture_pose/blend_pose/retarget archivados (§0.12 W4) — usar scene_script."
)]
#[allow(clippy::too_many_arguments)]
async fn animation(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    parent_path: Option<String>,
    player_name: Option<String>,
    player_path: Option<String>,
    anim_name: Option<String>,
    length: Option<f64>,
    loop_anim: Option<bool>,
    track_type: Option<String>,
    node_path: Option<String>,
    property: Option<String>,
    track_idx: Option<i64>,
    time: Option<f64>,
    value: Option<GodotVariant>,
    transition: Option<f64>,
    states: Option<GodotVariant>,
    transitions: Option<GodotVariant>,
    custom_blend: Option<f64>,
    speed: Option<f64>,
    graph_type: Option<String>,
    points: Option<GodotDict>,
    key_idx: Option<i64>,
    loop_mode: Option<String>,
    tracks: Option<GodotDict>,
    duration: Option<f64>,
    to: Option<GodotDict>,
    from: Option<GodotDict>,
    easing: Option<String>,
    fps: Option<f64>,
    path_path: Option<String>,
    amplitude: Option<f64>,
    frequency: Option<f64>,
    axis: Option<String>,
    new_name: Option<String>,
    library: Option<String>,
    start: Option<bool>,
    active: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("parent_path", parent_path.map(Value::String)),
            ("player_name", player_name.map(Value::String)),
            ("player_path", player_path.map(Value::String)),
            ("anim_name", anim_name.map(Value::String)),
            ("length", length.map(|v| json!(v))),
            ("loop", loop_anim.map(|v| json!(v))),
            ("track_type", track_type.map(Value::String)),
            ("node_path", node_path.map(Value::String)),
            ("property", property.map(Value::String)),
            ("track_idx", track_idx.map(|v| json!(v))),
            ("time", time.map(|v| json!(v))),
            ("value", value.map(Into::into)),
            ("transition", transition.map(|v| json!(v))),
            ("states", states.map(Into::into)),
            ("transitions", transitions.map(Into::into)),
            ("custom_blend", custom_blend.map(|v| json!(v))),
            ("speed", speed.map(|v| json!(v))),
            ("graph_type", graph_type.map(Value::String)),
            ("points", points.map(Into::into)),
            ("key_idx", key_idx.map(|v| json!(v))),
            ("loop_mode", loop_mode.map(Value::String)),
            ("tracks", tracks.map(Into::into)),
            ("duration", duration.map(|v| json!(v))),
            ("to", to.map(Into::into)),
            ("from", from.map(Into::into)),
            ("easing", easing.map(Value::String)),
            ("fps", fps.map(|v| json!(v))),
            ("path_path", path_path.map(Value::String)),
            ("amplitude", amplitude.map(|v| json!(v))),
            ("frequency", frequency.map(|v| json!(v))),
            ("axis", axis.map(Value::String)),
            ("new_name", new_name.map(Value::String)),
            ("library", library.map(Value::String)),
            ("start", start.map(|v| json!(v))),
            ("active", active.map(|v| json!(v))),
        ]),
    );
    // Animación: las acciones de ESCRITURA marcan dirty (persistencia
    // 2026-08-07); las de lectura (get_*/preview) no mutan el árbol.
    let mutating = matches!(
        action.as_str(),
        "create_player"
            | "create"
            | "add_track"
            | "add_key"
            | "state_machine"
            | "remove_track"
            | "remove_key"
            | "update_key"
            | "update_props"
            | "one_shot"
            | "record"
            | "from_path"
            | "loop_pose"
            | "duplicate"
            | "delete"
            | "rename"
            | "reverse"
            | "tween"
    );
    if mutating {
        forward_mutating(
            registry,
            &proj,
            &format!("animation/{action}"),
            a,
            &scene_path,
        )
        .await
    } else {
        forward(registry, &proj, &format!("animation/{action}"), a).await
    }
}

// ============================================================
// DEBUG
// ============================================================

#[tool(
    description = "Depuración: summary|breakpoint|control|stack|vars|profiler|run_scene|output. summary = snapshot completo (editor+plugin+game+errors+breakpoints+profiler+console). output = log del juego + errores del editor (filter=error|all). run_scene op=play|stop."
)]
#[allow(clippy::too_many_arguments)]
async fn debug(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    op: Option<String>,
    path: Option<String>,
    line: Option<i64>,
    enabled: Option<bool>,
    frame: Option<i64>,
    profiler: Option<String>,
    max_functions: Option<i64>,
    include_native: Option<bool>,
    limit: Option<i64>,
    filter: Option<String>,
    console_limit: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let a = args(&[
        (
            "scene_path",
            scene_path
                .as_deref()
                .map(normalize_scene_path)
                .map(Value::String),
        ),
        ("op", op.map(Value::String)),
        ("path", path.map(Value::String)),
        ("line", line.map(|v| json!(v))),
        ("enabled", enabled.map(|v| json!(v))),
        ("frame", frame.map(|v| json!(v))),
        ("profiler", profiler.map(Value::String)),
        ("max_functions", max_functions.map(|v| json!(v))),
        ("include_native", include_native.map(|v| json!(v))),
        ("limit", limit.map(|v| json!(v))),
        ("filter", filter.map(Value::String)),
        ("console_limit", console_limit.map(|v| json!(v))),
    ]);
    forward(registry, &proj, &format!("debug/{action}"), a).await
}

// ============================================================
// VALIDATE
// ============================================================

#[tool(    description = "Validación: scene|script|scripts|node|resource. scripts = bulk con el compilador del editor (reload) sobre todos los .gd del proyecto; mensajes en debug/output")]
async fn validate(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    script_path: Option<String>,
    node_path: Option<String>,
    resource_path: Option<String>,
    dir: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let a = args(&[
        (
            "scene_path",
            scene_path
                .as_deref()
                .map(normalize_scene_path)
                .map(Value::String),
        ),
        ("script_path", script_path.map(Value::String)),
        ("node_path", node_path.map(Value::String)),
        ("resource_path", resource_path.map(Value::String)),
        ("dir", dir.map(Value::String)),
    ]);
    forward(registry, &proj, &format!("validate/{action}"), a).await
}

// ============================================================
// SIGNAL
// ============================================================

#[tool(description = "Señales: connect|disconnect|list. set_script archivado (§0.12 W4) — usa node/set_script.")]
#[allow(clippy::too_many_arguments)]
async fn signal(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    from_node: Option<String>,
    to_node: Option<String>,
    signal_name: Option<String>,
    method: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!scene_path.is_empty()).then(|| Value::String(scene_path.clone())),
            ),
            ("from_node", from_node.map(Value::String)),
            ("to_node", to_node.map(Value::String)),
            ("signal_name", signal_name.map(Value::String)),
            ("method", method.map(Value::String)),
        ]),
    );
    // Señales: connect/disconnect mutan el árbol (dirty); list no.
    let mutating = matches!(action.as_str(), "connect" | "disconnect");
    if mutating {
        forward_mutating(registry, &proj, &format!("signal/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("signal/{action}"), a).await
    }
}

// `orchestrate` (tool plana para batch genérico) se quitó del schema público
// (AGENTS.md §0.8). Para batch de ops usa el flujo planning: scene/open +
// scene/plan + scene/orchestrate (steps tipados o GenericStep verbatim).

// ============================================================
// VISUAL — UNA tool, 4 acciones (Fase A+B+D de §0.11; visual_image ELIMINADO)
// Centralizada: coords|summary|ascii|spatial. Reemplaza captura de imagen
// (json puro, sin GPU off-screen, sin 800 tok por PNG).
// ============================================================

#[tool(
    description = "Visión textual pura (sin imagen): coords|summary|ascii|spatial. Barata, usarla primero. spatial: overlaps|distance|neighbors|layout|bounds. summary: recursivo con warnings (z_fighting, missing_material/texture/shape). args: scene_path, max_depth (default 10), y según mode: node_path, from, to, of, radius, padding."
)]
#[allow(clippy::too_many_arguments)]
async fn visual(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    max_depth: Option<i64>,
    mode: Option<String>,
    node_path: Option<String>,
    from: Option<String>,
    to: Option<String>,
    of: Option<String>,
    radius: Option<f64>,
    padding: Option<f64>,
    // Fase C (2026-09-04): tier de coords. Default 1 (mapa visual barato).
    // tier=3 → añade bloque `dynamic` por nodo (resumen: animation, animation_tree
    // con anim_player snapshot, skeleton_3d count+3 primeros, skeleton_2d, light_3d,
    // audio, camera). tier=4 → completo (todas las poses skeleton_3d, AnimationTree
    // params completos, skeleton_2d con weights). SÓLO aplica a action=coords.
    tier: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let handler = match action.as_str() {
        "coords" => "visual/scene_coords",
        "summary" => "visual/scene_summary",
        "ascii" => "visual/scene_ascii",
        "spatial" => "visual/scene_spatial",
        other => {
            return Err(ToolError::invalid_params(format!(
                "unknown visual action: {other} (coords|summary|ascii|spatial)"
            )));
        }
    };
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                scene_path
                    .as_deref()
                    .map(normalize_scene_path)
                    .map(Value::String),
            ),
            ("max_depth", max_depth.map(|v| json!(v))),
            ("mode", mode.map(Value::String)),
            ("node_path", node_path.map(Value::String)),
            ("from", from.map(Value::String)),
            ("to", to.map(Value::String)),
            ("of", of.map(Value::String)),
            ("radius", radius.map(|v| json!(v))),
            ("padding", padding.map(|v| json!(v))),
            ("tier", tier.map(|v| json!(v))),
        ]),
    );
    forward(registry, &proj, handler, a).await
}

// ============================================================
// SCENE SCRIPT (W4 Worker-First)
// ============================================================

#[tool(
    description = "Workers GDScript del agente: run|list|inspect. run ejecuta un worker (@tool, extends RefCounted, func run(ctx)) contra la escena: parse-check previo, save transaccional (solo si ctx.mark_modified()), snapshot+restore en fallo, coords del resultado. ctx: get_scene_root/set_scene_root/own/instance_scene/template/coords/get_node_or_null/find_nodes_by_name/remove_node/clear_children/log/error/mark_modified/output. mode=inspect es read-only detached. code (primera vez) o script_path (reintentos: parcha el mismo archivo con resource/edit_script). CONTRATO: ran=false = el worker falló (ver error) pero la tool tuvo éxito — itera parchando el script_path devuelto; la escena original queda intacta. inspect (W4b) vista READ-ONLY sin ejecutar worker: árbol recursivo (tier 1/2/3, default 1) + agregados (skeleton bones, animations, materials, lights, audio, cameras). PackedScene instanciadas opacas por defecto — opt-in vía expand_scene=[res://path.tscn,...]. NO muta."
)]
#[allow(clippy::too_many_arguments)]
async fn scene_script(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    code: Option<String>,
    script_path: Option<String>,
    mode: Option<String>,
    save: Option<bool>,
    tier: Option<i64>,
    depth: Option<i64>,
    expand_scene: Option<Vec<String>>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let normalized_scene = scene_path
        .as_deref()
        .map(normalize_scene_path)
        .unwrap_or_default();
    let is_inspect = mode.as_deref() == Some("inspect");
    let expand_json = expand_scene.map(|v| Value::Array(v.into_iter().map(Value::String).collect()));
    let a = apply_scene_context(
        &proj,
        args(&[
            (
                "scene_path",
                (!normalized_scene.is_empty()).then(|| Value::String(normalized_scene.clone())),
            ),
            ("code", code.map(Value::String)),
            ("script_path", script_path.map(Value::String)),
            ("mode", mode.map(Value::String)),
            ("save", save.map(Value::Bool)),
            ("tier", tier.map(|v| json!(v))),
            ("depth", depth.map(|v| json!(v))),
            ("expand_scene", expand_json),
        ]),
    );
    if action == "run" && !is_inspect {
        // run en modo edit muta la escena (dirty si no guardó).
        forward_mutating(
            registry,
            &proj,
            "scene_script/run",
            a,
            &normalized_scene,
        )
        .await
    } else {
        forward(registry, &proj, &format!("scene_script/{action}"), a).await
    }
}

// ============================================================
// FILESYSTEM (W4b §0.12 — EditorFileSystem: scan/status/import_errors/exists/import)
// ============================================================

#[tool(
    description = "EditorFileSystem: scan|status|import_errors|exists|import. scan fuerza un rescan y espera a is_scanning()=false (cierra el gap EFS en frío). status reporta is_scanning + file_count recursivo. import_errors lista archivos con errores de import (walk recursivo del EFS, max_items default 100). exists consulta FileAccess.file_exists para varios paths (mejor que ResourceLoader.exists para archivos sin .import). import reimporta un path puntual vía update_file(). timeouts en segundos."
)]
async fn filesystem(
    action: String,
    project_path: Option<String>,
    paths: Option<Vec<String>>,
    path: Option<String>,
    timeout_seconds: Option<f64>,
    max_items: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref()).await?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("paths", paths.map(|v| json!(v))),
        ("path", path.map(Value::String)),
        ("timeout_seconds", timeout_seconds.map(|v| json!(v))),
        ("max_items", max_items.map(|v| json!(v))),
    ]);
    forward(registry, &proj, &format!("filesystem/{action}"), a).await
}

// ============================================================
// HEALTH (reemplaza la antigua tool health simple y la tool session completa —
// sin lifecycle, Fennara-style)
// ============================================================
// (definida arriba; aquí solo el doc-link por contexto)

/// Punto de entrada del binario.
pub async fn run() -> Result<(), ServerError> {
    EditorRegistry::init_global();

    // Fase 1 (2026-09-03): state de planning vive en el plugin-registry
    // (HerenSceneRegistry en GDScript). El server NO mantiene SceneRegistry
    // propio — toda la orquestación es forward + pure-logic (coder/validator).
    // NOTA: ya NO escribimos discovery aquí (se hacía en CWD, no en project_path).
    // El discovery se escribe en ensure_editor_connected cuando hay project_path real.
    let _ = ws_port(); // inicializa el puerto (OnceLock)

    // WS plugin server: el EditorPlugin Godot conecta aquÃ­ (patrÃ³n gopeak).
    // Multi-sesiÃ³n (fix 2026-08-06): CADA heren-server de cada sesiÃ³n OpenCode
    // bindea su PROPIO puerto libre (ws_port cachea el mismo para session/open).
    // NO matamos otros heren-server â€” eso asesinaba servers de sesiones
    // hermanas a mitad de operaciÃ³n (MCP connection closed + AbortError).
    let port = ws_port();
    let ws_addr = format!("127.0.0.1:{port}");
    let ws_addr_clone = ws_addr.clone();
    tokio::spawn(async move {
        if let Err(e) = crate::ws_plugin_server::run_ws_plugin_server(&ws_addr_clone).await {
            eprintln!("[heren-server] WS plugin server error: {e}");
            eprintln!(
                "[heren-server] CRÃTICO: WS server no disponible en {ws_addr_clone} â€” \
                 el editor no podrÃ¡ conectar; verifica que HEREN_WS_ADDR no estÃ© ocupado"
            );
        }
    });

    // MCP server por stdio (OpenCode). Este bloquea hasta que termine.
    let result = flojo_run_stdio(Heren::new()).await;

    // NOTA: NO limpiamos discovery aquí — se escribe por-project en
    // ensure_editor_connected. Archivos stale son inofensivos (PID muerto).
    result
}
