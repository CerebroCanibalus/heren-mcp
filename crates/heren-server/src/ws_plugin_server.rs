//! WS plugin server — el EditorPlugin Godot conecta aquí (patrón gopeak).
//!
//! Port de `src/heren/v4/ws_server.py` (flujo de conexión del plugin):
//! 1. El plugin conecta como WS client e inmediatamente manda
//!    `notifications/godot_ready` con su `project_path`.
//! 2. El server registra el editor en el `EditorRegistry` (project_path → canal).
//! 3. `notifications/ping`/`pong` actualizan el heartbeat.
//! 4. Respuestas JSON-RPC entrantes (por id) se resuelven contra los
//!    `tools/call` pendientes vía `registry.resolve_response`.
//!
//! El registry ya tiene `call_tool` (envía tools/call + espera la respuesta);
//! este módulo solo conecta el socket WS al registry.

use std::net::SocketAddr;

use futures::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::protocol::Message;
use tracing::{debug, info, warn};

use crate::editor::{JsonRpcResponse, normalize_project_path};
use crate::registry::{EditorChannel, EditorRegistry};

/// Inicia el listener WS en `addr`, registrando editores en el registry global.
pub async fn run_ws_plugin_server(addr: &str) -> Result<(), String> {
    let listener = TcpListener::bind(addr)
        .await
        .map_err(|e| format!("ws bind failed on {addr}: {e}"))?;
    info!(addr = %addr, "WS plugin server listening");

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                warn!(error = %e, "ws accept error");
                continue;
            }
        };
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, peer).await {
                warn!(peer = %peer, error = %e, "ws connection error");
            }
        });
    }
}

/// Maneja una conexión de editor: registra, heartbeat, enruta respuestas.
async fn handle_connection(stream: TcpStream, peer: SocketAddr) -> Result<(), String> {
    let registry = EditorRegistry::global();
    let ws = accept_async(stream)
        .await
        .map_err(|e| format!("ws handshake failed: {e}"))?;
    info!(peer = %peer, "editor connected");

    let (mut sink, mut stream) = ws.split();
    let mut project_path: Option<String> = None;

    // Canal de salida hacia el editor (lo consume el registry.call_tool).
    let (tx, mut rx) = futures::channel::mpsc::unbounded();

    // Task: consume el canal de salida y envía frames al socket.
    let sink_task = tokio::spawn(async move {
        while let Some(ch) = rx.next().await {
            let msg = match ch {
                EditorChannel::Send(json) => {
                    let text = serde_json::to_string(&json).unwrap_or_default();
                    debug!(frame = %text.len(), "sink sending text frame");
                    Message::Text(text.into())
                }
                EditorChannel::SendBytes(bytes) => {
                    debug!(bytes = bytes.len(), "sink sending binary frame");
                    Message::Binary(bytes.into())
                }
            };
            if sink.send(msg).await.is_err() {
                debug!("sink send failed — socket closed");
                break;
            }
        }
    });

    loop {
        let frame = match stream.next().await {
            Some(Ok(f)) => f,
            Some(Err(e)) => {
                warn!(peer = %peer, error = %e, "ws read error");
                break;
            }
            None => break, // cerrado
        };

        match frame {
            Message::Text(text) => {
                let parsed: Option<Value> = serde_json::from_str(&text).ok();
                let Some(msg) = parsed else {
                    warn!(peer = %peer, "invalid JSON frame from editor");
                    continue;
                };
                handle_frame(msg, &mut project_path, &tx).await;
            }
            Message::Binary(_) => {
                // Imágenes binarias (preview_resource) — no son mensajes de control.
                warn!(peer = %peer, "unexpected binary frame from editor");
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    // Cleanup: des-registrar + cancelar task de sink.
    if let Some(path) = project_path {
        let key = normalize_project_path(&path);
        registry.unregister(&key).await;
        info!(peer = %peer, project_path = %key, "editor disconnected");
        // Rediseño persistencia 2026-08-07: si el editor se cerró sin pasar
        // por session/close, es un cierre INESPERADO (interrumpe el trabajo).
        // Marcamos el flag → las tools del proyecto fallan con error claro
        // hasta que el agente haga session/open (fail-fast, nunca silencio).
        // session/close llama clear_unexpected_close ANTES de cerrar el editor,
        // así un cierre normal NO marca el flag.
        if !registry.is_graceful_close(&key).await {
            registry.mark_unexpected_close(&key).await;
            warn!(project_path = %key, "editor closed WITHOUT session/close — unexpected_close marked");
        }
    }
    sink_task.abort();
    Ok(())
}

/// Procesa un frame JSON-RPC del editor.
async fn handle_frame(
    msg: Value,
    project_path: &mut Option<String>,
    tx: &futures::channel::mpsc::UnboundedSender<EditorChannel>,
) {
    let registry = EditorRegistry::global();
    let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");

    match method {
        "notifications/godot_ready" => {
            let params = msg.get("params").cloned().unwrap_or(Value::Null);
            let path = params
                .get("project_path")
                .and_then(|p| p.as_str())
                .unwrap_or("")
                .to_string();
            let plugin_version = params
                .get("plugin_version")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let key = normalize_project_path(&path);
            info!(
                project_path = %key,
                plugin_version = ?plugin_version,
                "godot_ready"
            );
            // El registry.register toma el tx (canal de salida).
            registry.register_ctrl(key.clone(), tx.clone(), plugin_version).await;
            *project_path = Some(key);
        }
        "notifications/ping" | "notifications/pong" => {
            // Heartbeat — sin estado que mantener (el WS ya demuestra vida).
        }
        _ => {
            // JSON-RPC response a un tools/call pendiente.
            if msg.get("id").is_some() {
                if let Ok(resp) = serde_json::from_value::<JsonRpcResponse>(msg.clone()) {
                    registry.resolve_response(resp).await;
                }
            }
        }
    }
}
