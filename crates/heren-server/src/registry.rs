//! EditorRegistry — WS peer registry (port de `WsServer` en ws_server.py).
//!
//! Mantiene los editores Godot conectados (project_path → canal WS),
//! correlaciona respuestas por id JSON-RPC (tolerante a "1.0"/"1"),
//! y reenvía `tools/call` al editor correcto.

use std::collections::HashMap;
use std::sync::Arc;

use futures::channel::mpsc;
use futures::lock::Mutex;
use serde_json::{Value, json};
use tokio::sync::oneshot;
use tracing::{debug, info};

use crate::editor::{GodotReady, JsonRpcResponse, ToolCallParams, normalize_project_path};

/// Canal de salida hacia un editor conectado (sender WS).
#[derive(Debug)]
pub enum EditorChannel {
    /// Text frame JSON-RPC.
    Send(serde_json::Value),
    /// Binario (payload `__image_base64`).
    SendBytes(Vec<u8>),
}

#[derive(Debug, Clone)]
pub struct EditorHandle {
    pub project_path: String,
    pub tx: mpsc::UnboundedSender<EditorChannel>,
    /// Versión del plugin que corre en el editor (reportada en godot_ready).
    pub plugin_version: Option<String>,
}

/// Estado compartido del registry.
#[derive(Debug, Default)]
pub struct RegistryState {
    editors: HashMap<String, EditorHandle>,
    pending: HashMap<String, oneshot::Sender<Result<Value, String>>>,
    /// Escenas con cambios sin guardar por proyecto (rediseño persistencia
    /// 2026-08-07): el agente muta el árbol vivo, `dirty` lo recuerda, y el
    /// cierre de sesión (o flush-before-destroy) persiste. Si el editor se
    /// cierra sin `session/close`, `unexpected_close` se marca y TODAS las
    /// tools fallan con error hasta `session/open` de nuevo (fail-fast).
    dirty: HashMap<String, std::collections::HashSet<String>>,
    unexpected_close: HashMap<String, std::collections::HashSet<String>>,
    /// Proyectos en cierre GRACEFUL (session/close en curso): la desconexión
    /// WS no debe marcar unexpected_close.
    graceful_closing: std::collections::HashSet<String>,
}

#[derive(Debug, Clone, Default)]
pub struct EditorRegistry {
    state: Arc<Mutex<RegistryState>>,
}

/// Registry global del proceso (single-instance server binario).
/// Las tools de FlojoMCP se registran vía inventory (funciones libres),
/// así que necesitan acceso global al registry — no al server instance.
static GLOBAL: std::sync::OnceLock<EditorRegistry> = std::sync::OnceLock::new();

