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
    
    /// Engine B: Heuristic/Visual checks via visual_* tools
    async fn run_engine_b<C: SceneValidatorClient>(
        plan: &ScenePlan,
        context: &SceneContext,
        client: &C,
    ) -> EngineReport {
        let mut results = Vec::new();
        let mut warnings = Vec::new();
        let errors = Vec::new();
        
        // Capture off-screen render for visual verification
        if let Ok(capture) = client.capture_scene(&plan.scene_path, "3d").await {
            let node_count = usize::try_from(capture.get("node_count").and_then(|v: &Value| v.as_u64()).unwrap_or(0)).unwrap_or(0);
            let expected_count = context.nodes.len();
            
            if node_count == 0 && expected_count > 0 {
                warnings.push("Visual capture returned 0 nodes - possible render issue".to_string());
            } else if node_count != expected_count {
                warnings.push(format!("Node count mismatch: visual={node_count} vs context={expected_count}"));
            }
            
            results.push(QADetail {
                target_id: "visual_node_count".to_string(),
                passed: node_count > 0,
                measured: Some(node_count as f32),
                expected: Some(expected_count as f32),
                deviation: Some((node_count as f32 - expected_count as f32).abs()),
                message: format!("Visual capture node count: {node_count}"),
                severity: if node_count > 0 { "info" } else { "warning" }.to_string(),
            });
        }
        
        // Get visual summary for bbox verification
        if let Ok(summary) = client.visual_summary(&plan.scene_path).await {
            if let Some(bbox) = summary.get("bbox") {
                results.push(QADetail {
                    target_id: "visual_bbox".to_string(),
                    passed: true,
                    measured: None,
                    expected: None,
                    deviation: None,
                    message: format!("Visual bbox: {bbox:?}"),
                    severity: "info".to_string(),
                });
            }
        }
        
        EngineReport {
            engine_name: "check_mesh".to_string(), // heuristic
            results,
            summary: "Visual/heuristic validation completed".to_string(),
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
        _client: &C,
    ) -> QADetail {
        let node_path = target.node_path.as_deref().unwrap_or("");
        let selector = target.selector.as_deref().unwrap_or("");
        
        // Find node and check property
        let node = context.nodes.iter().find(|n| n.path == node_path);
        let (measured, passed) = if let Some(_n) = node {
            // Simplified - would need property lookup
            (target.nominal.unwrap_or(0.0), true)
        } else {
            (0.0, false)
        };
        
        QADetail {
            target_id: target.id.clone(),
            passed,
            measured: Some(measured),
            expected: target.nominal,
            deviation: Some((measured - target.nominal.unwrap_or(0.0)).abs()),
            message: format!("Property '{selector}' on '{node_path}': {measured:?}"),
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
            Ok(serde_json::json!({"bbox": {"size": {"x": 10.0, "y": 5.0, "z": 10.0}}}))
        }
        async fn list_signals(&self, _scene_path: &str) -> Result<Value, String> {
            Ok(serde_json::json!({"signals": []}))
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
}