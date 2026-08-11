//! Launcher del editor Godot — port del bridge Python v4 (archivado en `archive/v3`).
//!
//! Auto-launch en `session/open`: encuentra el ejecutable Godot, instala el
//! plugin v4 en el proyecto si falta, lo habilita en project.godot, y lanza
//! `godot --editor --path <proj>` con `HEREN_MCP_PORT` (el plugin conecta al
//! WS server por ese puerto). Reutiliza el editor ya abierto (Q3).

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use tracing::info;

/// Rutas Godot conocidas + candidatos (prioridad: env > PATH > dirs).
const GODOT_CANDIDATES: &[&str] = &[
    "Godot_v4.7.1-stable_win64_console.exe",
    "Godot_v4.7.1-stable_win64.exe",
    "Godot_v4.6.1-stable_win64_console.exe",
    "Godot_v4.6.1-stable_win64.exe",
    "Godot_v4.6-stable_win64_console.exe",
    "Godot_v4.6-stable_win64.exe",
];

const GODOT_DIRS: &[&str] = &[
    r"D:\Mis Juegos\Godot",
    r"C:\Program Files\Godot",
    r"C:\Program Files (x86)\Godot",
];

/// Ruta del plugin (source of truth: heren-mcp/addons/heren).
pub fn plugin_source() -> PathBuf {
    // Se pasa por env HEREN_PLUGIN_SOURCE o default conocido.
    std::env::var("HEREN_PLUGIN_SOURCE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // Fallback: resolver relativo a un par de dirs conocidos.
            let candidates = [
                "D:\\Mis Juegos\\GodotMCP\\heren-mcp\\addons\\heren",
                "D:\\Mis Juegos\\GodotMCP\\heren-mcp\\addons\\heren",
            ];
            candidates
                .iter()
                .map(PathBuf::from)
                .find(|p| p.join("plugin.cfg").exists())
                .unwrap_or_default()
        })
}

/// Resuelve el ejecutable Godot (env GODOT_EXE > GODOT_PATH > PATH > dirs).
pub fn find_godot_executable() -> Option<String> {
    for env in ["GODOT_EXE", "GODOT_PATH"] {
        if let Ok(val) = std::env::var(env) {
            if Path::new(&val).exists() {
                return Some(val);
            }
        }
    }
    // Comprobar en PATH (godot).
    if let Ok(paths) = std::env::var("PATH") {
        for dir in std::env::split_paths(&paths) {
            for cand in GODOT_CANDIDATES {
                let p = dir.join(cand);
                if p.exists() {
                    return Some(p.to_string_lossy().to_string());
                }
            }
        }
    }
    for dir in GODOT_DIRS {
        for cand in GODOT_CANDIDATES {
            let p = Path::new(dir).join(cand);
            if p.exists() {
                return Some(p.to_string_lossy().to_string());
            }
        }
    }
    None
}

/// Copia addons/heren/ al proyecto SIEMPRE (reemplazo completo), aunque ya
/// esté instalado. El plugin SOURCE es la única verdad: cada llamada del
/// install tool / launch_editor sincroniza handlers ACTUALIZADOS. Decisión
/// del General (2026-08-04): NUNCA confiar en "ya está instalado" — el editor
/// puede llevar un plugin obsoleto que rompa la conexión en silencio.
/// Devuelve (instalado, msg).
/// Sincroniza el plugin source → proyecto de forma INCREMENTAL: copia solo
/// archivos que difieren (comparación por contenido) y borra huérfanos del
/// destino (archivos que ya no existen en source). Devuelve (cambió?, msg).
///
/// Antes (v4.3): borraba y recopiaba TODO addons/heren en cada llamada —
/// innecesario entre versiones. Ahora: si nada cambió, no toca disco.
pub fn ensure_plugin_installed(project_path: &str) -> (bool, String) {
    let src = plugin_source();
    if !src.join("plugin.cfg").exists() {
        return (false, "plugin source not found".into());
    }
    let dst = Path::new(project_path).join("addons").join("heren");
    if let Some(parent) = dst.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if !dst.exists() {
        let _ = std::fs::create_dir_all(&dst);
    }

    let src_files = collect_files(&src);
    let mut changed = false;

    // 1. Copiar solo diffs. Fix 2026-08-08: los fallos de copy se REPORTAN en
    // el msg (antes `is_ok()` los tragaba en silencio → "plugin up-to-date"
    // falso con el proyecto roto: core nuevo + handlers viejos → SCRIPT ERROR
    // al cargar → editor crasheaba sin conectar).
    let mut copy_failures: Vec<String> = Vec::new();
    for rel in &src_files {
        let from = src.join(rel);
        let to = dst.join(rel);
        if let Some(p) = to.parent() {
            let _ = std::fs::create_dir_all(p);
        }
        if files_differ(&from, &to) {
            match std::fs::copy(&from, &to) {
                Ok(_) => changed = true,
                Err(e) => copy_failures.push(format!("{}: {e}", rel.display())),
            }
        }
    }

    // 2. Borrar huérfanos del destino (source es la única verdad).
    if let Ok(entries) = std::fs::read_dir(&dst) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_file() {
                let rel = p.strip_prefix(&dst).unwrap_or(&p).to_path_buf();
                if !src_files.contains(&rel) {
                    let _ = std::fs::remove_file(&p);
                    changed = true;
                }
            }
        }
    }

    if !copy_failures.is_empty() {
        (
            changed,
            format!(
                "synced with {} COPY FAILURE(S) — plugin incompleto: {}",
                copy_failures.len(),
                copy_failures.join("; ")
            ),
        )
    } else if changed {
        (
            true,
            format!("synced {} file(s) from {}", src_files.len(), src.display()),
        )
    } else {
        (false, "plugin up-to-date (no changes)".into())
    }
}

