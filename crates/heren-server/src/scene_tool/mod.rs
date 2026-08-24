//! Scene Tool Module — High-level scene editing with planning/orchestration
//! Pattern: scene_plan/open → scene_plan/plan → scene_plan/orchestrate → scene_plan/validate → scene_plan/commit
//!
//! This module contains the core logic. The actual MCP tool is defined in server.rs
//! using the #[tool] attribute macro (same pattern as session, node, etc.)

pub mod schemas;
pub mod coder;
pub mod validator;
pub mod registry;

pub use crate::scene_tool::schemas::*;
use crate::scene_tool::registry::SceneRegistry;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Scene tool actions (parallel to session tool)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum SceneAction {
    /// Open scene for editing - creates lock, returns context
    Open {
        scene_path: String,
        #[serde(default)]
        mode: SceneMode,
        #[serde(default)]
        agent_id: Option<String>,
    },
    /// Write/update scene plan
    Plan {
        plan: ScenePlan,
    },
    /// Execute plan via deterministic coder
    Orchestrate,
    /// Validate scene against plan (dual-engine QA)
    Validate,
    /// Commit changes - save and release lock
    Commit {
        #[serde(default = "default_true")]
        save: bool,
    },
    /// Get scene status
    Status,
    /// List all active scenes
    List,
}

fn default_true() -> bool {
    true
}

/// Get or create SceneRegistry for a project
pub async fn get_or_create_scene_registry(project_path: &str) -> Arc<SceneRegistry> {
    use std::sync::OnceLock;
    static REGISTRIES: OnceLock<tokio::sync::RwLock<std::collections::HashMap<String, Arc<SceneRegistry>>>> = OnceLock::new();
    
    let registries = REGISTRIES.get_or_init(|| tokio::sync::RwLock::new(std::collections::HashMap::new()));
    
    let mut regs = registries.write().await;
    if let Some(reg) = regs.get(project_path) {
        return reg.clone();
    }
    
    let project_root = std::path::Path::new(project_path);
    let registry = Arc::new(SceneRegistry::new(project_root));
    regs.insert(project_path.to_string(), registry.clone());
    registry
}

/// Register scene tool in the MCP server (called from server.rs run())
pub fn init_scene_tool(project_root: &std::path::Path) -> Arc<SceneRegistry> {
    Arc::new(SceneRegistry::new(project_root))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_scene_action_serialization() {
        let action = SceneAction::Open {
            scene_path: "res://test.tscn".to_string(),
            mode: SceneMode::Isolated,
            agent_id: Some("agent-1".to_string()),
        };
        let json = serde_json::to_string(&action).unwrap();
        assert!(json.contains("open"));
        assert!(json.contains("res://test.tscn"));
    }
    
    #[test]
    fn test_scene_action_plan() {
        let plan = ScenePlan::default();
        let action = SceneAction::Plan { plan };
        let json = serde_json::to_string(&action).unwrap();
        assert!(json.contains("plan"));
    }
}