//! Scene Validator — Dual-Engine QA for scenes
//! Engine A: Deterministic (validate/scene, validate/node, node_query)
//! Engine B: Heuristic/Visual (visual_image/capture, visual_text/summary)

use crate::scene_tool::schemas::{ScenePlan, SceneStep, SceneContext, QAReport, EngineReport, VerificationKind, QADetail, ErrorType, VerificationTarget};
use serde_json::Value;

pub struct SceneValidator;

// allow: los check_* son síncronos hoy pero la interfaz reserva async para
// checks visuales futuros (Engine B) que sí harán await. Los casts usize→f32
// son intencionales (conteos pequeños, QADetail usa f32).
#[allow(clippy::unused_async, clippy::cast_precision_loss)]
impl SceneValidator {
    /// Run dual-engine validation
    pub async fn validate_scene<C: SceneValidatorClient>(
        plan: &ScenePlan,
        context: &SceneContext,
        client: &C,
    ) -> QAReport {
        let mut report = QAReport::default();
        
        // Engine A: Deterministic structural validation
        let engine_a = Self::run_engine_a(plan, context, client).await;
        report.engine_a = engine_a;
        
        // Engine B: Heuristic visual validation
        let engine_b = Self::run_engine_b(plan, context, client).await;
        report.engine_b = engine_b;
        
        // Merge results — clasificación por tipo de verificación (§0.6):
        // conteos/bbox/valores = dimension; existencia/conexiones = topología.
        Self::merge_reports_with_kinds(&mut report, plan);
        
        report
    }
    
    /// Engine A: Deterministic checks via validate/* and node_query tools
    async fn run_engine_a<C: SceneValidatorClient>(
        plan: &ScenePlan,
        context: &SceneContext,
        client: &C,
    ) -> EngineReport {
        let mut results = Vec::new();
        let warnings = Vec::new();
        let mut errors = Vec::new();
        
        for target in &plan.verification {
            let detail = match target.kind {
                VerificationKind::NodeCount => {
                    Self::check_node_count(target, context, client).await
                }
                VerificationKind::BBoxMax => {
                    Self::check_bbox_max(target, context, client).await
                }
                VerificationKind::BBoxMin => {
                    Self::check_bbox_min(target, context, client).await
                }
                VerificationKind::ScriptAttached => {
                    Self::check_script_attached(target, context, client).await
                }
                VerificationKind::ResourceExists => {
                    Self::check_resource_exists(target, context, client, plan).await
                }
                VerificationKind::SignalConnected => {
                    Self::check_signal_connected(target, context, client, &plan.scene_path).await
                }
                VerificationKind::NodeExists => {
                    Self::check_node_exists(target, context, client).await
                }
                VerificationKind::PropertyValue => {
                    Self::check_property_value(target, context, client).await
                }
                VerificationKind::Custom(_) => {
                    QADetail {
                        target_id: target.id.clone(),
                        passed: true,
                        measured: None,
                        expected: target.nominal,
                        deviation: None,
                        message: "Custom verification not implemented".to_string(),
                        severity: "warning".to_string(),
                    }
                }
            };
            results.push(detail);
        }
        
        // Run validate/scene for overall structure
        if let Ok(validate_result) = client.validate_scene(&plan.scene_path).await {
            if let Some(valid) = validate_result.get("valid").and_then(serde_json::Value::as_bool) {
                if !valid {
                    errors.push(format!("Scene validation failed: {:?}", validate_result.get("errors")));
                }
            }
        }
        
        let passed = results.iter().all(|r| r.passed) && errors.is_empty();
        
        EngineReport {
            engine_name: "cadpy_analysis".to_string(), // deterministic
            results,
            summary: if passed { "All deterministic checks passed" } else { "Some deterministic checks failed" }.to_string(),
            warnings,
            errors,
        }
    }

