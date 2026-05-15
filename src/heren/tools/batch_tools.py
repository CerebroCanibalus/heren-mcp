"""
Heren MCP - Batch Tool (Capa 2)

Ejecuta múltiples operaciones en una sola llamada.
Optimiza rendimiento reduciendo overhead de comunicaci�n.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import json
import logging
from typing import Any

from heren.core.session_manager import get_session_manager
from heren.tools.scene_tool import scene_tool
from heren.tools.node_tool import node_tool

logger = logging.getLogger(__name__)


def heren_batch(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta m�ltiples operaciones en batch.
    
    CON DAEMON: Env�a todas en UNA sola llamada WebSocket (~20ms)
    SIN DAEMON: Ejecuta secuencialmente via scripts temporales (~370ms cada una)
    
    Args:
        session_id: ID de sesi�n activa
        operations: Lista de operaciones
            Cada operaci�n es un dict con:
            - "action": str - Nombre de la operaci�n
            - "params": dict - Par�metros de la operaci�n
        stop_on_error: Si True, detiene en el primer error
    
    Returns:
        {
            "success": bool,
            "results": list[dict],
            "errors": list[dict],
            "success_count": int,
            "error_count": int,
        }
    
    Example:
        heren_batch(session_id, [
            {"action": "add_node", "params": {...}},
            {"action": "set_property", "params": {...}},
            {"action": "save_scene", "params": {...}},
        ])
    """
    try:
        session_manager = get_session_manager()
        
        # FIX: Validar y sanitizar operaciones antes de enviar
        sanitized_operations = []
        for op in operations:
            action = op.get("action", "")
            params = op.get("params", {})
            
            # Sanitizar strings en params para evitar JSON breakage
            sanitized_params = _sanitize_params(params)
            sanitized_operations.append({
                "action": action,
                "params": sanitized_params
            })
        
        # 1. Intentar GodotDaemon (WebSocket - m�s r�pido)
        daemon = session_manager.get_godot_daemon(session_id)
        if daemon:
            logger.info(f"[Daemon] Ejecutando batch de {len(sanitized_operations)} operaciones")
            # Traducir "action" a "method" para el daemon
            # Mapeo de acciones cortas a nombres de handlers del daemon
            ACTION_TO_METHOD = {
                # Scene operations
                "get_tree": "get_scene_tree",
                "save": "save_scene",
                "load": "load_scene",
                "unload": "unload_scene",
                "list_loaded": "get_loaded_scenes",
                "screenshot": "screenshot",
                "create": "create_scene",
                "delete": "delete_scene",
                "rename": "rename_scene",
                # Node operations
                "add": "add_node",
                "remove": "remove_node",
                "set_prop": "set_property",
                "get_prop": "get_node_properties",
                "duplicate": "duplicate_node",
                "rename_node": "rename_node",
                "move": "move_node",
                # Resource operations
                "create_resource": "create_resource",
                "read_resource": "read_resource",
                "update_resource": "update_resource",
                "delete_resource": "delete_resource",
                "list_resources": "list_resources",
                # Animation operations
                "create_player": "create_animation_player",
                "create_anim": "create_animation",
                "add_track": "add_animation_track",
                "add_key": "add_animation_key",
                "state_machine": "create_state_machine",
                # Skeleton operations
                "create_skeleton": "create_skeleton",
                "add_bone": "add_bone",
                "set_rest": "set_bone_rest",
                "skin": "skin_polygon2d",
                "attachment": "add_bone_attachment",
                # Shader operations
                "create_shader": "create_shader",
                "edit_shader": "edit_shader",
                "validate_shader": "validate_shader",
                "material": "create_shader_material",
                "uniform": "set_shader_uniform",
                # Tilemap operations
                "inspect_set": "inspect_tileset",
                "inspect_map": "inspect_tilemap",
                "set_cell": "set_tilemap_cell",
                "terrain": "apply_terrain",
                "pattern": "create_tile_pattern",
                # Project operations
                "set_setting": "set_project_setting",
                "get_setting": "get_project_setting",
                "add_autoload": "add_autoload",
                "remove_autoload": "remove_autoload",
                "shader_global": "set_shader_global",
                # Debug operations
                "breakpoint": "set_breakpoint",
                "stack_trace": "get_stack_trace",
                "watch": "watch_variable",
                "console": "get_console_output",
                # Validate operations
                "validate_scene": "validate_scene",
                "validate_script": "validate_script",
                "validate_node": "validate_node",
                "validate_resource": "validate_resource",
                # Visual operations
                "inspect_visual": "inspect_visual",
                "raycast": "raycast",
                "measure": "measure",
            }
            
            daemon_operations = []
            for op in sanitized_operations:
                action = op.get("action", "")
                method = ACTION_TO_METHOD.get(action, action)
                
                # FIX: Serializar params individualmente para detectar errores JSON
                try:
                    params_json = json.dumps(op.get("params", {}))
                    json.loads(params_json)  # Verificar que es parseable
                except (json.JSONDecodeError, TypeError) as e:
                    return {
                        "success": False,
                        "error": f"JSON invalido en params de action '{action}': {e}",
                        "results": [],
                        "errors": [{"index": 0, "action": action, "error": str(e)}],
                        "success_count": 0,
                        "error_count": 1
                    }
                
                daemon_op = {
                    "method": method,
                    "params": op.get("params", {})
                }
                daemon_operations.append(daemon_op)
            
            return session_manager.execute_batch_via_daemon(session_id, daemon_operations, stop_on_error)
        
        # 2. Intentar GodotServer (HTTP legacy)
        server = session_manager.get_godot_server(session_id)
        if server:
            logger.info(f"Ejecutando batch de {len(sanitized_operations)} operaciones via GodotServer")
            return server.execute("batch", {
                "operations": sanitized_operations,
                "stop_on_error": stop_on_error
            })
        
        # 3. Fallback: ejecutar una por una con scripts temporales
        logger.info(f"Ejecutando batch de {len(sanitized_operations)} operaciones via scripts temporales")
        return _execute_batch_fallback(session_id, sanitized_operations, stop_on_error)
        
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