/// Lista de archivos relativos bajo `dir` (recursivo).
/// FIX 2026-08-08 (bug raíz del sync roto): la recursión perdía el prefijo de
/// subdirectorio — `collect_files(&p)` hacía `strip_prefix(p)` en vez de
/// `strip_prefix(root)` → `handlers/a.gd` salía como `a.gd` → el sync copiaba
/// contra `src/a.gd` (inexistente) → copy fallaba silencioso → los handlers
/// NUNCA se actualizaban → core nuevo + handlers viejos → SCRIPT ERROR al
/// cargar → editor crasheaba. Ahora `walk` pasa el ROOT original siempre.
fn collect_files(root: &Path) -> Vec<PathBuf> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<PathBuf>) {
        if let Ok(rd) = std::fs::read_dir(dir) {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.is_dir() {
                    walk(root, &p, out);
                } else {
                    out.push(p.strip_prefix(root).unwrap_or(&p).to_path_buf());
                }
            }
        }
    }
    let mut out = Vec::new();
    walk(root, root, &mut out);
    out
}

/// ¿Difieren dos archivos? Comparación por contenido (si falla lectura → true).
fn files_differ(a: &Path, b: &Path) -> bool {
    match (std::fs::read(a), std::fs::read(b)) {
        (Ok(va), Ok(vb)) => va != vb,
        _ => true,
    }
}

/// Lee la versión del plugin instalado en un proyecto (addons/heren/plugin.cfg).
pub fn read_plugin_version(project_path: &str) -> Option<String> {
    read_cfg_version(
        &Path::new(project_path)
            .join("addons")
            .join("heren")
            .join("plugin.cfg"),
    )
}

/// Lee la versión del plugin source (heren-mcp/addons/heren).
pub fn source_plugin_version() -> Option<String> {
    read_cfg_version(&plugin_source().join("plugin.cfg"))
}

fn read_cfg_version(cfg_path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(cfg_path).ok()?;
    for line in text.lines() {
        let t = line.trim();
        if let Some(v) = t.strip_prefix("version=") {
            let v = v.trim().trim_matches('"').trim();
            return Some(v.to_string());
        }
    }
    None
}

