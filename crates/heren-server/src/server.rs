//! HerenServer â€” FlojoMCP server con las tools MCP v4 (paridad con bridge Python).
//!
//! Fase 4 enfoque paridad: cada tool reenvÃ­a al EditorPlugin v4 via
//! EditorRegistry (el bridge Python es el benchmark de comportamiento).

use flojo_mcp::prelude::*;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use crate::editor::normalize_project_path;
use crate::registry::EditorRegistry;

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

/// Server FlojoMCP: struct marcado con #[flojo_mcp].
#[flojo_mcp(name = "heren-server", version = "4.1.0")]
pub struct Heren;

/// Resuelve el project_path: el editor conectado ES la sesiÃ³n (ADR-004).
fn resolve_project(project_path: Option<&str>) -> Result<String, ToolError> {
    match project_path {
        Some(p) if !p.trim().is_empty() => Ok(normalize_project_path(p)),
        _ => Err(ToolError::invalid_params(
            "project_path required â€” use session/open first",
        )),
    }
}

/// Construye un args dict con los campos no-nulos.
/// IMPORTANTE (fix C1/C2): las keys None se OMITEN, no se insertan como
/// Value::Null. Antes `project/setting` get recibÃ­a `"value":null` y
/// `handle_setting` lo interpretaba como set (borraba el setting); ademÃ¡s
/// `str(null)` en GDScript = `"<null>"` rompÃ­a los guards `if x == ""`.
fn args(entries: &[(&str, Option<Value>)]) -> Value {
    let mut m = serde_json::Map::new();
    for (k, v) in entries {
        if let Some(val) = v {
            m.insert(k.to_string(), val.clone());
        }
    }
    Value::Object(m)
}

/// Normaliza un scene_path del agente a la forma canÃ³nica de Godot
/// (`res://` prefix, forward slashes, sin trailing slash). El plugin compara
/// `scene_file_path` (siempre `res://...` normalizado por Godot) contra la key
/// del SceneRegistry; si el agente manda `scenes/x.tscn` (sin res://),
/// backslashes o trailing slash, el match falla â†’ la escena se registra como
/// fantasma y save/open divergen de la pestaÃ±a real (fix 2026-08-06).
/// Empty string â†’ sin cambio (las tools lo tratan como "no path").
fn normalize_scene_path(path: &str) -> String {
    let s = path.trim();
    if s.is_empty() {
        return String::new();
    }
    let replaced = s.replace('\\', "/");
    let trimmed = replaced.trim_end_matches('/').to_string();
    // `res:/...` (tras convertir backslashes) o `res://...` ya son canÃ³nicos.
    // Cualquier otro prefijo (`scenes/...`, `../`, absoluto) â†’ anteponer res://
    if trimmed.starts_with("res://") || trimmed.starts_with("res:/") {
        // Normalizar `res:/` â†’ `res://` (Godot exige doble slash).
        if trimmed.starts_with("res:/") && !trimmed.starts_with("res://") {
            return format!("res://{}", &trimmed[5..]);
        }
        trimmed
    } else {
        format!("res://{trimmed}")
    }
}

/// ReenvÃ­a tools/call al editor y devuelve el resultado desenvuelto.
async fn forward(
    registry: &EditorRegistry,
    project_path: &str,
    tool_name: &str,
    args: Value,
) -> Result<Value, ToolError> {
    let raw = registry
        .call_tool(tool_name, args, project_path)
        .await
        .map_err(ToolError::internal)?;
    Ok(unwrap_result(&raw))
}

/// ReenvÃ­a una MUTACIÃ“N (tool que modifica el Ã¡rbol del editor) y marca la
/// escena como dirty. RediseÃ±o persistencia 2026-08-07: el server recuerda
/// quÃ© escenas tienen cambios sin guardar â†’ session/close hace flush y
/// session/info las expone. scene/save limpia el dirty (ver `scene` tool).
async fn forward_mutating(
    registry: &EditorRegistry,
    project_path: &str,
    tool_name: &str,
    args: Value,
    scene_path: &str,
) -> Result<Value, ToolError> {
    let result = forward(registry, project_path, tool_name, args).await?;
    // Marcar dirty solo si la mutaciÃ³n tuvo Ã©xito (ok=true) y hay scene_path.
    if !scene_path.is_empty() {
        let ok = result.get("ok").and_then(|o| o.as_bool()).unwrap_or(false);
        if ok {
            registry.mark_dirty(project_path, scene_path).await;
        }
    }
    Ok(result)
}

/// Desenvuelve la respuesta del plugin: content[0].text como JSON dict.
fn unwrap_result(raw: &Value) -> Value {
    if let Some(content) = raw.get("content").and_then(|c| c.as_array()) {
        for item in content {
            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                if let Ok(parsed) = serde_json::from_str::<Value>(text) {
                    return parsed;
                }
            }
            // Imagen base64 (__image_base64 en el text-stream).
            if let Some(b64) = item.get("__image_base64").and_then(|b| b.as_str()) {
                let mut m = serde_json::Map::new();
                m.insert("__image_base64".into(), Value::String(b64.to_string()));
                if let Some(fmt) = item.get("__image_format").and_then(|f| f.as_str()) {
                    m.insert("__image_format".into(), Value::String(fmt.to_string()));
                }
                return Value::Object(m);
            }
        }
    }
    raw.clone()
}

// ============================================================
// SESSION
// ============================================================

