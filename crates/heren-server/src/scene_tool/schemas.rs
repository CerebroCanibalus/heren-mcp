//! Scene Tool Schemas — Structured state passing for scene creation/editing
//! Inspired by Multi-Agent-CAD (MAC): CADBrief → ArchitectPlan → Coder → QA

use flojo_mcp::schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ============================================================================
// Core Types
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum Workplane {
    /// 3D world coordinates (XZ plane, Y up)
    #[default]
    #[serde(rename = "XZ", alias = "x_z")]
    XZ,
    /// 2D UI coordinates (XY plane, Y down)
    #[serde(rename = "XY", alias = "x_y")]
    XY,
    /// 3D alternative (YZ plane, X up)
    #[serde(rename = "YZ", alias = "y_z")]
    YZ,
}


#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum SceneMode {
    /// Agent works in isolated editor window
    #[default]
    Isolated,
    /// Agent works in user's editor window (advisory lock)
    Attached,
    /// Modify existing scene incrementally
    Modify,
}


#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ErrorType {
    #[default]
    None,
    Dimension,
    Topology,
    Fatal,
}

// ============================================================================
// Vector Types (matching Godot)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Vector2 {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Vector3 {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
    #[serde(default)]
    pub z: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Quaternion {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub w: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Transform3D {
    pub origin: Vector3,
    pub basis_x: Vector3,
    pub basis_y: Vector3,
    pub basis_z: Vector3,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Transform2D {
    pub origin: Vector2,
    pub x_axis: Vector2,
    pub y_axis: Vector2,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct Rect2 {
    pub position: Vector2,
    pub size: Vector2,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
pub struct AABB {
    pub position: Vector3,
    pub size: Vector3,
}

// ============================================================================
// Scene Context (returned by scene/open)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct NodeInfo {
    pub path: String,
    pub name: String,
    pub node_type: String,
    pub parent: Option<String>,
    pub position: Option<Vector3>,
    pub transform: Option<Transform3D>,
    pub anchors: Option<Anchors>,
    pub offsets: Option<Offsets>,
    pub script_path: Option<String>,
    pub children: Vec<String>,
    pub owner: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct Anchors {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct Offsets {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct ResourceInfo {
    pub path: String,
    pub resource_type: String,
    pub properties: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct ScriptInfo {
    pub path: String,
    pub class_name: Option<String>,
    pub attached_to: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct SceneContext {
    pub scene_path: String,
    pub root_name: String,
    pub root_type: String,
    pub workplane: Workplane,
    pub workplane_offset: Vector3,
    pub bbox: AABB,
    pub nodes: Vec<NodeInfo>,
    pub resources: Vec<ResourceInfo>,
    pub scripts: Vec<ScriptInfo>,
    pub plan_schema: serde_json::Value, // JSON Schema for ScenePlan
}

// ============================================================================
// Scene Plan (written by agent via scene/plan)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[derive(Default)]
pub struct ScenePlan {
    pub plan_id: String,
    pub scene_path: String,
    #[serde(default)]
    pub workplane: Workplane,
    #[serde(default)]
    pub workplane_offset: Vector3,
    pub steps: Vec<SceneStep>,
    #[serde(default)]
    pub verification: Vec<VerificationTarget>,
    #[serde(default)]
    pub key_dimensions: HashMap<String, serde_json::Value>,
}


#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum SceneStep {
    /// Add a new node
    AddNode {
        id: String,
        node_type: String,
        name: String,
        parent: String,
        #[serde(default)]
        workplane: Workplane,
        #[serde(default)]
        local_pos: Vector3,
        #[serde(default)]
        local_rot: Vector3,
        #[serde(default)]
        local_scale: Vector3,
        #[serde(default)]
        resource_path: Option<String>,
        #[serde(default)]
        script_path: Option<String>,
        #[serde(default)]
        template: Option<String>,
        #[serde(default)]
        template_params: HashMap<String, serde_json::Value>,
        /// Props libres passthrough (mesh, shape, material_override, colores,
        /// arrays…). P0a (2026-08-24): antes se descartaban silenciosamente.
        #[serde(default)]
        properties: HashMap<String, serde_json::Value>,
    },
    /// Set transform/position/rotation/scale on existing node
    SetTransform {
        id: String,
        node_path: String,
        #[serde(default)]
        position: Option<Vector3>,
        #[serde(default)]
        rotation: Option<Vector3>,
        #[serde(default)]
        scale: Option<Vector3>,
        #[serde(default)]
        transform: Option<Transform3D>,
        #[serde(default)]
        anchors: Option<Anchors>,
        #[serde(default)]
        offsets: Option<Offsets>,
        #[serde(default)]
        anchors_preset: Option<i32>,
    },
    /// Create or update a resource (.tres)
    AddResource {
        id: String,
        resource_type: String,
        path: String,
        #[serde(default)]
        properties: HashMap<String, serde_json::Value>,
        #[serde(default)]
        template: Option<String>,
    },
    /// Connect a signal
    ConnectSignal {
        id: String,
        from_node: String,
        signal_name: String,
        to_node: String,
        method: String,
    },
    /// Instantiate a template from registry
    InstantiateTemplate {
        id: String,
        template: String,
        parent: String,
        #[serde(default)]
        workplane: Workplane,
        #[serde(default)]
        local_pos: Vector3,
        #[serde(default)]
        params: HashMap<String, serde_json::Value>,
    },
    /// Remove a node
    RemoveNode {
        id: String,
        node_path: String,
    },
    /// Duplicate a node
    DuplicateNode {
        id: String,
        node_path: String,
        new_name: String,
        new_parent: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct VerificationTarget {
    pub id: String,
    pub kind: VerificationKind,
    pub description: String,
    pub nominal: Option<f32>,
    pub tolerance: f32,
    pub node_path: Option<String>,
    pub selector: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum VerificationKind {
    #[default]
    NodeCount,
    BBoxMax,
    BBoxMin,
    ScriptAttached,
    ResourceExists,
    SignalConnected,
    NodeExists,
    PropertyValue,
    Custom(String),
}

/// Ejemplo canónico de ScenePlan para que el agente sepa QUÉ escribir en un
/// plan_file sin leer fuentes. Devuelto por scene(action="plan") sin plan_file.
/// ⚠️ verification.tolerance es OBLIGATORIO (f32 sin default).
pub fn example_plan() -> serde_json::Value {
    serde_json::json!({
        "plan_id": "ejemplo-001",
        "scene_path": "res://mi_escena.tscn",
        "workplane": "XZ",
        "workplane_offset": {"x": 0.0, "y": 0.0, "z": 0.0},
        "steps": [
            {
                "action": "add_node",
                "id": "s1",
                "node_type": "StaticBody3D",
                "name": "Caja",
                "parent": ".",
                "local_pos": {"x": 0.0, "y": 0.5, "z": 0.0},
                "properties": {
                    "mesh": "res://meshes/caja.tres",
                    "material_override": "res://materials/metal.tres"
                }
            },
            {
                "action": "add_resource",
                "id": "s2",
                "resource_type": "BoxMesh",
                "path": "res://meshes/caja.tres",
                "properties": {"size": {"x": 1.0, "y": 1.0, "z": 1.0}}
            },
            {
                "action": "set_transform",
                "id": "s3",
                "node_path": "Caja",
                "scale": {"x": 2.0, "y": 1.0, "z": 2.0}
            },
            {
                "action": "instantiate_template",
                "id": "s4",
                "template": "health_bar",
                "parent": "UI/HUD",
                "local_pos": {"x": 20.0, "y": 20.0},
                "params": {}
            },
            {
                "action": "connect_signal",
                "id": "s5",
                "from_node": "Caja",
                "signal_name": "body_entered",
                "to_node": "Player",
                "method": "_on_body_entered"
            },
            {"action": "remove_node", "id": "s6", "node_path": "NodoViejo"},
            {"action": "duplicate_node", "id": "s7", "node_path": "Caja", "new_name": "Caja2"}
        ],
        "verification": [
            {
                "id": "v1",
                "kind": "node_count",
                "description": "al menos 5 nodos",
                "nominal": 5.0,
                "tolerance": 0.0
            },
            {
                "id": "v2",
                "kind": "node_exists",
                "description": "la torre existe",
                "node_path": "Tower_1",
                "tolerance": 0.0
            }
        ],
        "key_dimensions": {}
    })
}

// ============================================================================
// QA Report (returned by scene/validate)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct QAReport {
    pub error_type: ErrorType,
    pub passed: bool,
    pub details: Vec<QADetail>,
    pub engine_a: EngineReport,
    pub engine_b: EngineReport,
    pub suggestions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct QADetail {
    pub target_id: String,
    pub passed: bool,
    pub measured: Option<f32>,
    pub expected: Option<f32>,
    pub deviation: Option<f32>,
    pub message: String,
    pub severity: String, // info, warning, error, fatal
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct EngineReport {
    pub engine_name: String,
    pub results: Vec<QADetail>,
    pub summary: String,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

// ============================================================================
// Scene State (internal, stored in SceneRegistry)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct LockInfo {
    pub agent_id: String,
    pub scene_path: String,
    pub progress: String,
    pub pid: u32,
    pub since: String, // ISO 8601 timestamp
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, JsonSchema)]
pub struct SceneState {
    pub lock_id: String,
    pub scene_path: String,
    pub mode: SceneMode,
    pub context: Option<SceneContext>,
    pub plan: Option<ScenePlan>,
    pub qa_report: Option<QAReport>,
    pub dirty: bool,
    pub lock_info: Option<LockInfo>,
}

// ============================================================================
// Request/Response Types for scene tool actions
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneOpenRequest {
    pub scene_path: String,
    #[serde(default)]
    pub mode: SceneMode,
    #[serde(default)]
    pub agent_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneOpenResponse {
    pub lock_id: String,
    pub scene_context: SceneContext,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ScenePlanRequest {
    pub plan: ScenePlan,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ScenePlanResponse {
    pub ok: bool,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneOrchestrateResponse {
    pub executed_steps: Vec<String>,
    pub coords: Vec<serde_json::Value>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneValidateResponse {
    pub qa_report: QAReport,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneCommitRequest {
    #[serde(default = "default_true")]
    pub save: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneCommitResponse {
    pub saved: bool,
    pub scene_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SceneStatusResponse {
    pub lock_id: Option<String>,
    pub scene_path: String,
    pub mode: SceneMode,
    pub dirty: bool,
    pub has_plan: bool,
    pub qa_status: Option<ErrorType>,
    pub lock_info: Option<LockInfo>,
}

// ============================================================================
// Helper: Generate JSON Schema for ScenePlan (for agent guidance)
// ============================================================================

pub fn generate_plan_schema() -> serde_json::Value {
    serde_json::json!({
        "type": "object",
        "properties": {
            "plan_id": {"type": "string", "description": "Unique plan identifier"},
            "scene_path": {"type": "string", "description": "Target scene path (res://...)"},
            "workplane": {"type": "string", "enum": ["XZ", "XY", "YZ"], "default": "XZ"},
            "workplane_offset": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}, "default": {"x": 0, "y": 0, "z": 0}},
            "steps": {
                "type": "array",
                "items": {"type": "object", "properties": {
                    "action": {"type": "string", "enum": ["add_node", "set_transform", "add_resource", "connect_signal", "instantiate_template", "remove_node", "duplicate_node"]},
                    "id": {"type": "string"},
                    "node_type": {"type": "string"},
                    "name": {"type": "string"},
                    "parent": {"type": "string"},
                    "workplane": {"type": "string", "enum": ["XZ", "XY", "YZ"]},
                    "local_pos": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "local_rot": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "local_scale": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "resource_path": {"type": "string"},
                    "script_path": {"type": "string"},
                    "template": {"type": "string"},
                    "template_params": {"type": "object"},
                    "node_path": {"type": "string"},
                    "position": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "rotation": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "scale": {"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}}},
                    "transform": {"type": "object"},
                    "anchors": {"type": "object", "properties": {"left": {"type": "number"}, "top": {"type": "number"}, "right": {"type": "number"}, "bottom": {"type": "number"}}},
                    "offsets": {"type": "object", "properties": {"left": {"type": "number"}, "top": {"type": "number"}, "right": {"type": "number"}, "bottom": {"type": "number"}}},
                    "anchors_preset": {"type": "integer"},
                    "resource_type": {"type": "string"},
                    "path": {"type": "string"},
                    "properties": {"type": "object"},
                    "from_node": {"type": "string"},
                    "signal_name": {"type": "string"},
                    "to_node": {"type": "string"},
                    "method": {"type": "string"},
                    "new_name": {"type": "string"},
                    "new_parent": {"type": "string"},
                    "properties": {"type": "object", "description": "props libres del inspector: colores {r,g,b,a}, vectores {x,y,z}, arrays, paths res://"}
                }, "required": ["action", "id"]}
            },
            "verification": {
                "type": "array",
                "items": {"type": "object", "properties": {
                    "id": {"type": "string"},
                    "kind": {"type": "string", "enum": ["node_count", "bbox_max", "bbox_min", "script_attached", "resource_exists", "signal_connected", "node_exists", "property_value", "custom"]},
                    "description": {"type": "string"},
                    "nominal": {"type": "number"},
                    "tolerance": {"type": "number", "default": 0.1},
                    "node_path": {"type": "string"},
                    "selector": {"type": "string"}
                }, "required": ["id", "kind", "description"]}
            },
            "key_dimensions": {"type": "object"}
        },
        "required": ["plan_id", "scene_path", "steps"]
    })
}

// ============================================================================
// Coordinate Resolution Helpers
// ============================================================================

impl SceneContext {
    /// Resolve local coordinates to global based on workplane
    pub fn resolve_local_to_global(&self, local: &Vector3, workplane: &Workplane, offset: &Vector3) -> Vector3 {
        // Identidad + offset (2026-08-24): el agente piensa en coords de MUNDO
        // (igual que set_props position). El swap y/z del XZ antiguo era una
        // trampa silenciosa — el workplane queda como intención documental.
        let _ = workplane;
        Vector3 {
            x: local.x + offset.x,
            y: local.y + offset.y,
            z: local.z + offset.z,
        }
    }

    /// Resolve local rotation to global based on workplane
    pub fn resolve_local_rotation(&self, local: &Vector3, workplane: &Workplane) -> Vector3 {
        // Identidad (2026-08-24): misma razón que resolve_local_to_global —
        // el agente especifica rotación de mundo directa (grados).
        let _ = workplane;
        Vector3 {
            x: local.x,
            y: local.y,
            z: local.z,
        }
    }
}