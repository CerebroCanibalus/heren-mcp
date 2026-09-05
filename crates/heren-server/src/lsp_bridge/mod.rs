//! LSP bridge para OpenCode (sub-comando del binario `heren-server`).
//!
//! OpenCode soporta LSP servers vía `opencode.jsonc`:
//! ```jsonc
//! {
//!   "lsp": {
//!     "gdscript": {
//!       "command": ["heren-server", "lsp-bridge"],
//!       "extensions": [".gd", ".gdshader"]
//!     }
//!   }
//! }
//! ```
//!
//! OpenCode lanza el bridge como subproceso y habla LSP por stdio. Godot LSP
//! habla LSP por **TCP** en `127.0.0.1:6005`. El bridge hace de proxy
//! bidireccional.
//!
//! ## Por qué un sub-comando y no un binario separado
//!
//! 1. Un solo binario para mantener, una sola `cargo build`.
//! 2. Reutilizamos tipos del workspace (serde, tracing, thiserror, tokio).
//! 3. Compatibilidad: invocar `heren-server` sin args sigue corriendo el MCP
//!    server (comportamiento histórico). El sub-comando `lsp-bridge` es la
//!    única ruta al LSP bridge.
//!
//! ## Modo de operación
//!
//! 1. Intenta conectar a `127.0.0.1:6005` con timeout 2s.
//! 2. Si **no conecta** y `--auto-launch-godot` (default: ON) → lanza Godot
//!    en modo headless liviano (`--editor --headless --audio-driver Dummy`)
//!    con el `--project-path` dado. Espera conexión con backoff 250ms→2s
//!    hasta `launch-timeout-ms` (default 20s).
//! 3. Inicia el proxy bidireccional con reconexión automática.
//!
//! ## Logs
//!
//! Mismo patrón que el MCP server: `HEREN_LOG_FILE` define archivo, si no
//! → silencio total (OpenCode no drena stderr). `--verbose` añade previews
//! de 80 chars por mensaje a stderr.

pub mod frame;
pub mod launcher;
pub mod proxy;

use std::path::PathBuf;
use std::process::Child;

use clap::{Args, Parser, Subcommand};
use thiserror::Error;

pub use frame::{encode, FrameParser, FrameError, ParseOutcome};
pub use launcher::{AutoLauncher, LaunchConfig, LauncherError};
pub use proxy::{run_proxy_loop, ProxyError};

/// Argumentos CLI del sub-comando `lsp-bridge`.
#[derive(Debug, Args, Clone)]
pub struct BridgeArgs {
    /// Host del LSP nativo de Godot.
    #[arg(long, default_value_t = default_lsp_host(), env = "HEREN_LSP_HOST")]
    pub lsp_host: String,

    /// Puerto del LSP nativo de Godot. Default: `0` = **auto-detect** (escanea
    /// el rango `--lsp-port-range` y conecta al primero que responda). Pasa un
    /// número explícito para forzar un puerto fijo.
    #[arg(long, default_value_t = 0, env = "HEREN_LSP_PORT")]
    pub lsp_port: u16,

    /// Rango de puertos a escanear cuando `--lsp-port=0`. Formato "START-END"
    /// (inclusivo). Default: `6005-6010`. Rango pequeño para no tardar mucho
    /// y no pegar con puertos comunes de otras apps.
    #[arg(long, default_value_t = default_port_range_str(), env = "HEREN_LSP_PORT_RANGE")]
    pub lsp_port_range: String,

    /// Auto-lanzar Godot headless si nadie escucha en el puerto LSP.
    /// Default: ON (decisión de diseño — el bridge debe funcionar sin
    /// configuración adicional del usuario más allá de tener el binario en PATH).
    #[arg(long, default_value_t = true, action = clap::ArgAction::Set)]
    pub auto_launch_godot: bool,

    /// Negación explícita de `--auto-launch-godot` (útil en scripts/CI).
    #[arg(long, conflicts_with = "auto_launch_godot")]
    pub no_auto_launch_godot: bool,