#[tool(
    description = "Gestion de sesiones v4: open|reopen|close|list|info|health|diagnose - reopen mata el editor y relanza limpio (tras settings restart_required); diagnose = DEBUGGER UNIFICADO del plugin (integridad archivo x archivo + validacion grafo godot headless + estado editor)"
)]
async fn session(
    action: String,
    project_path: Option<String>,
    godot_path: Option<String>,
    close_editor: Option<bool>,
) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let kill_editor = close_editor.unwrap_or(false);
    match action.as_str() {
        "list" => Ok(json!({
            "ok": true,
            "projects": registry.connected_projects().await,
        })),
        "health" => {
            let editors = registry.connected_projects().await;
            let source = crate::launcher::source_plugin_version();
            // Â¿AlgÃºn editor conectado corre una versiÃ³n antigua del plugin?
            let mut stale: Vec<Value> = Vec::new();
            for proj in &editors {
                let live = registry.editor_plugin_version(proj).await;
                if let Some(live) = &live {
                    if let Some(src) = &source {
                        if live != src {
                            stale.push(json!({
                                "project_path": proj,
                                "plugin_version_editor": live,
                                "plugin_version_source": src,
                                "remedy": "session/reopen para recargar el plugin con el codigo nuevo",
                            }));
                        }
                    }
                }
            }
            Ok(json!({
                "ok": true,
                "connected_projects": editors,
                "count": editors.len(),
                "plugin_source_version": source,
                "stale_editors": stale,
            }))
        }
        "info" => {
            let proj = resolve_project(project_path.as_deref())?;
            let connected = registry.has_editor(&proj).await;
            let source = crate::launcher::source_plugin_version();
            let live = registry.editor_plugin_version(&proj).await;
            let installed = crate::launcher::read_plugin_version(&proj);
            let stale = matches!((&live, &source), (Some(l), Some(s)) if l != s);
            let dirty = registry.dirty_scenes(&proj).await;
            let unexpected = registry.unexpected_close(&proj).await;
            Ok(json!({
                "ok": true,
                "project_path": proj,
                "connected": connected,
                "plugin_version_source": source,
                "plugin_version_installed": installed,
                "plugin_version_editor": live,
                "plugin_stale": stale,
                "plugin_stale_remedy": if stale {
                    "El editor corre una version ANTIGUA del plugin. Ejecuta session/reopen para recargar el codigo nuevo; hasta entonces las tools usan la version vieja."
                } else {
                    ""
                },
                // RediseÃ±o persistencia 2026-08-07:
                "dirty_scenes": dirty,
                "unexpected_close": unexpected.is_some(),
                "unexpected_close_dirty": unexpected.unwrap_or_default(),
            }))
        }
        "open" => {
            // Auto-launch del editor (port de godot_launcher.py).
            let proj = resolve_project(project_path.as_deref())?;
            let port = ws_port();
            // RediseÃ±o persistencia: al reconectar, limpiar el flag de cierre
            // inesperado (el agente ya fue avisado por el error de la tool).
            registry.clear_unexpected_close(&proj).await;
            // Si hay un editor del proyecto YA conectado, se reutiliza; si hay
            // un proceso zombie sin conectar, launch_editor lo mata y relanza.
            let editor_connected = registry.has_editor(&proj).await;
            let outcome = crate::launcher::launch_editor(
                &proj,
                port,
                godot_path.as_deref(),
                editor_connected,
            );
            let dirty = registry.dirty_scenes(&proj).await;
            Ok(json!({
                "ok": true,
                "project_path": proj,
                "daemon_active": true,
                "launched": outcome.launched,
                "plugin_changed": outcome.plugin_changed,
                "plugin_version_source": outcome.source_version,
                "plugin_version_installed": outcome.installed_version,
                "message": outcome.msg,
                "dirty_scenes": dirty,
                "note": "editor abierto/reutilizado â€” el plugin conecta al WS server automÃ¡ticamente; si el plugin cambio en disco y el editor ya estaba conectado, ejecuta session/reopen para recargar el codigo nuevo",
            }))
        }
        "reopen" => {
            // Recarga limpia: mata el editor (aunque estÃ© conectado) y relanza.
            // Usado tras settings read-at-startup que devuelven
            // restart_required: true, o para recargar el plugin actualizado.
            // Reusa el contexto del proyecto â€” el agente NO repite project_path.
            //
            // Fix 2026-08-07: reopen es un reinicio DELIBERADO del editor â€”
            // igual que session/close: flush dirty ANTES del kill y marcar
            // GRACEFUL para que la desconexiÃ³n WS que sigue NO marque
            // unexpected_close. Tras relanzar, limpiar cualquier flag previo
            // (el editor nuevo conecta limpio).
            let proj = resolve_project(project_path.as_deref())?;
            let port = ws_port();
            let dirty = registry.dirty_scenes(&proj).await;
            let mut flushed: Vec<String> = Vec::new();
            let mut failed: Vec<String> = Vec::new();
            for scene in &dirty {
                match forward(registry, &proj, "scene/save", json!({"scene_path": scene})).await {
                    Ok(_) => {
                        registry.clean_dirty(&proj, scene).await;
                        flushed.push(scene.clone());
                    }
                    Err(_) => failed.push(scene.clone()),
                }
            }
            registry.mark_graceful_close(&proj).await;
            let killed = crate::launcher::close_editor(&proj);
            registry.take_graceful_close(&proj).await;
            if killed {
                // esperar a que libere el lock
                std::thread::sleep(std::time::Duration::from_millis(1500));
            }
            registry.clear_unexpected_close(&proj).await;
            let outcome = crate::launcher::launch_editor(
                &proj,
                port,
                godot_path.as_deref(),
                false, // tras el kill nunca hay editor conectado
            );
            Ok(json!({
                "ok": true,
                "project_path": proj,
                "killed_editor": killed,
                "launched": outcome.launched,
                "plugin_changed": outcome.plugin_changed,
                "plugin_version_source": outcome.source_version,
                "plugin_version_installed": outcome.installed_version,
                "flushed_scenes": flushed,
                "flush_failed": failed,
                "message": outcome.msg,
            }))
        }
        "close" => {
            let proj = resolve_project(project_path.as_deref())?;
            // RediseÃ±o persistencia 2026-08-07:
            // 1. Flush: si hay escenas dirty, guardarlas ANTES de cerrar
            //    (el editor sigue vivo â€” podemos pedir scene/save).
            // 2. Marcar cierre GRACEFUL para que la desconexiÃ³n WS que sigue
            //    NO marque unexpected_close.
            let dirty = registry.dirty_scenes(&proj).await;
            let mut flushed: Vec<String> = Vec::new();
            let mut failed: Vec<String> = Vec::new();
            for scene in &dirty {
                match forward(registry, &proj, "scene/save", json!({"scene_path": scene})).await {
                    Ok(_) => {
                        registry.clean_dirty(&proj, scene).await;
                        flushed.push(scene.clone());
                    }
                    Err(_) => failed.push(scene.clone()),
                }
            }
            if kill_editor {
                registry.mark_graceful_close(&proj).await;
                let killed = crate::launcher::close_editor(&proj);
                registry.take_graceful_close(&proj).await;
                Ok(json!({
                    "ok": true,
                    "project_path": proj,
                    "closed_editor": killed,
                    "flushed_scenes": flushed,
                    "flush_failed": failed,
                }))
            } else {
                // Sin matar el editor: el plugin queda reconectando, listo para
                // la prÃ³xima sesiÃ³n (decisiÃ³n del General).
                Ok(json!({
                    "ok": true,
                    "project_path": proj,
                    "closed_editor": false,
                    "flushed_scenes": flushed,
                    "flush_failed": failed,
                    "message": "editor dejado vivo (reconecta solo)",
                }))
            }
        }
        "diagnose" => {
            // DEBUGGER UNIFICADO del plugin (2026-08-08): deja de adivinar.
            // Reporta: integridad archivo por archivo (source vs instalado),
            // validaciÃ³n del grafo completo (godot headless en sandbox), y
            // estado del editor (procesos vivos con cmdline, conexiÃ³n WS).
            let proj = resolve_project(project_path.as_deref())?;
            let source = crate::launcher::source_plugin_version();
            let installed = crate::launcher::read_plugin_version(&proj);
            let live = registry.editor_plugin_version(&proj).await;
            let connected = registry.has_editor(&proj).await;
            let integrity = crate::launcher::plugin_integrity(&proj);
            let stale_count = integrity
                .iter()
                .filter(|f| f.status == "stale" || f.status == "missing")
                .count();
            let graph = crate::launcher::validate_plugin_graph(&proj, godot_path.as_deref());
            let procs = crate::launcher::godot_processes_detailed(&proj);
            Ok(json!({
                "ok": true,
                "project_path": proj,
                "plugin": {
                    "source_version": source,
                    "installed_version": installed,
                    "editor_version": live,
                    "stale": matches!((&live, &source), (Some(l), Some(s)) if l != s),
                },
                "integrity": {
                    "files": integrity,
                    "stale_count": stale_count,
                    "message": if stale_count == 0 {
                        "plugin integro: todos los archivos coinciden con source"
                    } else {
                        "plugin INCOMPLETO: hay archivos stale/missing - ejecuta session/open (sync) y session/reopen (recarga el editor)"
                    },
                },
                "graph": {
                    "ok": graph.ok,
                    "errors": graph.errors,
                    "output_tail": graph.output_tail,
                    "message": if graph.ok {
                        "el plugin CARGA sin errores en godot headless (grafo completo)"
                    } else {
                        "el plugin FALLA al cargar - SCRIPT ERROR/Parse Error arriba (esto crashea el editor real)"
                    },
                },
                "editor": {
                    "connected": connected,
                    "processes": procs.iter().map(|(pid, cmd)| json!({
                        "pid": pid,
                        "cmdline": cmd,
                    })).collect::<Vec<_>>(),
                    "detected": !procs.is_empty(),
                    "port": ws_port(),
                },
                "remedy": if !graph.ok || stale_count > 0 {
                    "session/open (sync plugin) + session/reopen (recarga editor). Si el grafo sigue roto, el bug esta en addons/heren source."
                } else {
                    ""
                },
            }))
        }
        other => Err(ToolError::invalid_params(format!(
            "unknown session action: {other}"
        ))),
    }
}

