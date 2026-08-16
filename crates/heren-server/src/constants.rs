//! Constantes del server Heren MCP (Fase C5).
//!
//! Centraliza números mágicos de configuración/protocolo para que no queden
//! duplicados en server.rs, registry.rs o launcher.rs. Los valores "100.0" de
//! redondeo de coordenadas NO van aquí (son precisión de salida, no config).

/// Puerto base del WS plugin server (Fase C5). El server busca `9099+N` libre;
/// el plugin intenta conectar a 9099 por defecto (ws_client.gd). El puerto real
/// se pasa al plugin via `HEREN_MCP_PORT` al lanzar el editor.
pub const WS_PORT_BASE: u16 = 9099;

/// Timeout de respuesta de tools/call hacia el editor (registry.rs).
pub const TOOL_TIMEOUT_MS: u64 = 35_000;

/// Espera tras matar el editor zombie antes de relanzar (server.rs reopen).
pub const EDITOR_KILL_WAIT_MS: u64 = 1500;

/// D2 (2026-08-15): timeout total esperando que el plugin conecte al WS tras
/// session/open (el editor tarda 3-5s en arrancar+conectar; 15s cubre
/// arranques lentos y detecta crash al cargar).
pub const EDITOR_CONNECT_TIMEOUT_MS: u64 = 15_000;

/// D2: intervalo de polling de conexión del editor (server.rs open).
pub const EDITOR_CONNECT_POLL_MS: u64 = 500;
