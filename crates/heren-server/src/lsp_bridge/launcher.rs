//! Auto-launcher de Godot para servir LSP.
//!
//! Lanza Godot en modo **headless liviano** cuando nadie escucha en el puerto
//! LSP. Configuración mínima de recursos:
//!
//! - `--headless` → no display, no renderer GPU.
//! - `--audio-driver Dummy` → sin audio.
//! - `--editor` → necesario porque el LSP nativo de Godot SOLO corre dentro
//!   del editor (no es un binario standalone; ver MasuRii/opencode-godot-lsp
//!   y godot-proposals #7558).
//! - stdin/stdout/stderr a `Stdio::null()` para no contaminar logs.
//!
//! ## Pre-requisito: `project.godot` debe tener LSP habilitado
//!
//! El LSP nativo de Godot **no arranca** aunque le pasemos `--lsp-port` si el
//! `project.godot` no tiene `[network] language_server/enabled=true`. El bridge
//! **NO modifica** el `project.godot` del usuario (decisión conservadora — el
//! setup.md documenta la activación, y un flag `--enable-lsp-in-project` puede
//! añadirse en el futuro si el flujo lo demanda).

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use thiserror::Error;
use tokio::net::TcpStream;

#[derive(Debug, Error)]
pub enum LauncherError {
    #[error("godot executable not found; pass --godot-path or set GODOT_PATH")]
    GodotNotFound,

    #[error("project.godot not found at {0}")]
    ProjectNotFound(PathBuf),

    #[error(
        "no project.godot found starting from {0} (and no --project-path given); \
         pass --project-path <DIR> to specify one"
    )]
    NoProjectFound(PathBuf),

    #[error(
        "LSP not enabled in project.godot; add to [network] section:\n  \
         language_server/enabled=true\n  \
         language_server/port=6005"
    )]
    LspNotEnabled,

    #[error("LSP did not become ready on {host}:{port} within {timeout_ms}ms")]
    Timeout {
        host: String,
        port: u16,
        timeout_ms: u64,
    },

    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

/// Busca `project.godot` empezando en `start` y subiendo hasta `max_depth` directorios.
/// Devuelve el directorio que contiene `project.godot` (no el archivo).
pub fn find_project_godot(start: &Path, max_depth: u32) -> Option<PathBuf> {
    let mut current: Option<&Path> = Some(start);
    let mut depth: u32 = 0;
    while let Some(dir) = current {
        if dir.join("project.godot").is_file() {
            return Some(dir.to_path_buf());
        }
        if depth >= max_depth {
            return None;
        }
        depth += 1;
        current = dir.parent();
    }
    None
}

/// Config del launcher (subset de `BridgeConfig` que afecta el spawn).
#[derive(Debug, Clone)]
pub struct LaunchConfig {
    pub godot_path: Option<PathBuf>,
    pub project_path: PathBuf,
    pub lsp_port: u16,
    pub launch_timeout_ms: u64,
}

/// Lanza Godot headless liviano y espera a que el puerto LSP esté abierto.
pub struct AutoLauncher;

impl AutoLauncher {
    /// Resuelve path a godot por orden de precedencia:
    /// 1. `--godot-path` (flag CLI)
    /// 2. `GODOT_PATH` (env var)
    /// 3. Búsqueda en `PATH`
    /// 4. Paths estándar de instalación (Windows: `C:/Program Files/Godot/`)
    pub fn resolve_godot(override_path: Option<&Path>) -> Option<PathBuf> {
        if let Some(p) = override_path {
            return Some(p.to_path_buf());
        }
        if let Ok(p) = std::env::var("GODOT_PATH") {
            return Some(PathBuf::from(p));
        }
        which_godot()
    }

    /// Verifica que el proyecto existe y tiene LSP habilitado.
    pub async fn verify_project(project: &Path) -> Result<(), LauncherError> {
        let project_godot = project.join("project.godot");
        if !project_godot.exists() {
            return Err(LauncherError::ProjectNotFound(project_godot));
        }
        let content = tokio::fs::read_to_string(&project_godot).await?;
        if !has_lsp_enabled(&content) {
            return Err(LauncherError::LspNotEnabled);
        }
        Ok(())
    }