/// Lee el puerto WS (default 9099). SIEMPRE cacheado con OnceLock: todas las
/// llamadas del proceso devuelven el mismo puerto (el WS server bindea Y
/// `session/open` lo pasa al editor vÃ­a HEREN_MCP_PORT â€” deben coincidir).
///
/// CRÃTICO multi-sesiÃ³n (fix 2026-08-06): OpenCode lanza un heren-server por
/// sesiÃ³n/chat/agente. Si 9099 ya estÃ¡ tomado por OTRA sesiÃ³n viva, este
/// proceso prueba 9099+1, 9099+2â€¦ hasta encontrar uno libre. NUNCA matamos
/// otros heren-server (kill_previous_servers ELIMINADO: mataba los servers
/// de sesiones OpenCode hermanas â†’ "MCP connection closed" + AbortError).
fn ws_port() -> u16 {
    static PORT: OnceLock<u16> = OnceLock::new();
    *PORT.get_or_init(|| {
        let base = std::env::var("HEREN_WS_ADDR")
            .ok()
            .and_then(|a| a.rsplit(':').next().map(|s| s.to_string()))
            .and_then(|p| p.parse().ok())
            .unwrap_or(9099);
        // HEREN_WS_ADDR explÃ­cito â†’ respetar sin buscar (el usuario lo fijÃ³).
        if std::env::var("HEREN_WS_ADDR").is_ok() {
            return base;
        }
        // Buscar puerto libre partiendo de 9099 (otra sesiÃ³n puede tenerlo).
        for port in base..base + 20 {
            if std::net::TcpListener::bind(("127.0.0.1", port)).is_ok() {
                return port;
            }
        }
        base // todos ocupados: improbable; el bind fallarÃ¡ con error claro
    })
}

// ============================================================
// SCENE
// ============================================================

