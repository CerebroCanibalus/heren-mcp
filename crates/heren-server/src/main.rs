//! Heren MCP v4 — bridge Rust (FlojoMCP dogfooding).
//!
//! Arquitectura (paridad con bridge Python v4):
//!
//! ```text
//! OpenCode (stdio MCP)
//!    |  stdio
//!    v
//! heren-server (FlojoMCP stdio server + tools)
//!    |  tools/call -> reenvio
//!    v
//! EditorRegistry (WS peer registry — port de ws_server.py)
//!    |  WS localhost
//!    v
//! EditorPlugin v4 (Godot, WS client)
//! ```
//!
//! Sub-comandos del binario:
//! - (sin args) → MCP stdio server (default histórico, lo que OpenCode invoca).
//! - `lsp-bridge` → LSP bridge OpenCode (stdio) ↔ Godot (TCP :6005). Ver
//!   `lsp_bridge::run_bridge`.
//!
//! Lints: pedantic como warning (Fase D3) — CI lo promueve a error con
//! `cargo clippy -- -D warnings`.
//!
//! Allows de estilo para un crate interno con doc-comentarios en español:
//! los lints de documentación (backticks, secciones # Errors/# Panics) y
//! `must_use` añaden ruido sin valor real aquí. Los lints de CÓDIGO
//! (redundant_closure, needless, long_literal...) sí se corrigen.

#![warn(clippy::pedantic)]
#![allow(
    clippy::doc_markdown,
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::must_use_candidate,
    clippy::too_many_lines,
    clippy::module_name_repetitions
)]
#![recursion_limit = "256"]

use std::process::ExitCode;

use clap::Parser;

use heren_server::lsp_bridge::{run_bridge, BridgeArgs, TopLevelCli};

#[tokio::main]
async fn main() -> ExitCode {
    // IMPORTANTE: parseamos args PRIMERO. Si es `lsp-bridge`, NO inicializamos
    // logging del MCP server (puede tener comportamiento distinto). Cada rama
    // configura su propio logging.
    let cli = TopLevelCli::parse();

    match cli.command {
        Some(heren_server::lsp_bridge::LspCommand::LspBridge(args)) => {
            run_lsp_bridge_entry(args).await
        }
        None => run_mcp_entry().await,
    }
}

async fn run_lsp_bridge_entry(args: BridgeArgs) -> ExitCode {
    // Logging del bridge: mismo patrón que MCP (HEREN_LOG_FILE → archivo).
    init_logging("HEREN_LSP_LOG_FILE");
    match run_bridge(args).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            // El bridge SIEMPRE escribe a stderr (no inunda — son errores).
            eprintln!("[heren-lsp] fatal: {e}");
            if let Some(source) = std::error::Error::source(&e) {
                eprintln!("[heren-lsp] cause: {source}");
            }
            ExitCode::FAILURE
        }
    }
}

async fn run_mcp_entry() -> ExitCode {
    // Logging del MCP server (patrón existente, preservado bit-a-bit).
    let level = std::env::var("HEREN_LOG_LEVEL")
        .or_else(|_| std::env::var("RUST_LOG"))
        .unwrap_or_else(|_| "info".to_string());
    if let Ok(log_path) = std::env::var("HEREN_LOG_FILE") {
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path);
        match file {
            Ok(file) => {
                tracing_subscriber::fmt()
                    .with_writer(file)
                    .with_env_filter(&level)
                    .with_ansi(false)
                    .init();
                eprintln!("[heren-server] log a archivo: {log_path} (level={level})");
            }
            Err(e) => {
                eprintln!("[heren-server] no se pudo abrir HEREN_LOG_FILE={log_path}: {e}");
            }
        }
    }
    match heren_server::run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("[heren-server] fatal: {e}");
            ExitCode::FAILURE
        }
    }
}

/// Inicializa logging solo si la env var está definida (mismo patrón que MCP).
fn init_logging(env_var: &str) {
    let level = std::env::var("HEREN_LOG_LEVEL")
        .or_else(|_| std::env::var("RUST_LOG"))
        .unwrap_or_else(|_| "info".to_string());
    if let Ok(log_path) = std::env::var(env_var) {
        if let Ok(file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
        {
            let _ = tracing_subscriber::fmt()
                .with_writer(file)
                .with_env_filter(&level)
                .with_ansi(false)
                .try_init();
            eprintln!("[heren-lsp] log a archivo: {log_path} (level={level})");
        }
    }
}
