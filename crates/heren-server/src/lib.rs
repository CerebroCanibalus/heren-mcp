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

pub mod constants;
pub mod editor;
pub mod launcher;
pub mod pure;
pub mod registry;
pub mod server;
pub mod ws_plugin_server;

pub use registry::EditorRegistry;
pub use server::Heren;
pub use server::run;