#[tool(description = "Escenas (v4): get_open_scenes|get_edited_scene_root|open|save|create|unload")]
async fn scene(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    output_path: Option<String>,
    root_type: Option<String>,
    root_name: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let explicit_path = scene_path.clone().map(|p| normalize_scene_path(&p)).unwrap_or_default();
    let scene_path = scene_path.as_deref().map(normalize_scene_path);
    let a = args(&[
        ("scene_path", scene_path.as_deref().map(|s| Value::String(s.to_string()))),
        ("output_path", output_path.map(|p| normalize_scene_path(&p)).map(Value::String)),
        ("root_type", root_type.map(Value::String)),
        ("root_name", root_name.map(Value::String)),
    ]);
    // Contexto de escena: save/open sin scene_path usan el Ãºltimo conocido
    // (registrado por create o por cualquier node/animation/shader op).
    // create NO usa contexto: define un path nuevo (nunca sobreescribir el previo).
    let a = if action == "save" || action == "open" {
        apply_scene_context(&proj, a)
    } else {
        remember_scene_context(&proj, &explicit_path);
        a
    };
    // Regla 1 (persistencia 2026-08-07): "Antes de destruir un Ã¡rbol dirty â†’
    // guardar". scene/open reemplaza la pestaÃ±a (y el Ã¡rbol RAM del registry)
    // por una recarga desde disco; si la escena tiene cambios sin guardar,
    // flush ANTES para no perderlos.
    if action == "open" {
        if let Some(p) = scene_path.as_deref() {
            let dirty = registry.dirty_scenes(&proj).await;
            if dirty.iter().any(|d| d == p) {
                let saved = forward(registry, &proj, "scene/save", json!({"scene_path": p})).await;
                if let Ok(v) = &saved {
                    if v.get("ok").and_then(|o| o.as_bool()).unwrap_or(false) {
                        registry.clean_dirty(&proj, p).await;
                    }
                }
            }
        }
    }
    let result = forward(registry, &proj, &format!("scene/{action}"), a).await?;
    match action.as_str() {
        "save" => {
            // Persistencia 2026-08-07: guardar limpia el dirty de esa escena.
            if let Some(p) = scene_path.as_deref() {
                if result.get("ok").and_then(|o| o.as_bool()).unwrap_or(false) {
                    registry.clean_dirty(&proj, p).await;
                }
            }
        }
        "create" => {
            // create escribe a disco (nunca queda dirty por sÃ­ mismo), pero
            // el registro del SceneRegistry en el plugin marca el contexto.
            remember_scene_context(&proj, &explicit_path);
        }
        _ => {}
    }
    Ok(result)
}

// ============================================================
// NODE
// ============================================================

#[tool(
    description = "Nodos (v4.6): MUTACIONES estructurales â€” add|instantiate|remove|duplicate|rename|move|set_owner|reorder. args: node_path, parent_path, node_type, node_name, instance_path, properties (dict), new_name, new_parent, index. Lecturas y props â†’ node_query / node_props."
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
    properties: Option<Value>,
    new_name: Option<String>,
    new_parent: Option<String>,
    index: Option<i64>,
    parent_path: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("node_path", node_path.map(Value::String)),
            ("node_type", node_type.map(Value::String)),
            ("node_name", node_name.map(Value::String)),
            ("instance_path", instance_path.map(Value::String)),
            ("properties", properties),
            ("new_name", new_name.map(Value::String)),
            ("new_parent", new_parent.map(Value::String)),
            ("index", index.map(|i| json!(i))),
            ("parent_path", parent_path.map(Value::String)),
        ]),
    );
    forward_mutating(registry, &proj, &format!("node/{action}"), a, &scene_path).await
}

#[tool(
    description = "Nodos (v4.6): LECTURAS â€” get_info|get_children|get_prop|find. args: node_path, property_name, recursive (get_children/find), query/by (find: texto o tipo). NO muta la escena."
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
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("node_path", node_path.map(Value::String)),
            ("property_name", property_name.map(Value::String)),
            ("recursive", recursive.map(|v| json!(v))),
            ("query", query.map(Value::String)),
        ]),
    );
    forward(registry, &proj, &format!("node/{action}"), a).await
}

