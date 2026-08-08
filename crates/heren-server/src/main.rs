//! Heren MCP v4 — bridge Rust (FlojoMCP dogfooding).
//!
//! OpenCode (stdio MCP) <-> heren-server (FlojoMCP stdio)
//!                        <-> WS peer registry <-> EditorPlugin v4
//!
//! Logging:
//! - El log de tracing va a HEREN_LOG_FILE SIEMPRE que esté definido.
//! - Sin HEREN_LOG_FILE → SILENCIO total (un MCP server no debe inundar
//!   stderr: OpenCode no lo drena y el pipe (64KB) se llena → timeout).
//! - Mensajes críticos SIEMPRE van a stderr (muy pocos, no bloquean).

use heren_server::run;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let level = std::env::var("HEREN_LOG_LEVEL")
        .or_else(|_| std::env::var("RUST_LOG"))
        .unwrap_or_else(|_| "info".to_string());

    // HEREN_LOG_FILE definido → log a archivo. Si NO → silencio (sin tracing
    // a stderr). CRÍTICO: con OpenCode el stderr del server no se drena; si
    // el server escribe tracing ahí, el pipe se llena y el server se bloquea
    // -> 'timeout'/'tarda demasiado y muere'.
    if let Ok(log_path) = std::env::var("HEREN_LOG_FILE") {
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;
        tracing_subscriber::fmt()
            .with_writer(file)
            .with_env_filter(&level)
            .with_ansi(false)
            .init();
        eprintln!("[heren-server] log a archivo: {log_path} (level={level})");
    }

    run().await.map_err(|e| e.into())
}
