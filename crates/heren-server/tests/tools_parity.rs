//! Salud del toolset — verificación ESTRUCTURAL, no enumerativa.
//!
//! Filosofía (2026-08-24): añadir una tool NO debe requerir editar este archivo.
//! En vez de una lista hardcodeada de nombres (que se pudre en cada add/remove),
//! se verifican invariantes que TODA tool debe cumplir + una lista mínima de
//! herramientas PROHIBIDAS para regresiones.
//!
//! Checklist real al tocar tools (ver AGENTS.md §6):
//! - AÑADIR: escribir la fn #[tool] en server.rs. Nada más.
//! - QUITAR: borrar la fn. Si quieres regresión, añade el nombre a FORBIDDEN_TOOLS.
//! - NUEVA action de tool existente: añadir (tool, action) a DISPATCH_ROUTES.

use flojo_mcp::prelude::*;
use heren_server::Heren;

/// Tools eliminadas que NO deben volver a aparecer (guarda de regresión).
/// help (2026-08-24): el descubrimiento es nativo del protocolo MCP (tools/list).
const FORBIDDEN_TOOLS: &[&str] = &["help", "scene_plan"];

/// Mínimo sanitario de tools expuestas. No es una lista exacta: si un refactor
/// masivo rompe el registro de tools, este número lo detecta.
const MIN_TOOLS: usize = 15;

/// Tools legítimas sin parámetro `action` (no siguen el patrón "1 tool N acciones"):
/// health solo project_path.
const TOOLS_WITHOUT_ACTION: &[&str] = &["health"];

/// Routes que el server usa internamente via forward() al plugin.
/// Cada (tool, action) debe existir en `addons/heren/_routes.gd::ROUTES`.
/// Si añades un nuevo forward() a scene/nodepath/etc., agrégalo aquí Y en
/// _routes.gd (Fase 3 §0.8, 2026-09-03).
///
/// 2026-09-09 (§0.12 W4 cleanup): removidas routes archivadas:
///   animation/tree_*, animation/blend_pose/retarget/capture_pose,
///   skeleton/*, tilemap/*, ui/layout, ui/theme,
///   shader/material/uniform/apply, node/reorder/move/set_owner,
///   signal/set_script.
const DISPATCH_ROUTES: &[&str] = &[
    "scene/open", "scene/save", "scene/get_edited_scene_root",
    "scene/get_open_scenes", "scene/get_plan", "scene/set_qa_report",
    "scene/plan", "scene/orchestrate", "scene/validate", "scene/commit",
    "scene/status", "scene/list",
    "node/get_children", "node/add", "node/set_props", "node/set_prop",
    "node/instantiate", "node/remove", "node/duplicate",
    "resource/create",
    "signal/connect", "signal/list",
    "validate/scene",
    "visual/scene_summary",
    "animation/add_track", "animation/add_key", "animation/create_player",
    "animation/create", "animation/update_props", "animation/duplicate",
    "animation/delete",
    "filesystem/scan", "filesystem/status", "filesystem/import_errors",
    "filesystem/exists", "filesystem/import",
];

async fn list_tools() -> Vec<flojo_mcp::rmcp::model::Tool> {
    let tester = FlojoTester::with_context(Heren::new(), Context::default());
    tester.list_tools().await.expect("list_tools")
}

#[tokio::test]
async fn no_forbidden_tools_exposed() {
    let tools = list_tools().await;
    for forbidden in FORBIDDEN_TOOLS {
        assert!(
            !tools.iter().any(|t| t.name.as_ref() == *forbidden),
            "tool prohibida '{forbidden}' está expuesta. Tools actuales: {:?}",
            tools.iter().map(|t| t.name.as_ref()).collect::<Vec<_>>()
        );
    }
}

#[tokio::test]
async fn toolset_not_emptied() {
    let tools = list_tools().await;
    assert!(
        tools.len() >= MIN_TOOLS,
        "solo {} tools expuestas (mínimo esperado {MIN_TOOLS}) — ¿un refactor rompió el registro?",
        tools.len()
    );
}

#[tokio::test]
async fn all_tools_have_valid_non_empty_schema() {
    let tools = list_tools().await;
    for tool in &tools {
        assert!(
            !tool.input_schema.is_empty(),
            "tool '{}' tiene schema vacío (generado en compile-time)",
            tool.name
        );
        let schema = serde_json::to_value(&tool.input_schema).unwrap();
        assert!(
            schema.is_object(),
            "tool '{}' schema no es objeto",
            tool.name
        );
    }
}