def _execute_batch_fallback(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta batch usando scripts temporales (fallback).
    """
    results = []
    errors = []
    
    for i, op in enumerate(operations):
        try:
            action = op.get("action", "")
            params = op.get("params", {})
            
            # Mapear acciones a tools centralizadas
            result = None
            
            if action in ["get_tree", "save", "load", "unload", "list_loaded", "screenshot", "create", "delete", "rename"]:
                # Scene tool
                result = scene_tool(
                    action=action,
                    session_id=session_id,
                    scene_path=params.get("scene_path"),
                    output_path=params.get("output_path"),
                    resolution=params.get("resolution", (1920, 1080)),
                    wait_frames=params.get("wait_frames", 3),
                    format=params.get("format", "png"),
                    quality=params.get("quality", 0.9)
                )
            elif action in ["add", "remove", "set_prop", "get_prop", "duplicate", "rename", "move"]:
                # Node tool
                result = node_tool(
                    action=action,
                    session_id=session_id,
                    scene_path=params.get("scene_path", ""),
                    node_path=params.get("node_path"),
                    node_type=params.get("node_type"),
                    node_name=params.get("node_name"),
                    properties=params.get("properties"),
                    property_name=params.get("property_name"),
                    value=params.get("value"),
                    new_name=params.get("new_name"),
                    new_parent=params.get("new_parent")
                )
            else:
                result = {"success": False, "error": f"Acción no soportada en fallback: {action}"}
            
            results.append(result)
            
            if result.get("error") or not result.get("success", True):
                errors.append({
                    "index": i,
                    "action": action,
                    "error": result.get("error", "Unknown error")
                })
                
                if stop_on_error:
                    break
                    
        except Exception as e:
            error_info = {
                "index": i,
                "action": op.get("action", ""),
                "error": str(e)
            }
            errors.append(error_info)
            results.append({"success": False, "error": str(e)})
            
            if stop_on_error:
                break
    
    return {
        "success": len(errors) == 0,
        "results": results,
        "errors": errors,
        "success_count": len(operations) - len(errors),
        "error_count": len(errors)
    }


def _sanitize_params(params: dict) -> dict:
    """Sanitiza parametros para evitar problemas de JSON."""
    if not isinstance(params, dict):
        return params
    
    result = {}
    for key, value in params.items():
        if isinstance(value, str):
            # Escapar caracteres problem�ticos
            sanitized = value.replace('\x00', '')  # Null bytes
            result[key] = sanitized
        elif isinstance(value, dict):
            result[key] = _sanitize_params(value)
        elif isinstance(value, list):
            result[key] = [_sanitize_params(item) if isinstance(item, dict) else item for item in value]
        else:
            result[key] = value
    
    return result