    /// Spawn Godot headless y espera conexión al puerto LSP. Devuelve el handle
    /// del child para poder matarlo al shutdown.
    pub async fn launch_and_wait(
        cfg: &LaunchConfig,
    ) -> Result<(Child, TcpStream), LauncherError> {
        let godot = Self::resolve_godot(cfg.godot_path.as_deref())
            .ok_or(LauncherError::GodotNotFound)?;
        Self::verify_project(&cfg.project_path).await?;

        let child = Self::spawn_lightweight(&godot, &cfg.project_path, cfg.lsp_port)?;

        let stream = wait_for_lsp_port(
            "127.0.0.1",
            cfg.lsp_port,
            Duration::from_millis(cfg.launch_timeout_ms),
        )
        .await?;

        Ok((child, stream))
    }

    fn spawn_lightweight(
        godot: &Path,
        project: &Path,
        lsp_port: u16,
    ) -> Result<Child, LauncherError> {
        let cmd = Command::new(godot)
            .arg("--editor")
            .arg("--headless")
            .arg("--audio-driver")
            .arg("Dummy")
            .arg(format!("--lsp-port={lsp_port}"))
            .arg("--path")
            .arg(project)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        Ok(cmd)
    }
}

/// Espera conexión al puerto LSP con backoff exponencial (250ms → 2s, cap).
async fn wait_for_lsp_port(
    host: &str,
    port: u16,
    timeout: Duration,
) -> Result<TcpStream, LauncherError> {
    let deadline = Instant::now() + timeout;
    let mut delay = Duration::from_millis(250);
    loop {
        if Instant::now() >= deadline {
            return Err(LauncherError::Timeout {
                host: host.to_string(),
                port,
                timeout_ms: u64::try_from(timeout.as_millis()).unwrap_or(u64::MAX),
            });
        }
        if let Ok(Ok(stream)) =
            tokio::time::timeout(Duration::from_millis(500), TcpStream::connect((host, port)))
                .await
        {
            return Ok(stream);
        }
        tokio::time::sleep(delay).await;
        delay = (delay * 2).min(Duration::from_millis(2000));
    }
}

/// Parser tolerante de `project.godot` para detectar LSP habilitado.
/// Formato Godot 4:
/// ```ini
/// [application]
/// config/name="..."
/// [network]
/// language_server/enabled=true
/// language_server/port=6005
/// ```
fn has_lsp_enabled(content: &str) -> bool {
    let mut in_network = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            in_network = trimmed.eq_ignore_ascii_case("[network]");
            continue;
        }
        if !in_network {
            continue;
        }
        // líneas `language_server/enabled=true` o `language_server/enabled = true`
        // (case-insensitive en key y value, tolerante a espacios).
        let normalized = trimmed
            .split_whitespace()
            .collect::<Vec<_>>()
            .join("")
            .to_ascii_lowercase();
        if let Some(value) = normalized.strip_prefix("language_server/enabled=") {
            return value == "true" || value == "1";
        }
    }
    false
}

// ============================================================================
// Búsqueda de godot en PATH/registro (sin dep externa `which`).
// ============================================================================

#[cfg(target_os = "windows")]
fn which_godot() -> Option<PathBuf> {
    // Candidatos declarados al inicio (clippy::items_after_statements).
    const EXACT_CANDIDATES: &[&str] = &[
        r"C:\Program Files\Godot\godot.exe",
        r"C:\Program Files (x86)\Godot\godot.exe",
        r"C:\Godot\godot.exe",
        r"D:\Godot\godot.exe",
        r"D:\Mis Juegos\Godot\godot.exe",
        r"D:\Mis Juegos\Godot_v4.7.1-stable_win64.exe",
    ];
    const SCAN_DIRS: &[&str] = &[r"D:\Mis Juegos", r"D:\Godot", r"C:\Godot"];
    // Orden de búsqueda:
    //   1. PATH (godot.exe)
    //   2. Rutas absolutas comunes de instalación
    //   3. Scan recursivo en D:\Mis Juegos, D:\Godot, C:\Godot
    if let Some(p) = find_in_path("godot.exe") {
        return Some(p);
    }
    for c in EXACT_CANDIDATES {
        let p = PathBuf::from(c);
        if p.is_file() {
            return Some(p);
        }
    }
    for dir in SCAN_DIRS {
        if let Some(p) = find_godot_under(Path::new(dir), 3) {
            return Some(p);
        }
    }
    None
}

