"""
Heren MCP - Signal Tool (Centralizada)

Tool para gestionar senales, conexiones y scripts de nodos.
Modo UNICO: GodotDaemon.
"""

import logging

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def signal_tool(
    action: str,
    session_id: str,
    scene_path: str = "",
    from_node: str = "",
    signal_name: str = "",
    to_node: str = "",
    method: str = "",
    node_path: str = "",
    script_path: str = "",
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
            "message": "Signal operations requieren GodotDaemon activo"
        }

    if action == "connect":
        return _action_connect(manager, session_id, scene_path, from_node, signal_name, to_node, method)
    elif action == "disconnect":
        return _action_disconnect(manager, session_id, scene_path, from_node, signal_name, to_node, method)
    elif action == "list":
        return _action_list(manager, session_id, scene_path, from_node)
    elif action == "set_script":
        return _action_set_script(manager, session_id, scene_path, node_path, script_path)
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: connect, disconnect, list, set_script"
        }


def _execute_daemon(manager, session_id: str, operation: str, params: dict) -> dict:
    return manager.execute_via_daemon(session_id, operation, params)


def _action_connect(manager, session_id: str, scene_path: str, from_node: str,
                    signal_name: str, to_node: str, method: str) -> dict:
    if not all([scene_path, from_node, signal_name, to_node, method]):
        return {
            "success": False,
            "error": "scene_path, from_node, signal_name, to_node y method requeridos para action='connect'"
        }
    return _execute_daemon(manager, session_id, "connect_signal", {
        "scene_path": scene_path, "from_node": from_node,
        "signal_name": signal_name, "to_node": to_node, "method": method
    })


def _action_disconnect(manager, session_id: str, scene_path: str, from_node: str,
                       signal_name: str, to_node: str, method: str) -> dict:
    if not all([scene_path, from_node, signal_name, to_node, method]):
        return {
            "success": False,
            "error": "scene_path, from_node, signal_name, to_node y method requeridos para action='disconnect'"
        }
    return _execute_daemon(manager, session_id, "disconnect_signal", {
        "scene_path": scene_path, "from_node": from_node,
        "signal_name": signal_name, "to_node": to_node, "method": method
    })


def _action_list(manager, session_id: str, scene_path: str, from_node: str) -> dict:
    if not all([scene_path, from_node]):
        return {"success": False, "error": "scene_path y from_node requeridos para action='list'"}
    return _execute_daemon(manager, session_id, "list_signals",
                          {"scene_path": scene_path, "node_path": from_node})


def _action_set_script(manager, session_id: str, scene_path: str,
                       node_path: str, script_path: str) -> dict:
    if not all([scene_path, node_path, script_path]):
        return {
            "success": False,
            "error": "scene_path, node_path y script_path requeridos para action='set_script'"
        }
    return _execute_daemon(manager, session_id, "set_script", {
        "scene_path": scene_path, "node_path": node_path, "script_path": script_path
    })