    /// Path al proyecto Godot (necesario para `--auto-launch-godot`).
    #[arg(long, env = "HEREN_LSP_PROJECT")]
    pub project_path: Option<PathBuf>,

    /// Path explícito a godot.exe/godot. Si no, busca en PATH + `GODOT_PATH`.
    #[arg(long, env = "GODOT_PATH")]
    pub godot_path: Option<PathBuf>,

    /// Timeout en ms para que el LSP esté listo tras auto-launch.
    #[arg(long, default_value_t = 20_000)]
    pub launch_timeout_ms: u64,

    /// Ventana total de reconexión en ms cuando el LSP se cae a mitad de sesión.
    #[arg(long, default_value_t = 60_000)]
    pub reconnect_max_ms: u64,

    /// Modo verbose: muestra previews de 80 chars por mensaje LSP a stderr.
    #[arg(long, short = 'v', default_value_t = false)]
    pub verbose: bool,
}

impl BridgeArgs {
    /// Resuelve la config final considerando los flags negadores.
    pub fn into_config(self) -> BridgeConfig {
        BridgeConfig {
            lsp_host: self.lsp_host,
            lsp_port: self.lsp_port,
            lsp_port_range: parse_port_range(&self.lsp_port_range).unwrap_or((6005, 6010)),
            auto_launch_godot: self.auto_launch_godot && !self.no_auto_launch_godot,
            project_path: self.project_path,
            godot_path: self.godot_path,
            launch_timeout_ms: self.launch_timeout_ms,
            reconnect_max_ms: self.reconnect_max_ms,
            verbose: self.verbose,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BridgeConfig {
    pub lsp_host: String,
    /// `0` = auto-detect via port scanning.
    pub lsp_port: u16,
    /// Rango (start, end) inclusivo para el port scanner. Default: (6005, 6010).
    pub lsp_port_range: (u16, u16),
    pub auto_launch_godot: bool,
    pub project_path: Option<PathBuf>,
    pub godot_path: Option<PathBuf>,
    pub launch_timeout_ms: u64,
    pub reconnect_max_ms: u64,
    pub verbose: bool,
}

impl BridgeConfig {
    /// Puerto efectivo a usar. Si `lsp_port == 0` (auto), devuelve el primero
    /// del rango. Para port scanning dinámico usa `resolve_lsp_port()`.
    pub fn fallback_port(&self) -> u16 {
        if self.lsp_port != 0 {
            self.lsp_port
        } else {
            self.lsp_port_range.0
        }
    }
}

#[derive(Debug, Error)]
pub enum BridgeError {
    #[error("launcher: {0}")]
    Launcher(#[from] LauncherError),
    #[error("proxy: {0}")]
    Proxy(#[from] ProxyError),
    #[error(
        "LSP not reachable at {host}:{port} and --no-auto-launch-godot is set. \
         Start Godot manually with the editor open, or remove --no-auto-launch-godot."
    )]
    NoLspAndNoAutoLaunch { host: String, port: u16 },
}

/// Entry point del sub-comando `lsp-bridge`. Llamado desde `main.rs`.
///
/// Mantiene el child de Godot vivo (si lo auto-lanzó) hasta que el proxy
/// termina; entonces mata el child limpiamente.
pub async fn run_bridge(args: BridgeArgs) -> Result<(), BridgeError> {
    let cfg = args.into_config();

    if cfg.verbose {
        eprintln!(
            "[heren-lsp] starting: host={} port={} range={:?} auto_launch={} verbose=true",
            cfg.lsp_host, cfg.lsp_port, cfg.lsp_port_range, cfg.auto_launch_godot
        );
    }

    // 1. Resolver puerto efectivo:
    //    - Si --lsp-port fue pasado (>0): usar ese directo (compat).
    //    - Si no (auto): escanear el rango y conectar al primero que responda.
    let mut godot_child: Option<Child> = None;
    let (effective_host, effective_port, initial_stream) = if cfg.lsp_port != 0 {
        // Modo explícito: conectar al puerto pedido.
        let connect_result = try_connect(&cfg.lsp_host, cfg.lsp_port, 2000).await;
        if let Ok(stream) = connect_result {
            if cfg.verbose {
                eprintln!("[heren-lsp] connected to LSP at {}:{}", cfg.lsp_host, cfg.lsp_port);
            }
            (cfg.lsp_host.clone(), cfg.lsp_port, stream)
        } else if cfg.auto_launch_godot {
            let (child, stream, port) = auto_launch_godot(&cfg).await?;
            godot_child = Some(child);
            (cfg.lsp_host.clone(), port, stream)
        } else {
            return Err(BridgeError::NoLspAndNoAutoLaunch {
                host: cfg.lsp_host.clone(),
                port: cfg.lsp_port,
            });
        }
    } else {
        // Modo auto: port scanning.
        let scan_result = scan_for_lsp(&cfg.lsp_host, cfg.lsp_port_range, 500).await;
        if let Some((port, stream)) = scan_result {
            if cfg.verbose {
                eprintln!("[heren-lsp] auto-detected LSP at {}:{}", cfg.lsp_host, port);
            }
            (cfg.lsp_host.clone(), port, stream)
        } else if cfg.auto_launch_godot {
            let (child, stream, port) = auto_launch_godot(&cfg).await?;
            godot_child = Some(child);
            (cfg.lsp_host.clone(), port, stream)
        } else {
            return Err(BridgeError::NoLspAndNoAutoLaunch {
                host: cfg.lsp_host.clone(),
                port: cfg.lsp_port_range.0,
            });
        }
    };

    // 2. Correr el proxy. Mantenemos el child vivo aquí.
    let proxy_result = run_proxy_loop(
        effective_host.clone(),
        effective_port,
        cfg.reconnect_max_ms,
        cfg.verbose,
    )
    .await;

    // 3. Cleanup: matar el Godot que auto-lanzamos (si lo hicimos).
    if let Some(mut child) = godot_child {
        let _ = child.kill();
        let _ = child.wait();
    }

    drop(initial_stream);
    proxy_result.map_err(BridgeError::from)
}

/// Escanea un rango de puertos y devuelve el primero que tenga algo escuchando.
/// NO valida que sea un LSP válido (eso requeriría enviar `initialize`); eso
/// se hace de forma implícita al recibir la primera respuesta.
async fn scan_for_lsp(
    host: &str,
    range: (u16, u16),
    per_port_timeout_ms: u64,
) -> Option<(u16, tokio::net::TcpStream)> {
    for port in range.0..=range.1 {
        if let Ok(Ok(stream)) = tokio::time::timeout(
            std::time::Duration::from_millis(per_port_timeout_ms),
            tokio::net::TcpStream::connect((host, port)),
        )
        .await
        {
            return Some((port, stream));
        }
    }
    None
}

/// Auto-launch Godot en el primer puerto libre del rango (o el puerto
/// explícito si fue pasado).
async fn auto_launch_godot(
    cfg: &BridgeConfig,
) -> Result<(Child, tokio::net::TcpStream, u16), BridgeError> {
    let project = cfg.project_path.clone().ok_or_else(|| {
        BridgeError::Launcher(LauncherError::ProjectNotFound(PathBuf::from(
            "<no --project-path given>",
        )))
    })?;
    // Elegir puerto: si fue pasado, usarlo; si no, el primero del rango.
    let lsp_port = cfg.fallback_port();
    let launch_cfg = LaunchConfig {
        godot_path: cfg.godot_path.clone(),
        project_path: project,
        lsp_port,
        launch_timeout_ms: cfg.launch_timeout_ms,
    };
    if cfg.verbose {
        eprintln!(
            "[heren-lsp] no LSP running; auto-launching Godot on {}:{} (lightweight headless)...",
            cfg.lsp_host, lsp_port
        );
    }
    let (child, stream) = AutoLauncher::launch_and_wait(&launch_cfg).await?;
    if cfg.verbose {
        eprintln!("[heren-lsp] Godot LSP ready on {lsp_port}");
    }
    Ok((child, stream, lsp_port))
}

async fn try_connect(
    host: &str,
    port: u16,
    timeout_ms: u64,
) -> Result<tokio::net::TcpStream, std::io::Error> {
    match tokio::time::timeout(
        std::time::Duration::from_millis(timeout_ms),
        tokio::net::TcpStream::connect((host, port)),
    )
    .await
    {
        Ok(Ok(stream)) => Ok(stream),
        Ok(Err(e)) => Err(e),
        Err(_) => Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            format!("connect to {host}:{port} timed out after {timeout_ms}ms"),
        )),
    }
}

/// Definición clap parseable desde `argv`. Usado por `main.rs` para detectar
/// si el usuario quiere el MCP server (sin args o con args desconocidos para
/// OpenCode) o el LSP bridge (`lsp-bridge`).
#[derive(Debug, Parser)]
#[command(name = "heren-server", version, about = "Heren MCP server (Godot EditorPlugin bridge)")]
pub struct TopLevelCli {
    #[command(subcommand)]
    pub command: Option<LspCommand>,
}

/// Sub-comandos del binario. El default (ninguno) es el MCP server.
#[derive(Debug, Subcommand)]
pub enum LspCommand {
    /// Run as LSP bridge between OpenCode (stdio) and Godot (TCP).
    LspBridge(BridgeArgs),
}

fn default_lsp_host() -> String {
    "127.0.0.1".to_string()
}

fn default_port_range_str() -> String {
    "6005-6010".to_string()
}

/// Parsea un rango "START-END" como "6005-6010" → Some((6005, 6010)).
/// Devuelve None si el formato es inválido.
fn parse_port_range(s: &str) -> Option<(u16, u16)> {
    let (a, b) = s.split_once('-')?;
    let start: u16 = a.trim().parse().ok()?;
    let end: u16 = b.trim().parse().ok()?;
    if start == 0 || end == 0 || start > end {
        return None;
    }
    Some((start, end))
}

// ============================================================================
// Tests de integración del BridgeArgs (clap parsing).
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_has_auto_launch_on() {
        let cli = TopLevelCli::parse_from(["heren-server", "lsp-bridge"]);
        let args = extract_bridge_args(cli);
        let cfg = args.into_config();
        assert!(cfg.auto_launch_godot);
        assert_eq!(cfg.lsp_host, "127.0.0.1");
        assert_eq!(cfg.lsp_port, 0); // 0 = auto-detect
        assert_eq!(cfg.lsp_port_range, (6005, 6010));
        assert_eq!(cfg.launch_timeout_ms, 20_000);
        assert_eq!(cfg.reconnect_max_ms, 60_000);
        assert!(!cfg.verbose);
    }