impl EditorRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Inicializa el registry global (idempotente; devuelve el existente).
    pub fn init_global() -> &'static EditorRegistry {
        GLOBAL.get_or_init(EditorRegistry::new)
    }

    /// Acceso al registry global (panics si no inicializado — solo se usa
    /// desde run(), que llama init_global primero).
    pub fn global() -> &'static EditorRegistry {
        GLOBAL
            .get()
            .expect("EditorRegistry::init_global() must be called in run()")
    }

    /// Registra un editor conectado (notificación godot_ready).
    pub async fn register(
        &self,
        ready: GodotReady,
        tx: mpsc::UnboundedSender<EditorChannel>,
    ) -> String {
        let key = normalize_project_path(&ready.project_path);
        self.register_ctrl(key, tx, ready.plugin_version.clone())
            .await
    }

    /// Registra un editor por clave canónica ya normalizada.
    pub async fn register_ctrl(
        &self,
        key: String,
        tx: mpsc::UnboundedSender<EditorChannel>,
        plugin_version: Option<String>,
    ) -> String {
        let mut state = self.state.lock().await;
        info!(project_path = %key, plugin_version = ?plugin_version.as_deref(), "editor registered");
        state.editors.insert(
            key.clone(),
            EditorHandle {
                project_path: key.clone(),
                tx,
                plugin_version,
            },
        );
        key
    }

    /// Des-registra un editor (desconexión).
    pub async fn unregister(&self, project_path: &str) {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        state.editors.remove(&key);
        debug!(project_path = %key, "editor unregistered");
    }

    /// ¿Hay editor conectado para el proyecto?
    pub async fn has_editor(&self, project_path: &str) -> bool {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        state.editors.contains_key(&key)
    }

    /// Versión del plugin que corre en el editor conectado (si lo hay).
    pub async fn editor_plugin_version(&self, project_path: &str) -> Option<String> {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        state
            .editors
            .get(&key)
            .and_then(|h| h.plugin_version.clone())
    }

    /// Proyectos con editor vivo.
    pub async fn connected_projects(&self) -> Vec<String> {
        let state = self.state.lock().await;
        let mut keys: Vec<String> = state.editors.keys().cloned().collect();
        keys.sort();
        keys
    }

    /// Marca una escena como dirty (con cambios sin guardar) para el proyecto.
    /// Rediseño persistencia 2026-08-07: el server recuerda qué escenas el
    /// agente tocó; `scene/save` las limpia; `session/close` hace flush.
    pub async fn mark_dirty(&self, project_path: &str, scene_path: &str) {
        let key = normalize_project_path(project_path);
        if scene_path.is_empty() {
            return;
        }
        let mut state = self.state.lock().await;
        state
            .dirty
            .entry(key)
            .or_default()
            .insert(scene_path.to_string());
    }

    /// Limpia una escena tras guardarla (scene/save o flush).
    pub async fn clean_dirty(&self, project_path: &str, scene_path: &str) {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        if let Some(set) = state.dirty.get_mut(&key) {
            set.remove(scene_path);
            if set.is_empty() {
                state.dirty.remove(&key);
            }
        }
    }

    /// Escenas dirty del proyecto (ordenadas).
    pub async fn dirty_scenes(&self, project_path: &str) -> Vec<String> {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        let mut v: Vec<String> = state
            .dirty
            .get(&key)
            .map(|s| s.iter().cloned().collect())
            .unwrap_or_default();
        v.sort();
        v
    }

    /// Marca el cierre INESPERADO del editor (WS cayó sin session/close).
    /// Guarda las dirty que quedaban para el diagnóstico del agente.
    ///
    /// Fix 2026-08-07: SOLO marca si hay escenas sucias (trabajo que se
    /// perdería). Un cierre con 0 dirty es una desconexión benigna: no hay
    /// nada que proteger → las tools fallan con el error normal
    /// "no editor connected" hasta `session/open`, sin fail-fast duro.
    pub async fn mark_unexpected_close(&self, project_path: &str) {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        let dirty = state.dirty.remove(&key).unwrap_or_default();
        if !dirty.is_empty() {
            state.unexpected_close.insert(key, dirty);
        }
    }

    /// ¿El editor se cerró inesperadamente (requiere session/open)?
    pub async fn unexpected_close(&self, project_path: &str) -> Option<Vec<String>> {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        let mut v: Vec<String> = state
            .unexpected_close
            .get(&key)
            .map(|s| s.iter().cloned().collect())
            .unwrap_or_default();
        v.sort();
        if v.is_empty() && !state.unexpected_close.contains_key(&key) {
            None
        } else {
            Some(v)
        }
    }

    /// Limpia el flag de cierre inesperado (tras session/open o close normal).
    pub async fn clear_unexpected_close(&self, project_path: &str) {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        state.unexpected_close.remove(&key);
    }

    /// Marca el proyecto como en cierre GRACEFUL (session/close). La
    /// desconexión WS que sigue NO marca unexpected_close.
    pub async fn mark_graceful_close(&self, project_path: &str) {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        state.graceful_closing.insert(key);
    }

    /// ¿La desconexión WS de este proyecto fue un cierre graceful?
    pub async fn is_graceful_close(&self, project_path: &str) -> bool {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        state.graceful_closing.contains(&key)
    }

    /// Consume y limpia el flag de cierre graceful (una sola vez por close).
    pub async fn take_graceful_close(&self, project_path: &str) -> bool {
        let key = normalize_project_path(project_path);
        let mut state = self.state.lock().await;
        state.graceful_closing.remove(&key)
    }

    /// Envía `tools/call` al editor y espera la respuesta correlacionada.
    pub async fn call_tool(
        &self,
        tool_name: &str,
        args: Value,
        project_path: &str,
    ) -> Result<Value, String> {
        let key = normalize_project_path(project_path);
        let tx = {
            let state = self.state.lock().await;
            // Fail-fast (rediseño persistencia 2026-08-07): si el editor se
            // cerró SIN session/close, el agente debe saberlo INMEDIATAMENTE
            // (el trabajo se interrumpió), no seguir contra un editor muerto.
            if let Some(dirty) = state.unexpected_close.get(&key) {
                let paths: Vec<String> = dirty.iter().cloned().collect();
                return Err(format!(
                    "editor_closed_unexpectedly: el editor se cerró sin session/close; \
                     había {} escena(s) con cambios sin guardar: {}. \
                     Ejecuta session/open para reconectar y session/health para diagnosticar.",
                    paths.len(),
                    if paths.is_empty() {
                        "(sin escenas sucias)".to_string()
                    } else {
                        paths.join(", ")
                    }
                ));
            }
            state
                .editors
                .get(&key)
                .map(|h| h.tx.clone())
                .ok_or_else(|| format!("no editor connected: {key}"))?
        };

        let req_id = make_req_id();
        let (resp_tx, resp_rx) = oneshot::channel();
        {
            let mut state = self.state.lock().await;
            state.pending.insert(req_id.clone(), resp_tx);
        }

        let msg = json!({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "id": req_id,
            "params": ToolCallParams {
                name: tool_name.to_string(),
                arguments: args,
            },
        });

        tx.unbounded_send(EditorChannel::Send(msg))
            .map_err(|e| format!("ws send failed: {e}"))?;

        let resp = tokio::time::timeout(
            tokio::time::Duration::from_millis(crate::constants::TOOL_TIMEOUT_MS),
            resp_rx,
        )
        .await
        .map_err(|_| format!("tool timeout: {tool_name}"))?
        .map_err(|_| format!("tool cancelled: {tool_name}"))?;

        let mut state = self.state.lock().await;
        state.pending.remove(&req_id);
        resp
    }

    /// Resuelve una respuesta entrante contra un request pendiente.
    /// Tolerante al id del plugin: str(id) del request puede llegar como "1.0".
    pub async fn resolve_response(&self, resp: JsonRpcResponse) -> bool {
        let candidates = id_candidates(&resp.id);
        let mut state = self.state.lock().await;
        for key in &candidates {
            if let Some(tx) = state.pending.remove(key) {
                if let Some(err) = resp.error {
                    let _ = tx.send(Err(err.message.clone()));
                } else {
                    let _ = tx.send(Ok(resp.result.unwrap_or(Value::Null)));
                }
                return true;
            }
        }
        false
    }

    /// Empuja una notificación al editor (p.ej. para pings).
    pub async fn send_notification(&self, project_path: &str, method: &str, params: Value) {
        let key = normalize_project_path(project_path);
        let state = self.state.lock().await;
        if let Some(h) = state.editors.get(&key) {
            let _ = h.tx.unbounded_send(EditorChannel::Send(json!({
                "jsonrpc": "2.0",
                "method": method,
                "params": params,
            })));
        }
    }
}