/// Busca recursivamente un godot*.exe en `dir` hasta `max_depth` niveles.
/// Heurística: matchea `Godot*win64.exe` o `Godot*.exe`.
#[cfg(target_os = "windows")]
fn find_godot_under(dir: &Path, max_depth: u32) -> Option<PathBuf> {
    use std::fs;
    fn helper(dir: &Path, depth: u32, max_depth: u32) -> Option<PathBuf> {
        if depth > max_depth {
            return None;
        }
        let Ok(entries) = fs::read_dir(dir) else {
            return None;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = match entry.file_name().to_str() {
                Some(n) => n.to_string(),
                None => continue,
            };
            if path.is_file()
                && (name.to_ascii_lowercase().starts_with("godot")
                    || name.contains("Godot_v"))
                && name.to_ascii_lowercase().ends_with(".exe")
            {
                return Some(path);
            }
            if path.is_dir() && depth < max_depth {
                if let Some(found) = helper(&path, depth + 1, max_depth) {
                    return Some(found);
                }
            }
        }
        None
    }
    helper(dir, 0, max_depth)
}

#[cfg(not(target_os = "windows"))]
fn which_godot() -> Option<PathBuf> {
    find_in_path("godot")
}

fn find_in_path(cmd: &str) -> Option<PathBuf> {
    let path_var = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path_var) {
        let candidate = dir.join(cmd);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

// ============================================================================
// Tests unitarios.
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn has_lsp_enabled_simple() {
        let content = "[application]\nname=x\n[network]\nlanguage_server/enabled=true\n";
        assert!(has_lsp_enabled(content));
    }

    #[test]
    fn has_lsp_enabled_with_spaces() {
        let content = "[network]\nlanguage_server/enabled = true\n";
        assert!(has_lsp_enabled(content));
    }

    #[test]
    fn has_lsp_enabled_section_case_insensitive() {
        let content = "[NETWORK]\nLanguage_Server/Enabled=true\n";
        assert!(has_lsp_enabled(content));
    }

    #[test]
    fn has_lsp_enabled_missing() {
        let content = "[application]\nname=x\n[network]\nport=6005\n";
        assert!(!has_lsp_enabled(content));
    }

    #[test]
    fn has_lsp_enabled_wrong_section() {
        let content = "[debug]\nlanguage_server/enabled=true\n";
        // Está en [debug], NO en [network] → falso.
        assert!(!has_lsp_enabled(content));
    }

    #[test]
    fn has_lsp_enabled_explicit_false() {
        let content = "[network]\nlanguage_server/enabled=false\n";
        assert!(!has_lsp_enabled(content));
    }

    #[tokio::test]
    async fn verify_project_missing() {
        let tmp = std::env::temp_dir().join("heren_lsp_bridge_verify_missing");
        let _ = std::fs::remove_dir_all(&tmp);
        let err = AutoLauncher::verify_project(&tmp).await.unwrap_err();
        assert!(matches!(err, LauncherError::ProjectNotFound(_)));
    }

    #[tokio::test]
    async fn verify_project_lsp_not_enabled() {
        let tmp = std::env::temp_dir().join("heren_lsp_bridge_verify_no_lsp");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::write(tmp.join("project.godot"), "[application]\nname=test\n").unwrap();
        let err = AutoLauncher::verify_project(&tmp).await.unwrap_err();
        assert!(matches!(err, LauncherError::LspNotEnabled));
    }

    #[tokio::test]
    async fn verify_project_ok() {
        let tmp = std::env::temp_dir().join("heren_lsp_bridge_verify_ok");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::write(
            tmp.join("project.godot"),
            "[network]\nlanguage_server/enabled=true\n",
        )
        .unwrap();
        assert!(AutoLauncher::verify_project(&tmp).await.is_ok());
    }
}