    #[test]
    fn no_auto_launch_disables() {
        let cli =
            TopLevelCli::parse_from(["heren-server", "lsp-bridge", "--no-auto-launch-godot"]);
        let args = extract_bridge_args(cli);
        let cfg = args.into_config();
        assert!(!cfg.auto_launch_godot);
    }

    #[test]
    fn explicit_flags_override_defaults() {
        let cli = TopLevelCli::parse_from([
            "heren-server",
            "lsp-bridge",
            "--lsp-port",
            "6008",
            "--lsp-host",
            "0.0.0.0",
            "--launch-timeout-ms",
            "5000",
            "--verbose",
        ]);
        let args = extract_bridge_args(cli);
        let cfg = args.into_config();
        assert_eq!(cfg.lsp_port, 6008);
        assert_eq!(cfg.lsp_host, "0.0.0.0");
        assert_eq!(cfg.launch_timeout_ms, 5000);
        assert!(cfg.verbose);
    }

    #[test]
    fn top_level_dispatch_mcp_default() {
        // Sin subcomando → command = None → caller corre MCP server.
        let cli = TopLevelCli::parse_from(["heren-server"]);
        assert!(cli.command.is_none());
    }

    #[test]
    fn top_level_dispatch_lsp_bridge() {
        let cli = TopLevelCli::parse_from(["heren-server", "lsp-bridge"]);
        let args = extract_bridge_args(cli);
        assert_eq!(args.lsp_port, 0); // default = auto-detect
    }

