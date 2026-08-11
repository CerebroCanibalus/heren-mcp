//! Editor connection types — port del bridge Python v4 (archivado en `archive/v3`).
//!
//! Un editor conectado = proyecto (project_path canónico) + canal WS.

use serde::{Deserialize, Serialize};

/// project_path normalizado (clave canónica): forward slashes + sin trailing.
pub fn normalize_project_path(path: &str) -> String {
    let replaced = path.replace('\\', "/");
    replaced.trim_end_matches('/').to_string()
}

/// Notificación `notifications/godot_ready` enviada por el plugin al conectar.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GodotReady {
    #[serde(default)]
    pub project_path: String,
    /// Versión del plugin que CORRE dentro del editor (leída de plugin.cfg al
    /// arrancar). El server la compara con la versión source para avisar al
    /// agente cuando el editor corre una versión antigua (requiere reopen).
    #[serde(default)]
    pub plugin_version: Option<String>,
}

/// Request `tools/call` que el server reenvía al plugin.
#[derive(Debug, Clone, Serialize)]
pub struct ToolCallRequest {
    pub jsonrpc: String,
    pub method: String,
    pub id: serde_json::Value,
    pub params: ToolCallParams,
}

#[derive(Debug, Clone, Serialize)]
pub struct ToolCallParams {
    pub name: String,
    pub arguments: serde_json::Value,
}

/// Respuesta JSON-RPC del plugin (tolerante: id puede venir como "1.0").
#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcResponse {
    pub id: serde_json::Value,
    #[serde(default)]
    pub result: Option<serde_json::Value>,
    #[serde(default)]
    pub error: Option<JsonRpcError>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcError {
    #[serde(default)]
    pub code: i64,
    #[serde(default)]
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_paths() {
        assert_eq!(normalize_project_path(r"D:\proj"), "D:/proj");
        assert_eq!(normalize_project_path("D:/proj/"), "D:/proj");
        assert_eq!(
            normalize_project_path("D:/proj/"),
            normalize_project_path(r"D:\proj")
        );
    }
}