#[tool(
    description = "Nodos (v4.6): PROPIEDADES â€” set_prop|set_props|array_append|array_remove. args: node_path, property_name, value, properties (dict), index (array_remove). Pasa recursos por PATH (res://...) para ext_resource; dict inline â†’ warning."
)]
#[allow(clippy::too_many_arguments)]
async fn node_props(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    node_path: Option<String>,
    property_name: Option<String>,
    value: Option<Value>,
    properties: Option<Value>,
    index: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("node_path", node_path.map(Value::String)),
            ("property_name", property_name.map(Value::String)),
            ("value", value),
            ("properties", properties),
            ("index", index.map(|i| json!(i))),
        ]),
    );
    let mutating = matches!(action.as_str(), "set_prop" | "set_props" | "array_append" | "array_remove");
    if mutating {
        forward_mutating(registry, &proj, &format!("node/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("node/{action}"), a).await
    }
}

// ============================================================
// RESOURCE
// ============================================================

#[tool(
    description = "Recursos .tres y scripts .gd (v4.6): create|read|update|delete|list|create_script|read_script|edit_script. args: resource_path, resource_type, properties (dict), directory, extension, recursive, script_path, content, append, template â€” TODOS opcionales salvo action (defaults en el plugin)."
)]
#[allow(clippy::too_many_arguments)]
async fn resource(
    action: String,
    project_path: Option<String>,
    resource_path: Option<String>,
    resource_type: Option<String>,
    properties: Option<Value>,
    directory: Option<String>,
    extension: Option<String>,
    recursive: Option<bool>,
    script_path: Option<String>,
    content: Option<String>,
    append: Option<bool>,
    template: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("resource_path", resource_path.map(Value::String)),
        ("resource_type", resource_type.map(Value::String)),
        ("properties", properties),
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
    description = "Config proyecto (v4): create|setup_plugin|setting(op=get/set/list/delete/set_multi)|autoload|remove_autoload|input_map(type=add/get/list/add_event/set_events/remove_event/set_deadzone/set_event/remove)|shader_global"
)]
#[allow(clippy::too_many_arguments)]
async fn project(
    action: String,
    project_path: Option<String>,
    op: Option<String>,
    setting_name: Option<String>,
    value: Option<Value>,
    values: Option<Value>,
    prefix: Option<String>,
    autoload_name: Option<String>,
    script_path: Option<String>,
    global_name: Option<String>,
    r#type: Option<String>,
    action_name: Option<String>,
    event: Option<Value>,
    events: Option<Value>,
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

    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("op", op.map(Value::String)),
        ("setting_name", setting_name.map(Value::String)),
        ("value", value),
        ("values", values),
        ("prefix", prefix.map(Value::String)),
        ("autoload_name", autoload_name.map(Value::String)),
        ("script_path", script_path.map(Value::String)),
        ("global_name", global_name.map(Value::String)),
        ("type", r#type.map(Value::String)),
        ("action_name", action_name.map(Value::String)),
        ("event", event),
        ("events", events),
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
        "message": format!(
            "plugin: {install_msg}; [editor_plugins]: {}",
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
    description = "Shaders y materiales (v4.6): create|edit|get|inspect|validate|material|uniform|apply (one-shot). args: shader_path, shader_type, code, append, node_path, material_name, uniforms, uniform_name, value — TODOS opcionales (defaults por action en el plugin)."
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
    node_path: Option<String>,
    material_name: Option<String>,
    uniforms: Option<Value>,
    uniform_name: Option<String>,
    value: Option<Value>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("shader_path", shader_path.map(Value::String)),
            ("shader_type", shader_type.map(Value::String)),
            ("code", code.map(Value::String)),
            ("append", append.map(|v| json!(v))),
            ("node_path", node_path.map(Value::String)),
            ("material_name", material_name.map(Value::String)),
            ("uniforms", uniforms),
            ("uniform_name", uniform_name.map(Value::String)),
            ("value", value),
        ]),
    );
    // Shader: las acciones que ESCRIBEN (create/edit/apply/material/uniform)
    // marcan dirty; las de lectura (get/inspect/validate) no.
    let mutating = matches!(
        action.as_str(),
        "create" | "edit" | "apply" | "material" | "uniform"
    );
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
    description = "Animaciones (v4.6): create_player|create|add_track|add_key|state_machine|play|stop|seek|speed|get_*|remove_*|update_*|one_shot|tween|record|from_path|loop_pose|preview|curve|capture_pose|tree_*|duplicate|delete|rename|reverse|blend_pose|retarget. TODOS los args opcionales â€” el plugin aplica defaults por action (solo `action` es required)."
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
    value: Option<Value>,
    transition: Option<f64>,
    states: Option<Value>,
    transitions: Option<Value>,
    custom_blend: Option<f64>,
    speed: Option<f64>,
    tree_path: Option<String>,
    graph_type: Option<String>,
    parameters: Option<Value>,
    nodes: Option<Value>,
    connections: Option<Value>,
    points: Option<Value>,
    key_idx: Option<i64>,
    loop_mode: Option<String>,
    tracks: Option<Value>,
    duration: Option<f64>,
    to: Option<Value>,
    from: Option<Value>,
    easing: Option<String>,
    fps: Option<f64>,
    path_path: Option<String>,
    amplitude: Option<f64>,
    frequency: Option<f64>,
    axis: Option<String>,
    skeleton_path: Option<String>,
    bone_name: Option<String>,
    transform: Option<Value>,
    ik_name: Option<String>,
    root_bone: Option<String>,
    tip_bone: Option<String>,
    target_path: Option<String>,
    interpolation: Option<f64>,
    max_iterations: Option<i64>,
    override_tip_basis: Option<bool>,
    start: Option<bool>,
    bones: Option<Value>,
    chain: Option<Value>,
    from_bone: Option<String>,
    depth: Option<i64>,
    dim: Option<String>,
    with_image: Option<bool>,
    state: Option<String>,
    name: Option<String>,
    target_position: Option<Value>,
    use_magnet: Option<bool>,
    magnet: Option<Value>,
    influence: Option<f64>,
    min_distance: Option<f64>,
    weights: Option<Value>,
    active: Option<bool>,
    new_name: Option<String>,
    library: Option<String>,
    source_skeleton: Option<String>,
    target_skeleton: Option<String>,
    target_pose: Option<Value>,
    factor: Option<f64>,
    rest: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
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
            ("value", value),
            ("transition", transition.map(|v| json!(v))),
            ("states", states),
            ("transitions", transitions),
            ("custom_blend", custom_blend.map(|v| json!(v))),
            ("speed", speed.map(|v| json!(v))),
            ("tree_path", tree_path.map(Value::String)),
            ("graph_type", graph_type.map(Value::String)),
            ("parameters", parameters),
            ("nodes", nodes),
            ("connections", connections),
            ("points", points),
            ("key_idx", key_idx.map(|v| json!(v))),
            ("loop_mode", loop_mode.map(Value::String)),
            ("tracks", tracks),
            ("duration", duration.map(|v| json!(v))),
            ("to", to),
            ("from", from),
            ("easing", easing.map(Value::String)),
            ("fps", fps.map(|v| json!(v))),
            ("path_path", path_path.map(Value::String)),
            ("amplitude", amplitude.map(|v| json!(v))),
            ("frequency", frequency.map(|v| json!(v))),
            ("axis", axis.map(Value::String)),
            ("skeleton_path", skeleton_path.map(Value::String)),
            ("bone_name", bone_name.map(Value::String)),
            ("transform", transform),
            ("ik_name", ik_name.map(Value::String)),
            ("root_bone", root_bone.map(Value::String)),
            ("tip_bone", tip_bone.map(Value::String)),
            ("target_path", target_path.map(Value::String)),
            ("interpolation", interpolation.map(|v| json!(v))),
            ("max_iterations", max_iterations.map(|v| json!(v))),
            ("override_tip_basis", override_tip_basis.map(|v| json!(v))),
            ("start", start.map(|v| json!(v))),
            ("bones", bones),
            ("chain", chain),
            ("from_bone", from_bone.map(Value::String)),
            ("depth", depth.map(|v| json!(v))),
            ("dim", dim.map(Value::String)),
            ("with_image", with_image.map(|v| json!(v))),
            ("state", state.map(Value::String)),
            ("name", name.map(Value::String)),
            ("target_position", target_position),
            ("use_magnet", use_magnet.map(|v| json!(v))),
            ("magnet", magnet),
            ("influence", influence.map(|v| json!(v))),
            ("min_distance", min_distance.map(|v| json!(v))),
            ("weights", weights),
            ("active", active.map(|v| json!(v))),
            ("new_name", new_name.map(Value::String)),
            ("library", library.map(Value::String)),
            ("source_skeleton", source_skeleton.map(Value::String)),
            ("target_skeleton", target_skeleton.map(Value::String)),
            ("target_pose", target_pose),
            ("factor", factor.map(|v| json!(v))),
            ("rest", rest.map(|v| json!(v))),
        ]),
    );
    // AnimaciÃ³n: las acciones de ESCRITURA marcan dirty (persistencia
    // 2026-08-07); las de lectura (get_*/preview) no mutan el Ã¡rbol.
    let mutating = matches!(
        action.as_str(),
        "create_player" | "create" | "add_track" | "add_key" | "state_machine"
            | "remove_track" | "remove_key" | "update_key" | "update_props" | "one_shot"
            | "record" | "from_path" | "loop_pose" | "capture_pose" | "tree_activate"
            | "tree_travel" | "tree_set_param" | "duplicate" | "delete" | "rename"
            | "reverse" | "blend_pose" | "retarget" | "tween"
    );
    if mutating {
        forward_mutating(registry, &proj, &format!("animation/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("animation/{action}"), a).await
    }
}

// ============================================================
// SKELETON
// ============================================================

#[tool(
    description = "Esqueletos 2D/3D (v4.6): skeleton_create|skeleton_add_bone|skeleton_set_rest|skeleton_skin|skeleton_attachment|skeleton_get_bones|skeleton_get_pose|skeleton_set_pose|skeleton_ik|skeleton_fabrik|capture_pose. TODOS los args opcionales (defaults por action en el plugin)."
)]
#[allow(clippy::too_many_arguments)]
async fn skeleton(
    action: String,
    project_path: Option<String>,
    parent_path: Option<String>,
    skeleton_name: Option<String>,
    is_3d: Option<bool>,
    skeleton_path: Option<String>,
    bone_name: Option<String>,
    rest_transform: Option<Value>,
    length: Option<f64>,
    bone_angle: Option<f64>,
    polygon_path: Option<String>,
    bone_weights: Option<Value>,
    attachment_name: Option<String>,
    transform: Option<Value>,
    ik_name: Option<String>,
    root_bone: Option<String>,
    tip_bone: Option<String>,
    target_path: Option<String>,
    interpolation: Option<f64>,
    max_iterations: Option<i64>,
    override_tip_basis: Option<bool>,
    start: Option<bool>,
    target_position: Option<Value>,
    use_magnet: Option<bool>,
    magnet: Option<Value>,
    influence: Option<f64>,
    min_distance: Option<f64>,
    weights: Option<Value>,
    bones: Option<Value>,
    chain: Option<Value>,
    from_bone: Option<String>,
    depth: Option<i64>,
    compact: Option<bool>,
    context: Option<bool>,
    compare: Option<Value>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("parent_path", parent_path.map(Value::String)),
        ("skeleton_name", skeleton_name.map(Value::String)),
        ("is_3d", is_3d.map(|v| json!(v))),
        ("skeleton_path", skeleton_path.map(Value::String)),
        ("bone_name", bone_name.map(Value::String)),
        ("rest_transform", rest_transform),
        ("length", length.map(|v| json!(v))),
        ("bone_angle", bone_angle.map(|v| json!(v))),
        ("polygon_path", polygon_path.map(Value::String)),
        ("bone_weights", bone_weights),
        ("attachment_name", attachment_name.map(Value::String)),
        ("transform", transform),
        ("ik_name", ik_name.map(Value::String)),
        ("root_bone", root_bone.map(Value::String)),
        ("tip_bone", tip_bone.map(Value::String)),
        ("target_path", target_path.map(Value::String)),
        ("interpolation", interpolation.map(|v| json!(v))),
        ("max_iterations", max_iterations.map(|v| json!(v))),
        ("override_tip_basis", override_tip_basis.map(|v| json!(v))),
        ("start", start.map(|v| json!(v))),
        ("target_position", target_position),
        ("use_magnet", use_magnet.map(|v| json!(v))),
        ("magnet", magnet),
        ("influence", influence.map(|v| json!(v))),
        ("min_distance", min_distance.map(|v| json!(v))),
        ("weights", weights),
        ("bones", bones),
        ("chain", chain),
        ("from_bone", from_bone.map(Value::String)),
        ("depth", depth.map(|v| json!(v))),
        ("compact", compact.map(Value::Bool)),
        ("context", context.map(Value::Bool)),
        ("compare", compare),
    ]);
    forward(registry, &proj, &format!("skeleton/{action}"), a).await
}