    /// Helper de tests: extrae `BridgeArgs` del `TopLevelCli` parseado o
    /// panicea. Evita el `match` con un solo patrón real (clippy::single-match-else).
    fn extract_bridge_args(cli: TopLevelCli) -> BridgeArgs {
        let Some(LspCommand::LspBridge(args)) = cli.command else {
            panic!("expected LspBridge subcommand");
        };
        args
    }

    // ----- port_range parsing -----

    #[test]
    fn parse_port_range_valid() {
        assert_eq!(parse_port_range("6005-6010"), Some((6005, 6010)));
        assert_eq!(parse_port_range("  6005 - 6010  "), Some((6005, 6010)));
        assert_eq!(parse_port_range("1-1"), Some((1, 1)));
    }

    #[test]
    fn parse_port_range_invalid() {
        assert_eq!(parse_port_range(""), None);
        assert_eq!(parse_port_range("6005"), None);
        assert_eq!(parse_port_range("6005-"), None);
        assert_eq!(parse_port_range("-6010"), None);
        assert_eq!(parse_port_range("6010-6005"), None); // start > end
        assert_eq!(parse_port_range("abc-def"), None);
        assert_eq!(parse_port_range("6005-6010-extra"), None);
    }

    #[test]
    fn fallback_port_returns_explicit_if_set() {
        let cfg = BridgeConfig {
            lsp_host: "127.0.0.1".to_string(),
            lsp_port: 7777,
            lsp_port_range: (6005, 6010),
            auto_launch_godot: true,
            project_path: None,
            godot_path: None,
            launch_timeout_ms: 1000,
            reconnect_max_ms: 1000,
            verbose: false,
        };
        assert_eq!(cfg.fallback_port(), 7777);
    }