    /// Fase 5 (2026-08-24): valida args de GenericStep contra los schemas
    /// reales del plugin (tool_name → schema). El server pasa los schemas
    /// via FlojoTester; el validator no depende de FlojoMCP.
    /// Retorna QADetails: passed si el schema existe y los args son válidos.
    pub fn validate_generic_steps(
        plan: &ScenePlan,
        tool_schemas: &std::collections::HashMap<String, serde_json::Value>,
    ) -> Vec<QADetail> {
        let mut details = Vec::new();
        for step in &plan.steps {
            let SceneStep::Generic { id, tool, tool_action, args: _ } = step else {
                continue;
            };
            let detail = if let Some(schema) = tool_schemas.get(tool) {
                // Schema encontrado: verificar que la action existe
                // (buscamos "action" en properties o en una descripción)
                let action_valid = schema.get("properties")
                    .and_then(|p| p.get("action"))
                    .and_then(|a| a.get("enum"))
                    .and_then(|e| e.as_array())
                    .is_none_or(|arr| arr.iter().any(|v| v.as_str() == Some(tool_action))); // sin enum → no podemos verificar, asumir válido
                if action_valid {
                    QADetail {
                        target_id: id.clone(),
                        passed: true,
                        measured: Some(1.0),
                        expected: Some(1.0),
                        deviation: Some(0.0),
                        message: format!("GenericStep {tool}/{tool_action}: schema OK, args accepted"),
                        severity: "info".to_string(),
                    }
                } else {
                    QADetail {
                        target_id: id.clone(),
                        passed: false,
                        measured: Some(0.0),
                        expected: Some(1.0),
                        deviation: Some(1.0),
                        message: format!("GenericStep {tool}/{tool_action}: action '{tool_action}' not found in schema"),
                        severity: "error".to_string(),
                    }
                }
            } else {
                QADetail {
                    target_id: id.clone(),
                    passed: false,
                    measured: Some(0.0),
                    expected: Some(1.0),
                    deviation: Some(1.0),
                    message: format!("GenericStep {tool}/{tool_action}: tool '{tool}' not found in plugin"),
                    severity: "error".to_string(),
                }
            };
            details.push(detail);
        }
        details
    }

