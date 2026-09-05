//! Proxy bidireccional stdin ↔ socket TCP con **reconexión automática**.
//!
//! LSP sobre TCP es **stateless para nosotros**: el bridge solo mueve bytes
//! entre stdin y el socket. La reconexión es trivial — basta con cerrar el
//! socket viejo, abrir uno nuevo y seguir.
//!
//! ## Comportamiento ante caídas
//!
//! - **Socket cerrado** (Godot reiniciado, crash, etc.) → reintenta conectar
//!   cada 1s hasta `reconnect_max_ms` total desde el primer disconnect. Si
//!   pasa ese tiempo, devuelve `ReconnectTimeout` y termina.
//! - **stdin cerrado** (OpenCode cerró el LSP bridge) → terminamos OK.
//! - **Signal SIGINT/SIGTERM** → terminamos OK.
//!
//! ## Mensajes de OpenCode durante la desconexión
//!
//! Mientras el socket está caído, los mensajes LSP que OpenCode envíe por
//! stdin se **descartan** con un warn en verbose. Razón: LSP requests tienen
//! timeout corto en OpenCode (típicamente 5s); mejor fallar rápido y dejar
//! que OpenCode reintente la próxima vez que el usuario pida autocomplete.

use std::time::{Duration, Instant};

use thiserror::Error;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::signal;
use tokio::time::sleep;

use super::frame::{encode, FrameParser};

#[derive(Debug, Error)]
pub enum ProxyError {
    #[error("stdin closed")]
    StdinClosed,
    #[error("LSP socket disconnected; reconnect window exhausted ({timeout_ms}ms)")]
    ReconnectTimeout { timeout_ms: u64 },
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

/// Loop principal del proxy. Conecta → hace proxy → si cae, reconecta.
/// Usa stdin/stdout directamente (la entry point del binario).
pub async fn run_proxy_loop(
    host: String,
    port: u16,
    reconnect_max_ms: u64,
    verbose: bool,
) -> Result<(), ProxyError> {
    run_proxy(
        host,
        port,
        reconnect_max_ms,
        verbose,
        tokio::io::stdin(),
        tokio::io::stdout(),
    )
    .await
}

/// Loop principal del proxy, genérico sobre `AsyncRead`/`AsyncWrite`. Usado
/// por `run_proxy_loop` (stdin/stdout reales) y por los tests (pipes).
pub async fn run_proxy<R, W>(
    host: String,
    port: u16,
    reconnect_max_ms: u64,
    verbose: bool,
    stdin: R,
    mut stdout: W,
) -> Result<(), ProxyError>
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    // Conexión inicial. Si falla aquí, el caller decide qué hacer (el caller
    // ya intentó auto-launch antes de llamarnos).
    let initial_socket = TcpStream::connect((host.as_str(), port)).await?;
    if verbose {
        eprintln!("[heren-lsp] connected to LSP at {host}:{port}");
    }

    run_with_reconnect(
        initial_socket,
        &host,
        port,
        reconnect_max_ms,
        verbose,
        stdin,
        &mut stdout,
    )
    .await
}

async fn run_with_reconnect<R, W>(
    initial_socket: TcpStream,
    host: &str,
    port: u16,
    reconnect_max_ms: u64,
    verbose: bool,
    mut stdin: R,
    mut stdout: &mut W,
) -> Result<(), ProxyError>
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    let mut socket = initial_socket;
    let mut parser = FrameParser::new();
    let mut stdin_buf = vec![0u8; 64 * 1024];
    let mut socket_buf = vec![0u8; 64 * 1024];

    loop {
        // Si llegamos aquí con un socket nuevo (post-reconnect), seguimos.
        // Si falla, volvemos a intentar.
        match proxy_one_session(
            &mut stdin,
            &mut stdout,
            &mut socket,
            &mut parser,
            &mut stdin_buf,
            &mut socket_buf,
            verbose,
        )
        .await
        {
            Ok(SessionEnd::StdinClosed | SessionEnd::Signaled) => return Ok(()),
            Ok(SessionEnd::SocketClosed) => {
                if verbose {
                    eprintln!("[heren-lsp] LSP socket closed; reconnecting...");
                }
                socket = match reconnect_loop(host, port, reconnect_max_ms, verbose).await {
                    Ok(s) => s,
                    Err(e) => return Err(e),
                };
            }
            Err(e) => return Err(e),
        }
    }
}