    #[test]
    fn fallback_port_returns_range_start_if_auto() {
        let cfg = BridgeConfig {
            lsp_host: "127.0.0.1".to_string(),
            lsp_port: 0,
            lsp_port_range: (6007, 6010),
            auto_launch_godot: true,
            project_path: None,
            godot_path: None,
            launch_timeout_ms: 1000,
            reconnect_max_ms: 1000,
            verbose: false,
        };
        assert_eq!(cfg.fallback_port(), 6007);
    }

    // ----- scan_for_lsp -----

    #[tokio::test]
    async fn scan_for_lsp_finds_listening_port() {
        // Levantar un listener en puerto aleatorio.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let port = listener.local_addr().unwrap().port();

        // Escanear un rango que incluya ese puerto.
        let result = scan_for_lsp("127.0.0.1", (port - 1, port + 1), 200).await;
        let (found_port, _stream) = result.expect("scan should find listener");
        assert_eq!(found_port, port);
        drop(listener);
    }

    #[tokio::test]
    async fn scan_for_lsp_returns_none_when_nothing_listening() {
        // Rango con puertos muy improbables de estar ocupados.
        let result = scan_for_lsp("127.0.0.1", (49900, 49903), 100).await;
        assert!(result.is_none(), "scan shouldn't find anything");
    }

    #[tokio::test]
    async fn scan_for_lsp_picks_first_in_range() {
        // Listener en puerto A y B, scan debe devolver A (el primero).
        let l_a = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port_a = l_a.local_addr().unwrap().port();
        let l_b = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port_b = l_b.local_addr().unwrap().port();
        // Normalizar rango (start <= end).
        let (start, end) = if port_a < port_b {
            (port_a, port_b)
        } else {
            (port_b, port_a)
        };
        let result = scan_for_lsp("127.0.0.1", (start, end), 200).await;
        let (found_port, _) = result.unwrap();
        assert_eq!(found_port, start);
        drop(l_a);
        drop(l_b);
    }
}

