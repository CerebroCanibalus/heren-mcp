//! Helpers puros del server Heren MCP.
//!
//! Funciones sin efectos secundarios (no tocan registry, WS, disco ni estado
//! global). Extraídas de `server.rs` (Fase C1) para poder testearlas de forma
//! aislada y reducir el tamaño del módulo de dispatch.

use serde_json::{Map, Value};

/// Construye un args dict con los campos no-nulos.
/// IMPORTANTE (fix C1/C2): las keys None se OMITEN, no se insertan como
/// `Value::Null`. Antes `project/setting` get recibía `"value":null` y
/// `handle_setting` lo interpretaba como set (borraba el setting); además
/// `str(null)` en GDScript = `"<null>"` rompía los guards `if x == ""`.
pub fn args(entries: &[(&str, Option<Value>)]) -> Value {
    let mut m = Map::new();
    for (k, v) in entries {
        if let Some(val) = v {
            m.insert(k.to_string(), val.clone());
        }
    }
    Value::Object(m)
}

/// Normaliza un scene_path del agente a la forma canónica de Godot
/// (`res://` prefix, forward slashes, sin trailing slash). El plugin compara
/// `scene_file_path` (siempre `res://...` normalizado por Godot) contra la key
/// del SceneRegistry; si el agente manda `scenes/x.tscn` (sin res://),
/// backslashes o trailing slash, el match falla → la escena se registra como
/// fantasma y save/open divergen de la pestaña real (fix 2026-08-06).
/// Empty string → sin cambio (las tools lo tratan como "no path").
pub fn normalize_scene_path(path: &str) -> String {
    let s = path.trim();
    if s.is_empty() {
        return String::new();
    }
    let replaced = s.replace('\\', "/");
    let trimmed = replaced.trim_end_matches('/').to_string();
    // `res:/...` (tras convertir backslashes) o `res://...` ya son canónicos.
    // Cualquier otro prefijo (`scenes/...`, `../`, absoluto) → anteponer res://
    if trimmed.starts_with("res://") || trimmed.starts_with("res:/") {
        // Normalizar `res:/` → `res://` (Godot exige doble slash).
        if trimmed.starts_with("res:/") && !trimmed.starts_with("res://") {
            return format!("res://{}", &trimmed[5..]);
        }
        trimmed
    } else {
        format!("res://{trimmed}")
    }
}

/// Desenvuelve la respuesta del plugin: content[0].text como JSON dict.
/// Si el content incluye `__image_base64`, devuelve la imagen (y formato)
/// como dict MCP en lugar del texto.
pub fn unwrap_result(raw: &Value) -> Value {
    if let Some(content) = raw.get("content").and_then(|c| c.as_array()) {
        for item in content {
            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                if let Ok(parsed) = serde_json::from_str::<Value>(text) {
                    return parsed;
                }
            }
            // Imagen base64 (__image_base64 en el text-stream).
            if let Some(b64) = item.get("__image_base64").and_then(|b| b.as_str()) {
                let mut m = Map::new();
                m.insert("__image_base64".into(), Value::String(b64.to_string()));
                if let Some(fmt) = item.get("__image_format").and_then(|f| f.as_str()) {
                    m.insert("__image_format".into(), Value::String(fmt.to_string()));
                }
                return Value::Object(m);
            }
        }
    }
    raw.clone()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn args_omits_none_keys() {
        let a = args(&[
            ("scene_path", Some(Value::String("res://x.tscn".into()))),
            ("node_path", None),
            ("recursive", Some(json!(true))),
        ]);
        let obj = a.as_object().unwrap();
        assert!(obj.contains_key("scene_path"));
        assert!(!obj.contains_key("node_path"), "keys None se omiten");
        assert!(obj.contains_key("recursive"));
        assert_eq!(obj["recursive"], json!(true));
    }

    #[test]
    fn args_empty_slice_is_empty_object() {
        assert_eq!(args(&[]), json!({}));
    }

    #[test]
    fn normalize_scene_path_adds_res_prefix() {
        assert_eq!(
            normalize_scene_path("scenes/level1.tscn"),
            "res://scenes/level1.tscn"
        );
    }

    #[test]
    fn normalize_scene_path_converts_backslashes() {
        assert_eq!(
            normalize_scene_path("res:\\scenes\\level1.tscn"),
            "res://scenes/level1.tscn"
        );
    }

    #[test]
    fn normalize_scene_path_strips_trailing_slash() {
        assert_eq!(
            normalize_scene_path("res://scenes/level1.tscn/"),
            "res://scenes/level1.tscn"
        );
    }

    #[test]
    fn normalize_scene_path_keeps_clean() {
        assert_eq!(
            normalize_scene_path("res://scenes/level1.tscn"),
            "res://scenes/level1.tscn"
        );
    }

    #[test]
    fn normalize_scene_path_empty_stays_empty() {
        assert_eq!(normalize_scene_path(""), "");
        assert_eq!(normalize_scene_path("   "), "");
    }

    #[test]
    fn unwrap_result_parses_text_content() {
        let raw = json!({
            "content": [{"type": "text", "text": "{\"ok\":true,\"a\":1}"}],
            "structuredContent": null
        });
        let out = unwrap_result(&raw);
        assert_eq!(out, json!({"ok": true, "a": 1}));
    }

    #[test]
    fn unwrap_result_extracts_image_base64() {
        let raw = json!({
            "content": [{"type": "text", "text": "hi", "__image_base64": "AAAA", "__image_format": "png"}]
        });
        let out = unwrap_result(&raw);
        assert_eq!(out["__image_base64"], "AAAA");
        assert_eq!(out["__image_format"], "png");
    }

    #[test]
    fn unwrap_result_passthrough_non_text() {
        let raw = json!({"raw": [1, 2, 3]});
        assert_eq!(unwrap_result(&raw), raw);
    }
}
