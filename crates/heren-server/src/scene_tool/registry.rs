//! Scene Registry — Manages scene locks, state, and persistence
//! Parallel to ConnectedEditors registry

use crate::scene_tool::schemas::{SceneState, LockInfo, SceneMode, SceneOpenResponse, SceneContext, ScenePlan, ScenePlanResponse, SceneOrchestrateResponse, SceneValidateResponse, SceneCommitResponse, SceneStatusResponse, SceneStep};
use crate::scene_tool::coder::MCPCall;
use crate::scene_tool::validator::SceneValidatorClient;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};
use tokio::fs;
use tracing::info;

/// SceneRegistry manages all active scene editing sessions
pub struct SceneRegistry {
    scenes: Arc<RwLock<HashMap<String, SceneState>>>,
    locks: Arc<RwLock<HashMap<String, LockInfo>>>,
    locks_dir: PathBuf,
}

impl SceneRegistry {
    pub fn new(project_root: &Path) -> Self {
        let locks_dir = project_root.join(".heren").join("locks");
        std::fs::create_dir_all(&locks_dir).ok();
        
        Self {
            scenes: Arc::new(RwLock::new(HashMap::new())),
            locks: Arc::new(RwLock::new(HashMap::new())),
            locks_dir,
        }
    }
    
    /// Open a scene for editing - creates lock, loads context
    pub async fn open_scene<C: SceneRegistryClient>(
        &self,
        scene_path: &str,
        mode: SceneMode,
        agent_id: &str,
        client: &C,
    ) -> Result<SceneOpenResponse, String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        // Check for existing lock
        {
            let locks = self.locks.read().unwrap();
            if let Some(existing) = locks.get(&normalized_path) {
                if existing.agent_id != agent_id {
                    return Err(format!(
                        "Scene '{}' is locked by agent '{}' (pid: {}, since: {})",
                        normalized_path, existing.agent_id, existing.pid, existing.since
                    ));
                }
                // Same agent re-opening - ok
            }
        }
        
        // Create lock
        let lock_id = uuid::Uuid::new_v4().to_string();
        let lock_info = LockInfo {
            agent_id: agent_id.to_string(),
            scene_path: normalized_path.clone(),
            progress: "Opening scene".to_string(),
            pid: std::process::id(),
            since: chrono::Utc::now().to_rfc3339(),
        };
        
        // Write lock file
        let lock_file = self.locks_dir.join(format!("{}.lock", sanitize_filename(&normalized_path)));
        fs::write(&lock_file, serde_json::to_string_pretty(&lock_info).unwrap()).await
            .map_err(|e| format!("Failed to write lock file: {e}"))?;
        
        // Load scene context from Godot
        let context: SceneContext = client.load_scene_context(&normalized_path).await?;
        
        // Create scene state
        let mode_for_state = mode.clone();
        let state = SceneState {
            lock_id: lock_id.clone(),
            scene_path: normalized_path.clone(),
            mode: mode_for_state,
            context: Some(context.clone()),
            plan: None,
            qa_report: None,
            dirty: false,
            lock_info: Some(lock_info.clone()),
        };
        
        // Register
        {
            let mut scenes = self.scenes.write().unwrap();
            scenes.insert(normalized_path.clone(), state);
        }
        {
            let mut locks = self.locks.write().unwrap();
            locks.insert(normalized_path.clone(), lock_info);
        }
        
        info!("Scene opened: {} (lock: {}, mode: {:?})", normalized_path, lock_id, mode.clone());
        