/// Añade [editor_plugins] enabled=PackedStringArray(...) a project.godot.
/// IDEMPOTENTE y NORMALIZADORA: reemplaza CUALQUIER línea `enabled=` dentro de
/// la sección [editor_plugins] (vacía `PackedStringArray()`, nombre desnudo
/// `"heren"`, ruta vieja, o duplicadas) por la única línea canónica con la ruta
/// completa. Solo escribe disco si el contenido cambió; verifica post-escritura.
///
/// Sin normalización: un editor vivo que guarde project.godot al salir (or un
/// estado previo `enabled=PackedStringArray()`) dejaría el plugin deshabilitado
/// en silencio, y las líneas duplicadas rompen el parseo de Godot.
///
/// Contrato de retorno (fix 2026-08-08 — bug crítico de auto-launch):
///   - `Ok(true)`  = se escribió (se normalizó/habilitó).
///   - `Ok(false)` = ya estaba correcto (idempotente, NO es un fallo).
///   - `Err(e)`    = fallo REAL (archivo inexistente/ilegible/no escribible).
///
/// Antes devolvía `bool` y `launch_editor` trataba el `false` idempotente como
/// error → con project.godot YA canónico (lo normal tras un editor que guarda),
/// session/open decía "enable_plugin_in_project failed" y NUNCA lanzaba Godot.
/// El workaround empírico era escribir `enabled=PackedStringArray("heren")`
/// para forzar una reescritura → true → lanzar. Ese misterio queda resuelto.
pub fn enable_plugin_in_project(project_path: &str) -> Result<bool, String> {
    let pg = Path::new(project_path).join("project.godot");
    if !pg.exists() {
        return Err(format!("project.godot not found: {}", pg.display()));
    }
    let text = match std::fs::read_to_string(&pg) {
        Ok(t) => t,
        Err(e) => return Err(format!("cannot read project.godot: {e}")),
    };
    let plugin_line = "enabled=PackedStringArray(\"res://addons/heren/plugin.cfg\")";

    let mut out = String::new();
    let mut in_section = false;
    let mut enabled_written = false;
    let mut section_present = false;

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            // Cambio de sección: si acabamos de salir de [editor_plugins] y aún
            // no escribimos enabled, insertarlo aquí (caso: sección vacía).
            if in_section && !enabled_written {
                out.push_str(plugin_line);
                out.push('\n');
                enabled_written = true;
            }
            in_section = trimmed == "[editor_plugins]";
            if in_section {
                section_present = true;
            }
            out.push_str(line);
            out.push('\n');
            continue;
        }
        if in_section && trimmed.starts_with("enabled=") {
            if !enabled_written {
                out.push_str(plugin_line);
                out.push('\n');
                enabled_written = true;
            }
            // Líneas `enabled=` duplicadas se descartan (solo la primera vale).
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }

    // Cierre de sección al final del archivo (o sección inexistente).
    if !enabled_written {
        if !section_present {
            out.push_str("\n[editor_plugins]\n");
        }
        out.push_str(plugin_line);
        out.push('\n');
    }

    // Solo escribir si cambió (no tocar disco innecesariamente).
    if out == text {
        return Ok(false); // ya canónico — éxito idempotente, NO un fallo
    }
    if let Err(e) = std::fs::write(&pg, out) {
        return Err(format!("cannot write project.godot: {e}"));
    }

    // Verificación post-escritura: exactamente 1 línea enabled= con la canónica.
    if let Ok(verify) = std::fs::read_to_string(&pg) {
        let count = verify
            .lines()
            .filter(|l| l.trim().starts_with("enabled="))
            .count();
        let canonical_present = verify.lines().any(|l| l.trim() == plugin_line);
        if canonical_present && count == 1 {
            return Ok(true);
        }
        return Err(format!(
            "post-write verification failed: canonical={canonical_present}, enabled_lines={count}"
        ));
    }
    Err("post-write verification failed: cannot re-read project.godot".into())
}

/// PIDs de procesos Godot editor corriendo para el proyecto (WMI en Windows).
pub fn godot_processes_for(project_path: &str) -> Vec<u32> {
    godot_processes_detailed(project_path)
        .into_iter()
        .map(|(pid, _)| pid)
        .collect()
}

/// Procesos Godot editor del proyecto con su CommandLine (diagnóstico).
pub fn godot_processes_detailed(project_path: &str) -> Vec<(u32, String)> {
    let proj_norm = normalize_cmd_path(project_path);
    let mut procs = Vec::new();
    #[cfg(windows)]
    {
        let out = Command::new("wmic")
            .args([
                "process",
                "where",
                "Name like '%Godot%'",
                "get",
                "ProcessId,CommandLine",
                "/format:csv",
            ])
            .output();
        if let Ok(out) = out {
            let stdout = String::from_utf8_lossy(&out.stdout);
            for line in stdout.lines().skip(1) {
                // CSV de wmic: `Node,CommandLine,ProcessId` →
                // parts[0]=Node, parts[1]=CommandLine, parts[2]=ProcessId.
                let parts: Vec<&str> = line.splitn(3, ',').collect();
                if parts.len() < 3 {
                    continue;
                }
                // Normalizar a forward slashes: la CommandLine de Windows usa
                // backslashes (`D:\proj\project.godot`) pero `proj_norm` es
                // con `/`. Sin esto, el doble clic nunca matcheaba (bug real
                // 2026-08-08: cmd "d:\mis juegos\project_rat\project.godot"
                // no contiene "d:/mis juegos/project_rat").
                let cmd = parts[1].to_lowercase().replace('\\', "/");
                // Editor abierto con doble clic en project.godot NO lleva
                // `--editor` ni `--path` (fix 2026-08-08): la CommandLine es
                // `...Godot.exe "D:\...\project.godot"`. Aceptar también esa
                // forma — el path del proyecto ya filtra por proyecto.
                if !cmd.contains("--editor")
                    && !cmd.contains("--path")
                    && !cmd.contains("project.godot")
                {
                    continue;
                }
                if cmd.contains(&proj_norm) {
                    if let Ok(pid) = parts[2].trim().parse::<u32>() {
                        procs.push((pid, parts[1].to_string()));
                    }
                }
            }
        }
    }
    #[cfg(not(windows))]
    {
        let out = Command::new("pgrep")
            .args(["-f", &format!("--editor.*{proj_norm}")])
            .output();
        if let Ok(out) = out {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                if let Ok(pid) = line.trim().parse::<u32>() {
                    procs.push((pid, format!("pgrep pid {pid}")));
                }
            }
        }
    }
    procs
}

/// ¿Hay editor Godot corriendo para el proyecto?
pub fn is_editor_running(project_path: &str) -> bool {
    !godot_processes_for(project_path).is_empty()
}

