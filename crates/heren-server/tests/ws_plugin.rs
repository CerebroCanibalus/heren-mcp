// Test de integración: WS plugin server.
// Simula el EditorPlugin Godot conectando al server Rust y verifica:
// 1. godot_ready registra el editor en el registry global.
// 2. tools/call se reenvía al plugin y la respuesta se correlaciona.
use std::time::Duration;

use futures::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::protocol::Message;

#[tokio::test]
async fn ws_plugin_server_registers_and_forwards() {
    // Inicializar el registry global (lo que hace run()).
    heren_server::EditorRegistry::init_global();

    // Arrancar el WS plugin server en un task.
    let server = tokio::spawn(async {
        let _ = heren_server::ws_plugin_server::run_ws_plugin_server("127.0.0.1:9911").await;
    });
    tokio::time::sleep(Duration::from_millis(300)).await;

    // Conectar como plugin simulado.
    let (mut ws, _) = tokio_tungstenite::connect_async("ws://127.0.0.1:9911")
        .await
        .expect("ws connect");
    // godot_ready.
    ws.send(Message::Text(
        r#"{"jsonrpc":"2.0","method":"notifications/godot_ready","params":{"project_path":"D:/proj"}}"#
            .into(),
    ))
    .await
    .unwrap();

    // Verificar que el registry registró el editor (dar tiempo al task).
    let reg = heren_server::EditorRegistry::global();
    let mut connected = false;
    for _ in 0..20 {
        if reg.has_editor("D:/proj").await {
            connected = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(connected, "editor debería estar registrado");

    // tools/call reenvío — el server manda el request al plugin.
    // El call_tool se ejecuta en un task para que corra en paralelo con el
    // test que espera recibir el frame tools/call en el socket del plugin.
    let reg_call = reg.clone();
    let call_handle = tokio::spawn(async move {
        reg_call
            .call_tool("scene/get_open_scenes", serde_json::json!({}), "D:/proj")
            .await
    });
    let resp = tokio::time::timeout(Duration::from_secs(5), ws.next())
        .await
        .expect("timeout esperando tools/call")
        .expect("stream closed");
    match resp {
        Ok(Message::Text(t)) => {
            let v: serde_json::Value = serde_json::from_str(&t).unwrap();
            assert_eq!(v["method"], "tools/call");
            assert_eq!(v["params"]["name"], "scene/get_open_scenes");
            // El plugin responde con el mismo id.
            let id = v["id"].clone();
            ws.send(Message::Text(
                serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {"content": [{"type": "text", "text": "{\"ok\":true,\"scenes\":[]}"}]}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
            let result = call_handle
                .await
                .expect("call_tool task")
                .expect("registry call_tool");
            // call_tool devuelve la respuesta JSON-RPC cruda del plugin.
            // content[0].text es el JSON del resultado.
            let text = result["content"][0]["text"].as_str().unwrap();
            let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
            assert_eq!(parsed["ok"], true);
            assert_eq!(parsed["scenes"], serde_json::json!([]));
        }
        other => panic!("esperaba tools/call, got {other:?}"),
    }

    // Cerrar conexión → el editor se des-registra.
    ws.close(None).await.ok();
    tokio::time::sleep(Duration::from_millis(200)).await;
    let still = reg.has_editor("D:/proj").await;
    assert!(!still, "editor debería des-registrarse al cerrar");

    server.abort();
}