// ============================================================
// TILEMAP
// ============================================================

#[tool(description = "TileMaps/TileSets (v4.6): inspect_set|inspect_map|set_cell|terrain|pattern. TODOS los args opcionales (defaults por action).")]
#[allow(clippy::too_many_arguments)]
async fn tilemap(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    tileset_path: Option<String>,
    tilemap_path: Option<String>,
    layer: Option<i64>,
    coords: Option<Value>,
    atlas_coords: Option<Value>,
    source_id: Option<i64>,
    alternative_tile: Option<i64>,
    cells: Option<Value>,
    terrain_set: Option<i64>,
    terrain: Option<i64>,
    region: Option<Value>,
    pattern_name: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("tileset_path", tileset_path.map(Value::String)),
            ("tilemap_path", tilemap_path.map(Value::String)),
            ("layer", layer.map(|v| json!(v))),
            ("coords", coords),
            ("atlas_coords", atlas_coords),
            ("source_id", source_id.map(|v| json!(v))),
            ("alternative_tile", alternative_tile.map(|v| json!(v))),
            ("cells", cells),
            ("terrain_set", terrain_set.map(|v| json!(v))),
            ("terrain", terrain.map(|v| json!(v))),
            ("region", region),
            ("pattern_name", pattern_name.map(Value::String)),
        ]),
    );
    // Tilemap: set_cell/terrain/pattern mutan el mapa (dirty); inspect_* no.
    let mutating = matches!(action.as_str(), "set_cell" | "terrain" | "pattern");
    if mutating {
        forward_mutating(registry, &proj, &format!("tilemap/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("tilemap/{action}"), a).await
    }
}

// ============================================================
// DEBUG
// ============================================================

#[tool(
    description = "DepuraciÃ³n (v4.5): status|breakpoint|control|stack|vars|profiler|run_scene|stop_scene|is_playing|get_editor_errors|output. status=estado del depurador; breakpoint(op=set|clear|list|clear_all,path,line); control(op=pause|continue|step_over|step_into); stack=rastreo de pila al pausar; vars(frame)=variables del frame; profiler(op=start|stop|status|get|clear); get_editor_errors=errores runtime (estructurados + output_errors con formato del panel); output(filter=error|all,limit)=salida del juego en ejecuciÃ³n"
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
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("scene_path", scene_path.as_deref().map(normalize_scene_path).map(Value::String)),
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
    ]);
    forward(registry, &proj, &format!("debug/{action}"), a).await
}

