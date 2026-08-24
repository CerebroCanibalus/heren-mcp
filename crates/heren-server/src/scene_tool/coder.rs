//! Scene Coder — Deterministic translator: ScenePlan → MCP calls
//! Zero-LLM for common operations (like MAC's _plan_to_code)

use crate::scene_tool::schemas::{ScenePlan, SceneContext, SceneStep, Vector3};
use serde_json::Value;
use std::collections::HashMap;

/// Represents a single MCP tool call to be executed
#[derive(Debug, Clone)]
pub struct MCPCall {
    /// id del step del plan que originó la call (trazabilidad en warnings, E4)
    pub step_id: String,
    pub tool: String,
    pub args: Value,
    pub description: String,
}

/// SceneCoder translates a ScenePlan into a batch of MCP calls
pub struct SceneCoder;

impl SceneCoder {
    /// Convert ScenePlan to ordered MCP calls
    pub fn plan_to_mcp_calls(plan: &ScenePlan, context: &SceneContext) -> Vec<MCPCall> {
        let mut calls = Vec::new();
        let mut node_props_batch: HashMap<String, Value> = HashMap::new();
        
        for step in &plan.steps {
            match step {
                SceneStep::AddNode { id, node_type, name, parent, workplane, local_pos, local_rot, local_scale, resource_path, script_path, template, template_params, properties } => {
                    // 🚨 node/add SOLO aplica `properties` (dict) + script:
                    // position/rotation/scale/recurso van DENTRO de properties
                    // (2026-08-24 — antes se emitían como args sueltos que el
                    // handler ignoraba → nodos en (0,0,0) silenciosamente).
                    //
                    // P0a: `properties` del step pasa VERBATIM al plugin — su
                    // deserialize_value ya convierte {r,g,b}→Color, {x,y,z}→
                    // Vector3, arrays y paths res://. Precedencia: las props
                    // EXPLÍCITAS del agente sobreescriben lo derivado.
                    let mut props = serde_json::json!({});
                    if local_pos.x != 0.0 || local_pos.y != 0.0 || local_pos.z != 0.0 {
                        props["position"] = serde_json::to_value(local_pos).unwrap_or(Value::Null);
                    }
                    if local_rot.x != 0.0 || local_rot.y != 0.0 || local_rot.z != 0.0 {
                        props["rotation_degrees"] = serde_json::to_value(local_rot).unwrap_or(Value::Null);
                    }
                    if local_scale.x != 0.0 || local_scale.y != 0.0 || local_scale.z != 0.0 {
                        props["scale"] = serde_json::to_value(local_scale).unwrap_or(Value::Null);
                    }
                    if let Some(res_path) = resource_path {
                        // Propiedad correcta según tipo (node/add no tiene resource_path).
                        let prop = match node_type.as_str() {
                            "CollisionShape3D" | "CollisionShape2D" => "shape",
                            _ => "mesh",
                        };
                        props[prop] = Value::String(res_path.clone());
                    }
                    if let Some(script) = script_path {
                        props["script"] = Value::String(script.clone());
                    }
                    // Explícito gana (merge al final).
                    for (k, v) in properties {
                        props[k] = v.clone();
                    }

                    // Handle template instantiation
                    if let Some(tmpl) = template {
                        calls.push(MCPCall {
                            step_id: id.clone(),
                            tool: "node".to_string(),
                            args: serde_json::json!({
                                "action": "instantiate",
                                "template": tmpl,
                                "parent_path": parent,
                                "node_name": name,
                                "properties": template_params,
                                "scene_path": plan.scene_path,
                            }),
                            description: format!("Instantiate template '{tmpl}' as '{name}' under '{parent}'"),
                        });
                    } else {
                        let zero = Vector3::default();
                        let has_offset = plan.workplane_offset != zero;
                        let global_pos = context.resolve_local_to_global(local_pos, workplane, &plan.workplane_offset);
                        let desc_pos = (global_pos.x, global_pos.y, global_pos.z);
                        // posición si hay local != 0 O el plan tiene offset
                        if *local_pos != zero || has_offset {
                            props["position"] = serde_json::to_value(global_pos).unwrap_or(Value::Null);
                        }
                        calls.push(MCPCall {
                            step_id: id.clone(),
                            tool: "node".to_string(),
                            args: serde_json::json!({
                                "action": "add",
                                "node_type": node_type,
                                "node_name": name,
                                "parent_path": parent,
                                "properties": props,
                                "scene_path": plan.scene_path,
                            }),
                            description: format!("Add {} '{}' under '{}' at ({:.1}, {:.1}, {:.1})", node_type, name, parent, desc_pos.0, desc_pos.1, desc_pos.2),
                        });
                    }
                }
                
                SceneStep::SetTransform { id: _, node_path, position, rotation, scale, transform, anchors, offsets, anchors_preset } => {
                    let mut props = serde_json::Map::new();
                    
                    if let Some(pos) = position {
                        props.insert("position".to_string(), serde_json::to_value(pos).unwrap_or(Value::Null));
                    }
                    if let Some(rot) = rotation {
                        props.insert("rotation".to_string(), serde_json::to_value(rot).unwrap_or(Value::Null));
                    }
                    if let Some(scl) = scale {
                        props.insert("scale".to_string(), serde_json::to_value(scl).unwrap_or(Value::Null));
                    }
                    if let Some(t) = transform {
                        props.insert("transform".to_string(), serde_json::to_value(t).unwrap_or(Value::Null));
                    }
                    if let Some(a) = anchors {
                        props.insert("anchor_left".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(a.left)).unwrap()));
                        props.insert("anchor_top".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(a.top)).unwrap()));
                        props.insert("anchor_right".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(a.right)).unwrap()));
                        props.insert("anchor_bottom".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(a.bottom)).unwrap()));
                    }
                    if let Some(o) = offsets {
                        props.insert("offset_left".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(o.left)).unwrap()));
                        props.insert("offset_top".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(o.top)).unwrap()));
                        props.insert("offset_right".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(o.right)).unwrap()));
                        props.insert("offset_bottom".to_string(), Value::Number(serde_json::Number::from_f64(f64::from(o.bottom)).unwrap()));
                    }
                    if let Some(preset) = anchors_preset {
                        props.insert("anchors_preset".to_string(), Value::Number((*preset).into()));
                    }
                    
                    if !props.is_empty() {
                        // Batch set_props by node_path
                        node_props_batch.entry(node_path.clone())
                            .or_insert_with(|| Value::Object(serde_json::Map::new()))
                            .as_object_mut()
                            .unwrap()
                            .extend(props);
                    }
                }
                
                SceneStep::AddResource { id, resource_type, path, properties, template } => {
                    let mut args = serde_json::json!({
                        "action": "create",
                        "resource_type": resource_type,
                        "resource_path": path,
                        "scene_path": plan.scene_path,
                    });
                    
                    if !properties.is_empty() {
                        args["properties"] = serde_json::to_value(properties).unwrap_or(Value::Null);
                    }
                    if let Some(tmpl) = template {
                        args["template"] = Value::String(tmpl.clone());
                    }
                    
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "resource".to_string(),
                        args,
                        description: format!("Create resource '{resource_type}' at '{path}'"),
                    });
                }
                
                SceneStep::ConnectSignal { id, from_node, signal_name, to_node, method } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "signal".to_string(),
                        args: serde_json::json!({
                            "action": "connect",
                            "from_node": from_node,
                            "signal_name": signal_name,
                            "to_node": to_node,
                            "method": method,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Connect {from_node}::{signal_name} -> {to_node}::{method}"),
                    });
                }
                
                SceneStep::InstantiateTemplate { id, template, parent, workplane, local_pos, params } => {
                    let global_pos = context.resolve_local_to_global(local_pos, workplane, &plan.workplane_offset);
                    
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "instantiate",
                            "template": template,
                            "parent_path": parent,
                            "position": {"x": global_pos.x, "y": global_pos.y, "z": global_pos.z},
                            "properties": params,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Instantiate template '{template}' under '{parent}'"),
                    });
                }
                
                SceneStep::RemoveNode { id, node_path } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "remove",
                            "node_path": node_path,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Remove node '{node_path}'"),
                    });
                }
                
                SceneStep::DuplicateNode { id, node_path, new_name, new_parent } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "duplicate",
                            "node_path": node_path,
                            "new_name": new_name,
                            "new_parent": new_parent,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Duplicate '{node_path}' as '{new_name}'"),
                    });
                }
                // Fase 1: step genérico → MCPCall directo (sin transformación).
                // El agente manda tool/action/args tal cual las conoce de tools/list.
                SceneStep::Generic { id, tool, tool_action, args } => {
                    let mut full_args = serde_json::to_value(args).unwrap_or(Value::Null);
                    if let Value::Object(ref mut map) = full_args {
                        map.insert("action".to_string(), Value::String(tool_action.clone()));
                        map.insert("scene_path".to_string(), Value::String(plan.scene_path.clone()));
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: tool.clone(),
                        args: full_args,
                        description: format!("{tool}/{tool_action}"),
                    });
                }
                // === Fase 2 — Animation typed steps ===
                SceneStep::AddTrack { id, player_path, anim_name, track_type, node_path, property, skeleton_path } => {
                    let mut args = serde_json::json!({
                        "player_path": player_path,
                        "anim_name": anim_name,
                        "track_type": track_type,
                        "node_path": node_path,
                        "property": property,
                        "scene_path": plan.scene_path,
                    });
                    if let Some(sp) = skeleton_path {
                        args["skeleton_path"] = Value::String(sp.clone());
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args,
                        description: format!("animation/add_track '{anim_name}' ({track_type})"),
                    });
                }
                SceneStep::AddKey { id, player_path, anim_name, track_idx, time, value, transition } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "player_path": player_path,
                            "anim_name": anim_name,
                            "track_idx": track_idx,
                            "time": time,
                            "value": value,
                            "transition": transition,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/add_key '{anim_name}' track={track_idx} t={time}"),
                    });
                }
                // === Fase 3 — Skeleton typed steps ===
                SceneStep::AddBone { id, skeleton_path, bone_name, parent_bone, rest_transform } => {
                    let mut args = serde_json::json!({
                        "skeleton_path": skeleton_path,
                        "bone_name": bone_name,
                        "scene_path": plan.scene_path,
                    });
                    if !parent_bone.is_empty() {
                        args["parent_bone"] = Value::String(parent_bone.clone());
                    }
                    if !rest_transform.is_null() {
                        args["rest_transform"] = rest_transform.clone();
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args,
                        description: format!("skeleton/add_bone '{bone_name}'"),
                    });
                }
                SceneStep::SetBoneRest { id, skeleton_path, bone_name, rest_transform } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args: serde_json::json!({
                            "skeleton_path": skeleton_path,
                            "bone_name": bone_name,
                            "rest_transform": rest_transform,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("skeleton/set_rest '{bone_name}'"),
                    });
                }
                // === Fase 4 — Script/Shader typed steps ===
                SceneStep::AttachScript { id, node_path, script_path } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "set_props",
                            "node_path": node_path,
                            "properties": {"script": script_path},
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("attach script '{script_path}' to '{node_path}'"),
                    });
                }
                SceneStep::CreateShader { id, shader_path, shader_type, code } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "shader".to_string(),
                        args: serde_json::json!({
                            "shader_path": shader_path,
                            "shader_type": shader_type,
                            "code": code,
                        }),
                        description: format!("shader/create '{shader_path}' ({shader_type})"),
                    });
                }
                SceneStep::SetShaderUniform { id, material_path, uniform_name, value } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "shader".to_string(),
                        args: serde_json::json!({
                            "action": "uniform",
                            "material_path": material_path,
                            "uniform_name": uniform_name,
                            "value": value,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("shader/uniform '{uniform_name}' on '{material_path}'"),
                    });
                }
            }
        }
        
        // Emit batched set_props calls
        for (node_path, props) in node_props_batch {
            if let Value::Object(map) = props {
                if !map.is_empty() {
                    calls.push(MCPCall {
                        step_id: "set_props_batch".to_string(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "set_props",
                            "node_path": node_path,
                            "properties": Value::Object(map),
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Set properties on '{node_path}'"),
                    });
                }
            }
        }
        
        calls
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene_tool::schemas::*;
    
    #[test]
    fn test_plan_to_calls_basic() {
        let plan = ScenePlan {
            plan_id: "test-1".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3 { x: 0.0, y: 1.0, z: 0.0 },
            steps: vec![
                SceneStep::AddNode {
                    id: "s1".to_string(),
                    node_type: "Node3D".to_string(),
                    name: "Robot".to_string(),
                    parent: ".".to_string(),
                    workplane: Workplane::XZ,
                    local_pos: Vector3 { x: 0.0, y: 0.0, z: 0.0 },
                    local_rot: Vector3::default(),
                    local_scale: Vector3::default(),
                    resource_path: None,
                    script_path: None,
                    template: None,
                    template_params: HashMap::new(),
                    properties: HashMap::new(),
                },
                SceneStep::AddNode {
                    id: "s2".to_string(),
                    node_type: "MeshInstance3D".to_string(),
                    name: "Body".to_string(),
                    parent: "Robot".to_string(),
                    workplane: Workplane::XZ,
                    local_pos: Vector3 { x: 0.0, y: 0.0, z: 0.0 },
                    local_rot: Vector3::default(),
                    local_scale: Vector3 { x: 1.0, y: 2.0, z: 1.0 },
                    resource_path: None,
                    script_path: None,
                    template: None,
                    template_params: HashMap::new(),
                    properties: HashMap::new(),
                },
            ],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        
        let context = SceneContext {
            scene_path: "res://test.tscn".to_string(),
            root_name: "Main".to_string(),
            root_type: "Node3D".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3 { x: 0.0, y: 1.0, z: 0.0 },
            bbox: AABB::default(),
            nodes: vec![],
            resources: vec![],
            scripts: vec![],
            plan_schema: Value::Null,
        };
        
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &context);
        
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].tool, "node");
        assert_eq!(calls[0].args["action"], "add");
        assert_eq!(calls[0].args["node_name"], "Robot");
        
        // Second node should have position with workplane_offset applied
        assert_eq!(calls[1].args["properties"]["position"]["y"], 1.0); // workplane_offset.y = 1.0 (identidad)
    }
    
    #[test]
    fn test_workplane_xy_ui() {
        let plan = ScenePlan {
            plan_id: "test-ui".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XY,
            workplane_offset: Vector3::default(),
            steps: vec![
                SceneStep::AddNode {
                    id: "s1".to_string(),
                    node_type: "Control".to_string(),
                    name: "HUD".to_string(),
                    parent: "UI".to_string(),
                    workplane: Workplane::XY,
                    local_pos: Vector3 { x: 20.0, y: 20.0, z: 0.0 },
                    local_rot: Vector3::default(),
                    local_scale: Vector3::default(),
                    resource_path: None,
                    script_path: None,
                    template: None,
                    template_params: HashMap::new(),
                    properties: HashMap::new(),
                },
            ],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        
        let context = SceneContext {
            scene_path: "res://test.tscn".to_string(),
            root_name: "Main".to_string(),
            root_type: "Node3D".to_string(),
            workplane: Workplane::XY,
            workplane_offset: Vector3::default(),
            bbox: AABB::default(),
            nodes: vec![],
            resources: vec![],
            scripts: vec![],
            plan_schema: Value::Null,
        };
        
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &context);
        
        assert_eq!(calls[0].args["properties"]["position"]["x"], 20.0);
        assert_eq!(calls[0].args["properties"]["position"]["y"], 20.0);
        assert_eq!(calls[0].args["properties"]["position"]["z"], 0.0);
    }
    
    #[test]
    fn test_set_transform_batching() {
        let plan = ScenePlan {
            plan_id: "test-batch".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![
                SceneStep::SetTransform {
                    id: "s1".to_string(),
                    node_path: "Robot/Body".to_string(),
                    position: Some(Vector3 { x: 1.0, y: 2.0, z: 3.0 }),
                    rotation: None,
                    scale: Some(Vector3 { x: 2.0, y: 2.0, z: 2.0 }),
                    transform: None,
                    anchors: None,
                    offsets: None,
                    anchors_preset: None,
                },
                SceneStep::SetTransform {
                    id: "s2".to_string(),
                    node_path: "Robot/Body".to_string(),
                    position: None,
                    rotation: Some(Vector3 { x: 0.0, y: 1.57, z: 0.0 }),
                    scale: None,
                    transform: None,
                    anchors: None,
                    offsets: None,
                    anchors_preset: None,
                },
            ],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        
        let context = SceneContext::default();
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &context);
        
        // Should batch into single set_props call
        let set_props_calls: Vec<_> = calls.iter().filter(|c| c.tool == "node").collect();
        assert_eq!(set_props_calls.len(), 1);
        
        let props = &set_props_calls[0].args["properties"];
        assert!(props["position"].is_object());
        assert!(props["scale"].is_object());
        assert!(props["rotation"].is_object());
    }
}