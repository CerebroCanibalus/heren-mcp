//! Tests Fase S — dos editores mismo project_path con roles distintos (user + agent)
//! Valida que el registry no colisiona y que el routing por rol es estable
//! mientras el usuario "hace cosas" en su ventana.

use futures::channel::mpsc;
use futures::StreamExt;
use heren_server::registry::EditorChannel;
use heren_server::EditorRegistry;
use heren_server::editor::GodotReady;

#[tokio::test]
async fn two_editors_same_project_different_roles_coexist() {
    let r = EditorRegistry::new();

    let (tx_user, _rx_user) = mpsc::unbounded::<EditorChannel>();
    let (tx_agent, _rx_agent) = mpsc::unbounded::<EditorChannel>();

    // Registra user y agent en MISMO proyecto
    let ready_user = GodotReady {
        project_path: "D:/game".to_string(),
        plugin_version: Some("4.7.0".to_string()),
        role: Some("user".to_string()),
    };
    let ready_agent = GodotReady {
        project_path: "D:/game".to_string(),
        plugin_version: Some("4.7.0".to_string()),
        role: Some("agent:test".to_string()),
    };

    let key_user = r.register(ready_user, tx_user).await;
    let key_agent = r.register(ready_agent, tx_agent).await;

    assert!(key_user.contains("user"), "key_user debe contener role");
    assert!(key_agent.contains("agent:test"), "key_agent debe contener role");
    assert_ne!(key_user, key_agent, "claves compuestas deben ser distintas");

    // connected_projects deduplica
    let projects = r.connected_projects().await;
    assert_eq!(projects, vec!["D:/game"], "un solo proyecto aunque dos roles");

    // connected_editors lista ambos
    let editors = r.connected_editors().await;
    assert_eq!(editors.len(), 2, "dos editores vivos");
    let roles: Vec<String> = editors.iter().map(|(_, role, _)| role.clone()).collect();
    assert!(roles.contains(&"user".to_string()));
    assert!(roles.contains(&"agent:test".to_string()));

    // has_editor_with_role específico
    assert!(r.has_editor_with_role("D:/game", "user").await);
    assert!(r.has_editor_with_role("D:/game", "agent:test").await);
    assert!(!r.has_editor_with_role("D:/game", "agent:other").await);

    // has_editor genérico (cualquier rol) sigue true
    assert!(r.has_editor("D:/game").await);
    assert!(!r.has_editor("D:/other").await);

    // unregister solo el agent, user queda vivo (estabilidad mientras usuario hace cosas)
    r.unregister_role("D:/game", "agent:test").await;
    assert!(r.has_editor("D:/game").await, "user debe seguir vivo tras quitar agent");
    assert!(!r.has_editor_with_role("D:/game", "agent:test").await);
    assert!(r.has_editor_with_role("D:/game", "user").await);

    let editors_after = r.connected_editors().await;
    assert_eq!(editors_after.len(), 1);
    assert_eq!(editors_after[0].1, "user");
}

#[tokio::test]
async fn call_tool_routing_by_role_is_stable() {
    let r = EditorRegistry::new();

    let (tx_user, mut rx_user) = mpsc::unbounded::<EditorChannel>();
    let (tx_agent, mut rx_agent) = mpsc::unbounded::<EditorChannel>();

    r.register(
        GodotReady {
            project_path: "D:/game".to_string(),
            plugin_version: Some("4.7.0".to_string()),
            role: Some("user".to_string()),
        },
        tx_user,
    )
    .await;
    r.register(
        GodotReady {
            project_path: "D:/game".to_string(),
            plugin_version: Some("4.7.0".to_string()),
            role: Some("agent:worker".to_string()),
        },
        tx_agent,
    )
    .await;

    // call_tool sin rol debe ir al user (compatibilidad)
    let h_user = tokio::spawn({
        let r = r.clone();
        async move { r.call_tool("node/add", serde_json::json!({}), "D:/game").await }
    });
    // Debe llegar al rx_user, no al agent
    let req_user = rx_user.next().await.expect("request debe llegar a user");
    // Asegurar que agent no recibió nada (con timeout corto)
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(rx_agent.try_next().is_err() || rx_agent.try_next().unwrap().is_none(), "agent no debe recibir call sin rol");

    // Resolver y verificar que call_tool se desbloquea
    let id = match req_user {
        EditorChannel::Send(v) => v.get("id").unwrap().as_str().unwrap().to_string(),
        _ => panic!("expected text"),
    };
    r.resolve_response(heren_server::editor::JsonRpcResponse {
        id: serde_json::Value::String(id),
        result: Some(serde_json::json!({"ok": true})),
        error: None,
    })
    .await;
    let _ = h_user.await.unwrap().unwrap();

    // call_tool_with_role agent debe ir al agent
    let h_agent = tokio::spawn({
        let r = r.clone();
        async move {
            r.call_tool_with_role("node/add", serde_json::json!({}), "D:/game", Some("agent:worker"))
                .await
        }
    });
    let req_agent = rx_agent.next().await.expect("request debe llegar a agent");
    let id2 = match req_agent {
        EditorChannel::Send(v) => v.get("id").unwrap().as_str().unwrap().to_string(),
        _ => panic!("expected text"),
    };
    r.resolve_response(heren_server::editor::JsonRpcResponse {
        id: serde_json::Value::String(id2),
        result: Some(serde_json::json!({"ok": true})),
        error: None,
    })
    .await;
    let _ = h_agent.await.unwrap().unwrap();
}

#[tokio::test]
async fn normalize_backslashes_and_trailing_slash_with_roles() {
    let r = EditorRegistry::new();
    let (tx, _rx) = mpsc::unbounded::<EditorChannel>();
    r.register(
        GodotReady {
            project_path: r"D:\game\".to_string(),
            plugin_version: None,
            role: Some("agent:1".to_string()),
        },
        tx,
    )
    .await;
    // Debe ser encontrable con forward slashes sin trailing
    assert!(r.has_editor_with_role("D:/game", "agent:1").await);
    assert!(r.has_editor("D:/game").await);
}
