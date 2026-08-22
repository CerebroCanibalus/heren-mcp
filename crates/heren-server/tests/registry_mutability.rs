//! Tests de mutabilidad del server Heren MCP.
//!
//! Cubre el modelo de estado mutable del server: dirty tracking de escenas,
//! aislamiento entre proyectos, y las transiciones dirty → unexpected_close.
//! Estos tests no requieren un editor Godot vivo porque ejercitan
//! `EditorRegistry` directamente.
//!
//! Para ejecutar:
//!     cargo test --test registry_mutability -- --nocapture

use futures::StreamExt;
use futures::channel::mpsc;
use heren_server::EditorRegistry;
use heren_server::editor::JsonRpcResponse;
use heren_server::registry::EditorChannel;

#[tokio::test]
async fn dirty_scenes_are_isolated_per_project() {
    let r = EditorRegistry::new();

    r.mark_dirty("D:/proj_a", "res://level1.tscn").await;
    r.mark_dirty("D:/proj_a", "res://level2.tscn").await;
    r.mark_dirty("D:/proj_b", "res://menu.tscn").await;

    let dirty_a = r.dirty_scenes("D:/proj_a").await;
    let dirty_b = r.dirty_scenes("D:/proj_b").await;
    let dirty_c = r.dirty_scenes("D:/proj_c").await;

    assert_eq!(dirty_a, vec!["res://level1.tscn", "res://level2.tscn"]);
    assert_eq!(dirty_b, vec!["res://menu.tscn"]);
    assert!(dirty_c.is_empty());
}

#[tokio::test]
async fn project_paths_are_normalized_for_dirty_tracking() {
    let r = EditorRegistry::new();

    // Backslashes, trailing slash y forward slashes deben resolver a la misma key.
    r.mark_dirty(r"D:\proj\", "res://a.tscn").await;
    r.mark_dirty("D:/proj", "res://b.tscn").await;

    let dirty = r.dirty_scenes("D:/proj").await;
    assert_eq!(dirty, vec!["res://a.tscn", "res://b.tscn"]);
}

#[tokio::test]
async fn clean_dirty_does_not_leak_across_projects() {
    let r = EditorRegistry::new();

    r.mark_dirty("D:/proj_a", "res://x.tscn").await;
    r.mark_dirty("D:/proj_b", "res://x.tscn").await;

    r.clean_dirty("D:/proj_a", "res://x.tscn").await;

    assert!(r.dirty_scenes("D:/proj_a").await.is_empty());
    assert_eq!(r.dirty_scenes("D:/proj_b").await, vec!["res://x.tscn"]);
}

#[tokio::test]
async fn unexpected_close_moves_dirty_to_fail_fast_state() {
    let r = EditorRegistry::new();

    r.mark_dirty("D:/proj", "res://a.tscn").await;
    r.mark_unexpected_close("D:/proj").await;

    // Las dirty desaparecen del tracking activo...
    assert!(r.dirty_scenes("D:/proj").await.is_empty());

    // ...y pasan al estado de cierre inesperado.
    let lost = r.unexpected_close("D:/proj").await;
    assert!(lost.is_some());
    assert_eq!(lost.unwrap(), vec!["res://a.tscn"]);
}

#[tokio::test]
async fn unexpected_close_without_dirty_is_benign() {
    let r = EditorRegistry::new();

    r.mark_unexpected_close("D:/proj").await;

    // Sin trabajo sucio, no hay nada que proteger.
    assert!(r.unexpected_close("D:/proj").await.is_none());
}

#[tokio::test]
async fn clear_unexpected_close_allows_reconnection() {
    let r = EditorRegistry::new();

    r.mark_dirty("D:/proj", "res://a.tscn").await;
    r.mark_unexpected_close("D:/proj").await;
    r.clear_unexpected_close("D:/proj").await;

    assert!(r.unexpected_close("D:/proj").await.is_none());
}

#[tokio::test]
async fn graceful_close_flag_is_consumed_once() {
    let r = EditorRegistry::new();

    assert!(!r.is_graceful_close("D:/proj").await);

    r.mark_graceful_close("D:/proj").await;
    assert!(r.is_graceful_close("D:/proj").await);

    // take_graceful_close consume el flag.
    assert!(r.take_graceful_close("D:/proj").await);
    assert!(!r.is_graceful_close("D:/proj").await);
    assert!(!r.take_graceful_close("D:/proj").await);
}

#[tokio::test]
async fn call_tool_fails_when_no_editor_connected() {
    let r = EditorRegistry::new();

    let err = r
        .call_tool("node/add", serde_json::json!({}), "D:/no_such_proj")
        .await;

    assert!(err.is_err());
    let msg = err.unwrap_err();
    assert!(
        msg.contains("no editor connected"),
        "error deberia indicar que no hay editor: {}",
        msg
    );
}

#[tokio::test]
async fn call_tool_fails_fast_after_unexpected_close_with_dirty() {
    let r = EditorRegistry::new();

    // Simulamos que el editor se cerró dejando trabajo sin guardar.
    r.mark_dirty("D:/proj", "res://a.tscn").await;
    r.mark_unexpected_close("D:/proj").await;

    let err = r
        .call_tool("node/add", serde_json::json!({}), "D:/proj")
        .await;

    assert!(err.is_err());
    let msg = err.unwrap_err();
    assert!(
        msg.contains("editor_closed_unexpectedly"),
        "error deberia ser fail-fast: {}",
        msg
    );
}

#[tokio::test]
async fn resolve_response_correlates_tool_result() {
    let r = EditorRegistry::new();

    // Creamos un canal dummy de editor.
    let (tx, mut rx) = mpsc::unbounded::<EditorChannel>();
    r.register_ctrl("D:/proj|user".to_string(), "D:/proj".to_string(), "user".to_string(), tx, Some("test-version".to_string()))
        .await;

    // Lanzamos call_tool en una tarea y esperamos el request saliente.
    let call = tokio::spawn({
        let r = r.clone();
        async move {
            r.call_tool("node/add", serde_json::json!({}), "D:/proj")
                .await
        }
    });

    // Recibimos el mensaje de request para extraer el id.
    let req = rx.next().await.expect("deberia llegar request");
    let id = match req {
        EditorChannel::Send(v) => v.get("id").and_then(|i| i.as_str()).unwrap().to_string(),
        EditorChannel::SendBytes(_) => panic!("no se esperan bytes"),
    };

    // Resolvemos la respuesta como si Godot respondiera ok.
    let resolved = r
        .resolve_response(JsonRpcResponse {
            id: serde_json::Value::String(id),
            result: Some(serde_json::json!({ "ok": true, "node_path": "res://test.tscn/Foo" })),
            error: None,
        })
        .await;

    assert!(resolved, "la respuesta deberia resolverse");

    let result = call.await.expect("join ok").expect("call ok");
    assert_eq!(result["ok"], true);
    assert_eq!(result["node_path"], "res://test.tscn/Foo");
}

#[tokio::test]
async fn concurrent_dirty_marking_is_safe() {
    let r = EditorRegistry::new();
    let mut handles = vec![];

    for i in 0..10 {
        let r = r.clone();
        handles.push(tokio::spawn(async move {
            for j in 0..10 {
                r.mark_dirty("D:/proj", &format!("res://scene_{}_{}.tscn", i, j))
                    .await;
            }
        }));
    }

    for h in handles {
        h.await.expect("task ok");
    }

    let dirty = r.dirty_scenes("D:/proj").await;
    assert_eq!(dirty.len(), 100);
}