#[tokio::test]
async fn all_tools_have_description_and_action_pattern() {
    let tools = list_tools().await;
    for tool in &tools {
        // description no vacía — el agente depende de ella para saber qué args
        // aplicar a cada action.
        let desc = tool.description.as_ref().map_or("", |d| d.as_ref());
        assert!(
            !desc.trim().is_empty(),
            "tool '{}' tiene description vacía",
            tool.name
        );

        // Toda tool centralizada expone `action` en su schema (salvo excepciones).
        if TOOLS_WITHOUT_ACTION.contains(&tool.name.as_ref()) {
            continue;
        }
        let schema = serde_json::to_value(&tool.input_schema).unwrap();
        let props = schema.get("properties").and_then(|p| p.as_object());
        assert!(
            props.map(|p| p.contains_key("action")).unwrap_or(false),
            "tool '{}' no expone parametro 'action' en su schema",
            tool.name
        );
    }
}

#[tokio::test]
async fn internal_forward_names_use_plugin_prefixes() {
    // H (2026-08-24): los adapters del planning reenviaban con nombres
    // SERVER-side (node_query/visual_image/visual_text) que el dispatcher del
    // plugin NO registra → "no handler for prefix". Contrato: forward() usa
    // SOLO prefijos BARE registrados en editor_plugin.gd (L144-156).
    const PLUGIN_PREFIXES: &[&str] = &[
        "scene", "node", "resource", "project", "signal", "validate", "debug",
        "shader", "animation", "skeleton", "tilemap", "visual", "ui",
    ];
    // Nombres internos usados por el flujo planning (adapters + coder).
    const USED_INTERNAL_NAMES: &[&str] = &[
        "scene/open",
        "scene/save",
        "scene/get_edited_scene_root",
        "node/get_children",
        "validate/scene",
        "visual/scene_summary",
        "signal/list",
        "node/add",
        "node/set_props",
        "node/instantiate",
        "node/remove",
        "node/duplicate",
        "resource/create",
        "signal/connect",
    ];
    for name in USED_INTERNAL_NAMES {
        let prefix = name.split('/').next().unwrap();
        assert!(
            PLUGIN_PREFIXES.contains(&prefix),
            "'{name}' usa prefijo '{prefix}' NO registrado en el plugin — revisa editor_plugin.gd"
        );
    }
}

#[tokio::test]
async fn dispatch_routes_are_in_plugin_table() {
    // Fase 3 (2026-09-03): las rutas internas (forward del server) deben estar
    // declaradas en `addons/heren/_routes.gd::ROUTES`. Esto evita el bug
    // A4 (dispatcher routing frágil): renames silenciosos rompen producción.
    let routes_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent().and_then(|p| p.parent())
        .map(|p| p.join("addons").join("heren").join("_routes.gd"))
        .expect("workspace root");
    let content = std::fs::read_to_string(&routes_path)
        .unwrap_or_else(|e| panic!("no se pudo leer {}: {}", routes_path.display(), e));
    for route in DISPATCH_ROUTES {
        assert!(
            content.contains(&format!("\"{}\"", route)) || content.contains(&format!("\"{}\":", route)),
            "route '{}' no está declarada en _routes.gd::ROUTES. Añádela (Fase 3 §0.8)",
            route
        );
    }
}

#[tokio::test]
async fn scene_plan_is_file_based_not_inline() {
    // H1 (2026-08-24): `plan: Option<Value>` generaba schema {} → el cliente
    // enviaba un STRING y el server fallaba "expected struct ScenePlan".
    // Incluso tipado, el anyOf del schema hacía rechazar planes válidos.
    // Decisión: el plan viaja como ARCHIVO (plan_file) — el parámetro inline
    // `plan` NO debe existir.
    let tools = list_tools().await;
    let scene = tools
        .iter()
        .find(|t| t.name.as_ref() == "scene")
        .expect("tool scene debe existir");
    let schema = serde_json::to_value(&scene.input_schema).unwrap();
    let props = schema.get("properties").and_then(|p| p.as_object()).unwrap();
    assert!(
        !props.contains_key("plan"),
        "scene NO debe exponer parámetro 'plan' inline (viaja por plan_file)"
    );
    assert!(
        props.contains_key("plan_file"),
        "scene debe exponer parámetro 'plan_file'"
    );
}