/// Resultado estructurado de `launch_editor` — el server lo expone al agente
/// para que sepa si el plugin está al día o necesita `session/reopen`.
pub struct LaunchOutcome {
    pub launched: bool,
    pub msg: String,
    /// ¿El plugin cambió en disco (source vs proyecto) durante este launch?
    pub plugin_changed: bool,
    /// Versión del plugin source (server).
    pub source_version: Option<String>,
    /// Versión del plugin instalado en el proyecto (disco).
    pub installed_version: Option<String>,
}

/// Lanza el editor Godot con el plugin para el proyecto.
///
/// Política "plugin siempre encendido + actualización inteligente":
/// 1. Si un editor del proyecto está CONECTADO al WS y el plugin NO cambió →
///    reutilizarlo, cero trabajo (no relanza).
/// 2. Si está conectado pero el plugin SÍ cambió → NO relanzar (rompería el
///    flujo en marcha): avisar al agente vía `plugin_changed` que ejecute
///    `session/reopen` para recargar el plugin nuevo.
/// 3. Editor zombie (proceso sin conectar) → matarlo PRIMERO, luego escribir
///    plugin+enable (sin editor vivo que pise project.godot) y relanzar limpio.
///
/// El enable solo se escribe en el camino de relanzamiento, nunca sobre un
/// editor vivo — elimina el lost-update de `[editor_plugins]`.
pub fn launch_editor(
    project_path: &str,
    port: u16,
    godot_path: Option<&str>,
    editor_connected: bool,
) -> LaunchOutcome {
    let godot = match godot_path {
        Some(p) if !p.is_empty() => Some(p.to_string()),
        _ => find_godot_executable(),
    };
    let Some(godot) = godot else {
        return LaunchOutcome {
            launched: false,
            msg: "no Godot executable found (set GODOT_EXE)".into(),
            plugin_changed: false,
            source_version: source_plugin_version(),
            installed_version: read_plugin_version(project_path),
        };
    };
    if !Path::new(project_path).exists() {
        return LaunchOutcome {
            launched: false,
            msg: format!("project not found: {project_path}"),
            plugin_changed: false,
            source_version: source_plugin_version(),
            installed_version: read_plugin_version(project_path),
        };
    }

    // Sincronizar plugin (incremental): solo diffs, sin reinstalación total.
    let (plugin_changed, sync_msg) = ensure_plugin_installed(project_path);
    let source_version = source_plugin_version();
    let installed_version = read_plugin_version(project_path);

    // Editor ya conectado → reutilizar. Si el plugin cambió, avisamos que hace
    // falta reopen para recargar el código nuevo (nunca relanzar a medias).
    if editor_connected {
        let msg = if plugin_changed {
            format!(
                "editor already running (connected); PLUGIN ACTUALIZADO en disco \
                 (v{installed} -> v{source}). Ejecuta session/reopen para recargar \
                 el plugin con el código nuevo.",
                installed = installed_version.as_deref().unwrap_or("?"),
                source = source_version.as_deref().unwrap_or("?"),
            )
        } else {
            format!(
                "editor already running (connected); plugin up-to-date v{} ({sync_msg})",
                source_version.as_deref().unwrap_or("?"),
            )
        };
        return LaunchOutcome {
            launched: false,
            msg,
            plugin_changed,
            source_version,
            installed_version,
        };
    }

    // ¿Proceso zombie (corriendo pero sin conectar)? Matarlo ANTES de escribir
    // project.godot — así ningún editor vivo puede pisar el enable.
    if is_editor_running(project_path) {
        info!(
            project_path,
            "editor running but NOT connected; killing zombie before writing plugin config"
        );
        close_editor(project_path);
        std::thread::sleep(std::time::Duration::from_millis(
            crate::constants::EDITOR_KILL_WAIT_MS,
        ));
    }

    // Escribir enable SOLO ahora (editor muerto o inexistente).
    // Ok(false) = ya estaba canónico (éxito idempotente); Err = fallo REAL.
    if let Err(e) = enable_plugin_in_project(project_path) {
        return LaunchOutcome {
            launched: false,
            msg: format!("no editor launched: enable_plugin_in_project failed: {e}"),
            plugin_changed,
            source_version,
            installed_version,
        };
    }
    write_last_project(project_path);

    info!(godot = %godot, project_path, "launching Godot editor");
    let mut cmd = Command::new(&godot);
    cmd.arg("--editor").arg("--path").arg(project_path);
    cmd.env("HEREN_MCP_PORT", port.to_string());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    match cmd.spawn() {
        Ok(_) => LaunchOutcome {
            launched: true,
            msg: format!("launched (plugin synced: {sync_msg})"),
            plugin_changed,
            source_version,
            installed_version,
        },
        Err(e) => LaunchOutcome {
            launched: false,
            msg: format!("launch failed: {e}"),
            plugin_changed,
            source_version,
            installed_version,
        },
    }
}

