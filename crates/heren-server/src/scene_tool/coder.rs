//! Scene Coder — Deterministic translator: ScenePlan → MCP calls
//! Zero-LLM for common operations (like MAC's _plan_to_code)

use crate::scene_tool::schemas::{ScenePlan, SceneContext, SceneStep, Vector3, Transform3D};
use serde_json::Value;
use std::collections::HashMap;

/// P-M10: pose tracking para consolidar AddNode + SetTransform del mismo nodo.
#[derive(Debug, Clone, Default)]
struct Poses {
    position: Vector3,
    rotation: Vector3,
    scale: Vector3,
}

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
        // P-M10: trackea el "last position/rotation/scale" por nodo añadido en
        // este plan. SetTransform posterior con el mismo node_path omite el campo
        // si ya está en el mapa (evita pisar la pose del AddNode).
        let mut last_posed: HashMap<String, Poses> = HashMap::new();

        // Primera pasada: AddNode → registra poses.
        for step in &plan.steps {
            if let SceneStep::AddNode { name, parent, local_pos, local_rot, local_scale, .. } = step {
                let path = if parent == "." { name.clone() } else { format!("{parent}/{name}") };
                last_posed.insert(path, Poses {
                    position: local_pos.clone(),
                    rotation: local_rot.clone(),
                    scale: local_scale.clone(),
                });
            }
        }

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
                    #[allow(clippy::float_cmp)]
                    if local_scale.x != 1.0 || local_scale.y != 1.0 || local_scale.z != 1.0 {
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
                        // P-B13: merge template_params + properties del step.
                        // Las properties explícitas del agente ganan sobre template_params.
                        let mut tmpl_props = serde_json::Map::new();
                        for (k, v) in template_params {
                            tmpl_props.insert(k.clone(), v.clone());
                        }
                        if let Value::Object(map) = &props {
                            for (k, v) in map {
                                tmpl_props.insert(k.clone(), v.clone());
                            }
                        }
                        calls.push(MCPCall {
                            step_id: id.clone(),
                            tool: "node".to_string(),
                            args: serde_json::json!({
                                "action": "instantiate",
                                "template": tmpl,
                                "parent_path": parent,
                                "node_name": name,
                                "properties": Value::Object(tmpl_props),
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
                    // P-M10: si este nodo se acaba de añadir con local_pos y el
                    // SetTransform NO cambia nada, omitimos position/rotation/scale
                    // para no emitir una segunda call que pise el AddNode.
                    let last = last_posed.get(node_path);
                    let skip_pose = last.is_some();

                    if let Some(pos) = position {
                        if !skip_pose || last.is_none_or(|p| p.position != *pos) {
                            props.insert("position".to_string(), serde_json::to_value(pos).unwrap_or(Value::Null));
                        }
                    }
                    if let Some(rot) = rotation {
                        if !skip_pose || last.is_none_or(|p| p.rotation != *rot) {
                            props.insert("rotation".to_string(), serde_json::to_value(rot).unwrap_or(Value::Null));
                        }
                    }
                    if let Some(scl) = scale {
                        if !skip_pose || last.is_none_or(|p| p.scale != *scl) {
                            props.insert("scale".to_string(), serde_json::to_value(scl).unwrap_or(Value::Null));
                        }
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
                // Round-3: DisconnectSignal (P-M4).
                SceneStep::DisconnectSignal { id, from_node, signal_name, to_node, method } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "signal".to_string(),
                        args: serde_json::json!({
                            "action": "disconnect",
                            "from_node": from_node,
                            "signal_name": signal_name,
                            "to_node": to_node,
                            "method": method,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("Disconnect {from_node}::{signal_name} -> {to_node}::{method}"),
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
                        "action": "add_track",
                        "player_path": player_path,
                        "anim_name": anim_name,
                        "track_type": track_type,
                        "node_path": node_path,
                        "scene_path": plan.scene_path,
                    });
                    // P-B4: omitir property si vacío — evita path "Node:" con
                    // dos puntos colgantes en handlers que concatenan.
                    if !property.is_empty() {
                        args["property"] = Value::String(property.clone());
                    }
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
                            "action": "add_key",
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
                // === Fase 2 — Animation typed steps (new) ===
                SceneStep::CreateAnimationPlayer { id, node_path, player_name } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "create_player",
                            "node_path": node_path,
                            "player_name": player_name,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/create_player '{player_name}' under '{node_path}'"),
                    });
                }
                SceneStep::CreateAnimation { id, player_path, anim_name, length, loop_mode } => {
                    let mut args = serde_json::json!({
                        "action": "create",
                        "player_path": player_path,
                        "anim_name": anim_name,
                        "length": length,
                        "scene_path": plan.scene_path,
                    });
                    if !loop_mode.is_empty() {
                        args["loop_mode"] = Value::String(loop_mode.clone());
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args,
                        description: format!("animation/create '{anim_name}' length={length}s"),
                    });
                }
                SceneStep::SetAnimPlayerProps { id, player_path, properties } => {
                    let mut args = serde_json::json!({
                        "action": "update_props",
                        "player_path": player_path,
                        "scene_path": plan.scene_path,
                    });
                    // Merge properties into top-level args for the handler.
                    for (k, v) in properties {
                        args[k] = v.clone();
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args,
                        description: format!("animation/update_props '{player_path}'"),
                    });
                }
                SceneStep::DuplicateAnimation { id, player_path, source_anim, new_anim } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "duplicate",
                            "player_path": player_path,
                            "anim_name": source_anim,
                            "new_name": new_anim,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/duplicate '{source_anim}' → '{new_anim}'"),
                    });
                }
                SceneStep::RemoveAnimation { id, player_path, anim_name } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "delete",
                            "player_path": player_path,
                            "anim_name": anim_name,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/delete '{anim_name}'"),
                    });
                }
                // === Fase 2b — AnimationTree typed steps ===
                SceneStep::CreateAnimationTree { id, node_path, tree_name, root_type, player_path } => {
                    // AnimationTree is a Node — create it via node/add.
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "add",
                            "node_type": "AnimationTree",
                            "node_name": tree_name,
                            "parent_path": node_path,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("node/add AnimationTree '{tree_name}' ({root_type}) under '{node_path}'"),
                    });
                    // P-B5: si hay player_path, asigna tree.anim_player inmediatamente
                    // (evita que el tree quede huérfano).
                    if let Some(pp) = player_path {
                        calls.push(MCPCall {
                            step_id: format!("{id}_player"),
                            tool: "animation".to_string(),
                            args: serde_json::json!({
                                "action": "tree_set_anim_player",
                                "tree_path": tree_name,
                                "player_path": pp,
                                "scene_path": plan.scene_path,
                            }),
                            description: format!("animation/tree_set_anim_player '{tree_name}' <- '{pp}'"),
                        });
                    }
                }
                SceneStep::AddBlendNode { id, tree_path, node_name, node_type, animation, graph_position } => {
                    // P-B2: usa el handler real tree_add_blend_node (bt.add_node).
                    // Antes esto emitía tree_set_param con un dict falso → falla.
                    let mut args = serde_json::json!({
                        "action": "tree_add_blend_node",
                        "tree_path": tree_path,
                        "node_name": node_name,
                        "node_type": node_type,
                        "scene_path": plan.scene_path,
                    });
                    if !animation.is_empty() {
                        args["animation"] = Value::String(animation.clone());
                    }
                    if let Some(pos) = graph_position {
                        args["graph_position"] = pos.clone();
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args,
                        description: format!("animation/tree_add_blend_node '{node_name}' ({node_type})"),
                    });
                }
                SceneStep::ConnectBlendNodes { id, tree_path, from_node, from_port, to_node, to_port: _ } => {
                    // P-B3: usa el handler real tree_connect_blend_nodes (bt.connect_node).
                    // Godot 4 acepta 3 args (to_port lo asigna el tree); el
                    // cuarto argumento se ignora silenciosamente.
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "tree_connect_blend_nodes",
                            "tree_path": tree_path,
                            "from_node": from_node,
                            "from_port": from_port,
                            "to_node": to_node,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("connect '{from_node}':{from_port} → '{to_node}'"),
                    });
                }
                SceneStep::SetTreeRoot { id, tree_path, root_node } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node_props".to_string(),
                        args: serde_json::json!({
                            "action": "set_prop",
                            "node_path": tree_path,
                            "property_name": "tree_root",
                            "value": root_node,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("set tree_root = '{root_node}'"),
                    });
                }
                SceneStep::SetTreeParam { id, tree_path, param_name, value } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "tree_set_param",
                            "tree_path": tree_path,
                            "param_name": param_name,
                            "value": value,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/tree_set_param '{param_name}'"),
                    });
                }
                // Round-3: SetTreeActive (P-M12).
                SceneStep::SetTreeActive { id, tree_path, active } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "animation".to_string(),
                        args: serde_json::json!({
                            "action": "tree_activate",
                            "tree_path": tree_path,
                            "active": active,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("animation/tree_activate {tree_path} active={active}"),
                    });
                }
                // Step dedicado para asignar el AnimationPlayer del tree
                // (alternativa a CreateAnimationTree.player_path).
                // Si llega como GenericStep, el coder lo trata igual — este
                // step tipado evita ambigüedad.
                // === Fase 3 — Skeleton typed steps ===
                SceneStep::AddBone { id, skeleton_path, bone_name, parent_bone, rest_transform } => {
                    let mut args = serde_json::json!({
                        "action": "skeleton_add_bone",
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
                            "action": "skeleton_set_rest",
                            "skeleton_path": skeleton_path,
                            "bone_name": bone_name,
                            "rest_transform": rest_transform,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("skeleton/set_rest '{bone_name}'"),
                    });
                }
                // === Fase C — Skeleton typed steps (new) ===
                SceneStep::CreateSkeleton { id, node_path, dimension, skeleton_name, bones } => {
                    // Skeleton is a Node — create it via node/add.
                    let node_type = if dimension == "2d" { "Skeleton2D" } else { "Skeleton3D" };
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "node".to_string(),
                        args: serde_json::json!({
                            "action": "add",
                            "node_type": node_type,
                            "node_name": skeleton_name,
                            "parent_path": node_path,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("node/add {node_type} '{skeleton_name}' under '{node_path}'"),
                    });
                    // If bones are provided, create them sequentially.
                    for bone in bones {
                        let bone_obj = bone.as_object();
                        let bone_name = bone_obj
                            .and_then(|o| o.get("name"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        if bone_name.is_empty() {
                            continue;
                        }
                        let parent_bone = bone_obj
                            .and_then(|o| o.get("parent"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let rest_transform = bone_obj
                            .and_then(|o| o.get("rest_transform"))
                            .cloned()
                            .unwrap_or(serde_json::Value::Null);
                        let mut bone_args = serde_json::json!({
                            "action": "skeleton_add_bone",
                            "skeleton_path": skeleton_name,
                            "bone_name": bone_name,
                            "scene_path": plan.scene_path,
                        });
                        if !parent_bone.is_empty() {
                            bone_args["parent_bone"] = Value::String(parent_bone.to_string());
                        }
                        if !rest_transform.is_null() {
                            bone_args["rest_transform"] = rest_transform;
                        }
                        calls.push(MCPCall {
                            step_id: id.clone(),
                            tool: "skeleton".to_string(),
                            args: bone_args,
                            description: format!("skeleton/add_bone '{bone_name}' → '{skeleton_name}'"),
                        });
                    }
                }
                SceneStep::SetBonePose { id, skeleton_path, bone_name, pose } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args: serde_json::json!({
                            "action": "skeleton_set_pose",
                            "skeleton_path": skeleton_path,
                            "bone_name": bone_name,
                            "pose": pose,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("skeleton/set_pose '{bone_name}'"),
                    });
                }
                SceneStep::CreateIK { id, skeleton_path, ik_name, dimension, properties } => {
                    let mut args = serde_json::json!({
                        "action": "skeleton_ik",
                        "skeleton_path": skeleton_path,
                        "ik_name": ik_name,
                        "scene_path": plan.scene_path,
                    });
                    // P-B6: dimension vacío → el handler auto-detecta.
                    if !dimension.is_empty() {
                        args["dimension"] = Value::String(dimension.clone());
                    }
                    for (k, v) in properties {
                        args[k] = v.clone();
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args,
                        description: format!("skeleton/ik '{ik_name}' ({dimension})"),
                    });
                }
                SceneStep::SetSkin { id, mesh_path, skeleton_path } => {
                    // SetSkin via skeleton/skin action.
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args: serde_json::json!({
                            "action": "skeleton_skin",
                            "skeleton_path": skeleton_path,
                            "mesh_path": mesh_path,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("skeleton/skin mesh='{mesh_path}' → skeleton='{skeleton_path}'"),
                    });
                }
                // Round-3 (2026-09-03): RemoveBone + AttachBone.
                SceneStep::RemoveBone { id, skeleton_path, bone_name } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args: serde_json::json!({
                            "action": "skeleton_remove_bone",
                            "skeleton_path": skeleton_path,
                            "bone_name": bone_name,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("skeleton/remove_bone '{bone_name}'"),
                    });
                }
                SceneStep::AttachBone { id, parent_path, bone_name, bone_idx, node_name, mesh_path, offset } => {
                    let mut args = serde_json::json!({
                        "action": "skeleton_attachment",
                        "skeleton_path": parent_path,
                        "bone_name": bone_name,
                        "scene_path": plan.scene_path,
                    });
                    if !node_name.is_empty() {
                        args["attachment_name"] = Value::String(node_name.clone());
                    }
                    if !mesh_path.is_empty() {
                        args["mesh_path"] = Value::String(mesh_path.clone());
                    }
                    if let Some(idx) = bone_idx {
                        args["bone_idx"] = Value::Number((*idx).into());
                    }
                    if *offset != Transform3D::default() {
                        args["offset"] = serde_json::to_value(offset).unwrap_or(Value::Null);
                    }
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "skeleton".to_string(),
                        args,
                        description: format!("skeleton/attach bone='{bone_name}' under '{parent_path}'"),
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
                            "action": "create",
                            "shader_path": shader_path,
                            "shader_type": shader_type,
                            "code": code,
                        }),
                        description: format!("shader/create '{shader_path}' ({shader_type})"),
                    });
                }
                SceneStep::SetShaderUniform { id, node_path, uniform_name, value } => {
                    calls.push(MCPCall {
                        step_id: id.clone(),
                        tool: "shader".to_string(),
                        args: serde_json::json!({
                            "action": "uniform",
                            "node_path": node_path,
                            "uniform_name": uniform_name,
                            "value": value,
                            "scene_path": plan.scene_path,
                        }),
                        description: format!("shader/uniform '{uniform_name}' on '{node_path}'"),
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

    // ========== Tests de fixes del General (2026-09-03) ==========

    /// P-B4: AddTrack SIN property (vacío) no debe emitir `"property": ""` en el JSON.
    #[test]
    fn test_add_track_omits_empty_property() {
        let plan = ScenePlan {
            plan_id: "p1".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::AddTrack {
                id: "s1".into(),
                player_path: "AnimationPlayer".into(),
                anim_name: "idle".into(),
                track_type: "value".into(),
                node_path: "Caja".into(),
                property: String::new(),
                skeleton_path: None,
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls.len(), 1);
        let args = &calls[0].args;
        assert!(args.get("property").is_none(), "property vacío NO debe aparecer en JSON");
    }

    /// P-B13: AddNode con template mergea properties + template_params.
    #[test]
    fn test_add_node_template_merges_properties() {
        let mut template_params = HashMap::new();
        template_params.insert("Fill.color".into(), serde_json::json!({"r":1.0,"g":0.0,"b":0.0,"a":1.0}));
        let mut properties = HashMap::new();
        properties.insert("modulate".into(), serde_json::json!({"r":1.0,"g":1.0,"b":1.0,"a":0.5}));

        let plan = ScenePlan {
            plan_id: "p2".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XY,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::AddNode {
                id: "s1".into(),
                node_type: "Control".into(),
                name: "HealthBar".into(),
                parent: "UI/HUD".into(),
                workplane: Workplane::XY,
                local_pos: Vector3::default(),
                local_rot: Vector3::default(),
                local_scale: Vector3::default(),
                resource_path: None,
                script_path: None,
                template: Some("health_bar".into()),
                template_params,
                properties,
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls.len(), 1);
        let props = &calls[0].args["properties"];
        // Ambos campos deben estar presentes.
        assert!(props.get("Fill.color").is_some(), "template_params pasaron");
        assert!(props.get("modulate").is_some(), "properties del step pasaron");
    }

    /// P-B5: CreateAnimationTree con player_path emite 2 calls:
    /// una para añadir el nodo y otra para asignar anim_player.
    #[test]
    fn test_create_animation_tree_with_player() {
        let plan = ScenePlan {
            plan_id: "p3".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::CreateAnimationTree {
                id: "s1".into(),
                node_path: "Robot".into(),
                tree_name: "AnimationTree".into(),
                root_type: "AnimationNodeBlendTree".into(),
                player_path: Some("AnimationPlayer".into()),
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].args["action"], "add");
        assert_eq!(calls[0].args["node_type"], "AnimationTree");
        assert_eq!(calls[1].args["action"], "tree_set_anim_player");
        assert_eq!(calls[1].args["player_path"], "AnimationPlayer");
    }

    /// P-B2: AddBlendNode emite `tree_add_blend_node`, NO `tree_set_param`.
    #[test]
    fn test_add_blend_node_uses_real_handler() {
        let plan = ScenePlan {
            plan_id: "p4".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::AddBlendNode {
                id: "s1".into(),
                tree_path: "AnimationTree".into(),
                node_name: "Idle".into(),
                node_type: "AnimationNodeAnimation".into(),
                animation: "idle".into(),
                graph_position: Some(serde_json::json!({"x": 100.0, "y": 50.0})),
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls[0].args["action"], "tree_add_blend_node");
        assert_eq!(calls[0].args["animation"], "idle");
        assert_eq!(calls[0].args["graph_position"]["x"], 100.0);
    }

    /// P-B3: ConnectBlendNodes emite `tree_connect_blend_nodes` con 3 campos clave.
    #[test]
    fn test_connect_blend_nodes_uses_real_handler() {
        let plan = ScenePlan {
            plan_id: "p5".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::ConnectBlendNodes {
                id: "s1".into(),
                tree_path: "AnimationTree".into(),
                from_node: "Idle".into(),
                from_port: 0,
                to_node: "output".into(),
                to_port: 0,
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls[0].args["action"], "tree_connect_blend_nodes");
        assert_eq!(calls[0].args["from_node"], "Idle");
        assert_eq!(calls[0].args["to_node"], "output");
        // NO debe existir una propiedad "connections"
        assert!(calls[0].args.get("property_name").is_none());
    }

    /// P-B6: CreateIK emite `dimension` cuando se pasa.
    #[test]
    fn test_create_ik_dimension_passed_through() {
        let plan = ScenePlan {
            plan_id: "p6".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::CreateIK {
                id: "s1".into(),
                skeleton_path: "Skeleton2D".into(),
                ik_name: "ArmIK".into(),
                dimension: "2d".into(),
                properties: HashMap::new(),
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls[0].args["dimension"], "2d");
    }

    /// P-M10: AddNode con local_pos + SetTransform sobre el mismo nodo → 1 call,
    /// no se duplica el position en set_props posterior.
    #[test]
    fn test_add_node_then_set_transform_consolidated() {
        let plan = ScenePlan {
            plan_id: "p7".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![
                SceneStep::AddNode {
                    id: "s1".into(),
                    node_type: "Node3D".into(),
                    name: "Body".into(),
                    parent: "Robot".into(),
                    workplane: Workplane::XZ,
                    local_pos: Vector3 { x: 1.0, y: 2.0, z: 3.0 },
                    local_rot: Vector3::default(),
                    local_scale: Vector3::default(),
                    resource_path: None,
                    script_path: None,
                    template: None,
                    template_params: HashMap::new(),
                    properties: HashMap::new(),
                },
                SceneStep::SetTransform {
                    id: "s2".into(),
                    node_path: "Robot/Body".into(),
                    position: Some(Vector3 { x: 1.0, y: 2.0, z: 3.0 }),
                    rotation: None,
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
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        // Debe haber 1 call de add, y 0 calls adicionales (SetTransform se consolidó).
        let total: usize = calls.len();
        assert_eq!(total, 1, "SetTransform debe consolidarse con AddNode");
        assert_eq!(calls[0].args["action"], "add");
        assert_eq!(calls[0].args["properties"]["position"]["x"], 1.0);
    }

    /// P-M10 negativo: SetTransform con position DIFERENTE sí se emite.
    #[test]
    fn test_set_transform_different_position_emitted() {
        let plan = ScenePlan {
            plan_id: "p8".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![
                SceneStep::AddNode {
                    id: "s1".into(),
                    node_type: "Node3D".into(),
                    name: "Body".into(),
                    parent: "Robot".into(),
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
                SceneStep::SetTransform {
                    id: "s2".into(),
                    node_path: "Robot/Body".into(),
                    position: Some(Vector3 { x: 5.0, y: 0.0, z: 0.0 }),
                    rotation: None,
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
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls.len(), 2, "SetTransform con position distinta debe emitirse");
        assert_eq!(calls[1].args["properties"]["position"]["x"], 5.0);
    }

    /// P-M10: SetTransform sobre un nodo NO presente en AddNode → emite set_props.
    #[test]
    fn test_set_transform_no_prior_add() {
        let plan = ScenePlan {
            plan_id: "p9".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![SceneStep::SetTransform {
                id: "s1".into(),
                node_path: "ExistingBody".into(),
                position: Some(Vector3 { x: 1.0, y: 2.0, z: 3.0 }),
                rotation: None,
                scale: None,
                transform: None,
                anchors: None,
                offsets: None,
                anchors_preset: None,
            }],
            verification: vec![],
            key_dimensions: HashMap::new(),
        };
        let calls = SceneCoder::plan_to_mcp_calls(&plan, &SceneContext::default());
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].args["action"], "set_props");
    }
}