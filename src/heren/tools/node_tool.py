"""
Heren MCP - Node Tool (Centralizada)

Una sola tool para TODAS las operaciones de nodos.
Modo UNICO: GodotDaemon. Todas las operaciones via WebSocket ~20ms.
"""

import logging
from typing import Optional, Any

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def node_tool(
    action: str,
    session_id: str,
    scene_path: str,
    node_path: str = None,
    node_type: str = None,
    node_name: str = None,
    properties: dict = None,
    property_name: str = None,
    value: Any = None,
    new_name: str = None,
    new_parent: str = None,
    index: int = -1,
    **kwargs,
) -> dict:
    manager = get_session_manager()

    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesión no encontrada: {session_id}"}

    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Node operations requieren GodotDaemon activo"
        }

    if action == "add":
        return _action_add(manager, session_id, scene_path, node_path, node_type, node_name, properties)

    elif action == "remove":
        return _action_remove(manager, session_id, scene_path, node_path)

    elif action == "set_prop":
        return _action_set_prop(manager, session_id, scene_path, node_path, property_name, value)

    elif action == "get_prop":
        return _action_get_prop(manager, session_id, scene_path, node_path, property_name)

    elif action == "duplicate":
        return _action_duplicate(manager, session_id, scene_path, node_path)

    elif action == "rename":
        return _action_rename(manager, session_id, scene_path, node_path, new_name)

    elif action == "move":
        return _action_move(manager, session_id, scene_path, node_path, new_parent)

    elif action == "array_append":
        return _action_array_append(manager, session_id, scene_path, node_path, property_name, value)

    elif action == "array_remove":
        return _action_array_remove(manager, session_id, scene_path, node_path, property_name, value, index)

    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: add, remove, set_prop, get_prop, duplicate, rename, move, array_append, array_remove"
        }


def _execute_daemon(manager, session_id: str, operation: str, params: dict) -> dict:
    return manager.execute_via_daemon(session_id, operation, params)


def _action_add(manager, session_id: str, scene_path: str, parent_path: str,
                node_type: str, node_name: str, properties: dict) -> dict:
    if not all([scene_path, parent_path, node_type, node_name]):
        return {
            "success": False,
            "error": "scene_path, parent_path, node_type y node_name requeridos para action='add'"
        }
    return _execute_daemon(manager, session_id, "add_node", {
        "scene_path": scene_path,
        "parent_path": parent_path,
        "node_type": node_type,
        "node_name": node_name,
        "properties": properties or {}
    })


def _action_remove(manager, session_id: str, scene_path: str, node_path: str) -> dict:
    if not all([scene_path, node_path]):
        return {"success": False, "error": "scene_path y node_path requeridos para action='remove'"}
    return _execute_daemon(manager, session_id, "remove_node",
                          {"scene_path": scene_path, "node_path": node_path})


def _action_set_prop(manager, session_id: str, scene_path: str, node_path: str,
                     property_name: str, value: Any) -> dict:
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='set_prop'"
        }
    prop_name = property_name
    return _execute_daemon(manager, session_id, "set_property", {
        "scene_path": scene_path,
        "node_path": node_path,
        "property": prop_name,
        "value": value
    })


def _action_get_prop(manager, session_id: str, scene_path: str, node_path: str,
                     property_name: str) -> dict:
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='get_prop'"
        }
    return _execute_daemon(manager, session_id, "get_node_properties",
                          {"scene_path": scene_path, "node_path": node_path})


def _action_duplicate(manager, session_id: str, scene_path: str, node_path: str) -> dict:
    if not all([scene_path, node_path]):
        return {"success": False, "error": "scene_path y node_path requeridos para action='duplicate'"}
    return _execute_daemon(manager, session_id, "duplicate_node",
                          {"scene_path": scene_path, "node_path": node_path})


def _action_rename(manager, session_id: str, scene_path: str, node_path: str,
                   new_name: str) -> dict:
    if not all([scene_path, node_path, new_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y new_name requeridos para action='rename'"
        }
    return _execute_daemon(manager, session_id, "rename_node",
                          {"scene_path": scene_path, "node_path": node_path, "new_name": new_name})


def _action_move(manager, session_id: str, scene_path: str, node_path: str,
                 new_parent: str) -> dict:
    if not all([scene_path, node_path, new_parent]):
        return {
            "success": False,
            "error": "scene_path, node_path y new_parent requeridos para action='move'"
        }
    return _execute_daemon(manager, session_id, "move_node",
                          {"scene_path": scene_path, "node_path": node_path, "new_parent": new_parent})


def _action_array_append(manager, session_id: str, scene_path: str, node_path: str,
                         property_name: str, value: Any) -> dict:
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='array_append'"
        }
    return _execute_daemon(manager, session_id, "array_append", {
        "scene_path": scene_path,
        "node_path": node_path,
        "property_name": property_name,
        "value": value
    })


def _action_array_remove(manager, session_id: str, scene_path: str, node_path: str,
                         property_name: str, value: Any, index: int) -> dict:
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='array_remove'"
        }

    params = {"scene_path": scene_path, "node_path": node_path, "property_name": property_name}

    if index >= 0:
        params["index"] = index
    elif value is not None:
        params["value"] = value
    else:
        return {"success": False, "error": "index o value requerido para action='array_remove'"}

    return _execute_daemon(manager, session_id, "array_remove", params)
