"""
Heren MCP - Batch Tool (Capa 2)

Ejecuta multiples operaciones en una sola llamada via GodotDaemon.
Modo UNICO: WebSocket. ~200ms para 11 operaciones.
"""

import json
import logging

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)

ACTION_TO_METHOD = {
    "get_tree": "get_scene_tree",
    "save": "save_scene",
    "load": "load_scene",
    "unload": "unload_scene",
    "list_loaded": "get_loaded_scenes",
    "screenshot": "screenshot",
    "create": "create_scene",
    "delete": "delete_scene",
    "rename": "rename_scene",
    "add": "add_node",
    "remove": "remove_node",
    "set_prop": "set_property",
    "get_prop": "get_node_properties",
    "duplicate": "duplicate_node",
    "rename_node": "rename_node",
    "move": "move_node",
    "create_resource": "create_resource",
    "read_resource": "read_resource",
    "update_resource": "update_resource",
    "delete_resource": "delete_resource",
    "list_resources": "list_resources",
    "create_player": "create_animation_player",
    "create_anim": "create_animation",
    "add_track": "add_animation_track",
    "add_key": "add_animation_key",
    "state_machine": "create_state_machine",
    "create_skeleton": "create_skeleton",
    "add_bone": "add_bone",
    "set_rest": "set_bone_rest",
    "skin": "skin_polygon2d",
    "attachment": "add_bone_attachment",
    "create_shader": "create_shader",
    "edit_shader": "edit_shader",
    "validate_shader": "validate_shader",
    "material": "create_shader_material",
    "uniform": "set_shader_uniform",
    "inspect_set": "inspect_tileset",
    "inspect_map": "inspect_tilemap",
    "set_cell": "set_tilemap_cell",
    "terrain": "apply_terrain",
    "pattern": "create_tile_pattern",
    "set_setting": "set_project_setting",
    "get_setting": "get_project_setting",
    "add_autoload": "add_autoload",
    "remove_autoload": "remove_autoload",
    "shader_global": "set_shader_global",
    "breakpoint": "set_breakpoint",
    "stack_trace": "get_stack_trace",
    "watch": "watch_variable",
    "console": "get_console_output",
    "validate_scene": "validate_scene",
    "validate_script": "validate_script",
    "validate_node": "validate_node",
    "validate_resource": "validate_resource",
    "inspect_visual": "inspect_visual",
    "raycast": "raycast",
    "measure": "measure",
}


def heren_batch(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    try:
        session_manager = get_session_manager()

        sanitized_operations = []
        for op in operations:
            action = op.get("action", "")
            params = op.get("params", {})
            sanitized_params = _sanitize_params(params)
            sanitized_operations.append({"action": action, "params": sanitized_params})

        daemon = session_manager.get_godot_daemon(session_id)
        if not daemon:
            return {
                "success": False,
                "error": "daemon_not_available",
                "message": "Batch operations requieren GodotDaemon activo",
                "results": [],
                "errors": [{"error": "daemon_not_available"}],
                "success_count": 0,
                "error_count": 1
            }

        logger.info(f"[Daemon] Ejecutando batch de {len(sanitized_operations)} operaciones")

        daemon_operations = []
        for op in sanitized_operations:
            action = op.get("action", "")
            method = ACTION_TO_METHOD.get(action, action)

            try:
                params_json = json.dumps(op.get("params", {}))
                json.loads(params_json)
            except (json.JSONDecodeError, TypeError) as e:
                return {
                    "success": False,
                    "error": f"JSON invalido en params de action '{action}': {e}",
                    "results": [],
                    "errors": [{"index": 0, "action": action, "error": str(e)}],
                    "success_count": 0,
                    "error_count": 1
                }

            daemon_operations.append({
                "method": method,
                "params": op.get("params", {})
            })

        return session_manager.execute_batch_via_daemon(session_id, daemon_operations, stop_on_error)

    except Exception as e:
        logger.error(f"Error en batch: {e}")
        return {
            "success": False,
            "error": str(e),
            "results": [],
            "errors": [{"index": 0, "error": str(e)}],
            "success_count": 0,
            "error_count": 1
        }


def _sanitize_params(params: dict) -> dict:
    if not isinstance(params, dict):
        return params

    result = {}
    for key, value in params.items():
        if isinstance(value, str):
            result[key] = value.replace('\x00', '')
        elif isinstance(value, dict):
            result[key] = _sanitize_params(value)
        elif isinstance(value, list):
            result[key] = [_sanitize_params(item) if isinstance(item, dict) else item for item in value]
        else:
            result[key] = value

    return result
