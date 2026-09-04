//! Scene Tool Module — High-level scene editing with planning/orchestration
//! Pattern: scene/open → scene/plan → scene/orchestrate → scene/validate → scene/commit
//!
//! Fase 1 (2026-09-03): SINGLE SOURCE OF TRUTH.
//! El state (plan, qa, lock, mode) vive en HerenSceneRegistry (plugin GDScript).
//! Este módulo solo contiene la pure-logic (coder, validator, schemas) que el
//! server ejecuta al orquestrar/validar. NO mantiene estado mutable.

pub mod schemas;
pub mod coder;
pub mod validator;

pub use crate::scene_tool::schemas::*;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scene_action_plan_legacy_compat() {
        // SceneAction::Plan ya no se usa — el agente envía scene(action="plan",
        // plan_file=...) directamente. Test de regresión mínimo.
        let plan = ScenePlan::default();
        let json = serde_json::to_string(&plan).unwrap();
        assert!(json.contains("plan_id"));
    }
}
