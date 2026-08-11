//! Verificación de paridad de tools: el server Rust debe exponer TODAS las
//! tools del bridge Python v4 (mismas firmas/schemas).

use flojo_mcp::prelude::*;
use heren_server::Heren;

/// Lista de tools esperadas (paridad con bridge Python v4 archivado en
/// `archive/v3` + v4.6 split).
/// v4.6: `visual` → `visual_text` + `visual_image`; `node` → `node` + `node_query` + `node_props`.
const EXPECTED_TOOLS: &[&str] = &[
    "session",
    "scene",
    "node",
    "node_query",
    "node_props",
    "resource",
    "project",
    "shader",
    "animation",
    "skeleton",
    "tilemap",
    "debug",
    "validate",
    "signal",
    "orchestrate",
    "visual_text",
    "visual_image",
    "health",
];

#[tokio::test]
async fn all_bridge_tools_exposed() {
    let tester = FlojoTester::with_context(Heren::new(), Context::default());
    let tools = tester.list_tools().await.expect("list_tools");
    let names: Vec<String> = tools.iter().map(|t| t.name.as_ref().to_string()).collect();

    for expected in EXPECTED_TOOLS {
        assert!(
            names.contains(&expected.to_string()),
            "tool '{expected}' no está expuesta. Tools actuales: {names:?}"
        );
    }

    // Verificar que cada tool tiene un schema input no vacío.
    for tool in &tools {
        assert!(
            !tool.input_schema.is_empty(),
            "tool '{}' tiene schema vacío (generado en compile-time)",
            tool.name
        );
    }
}

#[tokio::test]
async fn all_tools_have_valid_schemas() {
    let tester = FlojoTester::with_context(Heren::new(), Context::default());
    let tools = tester.list_tools().await.expect("list_tools");
    assert!(
        tools.len() >= EXPECTED_TOOLS.len(),
        "deben haber al menos {} tools",
        EXPECTED_TOOLS.len()
    );
    // Salud: cada tool con schema JSON válido.
    for tool in &tools {
        let schema = serde_json::to_value(&tool.input_schema).unwrap();
        assert!(
            schema.is_object(),
            "tool '{}' schema no es objeto",
            tool.name
        );
    }
}
