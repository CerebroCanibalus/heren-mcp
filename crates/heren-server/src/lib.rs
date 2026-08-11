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