        Ok(SceneOpenResponse {
            lock_id,
            scene_context: context,
        })
    }
    
    /// P0b (2026-08-24): reemplaza el contexto cacheado por uno fresco del
    /// editor vivo. validate() lo invoca ANTES de chequear para no validar
    /// contra el snapshot del open (árbol vacío → QA ciego).
    pub fn update_context(&self, scene_path: &str, context: SceneContext) -> Result<(), String> {
        let normalized_path = normalize_scene_path(scene_path);
        let mut scenes = self.scenes.write().unwrap();
        let state = scenes
            .get_mut(&normalized_path)
            .ok_or_else(|| format!("Scene '{normalized_path}' not opened"))?;
        state.context = Some(context);
        Ok(())
    }

    /// Write/update scene plan
    pub fn write_plan(&self, scene_path: &str, plan: ScenePlan) -> Result<ScenePlanResponse, String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        let mut scenes = self.scenes.write().unwrap();
        let state = scenes.get_mut(&normalized_path)
            .ok_or_else(|| format!("Scene '{normalized_path}' not opened (call scene/open first)"))?;
        
        // Validate plan against context schema
        let warnings = Self::validate_plan_against_context(&plan, state.context.as_ref());
        
        state.plan = Some(plan);
        state.dirty = true;
        
        Ok(ScenePlanResponse { ok: true, warnings })
    }
    
    /// Execute the plan - returns MCP calls to execute
    pub fn orchestrate(&self, scene_path: &str) -> Result<(SceneOrchestrateResponse, Vec<MCPCall>), String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        let scenes = self.scenes.read().unwrap();
        let state = scenes.get(&normalized_path)
            .ok_or_else(|| format!("Scene '{normalized_path}' not opened"))?;
        
        let plan = state.plan.as_ref()
            .ok_or_else(|| "No plan written (call scene/plan first)".to_string())?;
        
        let context = state.context.as_ref()
            .ok_or_else(|| "No scene context loaded".to_string())?;
        
        // Generate MCP calls via deterministic coder
        let calls = crate::scene_tool::coder::SceneCoder::plan_to_mcp_calls(plan, context);
        
        let executed_steps = calls.iter().map(|c| c.description.clone()).collect();
        let coords = calls.iter().map(|c| serde_json::to_value(&c.args).unwrap_or(Value::Null)).collect();
        
        Ok((SceneOrchestrateResponse {
            executed_steps,
            coords,
            warnings: vec![],
        }, calls))
    }
    
    /// Validate scene against plan
    pub async fn validate<C: SceneValidatorClient>(&self, scene_path: &str, client: &C) -> Result<SceneValidateResponse, String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        // Clone necessary data while holding the lock briefly
        let (plan, context) = {
            let scenes = self.scenes.read().unwrap();
            let state = scenes.get(&normalized_path)
                .ok_or_else(|| format!("Scene '{normalized_path}' not opened"))?;
            
            let plan = state.plan.as_ref()
                .ok_or_else(|| "No plan to validate".to_string())?;
            
            let context = state.context.as_ref()
                .ok_or_else(|| "No scene context".to_string())?;
            
            (plan.clone(), context.clone())
        };
        
        // Validate without holding the lock
        let qa_report = crate::scene_tool::validator::SceneValidator::validate_scene(&plan, &context, client).await;
        
        // Update state with QA report
        let mut scenes = self.scenes.write().unwrap();
        if let Some(state) = scenes.get_mut(&normalized_path) {
            state.qa_report = Some(qa_report.clone());
        }
        
        Ok(SceneValidateResponse { qa_report })
    }
    
    /// Commit changes - save scene and release lock
    pub async fn commit<C: SceneRegistryClient>(&self, scene_path: &str, save: bool, client: &C) -> Result<SceneCommitResponse, String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        // Save if requested
        if save {
            client.save_scene(&normalized_path).await?;
        }
        
        // Remove lock file
        let lock_file = self.locks_dir.join(format!("{}.lock", sanitize_filename(&normalized_path)));
        if lock_file.exists() {
            fs::remove_file(&lock_file).await.ok();
        }
        
        // Remove from registry
        {
            let mut scenes = self.scenes.write().unwrap();
            scenes.remove(&normalized_path);
        }
        {
            let mut locks = self.locks.write().unwrap();
            locks.remove(&normalized_path);
        }
        
        info!("Scene committed: {} (saved: {})", normalized_path, save);
        
        Ok(SceneCommitResponse {
            saved: save,
            scene_path: normalized_path,
        })
    }
    
    /// Get scene status
    pub fn status(&self, scene_path: &str) -> Result<SceneStatusResponse, String> {
        let normalized_path = normalize_scene_path(scene_path);
        
        let scenes = self.scenes.read().unwrap();
        let state = scenes.get(&normalized_path);
        
        Ok(SceneStatusResponse {
            lock_id: state.as_ref().map(|s| s.lock_id.clone()),
            scene_path: normalized_path,
            mode: state.as_ref().map_or(SceneMode::Isolated, |s| s.mode.clone()),
            dirty: state.as_ref().is_some_and(|s| s.dirty),
            has_plan: state.as_ref().is_some_and(|s| s.plan.is_some()),
            qa_status: state.as_ref().and_then(|s| s.qa_report.as_ref()).map(|r| r.error_type.clone()),
            lock_info: state.as_ref().and_then(|s| s.lock_info.clone()),
        })
    }
    
    /// List all active scenes
    pub fn list_scenes(&self) -> Vec<SceneStatusResponse> {
        let scenes = self.scenes.read().unwrap();
        scenes.values().map(|s| SceneStatusResponse {
            lock_id: Some(s.lock_id.clone()),
            scene_path: s.scene_path.clone(),
            mode: s.mode.clone(),
            dirty: s.dirty,
            has_plan: s.plan.is_some(),
            qa_status: s.qa_report.as_ref().map(|r| r.error_type.clone()),
            lock_info: s.lock_info.clone(),
        }).collect()
    }
    
    /// Mutate scene state with a closure
    pub fn with_scene_mut<F, R>(&self, scene_path: &str, f: F) -> Result<R, String>
    where
        F: FnOnce(&mut SceneState) -> R,
    {
        let normalized_path = normalize_scene_path(scene_path);
        let mut scenes = self.scenes.write().unwrap();
        let state = scenes.get_mut(&normalized_path)
            .ok_or_else(|| format!("Scene '{scene_path}' not opened"))?;
        Ok(f(state))
    }
    
    /// Update progress message for lock
    pub fn update_progress(&self, scene_path: &str, progress: &str) {
        let normalized_path = normalize_scene_path(scene_path);
        let mut locks = self.locks.write().unwrap();
        if let Some(lock) = locks.get_mut(&normalized_path) {
            lock.progress = progress.to_string();
        }
        if let Some(state) = self.scenes.write().unwrap().get_mut(&normalized_path) {
            if let Some(lock) = &mut state.lock_info {
                lock.progress = progress.to_string();
            }
        }
    }
    
    /// Validate plan against scene context schema.
    /// E1 (2026-08-24): simula los steps — un padre creado por el propio plan
    /// NO genera warning (antes: 23 falsos "Parent does not exist").
    fn validate_plan_against_context(plan: &ScenePlan, context: Option<&SceneContext>) -> Vec<String> {
        let mut warnings = Vec::new();

        if let Some(ctx) = context {
            // Nodos existentes + los que el plan va creando por el camino.
            let mut known: std::collections::HashSet<String> =
                ctx.nodes.iter().map(|n| n.path.clone()).collect();
            // El root de la escena también es parent válido ("." y su nombre).
            known.insert(".".to_string());
            known.insert(ctx.root_name.clone());

            for step in &plan.steps {
                match step {
                    SceneStep::AddNode { name, parent, .. } => {
                        if !known.contains(parent) {
                            warnings.push(format!("Parent node '{parent}' does not exist in current scene"));
                        }
                        // path del nodo creado (mismo formato que node paths)
                        let path = if parent == "." { name.clone() } else { format!("{parent}/{name}") };
                        known.insert(path);
                    }
                    SceneStep::SetTransform { node_path, .. } => {
                        if !known.contains(node_path) {
                            warnings.push(format!("Node '{node_path}' does not exist for transform"));
                        }
                    }
                    SceneStep::ConnectSignal { from_node, to_node, .. } => {
                        if !known.contains(from_node) {
                            warnings.push(format!("Signal source node '{from_node}' does not exist"));
                        }
                        if !known.contains(to_node) {
                            warnings.push(format!("Signal target node '{to_node}' does not exist"));
                        }
                    }
                    _ => {}
                }
            }
        }

        warnings
    }
}