/// Una sesión de proxy = un socket + (stdin, stdout).
/// Devuelve el motivo de terminación (caller decide si reconectar).
enum SessionEnd {
    StdinClosed,
    SocketClosed,
    Signaled,
}

async fn proxy_one_session<R, W>(
    stdin: &mut R,
    stdout: &mut W,
    socket: &mut TcpStream,
    parser: &mut FrameParser,
    stdin_buf: &mut [u8],
    socket_buf: &mut [u8],
    verbose: bool,
) -> Result<SessionEnd, ProxyError>
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    let (mut sock_read, mut sock_write) = socket.split();

    // Task: stdin → parser → encode → socket_write.
    let stdin_to_socket = async {
        loop {
            match stdin.read(stdin_buf).await {
                Ok(0) => return SessionEnd::StdinClosed,
                Ok(n) => {
                    let frames = parser.feed(&stdin_buf[..n]);
                    for body in frames {
                        if verbose {
                            log_frame("→ LSP", &body);
                        }
                        let wire = encode(&body);
                        if let Err(e) = sock_write.write_all(&wire).await {
                            if verbose {
                                eprintln!("[heren-lsp] socket write error: {e}");
                            }
                            return SessionEnd::SocketClosed;
                        }
                    }
                }
                Err(e) => {
                    if verbose {
                        eprintln!("[heren-lsp] stdin read error: {e}");
                    }
                    return SessionEnd::StdinClosed;
                }
            }
        }
    };

    // Task: socket_read → stdout (los frames ya vienen frameados del LSP server,
    // los pasamos tal cual — el LSP server hace el framing por nosotros).
    let socket_to_stdout = async {
        loop {
            match sock_read.read(socket_buf).await {
                Ok(0) => return SessionEnd::SocketClosed,
                Ok(n) => {
                    if verbose {
                        log_bytes("← LSP", n);
                    }
                    if let Err(e) = stdout.write_all(&socket_buf[..n]).await {
                        if verbose {
                            eprintln!("[heren-lsp] stdout write error: {e}");
                        }
                        return SessionEnd::StdinClosed;
                    }
                    if let Err(e) = stdout.flush().await {
                        if verbose {
                            eprintln!("[heren-lsp] stdout flush error: {e}");
                        }
                        return SessionEnd::StdinClosed;
                    }
                }
                Err(e) => {
                    if verbose {
                        eprintln!("[heren-lsp] socket read error: {e}");
                    }
                    return SessionEnd::SocketClosed;
                }
            }
        }
    };

    tokio::select! {
        reason = stdin_to_socket => Ok(reason),
        reason = socket_to_stdout => Ok(reason),
        _ = signal::ctrl_c() => Ok(SessionEnd::Signaled),
    }
}

/// Intenta reconectar al LSP con backoff 1s, hasta `reconnect_max_ms` total.
async fn reconnect_loop(
    host: &str,
    port: u16,
    reconnect_max_ms: u64,
    verbose: bool,
) -> Result<TcpStream, ProxyError> {
    let deadline = Instant::now() + Duration::from_millis(reconnect_max_ms);
    let mut attempt: u32 = 0;
    loop {
        attempt += 1;
        if Instant::now() >= deadline {
            return Err(ProxyError::ReconnectTimeout {
                timeout_ms: reconnect_max_ms,
            });
        }
        if let Ok(Ok(stream)) =
            tokio::time::timeout(Duration::from_millis(1000), TcpStream::connect((host, port)))
                .await
        {
            if verbose {
                eprintln!("[heren-lsp] reconnected after {attempt} attempt(s)");
            }
            return Ok(stream);
        }
        if verbose {
            eprintln!("[heren-lsp] reconnect attempt {attempt} failed; retrying...");
        }
        sleep(Duration::from_millis(1000)).await;
    }
}

/// Log minimalista de un frame LSP: preview de 80 chars del body.
fn log_frame(direction: &str, body: &[u8]) {
    log_bytes(direction, body.len());
    let preview_len = body.len().min(80);
    if let Ok(s) = std::str::from_utf8(&body[..preview_len]) {
        eprintln!("[heren-lsp] {direction} preview: {s}");
    } else {
        eprintln!("[heren-lsp] {direction} preview: <non-utf8>");
    }
}

fn log_bytes(direction: &str, n: usize) {
    eprintln!("[heren-lsp] {direction}: {n} bytes");
}