// ============================================================
// VALIDATE
// ============================================================

#[tool(description = "ValidaciÃ³n (v4): scene|script|node|resource")]
async fn validate(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    script_path: Option<String>,
    node_path: Option<String>,
    resource_path: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let a = args(&[
        ("scene_path", scene_path.as_deref().map(normalize_scene_path).map(Value::String)),
        ("script_path", script_path.map(Value::String)),
        ("node_path", node_path.map(Value::String)),
        ("resource_path", resource_path.map(Value::String)),
    ]);
    forward(registry, &proj, &format!("validate/{action}"), a).await
}

// ============================================================
// SIGNAL
// ============================================================

#[tool(description = "SeÃ±ales (v4): connect|disconnect|list|set_script")]
#[allow(clippy::too_many_arguments)]
async fn signal(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    from_node: Option<String>,
    to_node: Option<String>,
    signal_name: Option<String>,
    method: Option<String>,
    node_path: Option<String>,
    script_path: Option<String>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
            ("from_node", from_node.map(Value::String)),
            ("to_node", to_node.map(Value::String)),
            ("signal_name", signal_name.map(Value::String)),
            ("method", method.map(Value::String)),
            ("node_path", node_path.map(Value::String)),
            ("script_path", script_path.map(Value::String)),
        ]),
    );
    // SeÃ±ales: connect/disconnect/set_script mutan el Ã¡rbol (dirty); list no.
    let mutating = matches!(action.as_str(), "connect" | "disconnect" | "set_script");
    if mutating {
        forward_mutating(registry, &proj, &format!("signal/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("signal/{action}"), a).await
    }
}

// ============================================================
// ORCHESTRATE (batch)
// ============================================================

#[tool(
    description = "Orquestar (v4): multiples ops en una llamada. plan: {ops:[{tool,args}]}. tool puede ser node/add (se normaliza a action) o node+args.action. Errores por op en results, no abortan el batch"
)]
async fn orchestrate(
    project_path: Option<String>,
    plan: Option<Value>,
    plan_file: Option<String>,
    on_error: Option<String>,
    _auto_save: Option<bool>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let on_error = on_error.as_deref().unwrap_or("continue");
    let _auto_save = _auto_save.unwrap_or(false);

    // plan puede venir inline (Value) o por archivo (plan_file) â€” la ruta
    // plan_file evita el JSON gigante en el tool-call (dicts anidados).
    let plan_value = if let Some(pf) = plan_file {
        let content = std::fs::read_to_string(&pf)
            .map_err(|e| ToolError::invalid_params(format!("plan_file not readable: {e}")))?;
        serde_json::from_str::<Value>(&content)
            .map_err(|e| ToolError::invalid_params(format!("plan_file invalid JSON: {e}")))?
    } else {
        plan.unwrap_or(Value::Null)
    };

    let ops: Vec<Value> = plan_value
        .get("ops")
        .and_then(|o| o.as_array())
        .cloned()
        .unwrap_or_default();

    if ops.is_empty() {
        return Err(ToolError::invalid_params(
            "plan.ops required (lista de {tool, args})",
        ));
    }

    let mut results = serde_json::Map::new();
    for (i, op) in ops.iter().enumerate() {
        let tool_name_raw = op
            .get("tool")
            .and_then(|t| t.as_str())
            .ok_or_else(|| ToolError::invalid_params(format!("op[{i}] missing 'tool'")))?;
        // Normalizar "tool/action" (API amigable) â†’ tool + args.action.
        // Si el plan usa tool="node" + args.action="add", no se toca nada.
        let mut op_args = op.get("args").cloned().unwrap_or(Value::Null);
        let tool_name = match tool_name_raw.split_once('/') {
            Some((t, act)) => {
                if op_args.is_null() {
                    op_args = json!({});
                }
                if let Some(obj) = op_args.as_object_mut() {
                    obj.entry("action")
                        .or_insert_with(|| Value::String(act.to_string()));
                }
                t.to_string()
            }
            None => tool_name_raw.to_string(),
        };
        // Errores por op (nunca ToolError genÃ©rico que mate el batch sin
        // decir quÃ© op fallÃ³). Se reporta en results y se continÃºa.
        let raw = match registry.call_tool(&tool_name, op_args, &proj).await {
            Ok(r) => r,
            Err(e) => {
                results.insert(
                    i.to_string(),
                    json!({"ok": false, "error": format!("tool_error: {e}")}),
                );
                if on_error == "stop" {
                    break;
                }
                continue;
            }
        };
        let result = unwrap_result(&raw);
        let ok = result.get("ok").and_then(|o| o.as_bool()).unwrap_or(false);
        results.insert(i.to_string(), result);
        if on_error == "stop" && !ok {
            break;
        }
    }

    let count = results.len();
    let errors = results
        .values()
        .filter(|r| !r.get("ok").and_then(|o| o.as_bool()).unwrap_or(false))
        .count();
    Ok(json!({
        "ok": true,
        "results": Value::Object(results),
        "count": count,
        "errors": errors,
    }))
}