/// Cierra el editor Godot del proyecto (taskkill).
pub fn close_editor(project_path: &str) -> bool {
    let pids = godot_processes_for(project_path);
    if pids.is_empty() {
        return false;
    }
    for pid in pids {
        #[cfg(windows)]
        {
            let _ = Command::new("taskkill")
                .args(["/F", "/PID", &pid.to_string()])
                .output();
        }
        #[cfg(not(windows))]
        {
            let _ = Command::new("kill").arg("-9").arg(pid.to_string()).output();
        }
    }
    true
}

/// Estado de un archivo del plugin instalado vs source (diagnóstico).
#[derive(Serialize, Clone, Debug)]
pub struct PluginFileStatus {
    pub rel: String,
    /// ok | stale (difiere) | missing | orphan (solo en proyecto)
    pub status: String,
    pub source_size: u64,
    pub installed_size: Option<u64>,
}

/// Compara source vs plugin instalado en el proyecto, archivo por archivo.
/// El Debugger Unificado usa esto: "plugin up-to-date" falso era la causa de
/// plugins a medias (core nuevo + handlers viejos → SCRIPT ERROR al cargar).
pub fn plugin_integrity(project_path: &str) -> Vec<PluginFileStatus> {
    let src = plugin_source();
    let dst = Path::new(project_path).join("addons").join("heren");
    let mut out = Vec::new();
    if !src.join("plugin.cfg").exists() {
        return out;
    }
    let src_files = collect_files(&src);
    for rel in &src_files {
        let from = src.join(rel);
        let to = dst.join(rel);
        let (status, installed_size) = if !to.exists() {
            ("missing".to_string(), None)
        } else if files_differ(&from, &to) {
            (
                "stale".to_string(),
                std::fs::metadata(&to).ok().map(|m| m.len()),
            )
        } else {
            (
                "ok".to_string(),
                std::fs::metadata(&to).ok().map(|m| m.len()),
            )
        };
        out.push(PluginFileStatus {
            rel: rel.to_string_lossy().replace('\\', "/"),
            status,
            source_size: std::fs::metadata(&from).map(|m| m.len()).unwrap_or(0),
            installed_size,
        });
    }
    // Huérfanos: en el proyecto pero no en source (ej: .uid). Recursivo —
    // antes `read_dir` solo miraba el nivel 1 y se perdía handlers/*.uid.
    for rel in collect_files(&dst) {
        if !src_files.contains(&rel) {
            let p = dst.join(&rel);
            out.push(PluginFileStatus {
                rel: rel.to_string_lossy().replace('\\', "/"),
                status: "orphan".to_string(),
                source_size: 0,
                installed_size: std::fs::metadata(&p).ok().map(|m| m.len()),
            });
        }
    }
    out
}

/// Resultado de la validación del grafo del plugin (carga real en Godot).
#[derive(Serialize, Clone)]
pub struct GraphValidation {
    pub ok: bool,
    pub errors: Vec<String>,
    pub output_tail: String,
}

