//! Launcher del editor Godot — port de `src/heren/v4/godot_launcher.py`.
//!
//! Auto-launch en `session/open`: encuentra el ejecutable Godot, instala el
//! plugin v4 en el proyecto si falta, lo habilita en project.godot, y lanza
//! `godot --editor --path <proj>` con `HEREN_MCP_PORT` (el plugin conecta al
//! WS server por ese puerto). Reutiliza el editor ya abierto (Q3).

use std::path::{Path, PathBuf};
use std::process::Command;

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

    // 1. Copiar solo diffs.
    for rel in &src_files {
        let from = src.join(rel);
        let to = dst.join(rel);
        if let Some(p) = to.parent() {
            let _ = std::fs::create_dir_all(p);
        }
        if files_differ(&from, &to) && std::fs::copy(&from, &to).is_ok() {
            changed = true;
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

    if changed {
        (true, format!("synced {} file(s) from {}", src_files.len(), src.display()))
    } else {
        (false, "plugin up-to-date (no changes)".into())
    }
}

/// Lista de archivos relativos bajo `dir` (recursivo).
fn collect_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = std::fs::read_dir(dir) {
        for entry in rd.flatten() {
            let p = entry.path();
            if p.is_dir() {
                out.extend(collect_files(&p));
            } else {
                out.push(p.strip_prefix(dir).unwrap_or(&p).to_path_buf());
            }
        }
    }
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
    read_cfg_version(&Path::new(project_path).join("addons").join("heren").join("plugin.cfg"))
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
/// Sin normalización: un editor vivo que guarde project.godot al salir (o un
/// estado previo `enabled=PackedStringArray()`) dejaría el plugin deshabilitado
/// en silencio, y las líneas duplicadas rompen el parseo de Godot.
pub fn enable_plugin_in_project(project_path: &str) -> bool {
    let pg = Path::new(project_path).join("project.godot");
    if !pg.exists() {
        return false;
    }
    let text = match std::fs::read_to_string(&pg) {
        Ok(t) => t,
        Err(_) => return false,
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
        return false;
    }
    if std::fs::write(&pg, out).is_err() {
        return false;
    }

    // Verificación post-escritura: exactamente 1 línea enabled= con la canónica.
    if let Ok(verify) = std::fs::read_to_string(&pg) {
        let count = verify
            .lines()
            .filter(|l| l.trim().starts_with("enabled="))
            .count();
        let canonical_present = verify.lines().any(|l| l.trim() == plugin_line);
        return canonical_present && count == 1;
    }
    false
}

/// PIDs de procesos Godot editor corriendo para el proyecto (WMI en Windows).
pub fn godot_processes_for(project_path: &str) -> Vec<u32> {
    let proj_norm = normalize_cmd_path(project_path);
    let mut pids = Vec::new();
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
                let cmd = parts[1].to_lowercase();
                if !cmd.contains("--editor") && !cmd.contains("--path") {
                    continue;
                }
                if cmd.contains(&proj_norm) {
                    if let Ok(pid) = parts[2].trim().parse::<u32>() {
                        pids.push(pid);
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
                    pids.push(pid);
                }
            }
        }
    }
    pids
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
        std::thread::sleep(std::time::Duration::from_millis(1500));
    }

    // Escribir enable SOLO ahora (editor muerto o inexistente).
    let enabled = enable_plugin_in_project(project_path);
    write_last_project(project_path);

    if !enabled {
        return LaunchOutcome {
            launched: false,
            msg: "no editor launched: enable_plugin_in_project failed (project.godot no escrito correctamente)".into(),
            plugin_changed,
            source_version,
            installed_version,
        };
    }

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
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(changed, "debe escribir (estado vacío → canónico)");
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
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(changed, "debe escribir (nombre desnudo → ruta completa)");
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
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(changed, "debe escribir (duplicadas → 1 canónica)");
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
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(changed, "debe escribir (sección ausente)");
        let lines = read_enabled_lines(&dir);
        assert_eq!(lines.len(), 1, "exactamente 1 línea enabled: {lines:?}");
        assert_eq!(lines[0], CANONICAL);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Idempotencia: ya canónico → NO debe escribir (return false).
    #[test]
    fn enable_is_idempotent_when_canonical() {
        let dir = std::env::temp_dir().join("heren_enable_idem");
        let _ = std::fs::remove_dir_all(&dir);
        write_project(
            &dir,
            &format!(
                "[application]\nconfig/name=\"test\"\n\n[editor_plugins]\n{CANONICAL}\n"
            ),
        );
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(!changed, "no debe escribir si ya está canónico");
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
        let changed = enable_plugin_in_project(dir.to_str().unwrap());
        assert!(changed);
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
}