/// Client trait for registry to call MCP tools
#[async_trait::async_trait]
pub trait SceneRegistryClient: Send + Sync {
    async fn load_scene_context(&self, scene_path: &str) -> Result<SceneContext, String>;
    async fn save_scene(&self, scene_path: &str) -> Result<(), String>;
}

/// Normalize scene path to res:// format
fn normalize_scene_path(path: &str) -> String {
    let path = path.trim();
    if path.starts_with("res://") || path.starts_with("user://") {
        path.to_string()
    } else {
        format!("res://{}", path.trim_start_matches('/'))
    }
}

/// Sanitize filename for lock files
fn sanitize_filename(path: &str) -> String {
    path.replace("res://", "")
        .replace("user://", "")
        .replace(['/', '\\', ':'], "_")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene_tool::schemas::*;
    
    struct MockClient;
    
    #[async_trait::async_trait]
    impl SceneRegistryClient for MockClient {
        async fn load_scene_context(&self, scene_path: &str) -> Result<SceneContext, String> {
            Ok(SceneContext {
                scene_path: scene_path.to_string(),
                root_name: "Main".to_string(),
                root_type: "Node3D".to_string(),
                workplane: Workplane::XZ,
                workplane_offset: Vector3::default(),
                bbox: AABB { size: Vector3 { x: 10.0, y: 10.0, z: 10.0 }, ..Default::default() },
                nodes: vec![
                    NodeInfo { path: "Robot".to_string(), name: "Robot".to_string(), node_type: "Node3D".to_string(), parent: Some(".".to_string()), ..Default::default() },
                    NodeInfo { path: "Robot/Body".to_string(), name: "Body".to_string(), node_type: "MeshInstance3D".to_string(), parent: Some("Robot".to_string()), ..Default::default() },
                ],
                resources: vec![],
                scripts: vec![],
                plan_schema: Value::Null,
            })
        }
        async fn save_scene(&self, _scene_path: &str) -> Result<(), String> {
            Ok(())
        }
    }
    
    #[tokio::test]
    async fn test_open_scene() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = SceneRegistry::new(temp_dir.path());
        let client = MockClient;
        
        let response = registry.open_scene("res://test.tscn", SceneMode::Isolated, "agent-1", &client).await.unwrap();
        
        assert!(!response.lock_id.is_empty());
        assert_eq!(response.scene_context.scene_path, "res://test.tscn");
        
        // Try to open again with different agent - should fail
        let result = registry.open_scene("res://test.tscn", SceneMode::Isolated, "agent-2", &client).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("locked by agent"));
    }
    
    #[tokio::test]
    async fn test_write_plan() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = SceneRegistry::new(temp_dir.path());
        let client = MockClient;
        
        registry.open_scene("res://test.tscn", SceneMode::Isolated, "agent-1", &client).await.unwrap();
        
        let plan = ScenePlan {
            plan_id: "plan-1".to_string(),
            scene_path: "res://test.tscn".to_string(),
            workplane: Workplane::XZ,
            workplane_offset: Vector3::default(),
            steps: vec![
                SceneStep::AddNode {
                    id: "s1".to_string(),
                    node_type: "MeshInstance3D".to_string(),
                    name: "NewMesh".to_string(),
                    parent: "Robot".to_string(),
                    workplane: Workplane::XZ,
                    local_pos: Vector3 { x: 1.0, y: 0.0, z: 0.0 },
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
        
        let response = registry.write_plan("res://test.tscn", plan).unwrap();
        assert!(response.ok);
    }
    
    #[tokio::test]
    async fn test_commit() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = SceneRegistry::new(temp_dir.path());
        let client = MockClient;
        
        registry.open_scene("res://test.tscn", SceneMode::Isolated, "agent-1", &client).await.unwrap();
        
        let response = registry.commit("res://test.tscn", true, &client).await.unwrap();
        assert!(response.saved);
        
        // Scene should be removed from registry
        let status = registry.status("res://test.tscn").unwrap();
        assert!(status.lock_id.is_none());
    }
}