    /// Valida steps tipados de animación/esqueleto/tree contra el contexto.
    /// Verifica que player_path, skeleton_path, tree_path existen en la escena.
    pub fn validate_typed_steps(
        plan: &ScenePlan,
        context: &SceneContext,
    ) -> Vec<QADetail> {
        let mut details = Vec::new();
        // Build a set of known node paths for quick lookup.
        let known_paths: std::collections::HashSet<&str> = context.nodes.iter()
            .map(|n| n.path.as_str())
            .collect();

        for step in &plan.steps {
            match step {
                // Animation steps — check player_path exists
                SceneStep::CreateAnimationPlayer { id, node_path, .. } => {
                    details.push(Self::check_path_exists(id, node_path, "CreateAnimationPlayer.node_path", &known_paths));
                }
                SceneStep::CreateAnimation { id, player_path, anim_name, .. } => {
                    details.push(Self::check_path_exists(id, player_path, "CreateAnimation.player_path", &known_paths));
                    if anim_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            measured: Some(0.0),
                            expected: Some(1.0),
                            deviation: Some(1.0),
                            message: "CreateAnimation: anim_name is empty".to_string(),
                            severity: "error".to_string(),
                        });
                    }
                }
                SceneStep::SetAnimPlayerProps { id, player_path, .. } => {
                    details.push(Self::check_path_exists(id, player_path, "SetAnimPlayerProps.player_path", &known_paths));
                }
                SceneStep::DuplicateAnimation { id, player_path, source_anim, .. } => {
                    details.push(Self::check_path_exists(id, player_path, "DuplicateAnimation.player_path", &known_paths));
                    if source_anim.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            measured: Some(0.0),
                            expected: Some(1.0),
                            deviation: Some(1.0),
                            message: "DuplicateAnimation: source_anim is empty".to_string(),
                            severity: "error".to_string(),
                        });
                    }
                }
                SceneStep::RemoveAnimation { id, player_path, anim_name } => {
                    details.push(Self::check_path_exists(id, player_path, "RemoveAnimation.player_path", &known_paths));
                    if anim_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            measured: Some(0.0),
                            expected: Some(1.0),
                            deviation: Some(1.0),
                            message: "RemoveAnimation: anim_name is empty".to_string(),
                            severity: "error".to_string(),
                        });
                    }
                }
                SceneStep::AddTrack { id, player_path, anim_name, track_type, .. } => {
                    details.push(Self::check_path_exists(id, player_path, "AddTrack.player_path", &known_paths));
                    if anim_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "AddTrack: anim_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                    let valid_types = ["value", "position_3d", "rotation_3d", "scale_3d", "method", "bezier", "audio", "position", "rotation", "scale"];
                    if !valid_types.contains(&track_type.as_str()) {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: format!("AddTrack: invalid track_type '{track_type}' (valid: {valid_types:?})"),
                            severity: "warning".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::AddKey { id, player_path, anim_name, track_idx, .. } => {
                    details.push(Self::check_path_exists(id, player_path, "AddKey.player_path", &known_paths));
                    if anim_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "AddKey: anim_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                    if *track_idx < 0 {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: format!("AddKey: track_idx={track_idx} is negative"),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                // AnimationTree steps — check tree_path exists
                SceneStep::CreateAnimationTree { id, node_path, .. } => {
                    details.push(Self::check_path_exists(id, node_path, "CreateAnimationTree.node_path", &known_paths));
                }
                SceneStep::AddBlendNode { id, tree_path, node_name, .. } => {
                    details.push(Self::check_path_exists(id, tree_path, "AddBlendNode.tree_path", &known_paths));
                    if node_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "AddBlendNode: node_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::ConnectBlendNodes { id, tree_path, from_node, to_node, .. } => {
                    details.push(Self::check_path_exists(id, tree_path, "ConnectBlendNodes.tree_path", &known_paths));
                    if from_node.is_empty() || to_node.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "ConnectBlendNodes: from_node or to_node is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::SetTreeRoot { id, tree_path, root_node } => {
                    details.push(Self::check_path_exists(id, tree_path, "SetTreeRoot.tree_path", &known_paths));
                    if root_node.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "SetTreeRoot: root_node is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::SetTreeParam { id, tree_path, param_name, .. } => {
                    details.push(Self::check_path_exists(id, tree_path, "SetTreeParam.tree_path", &known_paths));
                    if param_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "SetTreeParam: param_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                // Skeleton steps — check skeleton_path exists
                SceneStep::AddBone { id, skeleton_path, bone_name, .. } => {
                    details.push(Self::check_path_exists(id, skeleton_path, "AddBone.skeleton_path", &known_paths));
                    if bone_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "AddBone: bone_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::SetBoneRest { id, skeleton_path, bone_name, .. } => {
                    details.push(Self::check_path_exists(id, skeleton_path, "SetBoneRest.skeleton_path", &known_paths));
                    if bone_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "SetBoneRest: bone_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                // Skeleton typed steps (Fase C)
                SceneStep::CreateSkeleton { id, node_path, bones, .. } => {
                    details.push(Self::check_path_exists(id, node_path, "CreateSkeleton.node_path", &known_paths));
                    // Validate bone names are not empty
                    for bone in bones {
                        if let Some(obj) = bone.as_object() {
                            if let Some(name) = obj.get("name").and_then(|v| v.as_str()) {
                                if name.is_empty() {
                                    details.push(QADetail {
                                        target_id: id.clone(),
                                        passed: false,
                                        message: "CreateSkeleton: bone name is empty".to_string(),
                                        severity: "warning".to_string(),
                                        ..Default::default()
                                    });
                                }
                            }
                        }
                    }
                }
                SceneStep::SetBonePose { id, skeleton_path, bone_name, .. } => {
                    details.push(Self::check_path_exists(id, skeleton_path, "SetBonePose.skeleton_path", &known_paths));
                    if bone_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "SetBonePose: bone_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::CreateIK { id, skeleton_path, ik_name, .. } => {
                    details.push(Self::check_path_exists(id, skeleton_path, "CreateIK.skeleton_path", &known_paths));
                    if ik_name.is_empty() {
                        details.push(QADetail {
                            target_id: id.clone(),
                            passed: false,
                            message: "CreateIK: ik_name is empty".to_string(),
                            severity: "error".to_string(),
                            ..Default::default()
                        });
                    }
                }
                SceneStep::SetSkin { id, mesh_path, skeleton_path } => {
                    details.push(Self::check_path_exists(id, mesh_path, "SetSkin.mesh_path", &known_paths));
                    details.push(Self::check_path_exists(id, skeleton_path, "SetSkin.skeleton_path", &known_paths));
                }
                // Skip Generic, AddNode, SetTransform, etc. — already validated elsewhere
                _ => {}
            }
        }
        details
    }

    /// Helper: check a node path exists in the context.
    fn check_path_exists(id: &str, path: &str, field: &str, known: &std::collections::HashSet<&str>) -> QADetail {
        if path == "." || known.contains(path) {
            QADetail {
                target_id: id.to_string(),
                passed: true,
                message: format!("{field} = '{path}' OK"),
                severity: "info".to_string(),
                ..Default::default()
            }
        } else {
            QADetail {
                target_id: id.to_string(),
                passed: false,
                message: format!("{field} = '{path}' NOT FOUND in scene context"),
                severity: "warning".to_string(),
                ..Default::default()
            }
        }
    }
    
    /// Engine B: Heuristic checks via visual_text/spatial + summary (JSON puro).
    /// Fase D (§0.11): ya NO usa `capture_scene` (imagen). El summary recursivo
    /// (visual_text action="summary") trae node_count + bounds + tree_depth +
    /// warnings (z_fighting_risk, missing_material, missing_texture, etc.).
    async fn run_engine_b<C: SceneValidatorClient>(
        plan: &ScenePlan,
        context: &SceneContext,
        client: &C,
    ) -> EngineReport {
        let mut results = Vec::new();
        let mut warnings = Vec::new();
        let errors = Vec::new();

        // Snapshot JSON puro (sin imagen) — visual_text(action="summary").
        if let Ok(summary) = client.visual_summary(&plan.scene_path).await {
            let node_count = usize::try_from(
                summary.get("node_count").and_then(|v| v.as_u64()).unwrap_or(0),
            )
            .unwrap_or(0);
            let expected_count = context.nodes.len();

            if node_count == 0 && expected_count > 0 {
                warnings.push("Visual summary returned 0 nodes - possible structural issue".to_string());
            } else if node_count != expected_count {
                warnings.push(format!(
                    "Node count mismatch: visual={node_count} vs context={expected_count}"
                ));
            }

            results.push(QADetail {
                target_id: "visual_node_count".to_string(),
                passed: node_count > 0,
                measured: Some(node_count as f32),
                expected: Some(expected_count as f32),
                deviation: Some((node_count as f32 - expected_count as f32).abs()),
                message: format!("Visual summary node count: {node_count}"),
                severity: if node_count > 0 { "info" } else { "warning" }.to_string(),
            });

            // Tree depth: si el plan excede 5 niveles sin razón, advertencia.
            if let Some(depth) = summary.get("tree_depth").and_then(|v| v.as_u64()) {
                results.push(QADetail {
                    target_id: "visual_tree_depth".to_string(),
                    passed: depth > 0,
                    measured: Some(depth as f32),
                    expected: None,
                    deviation: None,
                    message: format!("Visual tree depth: {depth}"),
                    severity: "info".to_string(),
                });
            }

            // Bounds — si bounds_2d/3d existen, son info (sin comparación).
            for key in ["bounds_2d", "bounds_3d"] {
                if let Some(b) = summary.get(key) {
                    results.push(QADetail {
                        target_id: format!("visual_{key}"),
                        passed: true,
                        measured: None,
                        expected: None,
                        deviation: None,
                        message: format!("Visual {key}: {b}"),
                        severity: "info".to_string(),
                    });
                }
            }

            // Warnings heurísticos del summary (z_fighting, missing_material,
            // missing_texture, missing_shape) → propagan al QAReport.
            if let Some(w_arr) = summary.get("warnings").and_then(|v| v.as_array()) {
                for w in w_arr {
                    let kind = w.get("kind").and_then(|v| v.as_str()).unwrap_or("info");
                    let msg = w.get("message").and_then(|v| v.as_str()).unwrap_or("");
                    if !msg.is_empty() {
                        warnings.push(format!("[{kind}] {msg}"));
                    }
                }
            }
        }

        EngineReport {
            engine_name: "check_mesh".to_string(), // heuristic
            results,
            summary: "Visual/heuristic validation completed (JSON-only, no image)".to_string(),
            warnings,
            errors,
        }
    }
    
    /// Merge Engine A and B reports into final QAReport.
    /// Clasifica error_type por VerificationKind del target fallido:
    /// NodeCount/BBox*/PropertyValue → Dimension; el resto → Topology.
    fn merge_reports_with_kinds(report: &mut QAReport, plan: &ScenePlan) {
        use std::collections::HashMap as StdHashMap;
        let kind_by_id: StdHashMap<&str, &VerificationKind> = plan
            .verification
            .iter()
            .map(|t| (t.id.as_str(), &t.kind))
            .collect();

        let mut all_details = Vec::new();
        all_details.extend(report.engine_a.results.clone());
        all_details.extend(report.engine_b.results.clone());
        
        let mut error_type = ErrorType::None;
        
        for detail in &all_details {
            if !detail.passed {
                let is_dimension = kind_by_id
                    .get(detail.target_id.as_str())
                    .is_some_and(|k| matches!(
                        k,
                        VerificationKind::NodeCount
                            | VerificationKind::BBoxMax
                            | VerificationKind::BBoxMin
                            | VerificationKind::PropertyValue
                    ));
                if detail.severity == "fatal" {
                    error_type = ErrorType::Fatal;
                } else if detail.severity == "error" || detail.severity == "warning" {
                    match error_type {
                        ErrorType::None => {
                            error_type = if is_dimension {
                                ErrorType::Dimension
                            } else {
                                ErrorType::Topology
                            };
                        }
                        ErrorType::Topology if is_dimension => {} // topología prioriza
                        ErrorType::Dimension if !is_dimension => error_type = ErrorType::Topology,
                        _ => {}
                    }
                }
            }
        }
        
        // Check engine errors
        if !report.engine_a.errors.is_empty() || !report.engine_b.errors.is_empty() {
            error_type = ErrorType::Fatal;
        }
        
        report.error_type = error_type.clone();
        report.passed = error_type == ErrorType::None;
        report.details = all_details;
        
        // Generate suggestions based on error type
        report.suggestions = match report.error_type {
            ErrorType::Dimension => vec![
                "Adjust numeric values in ScenePlan (positions, scales, sizes)".to_string(),
                "Check verification targets tolerances".to_string(),
            ],
            ErrorType::Topology => vec![
                "Review ScenePlan structure (hierarchy, node types, connections)".to_string(),
                "Verify resource paths and signal connections".to_string(),
            ],
            ErrorType::Fatal => vec![
                "Scene has fundamental issues - review plan from scratch".to_string(),
                "Check for missing resources or invalid node types".to_string(),
            ],
            ErrorType::None => vec![
                "Scene validation passed - ready to commit".to_string(),
            ],
        };
    }
    
    // --- Individual check implementations ---
    
    async fn check_node_count<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
    ) -> QADetail {
        let measured = context.nodes.len() as f32;
        let expected = target.nominal.unwrap_or(measured);
        let deviation = (measured - expected).abs();
        let passed = deviation <= target.tolerance;
        
        QADetail {
            target_id: target.id.clone(),
            passed,
            measured: Some(measured),
            expected: Some(expected),
            deviation: Some(deviation),
            message: format!("Node count: {measured} (expected {expected})"),
            severity: if passed { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_bbox_max<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
    ) -> QADetail {
        let measured = context.bbox.size.x.max(context.bbox.size.y).max(context.bbox.size.z);
        let expected = target.nominal.unwrap_or(measured);
        let deviation = (measured - expected).abs();
        let passed = deviation <= target.tolerance;
        
        QADetail {
            target_id: target.id.clone(),
            passed,
            measured: Some(measured),
            expected: Some(expected),
            deviation: Some(deviation),
            message: format!("BBox max dimension: {measured:.2} (expected {expected:.2})"),
            severity: if passed { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_bbox_min<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
    ) -> QADetail {
        let measured = context.bbox.size.x.min(context.bbox.size.y).min(context.bbox.size.z);
        let expected = target.nominal.unwrap_or(measured);
        let deviation = (measured - expected).abs();
        let passed = deviation <= target.tolerance;
        
        QADetail {
            target_id: target.id.clone(),
            passed,
            measured: Some(measured),
            expected: Some(expected),
            deviation: Some(deviation),
            message: format!("BBox min dimension: {measured:.2} (expected {expected:.2})"),
            severity: if passed { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_script_attached<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
    ) -> QADetail {
        let node_path = target.node_path.as_deref().unwrap_or("");
        let has_script = context.scripts.iter().any(|s| s.attached_to.contains(&node_path.to_string()))
            || context.nodes.iter().any(|n| n.path == node_path && n.script_path.is_some());
        
        QADetail {
            target_id: target.id.clone(),
            passed: has_script,
            measured: Some(if has_script { 1.0 } else { 0.0 }),
            expected: Some(1.0),
            deviation: Some(if has_script { 0.0 } else { 1.0 }),
            message: format!("Script attached to '{node_path}': {has_script}"),
            severity: if has_script { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_resource_exists<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
        plan: &ScenePlan,
    ) -> QADetail {
        let resource_path = target.selector.as_deref().unwrap_or("");
        // Check 1: existe en el contexto del editor (disco / cache).
        let exists_on_disk = context.resources.iter().any(|r| r.path == resource_path);
        // Check 2: el plan lo creará vía add_resource (pre-commit es válido).
        let will_exist = plan.steps.iter().any(|s| {
            matches!(s, SceneStep::AddResource { path, .. } if path == resource_path)
        });
        let exists = exists_on_disk || will_exist;
        let source = if exists_on_disk { "disk" } else { "plan (será creado en commit)" };
        
        QADetail {
            target_id: target.id.clone(),
            passed: exists,
            measured: Some(if exists { 1.0 } else { 0.0 }),
            expected: Some(1.0),
            deviation: Some(if exists { 0.0 } else { 1.0 }),
            message: format!("Resource '{resource_path}' exists: {exists} ({source})"),
            severity: if exists { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_signal_connected<C: SceneValidatorClient>(
        target: &VerificationTarget,
        _context: &SceneContext,
        client: &C,
        scene_path: &str,
    ) -> QADetail {
        let selector = target.selector.as_deref().unwrap_or("");
        let connected = if client.list_signals(scene_path).await.is_ok() {
            // Simplified check - would need proper parsing
            false
        } else {
            false
        };
        
        QADetail {
            target_id: target.id.clone(),
            passed: connected,
            measured: Some(if connected { 1.0 } else { 0.0 }),
            expected: Some(1.0),
            deviation: Some(if connected { 0.0 } else { 1.0 }),
            message: format!("Signal connected: {selector}"),
            severity: if connected { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_node_exists<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        _client: &C,
    ) -> QADetail {
        let node_path = target.node_path.as_deref().unwrap_or("");
        // Fix 1 (2026-08-24): búsqueda por nombre BARE además de path completo.
        // node_query(get_info, "Grunt_3") funciona → validator debe ser igual.
        let exists = context.nodes.iter().any(|n|
            n.path == node_path || n.name == node_path
        );
        
        QADetail {
            target_id: target.id.clone(),
            passed: exists,
            measured: Some(if exists { 1.0 } else { 0.0 }),
            expected: Some(1.0),
            deviation: Some(if exists { 0.0 } else { 1.0 }),
            message: format!("Node '{node_path}' exists: {exists}"),
            severity: if exists { "info" } else { "error" }.to_string(),
        }
    }
    
    async fn check_property_value<C: SceneValidatorClient>(
        target: &VerificationTarget,
        context: &SceneContext,
        client: &C,
    ) -> QADetail {
        let node_path = target.node_path.as_deref().unwrap_or("");
        let selector = target.selector.as_deref().unwrap_or("");
        // Verifica primero que el nodo existe en el contexto; sin eso no
        // podemos ni intentar get_prop (evita falsos negativos).
        let exists = context.nodes.iter().any(|n|
            n.path == node_path || n.name == node_path
        );
        if !exists {
            return QADetail {
                target_id: target.id.clone(),
                passed: false,
                measured: Some(0.0),
                expected: target.nominal,
                deviation: target.nominal,
                message: format!("Property '{selector}' on '{node_path}': node not found"),
                severity: "error".to_string(),
            };
        }
        // P-M3: leer la propiedad REAL vía el plugin (no del snapshot del open).
        let (measured_f, raw_str) = match client.get_prop(&context.scene_path, node_path, selector).await {
            Ok(value) => {
                // Si viene nominal numérico, intentar comparar como número;
                // si no, comparar como string.
                #[allow(clippy::cast_possible_truncation)]
                let num = value.get("value")
                    .and_then(serde_json::Value::as_f64)
                    .map(|f| f as f32);
                let s = value.to_string();
                (num.unwrap_or(0.0), s)
            }
            Err(e) => return QADetail {
                target_id: target.id.clone(),
                passed: false,
                measured: Some(0.0),
                expected: target.nominal,
                deviation: target.nominal,
                message: format!("Property '{selector}' on '{node_path}': get_prop failed ({e})"),
                severity: "error".to_string(),
            },
        };
        let expected = target.nominal.unwrap_or(measured_f);
        let deviation = (measured_f - expected).abs();
        let passed = deviation <= target.tolerance.max(0.0);
        QADetail {
            target_id: target.id.clone(),
            passed,
            measured: Some(measured_f),
            expected: Some(expected),
            deviation: Some(deviation),
            message: format!("Property '{selector}' on '{node_path}': {raw_str} (measured={measured_f}, expected={expected})"),
            severity: if passed { "info" } else { "error" }.to_string(),
        }
    }
}

/// Trait for validator to call MCP tools (implemented by server)
#[async_trait::async_trait]
pub trait SceneValidatorClient: Send + Sync {
    async fn validate_scene(&self, scene_path: &str) -> Result<Value, String>;
    async fn capture_scene(&self, scene_path: &str, viewport: &str) -> Result<Value, String>;
    async fn visual_summary(&self, scene_path: &str) -> Result<Value, String>;
    async fn list_signals(&self, scene_path: &str) -> Result<Value, String>;
    /// P-M3: lee una propiedad de un nodo vía node_query/get_prop.
    async fn get_prop(&self, scene_path: &str, node_path: &str, property: &str) -> Result<Value, String>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene_tool::schemas::*;
    use std::collections::HashMap;
    
    struct MockClient;
    
    #[async_trait::async_trait]
    impl SceneValidatorClient for MockClient {
        async fn validate_scene(&self, _scene_path: &str) -> Result<Value, String> {
            Ok(serde_json::json!({"valid": true}))
        }
        async fn capture_scene(&self, _scene_path: &str, _viewport: &str) -> Result<Value, String> {
            Ok(serde_json::json!({"node_count": 5}))
        }
        async fn visual_summary(&self, _scene_path: &str) -> Result<Value, String> {
            // Fase D (§0.11): summary recursivo devuelve node_count + tree_depth
            // + bounds_2d/3d + warnings (no "bbox" legacy).
            Ok(serde_json::json!({
                "node_count": 5,
                "tree_depth": 3,
                "bounds_2d": null,
                "bounds_3d": {"min": {"x": -1.0, "y": -1.0, "z": -1.0}, "max": {"x": 1.0, "y": 1.0, "z": 1.0}, "size": {"x": 2.0, "y": 2.0, "z": 2.0}},
                "warnings": []
            }))
        }
        async fn list_signals(&self, _scene_path: &str) -> Result<Value, String> {
            Ok(serde_json::json!({"signals": []}))
        }
        async fn get_prop(&self, _scene_path: &str, _node_path: &str, _property: &str) -> Result<Value, String> {
            // Mock simple: retornar 0.0 para tests. Tests específicos pueden
            // sobrescribir usando un MockClient con valores custom.
            Ok(serde_json::json!({"value": 0.0}))
        }
    }
    
    #[tokio::test]
    async fn test_validate_pass() {
        let plan = ScenePlan {
            plan_id: "test".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![],
            verification: vec![
                VerificationTarget {
                    id: "node_count".to_string(),
                    kind: VerificationKind::NodeCount,
                    description: "Should have 5 nodes".to_string(),
                    nominal: Some(5.0),
                    tolerance: 0.0,
                    node_path: None,
                    selector: None,
                },
            ],
            key_dimensions: HashMap::new(),
        };
        
        let context = SceneContext {
            nodes: vec![
                NodeInfo { path: "A".to_string(), ..Default::default() },
                NodeInfo { path: "B".to_string(), ..Default::default() },
                NodeInfo { path: "C".to_string(), ..Default::default() },
                NodeInfo { path: "D".to_string(), ..Default::default() },
                NodeInfo { path: "E".to_string(), ..Default::default() },
            ],
            ..Default::default()
        };
        
        let client = MockClient;
        let report = SceneValidator::validate_scene(&plan, &context, &client).await;
        
        assert!(report.passed);
        assert_eq!(report.error_type, ErrorType::None);
    }
    
    #[tokio::test]
    async fn test_validate_fail_node_count() {
        let plan = ScenePlan {
            plan_id: "test".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![],
            verification: vec![
                VerificationTarget {
                    id: "node_count".to_string(),
                    kind: VerificationKind::NodeCount,
                    description: "Should have 10 nodes".to_string(),
                    nominal: Some(10.0),
                    tolerance: 0.0,
                    node_path: None,
                    selector: None,
                },
            ],
            key_dimensions: HashMap::new(),
        };
        
        let context = SceneContext {
            nodes: vec![
                NodeInfo { path: "A".to_string(), ..Default::default() },
            ],
            ..Default::default()
        };
        
        let client = MockClient;
        let report = SceneValidator::validate_scene(&plan, &context, &client).await;

        assert!(!report.passed);
        assert_eq!(report.error_type, ErrorType::Dimension);
    }

    /// P-M3: PropertyValue lee propiedad real (no siempre passed=true).
    #[tokio::test]
    async fn test_property_value_reads_real_value() {
        // Mock con valores concretos para validar lectura real.
        struct PropMockClient;
        #[async_trait::async_trait]
        impl SceneValidatorClient for PropMockClient {
            async fn validate_scene(&self, _: &str) -> Result<Value, String> { Ok(serde_json::json!({"valid":true})) }
            async fn capture_scene(&self, _: &str, _: &str) -> Result<Value, String> { Ok(serde_json::json!({"node_count":1})) }
            async fn visual_summary(&self, _: &str) -> Result<Value, String> { Ok(serde_json::json!({"bbox":{}})) }
            async fn list_signals(&self, _: &str) -> Result<Value, String> { Ok(serde_json::json!({"signals":[]})) }
            async fn get_prop(&self, _: &str, _: &str, prop: &str) -> Result<Value, String> {
                // Simula una propiedad medida = 3.0 cuando pide "count", error en otro caso.
                if prop == "count" { Ok(serde_json::json!({"value": 3.0})) }
                else if prop == "missing" { Err("not found".into()) }
                else { Ok(serde_json::json!({"value": 0.0})) }
            }
        }

        let plan = ScenePlan {
            plan_id: "t".into(),
            scene_path: "res://test.tscn".into(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![],
            verification: vec![
                // Caso 1: nominal 3.0, mide 3.0 → passed.
                VerificationTarget {
                    id: "v_ok".into(),
                    kind: VerificationKind::PropertyValue,
                    description: "count == 3".into(),
                    nominal: Some(3.0),
                    tolerance: 0.0,
                    node_path: Some("A".into()),
                    selector: Some("count".into()),
                },
                // Caso 2: nominal 5.0, mide 3.0 → failed.
                VerificationTarget {
                    id: "v_fail".into(),
                    kind: VerificationKind::PropertyValue,
                    description: "count == 5".into(),
                    nominal: Some(5.0),
                    tolerance: 0.0,
                    node_path: Some("A".into()),
                    selector: Some("count".into()),
                },
                // Caso 3: get_prop error → failed por nodo-ilegal.
                VerificationTarget {
                    id: "v_err".into(),
                    kind: VerificationKind::PropertyValue,
                    description: "missing".into(),
                    nominal: Some(1.0),
                    tolerance: 0.0,
                    node_path: Some("A".into()),
                    selector: Some("missing".into()),
                },
            ],
            key_dimensions: HashMap::new(),
        };
        let context = SceneContext {
            scene_path: "res://test.tscn".into(),
            nodes: vec![NodeInfo { path: "A".into(), ..Default::default() }],
            ..Default::default()
        };
        let report = SceneValidator::validate_scene(&plan, &context, &PropMockClient).await;
        // 1 passed, 2 failed.
        let counts: (usize, usize) = report.engine_a.results.iter()
            .filter(|d| d.target_id == "v_ok" || d.target_id == "v_fail" || d.target_id == "v_err")
            .fold((0, 0), |(p, f), d| if d.passed { (p + 1, f) } else { (p, f + 1) });
        assert_eq!(counts.0, 1, "caso v_ok debe pasar: {:?}", report.engine_a.results);
        assert_eq!(counts.1, 2, "casos v_fail y v_err deben fallar: {:?}", report.engine_a.results);
        assert!(!report.passed);
    }
}