/// Valida que el plugin del proyecto cargue SIN errores en Godot headless:
/// copia addons/heren a un sandbox temp (proyecto mínimo con el plugin
/// habilitado) y ejecuta `godot --headless --editor --quit-after 3`,
/// capturando SCRIPT ERROR / Parse Error del output.
///
/// El sandbox evita tocar el proyecto real y el lock de .godot del editor.
/// Detecta lo que `--check-only` individual NO ve (grafo completo, inferencia
/// de tipos, métodos inexistentes — ej: set_debugger_plugin en handlers viejos).
pub fn validate_plugin_graph(project_path: &str, godot_path: Option<&str>) -> GraphValidation {
    let godot = match godot_path {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => match find_godot_executable() {
            Some(g) => g,
            None => {
                return GraphValidation {
                    ok: false,
                    errors: vec!["no Godot executable found".into()],
                    output_tail: String::new(),
                };
            }
        },
    };
    // Sandbox temp con el plugin del proyecto (lo que el editor REAL cargaría).
    let sandbox = std::env::temp_dir().join(format!("heren_graph_check_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&sandbox);
    let _ = std::fs::create_dir_all(&sandbox);
    let dst_addon = sandbox.join("addons").join("heren");
    let src_addon = Path::new(project_path).join("addons").join("heren");
    for rel in collect_files(&src_addon) {
        let from = src_addon.join(&rel);
        let to = dst_addon.join(&rel);
        if let Some(p) = to.parent() {
            let _ = std::fs::create_dir_all(p);
        }
        let _ = std::fs::copy(&from, &to);
    }
    let project_godot = "config_version=5\n\n[application]\nconfig/name=\"heren_graph_check\"\n\n[editor_plugins]\nenabled=PackedStringArray(\"res://addons/heren/plugin.cfg\")\n";
    let _ = std::fs::write(sandbox.join("project.godot"), project_godot);

    let output = Command::new(&godot)
        .arg("--headless")
        .arg("--editor")
        .arg("--path")
        .arg(&sandbox)
        .arg("--quit-after")
        .arg("3")
        .output();

    let _ = std::fs::remove_dir_all(&sandbox); // limpiar SIEMPRE

    match output {
        Ok(out) => {
            let text = format!(
                "{}{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            let errors: Vec<String> = text
                .lines()
                .filter(|l| {
                    l.contains("SCRIPT ERROR")
                        || l.contains("Parse Error")
                        || l.contains("Invalid call")
                        || l.contains("Nonexistent function")
                        || l.contains("Cannot infer")
                })
                .map(|l| l.trim().to_string())
                .collect();
            let tail: Vec<String> = text.lines().rev().take(10).map(|l| l.to_string()).collect();
            GraphValidation {
                ok: errors.is_empty(),
                errors,
                output_tail: tail.join("\n"),
            }
        }
        Err(e) => GraphValidation {
            ok: false,
            errors: vec![format!("godot run failed: {e}")],
            output_tail: String::new(),
        },
    }
}

/// Ruta del archivo de sesión (.heren/session.json).
pub fn session_file(project_path: &str) -> PathBuf {
    Path::new(project_path).join(".heren").join("session.json")
}

/// Lee last_project (1 clave, ADR-004).
pub fn read_last_project(project_path: &str) -> Option<String> {
    let f = session_file(project_path);
    let text = std::fs::read_to_string(f).ok()?;
    let v: serde_json::Value = serde_json::from_str(&text).ok()?;
    v.get("last_project")
        .and_then(|p| p.as_str())
        .map(|s| s.to_string())
}

/// Escribe last_project (1 clave, ADR-004).
pub fn write_last_project(project_path: &str) {
    let f = session_file(project_path);
    if let Some(parent) = f.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let v = serde_json::json!({ "last_project": normalize_cmd_path(project_path) });
    let _ = std::fs::write(f, serde_json::to_string_pretty(&v).unwrap_or_default());
}

/// Normaliza una ruta para comparar en cmdline (forward slashes, sin trailing).
fn normalize_cmd_path(p: &str) -> String {
    p.replace('\\', "/").trim_end_matches('/').to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_cmd_path_slashes_trailing() {
        assert_eq!(normalize_cmd_path(r"D:\proj\"), "d:/proj");
        assert_eq!(normalize_cmd_path("D:/proj"), "d:/proj");
        assert_eq!(
            normalize_cmd_path(r"D:\proj"),
            normalize_cmd_path("D:/proj/")
        );
    }

    /// El CSV real de wmic es `Node,CommandLine,ProcessId`. El parser debe
    /// tomar la CommandLine (parts[1]) y el PID (parts[2]) — no al revés.
    /// Bug 2026-08-04: índices invertidos → godot_processes_for() siempre
    /// vacío → session/open lanzaba un editor duplicado con el original abierto.
    #[test]
    fn wmic_csv_parse_extracts_pid() {
        let line = r#"DESKTOP-C36BCKD,"D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64.exe" --editor --path "D:/Mis Juegos/project_rat",15884"#;
        let parts: Vec<&str> = line.splitn(3, ',').collect();
        assert_eq!(parts.len(), 3, "debe haber Node,CommandLine,ProcessId");
        let cmd = parts[1].to_lowercase();
        assert!(
            cmd.contains("--editor"),
            "CommandLine debe contener --editor"
        );
        assert!(
            cmd.contains("d:/mis juegos/project_rat"),
            "CommandLine debe contener el path del proyecto"
        );
        let pid: u32 = parts[2].trim().parse().expect("PID debe parsear a u32");
        assert_eq!(pid, 15884);
    }

    /// Un editor ya abierto para el proyecto debe detectarse (no duplicar).
    #[test]
    fn wmic_csv_editor_detected_for_project() {
        let line = r#"DESKTOP-C36BCKD,"D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64.exe" --editor --path "D:/Mis Juegos/project_rat",15884"#;
        let proj_norm = normalize_cmd_path(r"D:\Mis Juegos\project_rat");
        let parts: Vec<&str> = line.splitn(3, ',').collect();
        let cmd = parts[1].to_lowercase();
        assert!(
            cmd.contains(&proj_norm),
            "cmd {cmd} debe contener {proj_norm}"
        );
    }

    /// Editor abierto con DOBLE CLIC en project.godot — CommandLine SIN
    /// `--editor` ni `--path`. Bug 2026-08-08: se descartaba → session/open no
    /// detectaba el editor que el usuario abrió manualmente → lanzaba duplicado
    /// o "no editor connected". Ahora `project.godot` en la cmdline basta, y
    /// los backslashes de Windows se normalizan a `/` (la CommandLine real usa
    /// `D:\proj\project.godot`, y proj_norm es `d:/proj`).
    #[test]
    fn wmic_csv_editor_detected_via_project_dot_godot() {
        let line = r#"DESKTOP-C36BCKD,"D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64.exe" "D:\Mis Juegos\project_rat\project.godot",16200"#;
        let proj_norm = normalize_cmd_path(r"D:\Mis Juegos\project_rat");
        let parts: Vec<&str> = line.splitn(3, ',').collect();
        assert_eq!(parts.len(), 3);
        let cmd = parts[1].to_lowercase().replace('\\', "/");
        assert!(
            !cmd.contains("--editor") && !cmd.contains("--path"),
            "caso real: doble clic NO lleva --editor ni --path"
        );
        assert!(
            cmd.contains("project.godot"),
            "cmd {cmd} debe contener project.godot"
        );
        assert!(
            cmd.contains(&proj_norm),
            "cmd {cmd} debe contener {proj_norm} (backslashes normalizados)"
        );
        // El filtro del proceso debe aceptar esta línea.
        let is_editor_of_proj = cmd.contains("project.godot") && cmd.contains(&proj_norm);
        assert!(
            is_editor_of_proj,
            "debe detectarse como editor del proyecto"
        );
        let pid: u32 = parts[2].trim().parse().expect("PID debe parsear a u32");
        assert_eq!(pid, 16200);
    }

    /// BUG RAÍZ del sync roto (2026-08-08): `collect_files` recursivo perdía
    /// el prefijo de subdirectorio → `handlers/a.gd` salía como `a.gd` → el
    /// sync copiaba contra rutas inexistentes y fallaba SILENCIOSO → los
    /// handlers nunca se actualizaban → core nuevo + handlers viejos.
    #[test]
    fn collect_files_preserves_subdir_prefix() {
        let dir = std::env::temp_dir().join("heren_collect");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("handlers")).unwrap();
        std::fs::write(dir.join("plugin.cfg"), "x").unwrap();
        std::fs::write(dir.join("handlers").join("a.gd"), "x").unwrap();
        std::fs::write(dir.join("handlers").join("b.gd"), "x").unwrap();
        let files = collect_files(&dir);
        assert!(
            files.contains(&PathBuf::from("plugin.cfg")),
            "raiz: {files:?}"
        );
        assert!(
            files.contains(&PathBuf::from("handlers").join("a.gd")),
            "handler con prefijo handlers/: {files:?}"
        );
        assert!(
            files.contains(&PathBuf::from("handlers").join("b.gd")),
            "handler con prefijo handlers/: {files:?}"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    const CANONICAL: &str = "enabled=PackedStringArray(\"res://addons/heren/plugin.cfg\")";

    fn write_project(dir: &std::path::Path, content: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("project.godot"), content).unwrap();
    }

    fn read_enabled_lines(dir: &std::path::Path) -> Vec<String> {
        let text = std::fs::read_to_string(dir.join("project.godot")).unwrap();
        text.lines()
            .filter(|l| l.trim().starts_with("enabled="))
            .map(|l| l.trim().to_string())
            .collect()
    }

    /// Bug: `enabled=PackedStringArray()` (editor vivo guardó al salir sin plugin).
    /// Debe normalizarse a la línea canónica — 1 sola línea, sin duplicar.
    #[test]
    fn enable_normalizes_empty_array() {
        let dir = std::env::temp_dir().join("heren_enable_empty");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            "[application]\nconfig/name=\"test\"\n\n[editor_plugins]\nenabled=PackedStringArray()\n",
        );
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(matches!(result, Ok(true)), "debe escribir: {result:?}");
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1, "exactamente 1 línea enabled: {lines:?}");
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Fix manual previo dejó `enabled=PackedStringArray("heren")` (nombre desnudo).
    /// Debe normalizarse a la ruta completa — sin duplicar.
    #[test]
    fn enable_normalizes_bare_name() {
        let dir = std::env::temp_dir().join("heren_enable_bare");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            "[application]\nconfig/name=\"test\"\n\n[editor_plugins]\nenabled=PackedStringArray(\"heren\")\n",
        );
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(matches!(result, Ok(true)), "debe escribir: {result:?}");
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1, "exactamente 1 línea enabled: {lines:?}");
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Duplicadas (ruta + nombre) — la normalización debe colapsarlas a 1.
    #[test]
    fn enable_collapses_duplicates() {
        let dir = std::env::temp_dir().join("heren_enable_dup");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            "[application]\nconfig/name=\"test\"\n\n[editor_plugins]\nenabled=PackedStringArray(\"res://addons/heren/plugin.cfg\")\nenabled=PackedStringArray(\"heren\")\n",
        );
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(matches!(result, Ok(true)), "debe escribir: {result:?}");
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1, "exactamente 1 línea enabled: {lines:?}");
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Sin sección [editor_plugins] — debe crearla con la línea canónica.
    #[test]
    fn enable_creates_section_when_missing() {
        let dir = std::env::temp_dir().join("heren_enable_nosect");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(&dir, "[application]\nconfig/name=\"test\"\n");
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(matches!(result, Ok(true)), "debe escribir: {result:?}");
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1, "exactamente 1 línea enabled: {lines:?}");
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Idempotencia: ya canónico → NO debe escribir, pero devolver Ok(false)
    /// (éxito), NUNCA Err. Bug 2026-08-08: el `false` idempotente se trataba
    /// como fallo y session/open no lanzaba el editor.
    #[test]
    fn enable_is_idempotent_when_canonical() {
        let dir = std::env::temp_dir().join("heren_enable_idem");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            &format!("[application]\nconfig/name=\"test\"\n\n[editor_plugins]\n{CANONICAL}\n"),
        );
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(
            matches!(result, Ok(false)),
            "ya canónico = Ok(false), NO Err: {result:?}"
        );
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// La sección [editor_plugins] vacía (sin línea enabled) → añadir dentro,
    /// NO crear una segunda sección duplicada al final.
    #[test]
    fn enable_adds_line_inside_existing_empty_section() {
        let dir = std::env::temp_dir().join("heren_enable_empty_section");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            "[application]\nconfig/name=\"test\"\n\n[editor_plugins]\n\n[application]\nconfig/version=\"1\"\n",
        );
        let result = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(matches!(result, Ok(true)), "debe escribir: {result:?}");
        let text = std::fs::read_to_string(dir.join("project.godot")).unwrap();
        assert_eq!(
            text.matches("[editor_plugins]").count(),
            1,
            "solo 1 sección editor_plugins, no duplicada"
        );
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Launcher NO debe abortar cuando el plugin YA está habilitado (Ok(false)).
    /// Bug 2026-08-08: `launch_editor` trataba el false idempotente como fallo
    /// → session/open decía "enable_plugin_in_project failed" con el plugin
    /// perfectamente habilitado → auto-launch roto en proyectos ya canónicos.
    #[test]
    fn enable_error_is_real_failure_not_idempotent() {
        let dir = std::env::temp_dir().join("heren_enable_missing");
        let _ = std::fs::remove_dir_all(&dir);
        // Proyecto inexistente → Err real (no Ok(false)).
        let result = enable_plugin_in_project(&dir.join("nope").to_string_lossy());
        assert!(
            result.is_err(),
            "proyecto inexistente = Err real: {result:?}"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Debugger unificado: `plugin_integrity` debe detectar archivos stale
    /// (mezcla tóxica core-nuevo + handlers-viejos que crashea el editor).
    /// Usa el SOURCE real (plugin_source default) como referencia y un
    /// proyecto fake con los mismos archivos: plugin.cfg ok + handler stale.
    #[test]
    fn integrity_detects_stale_and_orphan() {
        let src = plugin_source();
        if !src.join("plugin.cfg").exists() {
            eprintln!("skip: plugin source no disponible");
            return;
        }
        let proj = std::env::temp_dir().join("heren_int_proj");
        let _ = std::fs::remove_dir_all(&proj);
        std::fs::create_dir_all(proj.join("addons").join("heren").join("handlers")).unwrap();
        // Copiar TODO el source al proyecto fake (idéntico → todo "ok").
        let mut copy_errs: Vec<String> = Vec::new();
        for rel in collect_files(&src) {
            let from = src.join(&rel);
            let to = proj.join("addons").join("heren").join(&rel);
            if let Some(p) = to.parent() {
                let _ = std::fs::create_dir_all(p);
            }
            if let Err(e) = std::fs::copy(&from, &to) {
                copy_errs.push(format!("{}: {e}", rel.display()));
            }
        }
        assert!(
            copy_errs.is_empty(),
            "copiar source al fake no debe fallar: {copy_errs:?}"
        );
        // Corromper 1 handler (como project_rat: core nuevo + handler viejo).
        std::fs::write(
            proj.join("addons")
                .join("heren")
                .join("handlers")
                .join("debug_handlers.gd"),
            "func old_api() -> void:\n\tpass\n",
        )
        .unwrap();
        // Orphan: archivo que no existe en source.
        std::fs::write(
            proj.join("addons")
                .join("heren")
                .join("handlers")
                .join("ghost.gd.uid"),
            "uid://x",
        )
        .unwrap();

        let report = plugin_integrity(proj.to_str().unwrap());
        let plugin_cfg = report.iter().find(|f| f.rel == "plugin.cfg");
        assert!(
            matches!(plugin_cfg.map(|f| f.status.as_str()), Some("ok")),
            "plugin.cfg debe estar ok: {report:?}"
        );
        let dbg = report
            .iter()
            .find(|f| f.rel == "handlers/debug_handlers.gd");
        assert!(
            matches!(dbg.map(|f| f.status.as_str()), Some("stale")),
            "debug_handlers.gd debe estar stale (mezcla toxica): {report:?}"
        );
        let ghost = report.iter().find(|f| f.rel == "handlers/ghost.gd.uid");
        assert!(
            matches!(ghost.map(|f| f.status.as_str()), Some("orphan")),
            "ghost.gd.uid debe ser orphan: {report:?}"
        );
        let _ = std::fs::remove_dir_all(&proj);
    }
}