// ============================================================
// VISUAL (Sistema de visiÃ³n Â§13.6) â€” UNA tool, mÃºltiples acciones
// (filosofÃ­a centralizada: coords|summary|ascii|capture|node|budget|cache)
// ============================================================

#[tool(
    description = "VisiÃ³n TEXTUAL (v4.6, NIVEL 0-1, sin imagen): coords|summary|ascii. args: scene_path, max_depth (opcional, default 10). Barata ~20-150 tok â€” usarla SIEMPRE primero."
)]
async fn visual_text(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    max_depth: Option<i64>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let handler = match action.as_str() {
        "coords" => "visual/scene_coords",
        "summary" => "visual/scene_summary",
        "ascii" => "visual/scene_ascii",
        other => {
            return Err(ToolError::invalid_params(format!(
                "unknown visual_text action: {other} (coords|summary|ascii)"
            )));
        }
    };
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", scene_path.as_deref().map(normalize_scene_path).map(Value::String)),
            ("max_depth", max_depth.map(|v| json!(v))),
        ]),
    );
    forward(registry, &proj, handler, a).await
}

#[tool(
    description = "VisiÃ³n IMAGEN (v4.6, NIVEL 2-3): capture|node. args: scene_path, viewport=2d|3d (default 2d), source=scene|viewport (default scene), max_side (opcional, resize), node_path (framing), animation (seek previo). Devuelve image_content base64 + metadatos."
)]
#[allow(clippy::too_many_arguments)]
async fn visual_image(
    action: String,
    project_path: Option<String>,
    scene_path: Option<String>,
    viewport: Option<String>,
    source: Option<String>,
    max_side: Option<i64>,
    node_path: Option<String>,
    animation: Option<Value>,
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let handler = match action.as_str() {
        "capture" => "visual/capture",
        "node" => "visual/capture_node",
        other => {
            return Err(ToolError::invalid_params(format!(
                "unknown visual_image action: {other} (capture|node)"
            )));
        }
    };
    let a = apply_scene_context(
        &proj,
        args(&[
            ("scene_path", scene_path.as_deref().map(normalize_scene_path).map(Value::String)),
            ("viewport", viewport.map(Value::String)),
            ("source", source.map(Value::String)),
            ("max_side", max_side.map(|v| json!(v))),
            ("node_path", node_path.map(Value::String)),
            ("animation", animation),
        ]),
    );
    forward(registry, &proj, handler, a).await
}

// ============================================================
// HEALTH
// ============================================================

#[tool(description = "Health check del server y del editor")]
async fn health(project_path: Option<String>) -> Result<Value, ToolError> {
    let registry = EditorRegistry::global();
    let editors = registry.connected_projects().await;
    let project_connected = match project_path.as_deref() {
        Some(p) => registry.has_editor(p).await,
        None => false,
    };
    Ok(json!({
        "ok": true,
        "server": "heren-server (Rust)",
        "version": env!("CARGO_PKG_VERSION"),
        "connected_projects": editors,
        "project_connected": project_connected,
    }))
}

/// Punto de entrada del binario.
pub async fn run() -> Result<(), ServerError> {
    EditorRegistry::init_global();

    // WS plugin server: el EditorPlugin Godot conecta aquÃ­ (patrÃ³n gopeak).
    // Multi-sesiÃ³n (fix 2026-08-06): CADA heren-server de cada sesiÃ³n OpenCode
    // bindea su PROPIO puerto libre (ws_port cachea el mismo para session/open).
    // NO matamos otros heren-server â€” eso asesinaba servers de sesiones
    // hermanas a mitad de operaciÃ³n (MCP connection closed + AbortError).
    let ws_addr = format!("127.0.0.1:{}", ws_port());
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
    // Framing: NDJSON (JSON por lÃ­nea terminado en \n) â€” verificado con stdin-spy:
    // OpenCode 1.18 envÃ­a `{"method":"initialize",...}\n`, NO Content-Length.
    // (`flojo_run_stdio_cl` queda disponible en FlojoMCP para clientes LSP-style.)
    flojo_run_stdio(Heren::new()).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unwrap_result_parses_text_content() {
        let raw = json!({
            "content": [{"type": "text", "text": "{\"ok\":true,\"a\":1}"}],
            "structuredContent": null
        });
        let out = unwrap_result(&raw);
        assert_eq!(out, json!({"ok": true, "a": 1}));
    }

    #[test]
    fn unwrap_result_extracts_image_base64() {
        let raw = json!({
            "content": [{"type": "text", "text": "hi", "__image_base64": "AAAA", "__image_format": "png"}]
        });
        let out = unwrap_result(&raw);
        assert_eq!(out["__image_base64"], "AAAA");
        assert_eq!(out["__image_format"], "png");
    }

    #[test]
    fn unwrap_result_passthrough_non_text() {
        let raw = json!({"raw": [1, 2, 3]});
        assert_eq!(unwrap_result(&raw), raw);
    }

    #[test]
    fn normalize_scene_path_adds_res_prefix() {
        assert_eq!(normalize_scene_path("scenes/level1.tscn"), "res://scenes/level1.tscn");
    }

    #[test]
    fn normalize_scene_path_converts_backslashes() {
        assert_eq!(normalize_scene_path("res:\\scenes\\level1.tscn"), "res://scenes/level1.tscn");
    }

    #[test]
    fn normalize_scene_path_strips_trailing_slash() {
        assert_eq!(normalize_scene_path("res://scenes/level1.tscn/"), "res://scenes/level1.tscn");
    }

    #[test]
    fn normalize_scene_path_keeps_clean() {
        assert_eq!(normalize_scene_path("res://scenes/level1.tscn"), "res://scenes/level1.tscn");
    }

    #[test]
    fn normalize_scene_path_empty_stays_empty() {
        assert_eq!(normalize_scene_path(""), "");
        assert_eq!(normalize_scene_path("   "), "");
    }
}