/// Genera un id de request único.
fn make_req_id() -> String {
    static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    format!(
        "h{}",
        COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    )
}

/// Normaliza el id de una respuesta: exacto, string, y float-normalizado.
fn id_candidates(id: &Value) -> Vec<String> {
    let mut out = Vec::new();
    let raw = match id {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    };
    out.push(raw.clone());
    // "1.0" -> "1"
    if let Ok(f) = raw.parse::<f64>() {
        if f.fract() == 0.0 {
            out.push(format!("{f:.0}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_candidates_normalize_float_strings() {
        let c = id_candidates(&Value::String("1.0".into()));
        assert!(c.contains(&"1.0".to_string()));
        assert!(c.contains(&"1".to_string()));
    }

    #[test]
    fn normalize_same_key() {
        assert_eq!(
            normalize_project_path(r"D:\proj\"),
            normalize_project_path("D:/proj")
        );
    }

    #[tokio::test]
    async fn dirty_tracking_mark_clean_and_list() {
        let r = EditorRegistry::new();
        r.mark_dirty("D:/proj", "res://a.tscn").await;
        r.mark_dirty("D:/proj", "res://b.tscn").await;
        let dirty = r.dirty_scenes("D:/proj").await;
        assert_eq!(dirty, vec!["res://a.tscn", "res://b.tscn"]);
        r.clean_dirty("D:/proj", "res://a.tscn").await;
        let dirty = r.dirty_scenes("D:/proj").await;
        assert_eq!(dirty, vec!["res://b.tscn"]);
        r.clean_dirty("D:/proj", "res://b.tscn").await;
        assert!(r.dirty_scenes("D:/proj").await.is_empty());
    }

    #[tokio::test]
    async fn dirty_tracking_ignores_empty_scene() {
        let r = EditorRegistry::new();
        r.mark_dirty("D:/proj", "").await;
        assert!(r.dirty_scenes("D:/proj").await.is_empty());
    }

    #[tokio::test]
    async fn unexpected_close_marks_and_clears() {
        let r = EditorRegistry::new();
        assert!(r.unexpected_close("D:/proj").await.is_none());
        r.mark_dirty("D:/proj", "res://a.tscn").await;
        r.mark_unexpected_close("D:/proj").await;
        let dirty = r.unexpected_close("D:/proj").await;
        assert!(dirty.is_some());
        assert_eq!(dirty.unwrap(), vec!["res://a.tscn"]);
        // Tras el cierre inesperado, las dirty pasan al flag (no quedan activas).
        assert!(r.dirty_scenes("D:/proj").await.is_empty());
        r.clear_unexpected_close("D:/proj").await;
        assert!(r.unexpected_close("D:/proj").await.is_none());
    }

    #[tokio::test]
    async fn unexpected_close_without_dirty_is_benign() {
        let r = EditorRegistry::new();
        // Cierre sin escenas sucias = desconexión benigna: NO marca el flag
        // fail-fast (nada que perder → session/open reconecta normal, las
        // tools solo dan "no editor connected").
        r.mark_unexpected_close("D:/proj").await;
        assert!(r.unexpected_close("D:/proj").await.is_none());
        // Con dirty sí marca (hay trabajo sin guardar que se perdería).
        r.mark_dirty("D:/proj", "res://a.tscn").await;
        r.mark_unexpected_close("D:/proj").await;
        assert!(r.unexpected_close("D:/proj").await.is_some());
        assert_eq!(
            r.unexpected_close("D:/proj").await.unwrap(),
            vec!["res://a.tscn"]
        );
    }

    #[tokio::test]
    async fn graceful_close_flag_one_shot() {
        let r = EditorRegistry::new();
        assert!(!r.is_graceful_close("D:/proj").await);
        r.mark_graceful_close("D:/proj").await;
        assert!(r.is_graceful_close("D:/proj").await);
        assert!(r.take_graceful_close("D:/proj").await);
        assert!(!r.is_graceful_close("D:/proj").await);
    }
}
