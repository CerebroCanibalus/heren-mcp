//! Server discovery — archivo `.heren/server_port.json` para que el editor
//! sepa reconectar al server correcto cuando OpenCode reinicia.
//!
//! Problema (2026-09-03): OpenCode reinicia → nuevo server en puerto nuevo
//! (9099 ocupado → 9100). Editor sigue conectado al viejo (9099) → timeout.
//! Solución: cada server escribe su puerto + PID; el editor lee y reconecta.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Info de un server写入 `.heren/server_port.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerPort {
    pub port: u16,
    pub pid: u32,
}

/// Directorio `.heren` dentro del proyecto (relativo a `res://`).
fn heren_dir(project_root: &Path) -> PathBuf {
    project_root.join(".heren")
}

/// Ruta completa al archivo de discovery.
fn discovery_path(project_root: &Path) -> PathBuf {
    heren_dir(project_root).join("server_port.json")
}

/// Escribe el archivo de discovery con el puerto y PID de este server.
/// Crea `.heren/` si no existe. Falla silencioso si no puede escribir.
pub fn write_discovery(project_root: &Path, port: u16) {
    let dir = heren_dir(project_root);
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("[heren-server] discovery: no se pudo crear {}: {}", dir.display(), e);
        return;
    }
    let info = ServerPort {
        port,
        pid: std::process::id(),
    };
    let path = discovery_path(project_root);
    match serde_json::to_string_pretty(&info) {
        Ok(json) => {
            if let Err(e) = std::fs::write(&path, json) {
                eprintln!("[heren-server] discovery: no se pudo escribir {}: {}", path.display(), e);
            }
        }
        Err(e) => {
            eprintln!("[heren-server] discovery: serialize error: {e}");
        }
    }
}

/// Lee el archivo de discovery. Devuelve None si no existe o es inválido.
pub fn read_discovery(project_root: &Path) -> Option<ServerPort> {
    let path = discovery_path(project_root);
    let data = std::fs::read_to_string(&path).ok()?;
    serde_json::from_str(&data).ok()
}

/// Verifica si un PID está vivo. Usa `tasklist` (Windows) o `kill -0` (Unix).
pub fn is_process_alive(pid: u32) -> bool {
    #[cfg(target_os = "windows")]
    {
        // tasklist /FI "PID eq N" — rápido, nativo, sin dependencias extra.
        let out = std::process::Command::new("tasklist")
            .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
            .output();
        match out {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                // Si la salida contiene el PID, el proceso está vivo.
                stdout.contains(&pid.to_string())
            }
            Err(_) => false,
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        unsafe { libc::kill(pid as i32, 0) == 0 }
    }
}

/// Borra el archivo de discovery (al cerrar el server limpiamente).
pub fn remove_discovery(project_root: &Path) {
    let path = discovery_path(project_root);
    let _ = std::fs::remove_file(path);
}

/// Si el archivo de discovery apunta a un PID que sigue vivo, devuelve el
/// puerto de ese server. Si no (proceso muerto o archivo no existe), devuelve None.
pub fn active_server_port(project_root: &Path) -> Option<u16> {
    let info = read_discovery(project_root)?;
    if is_process_alive(info.pid) {
        Some(info.port)
    } else {
        None
    }
}
