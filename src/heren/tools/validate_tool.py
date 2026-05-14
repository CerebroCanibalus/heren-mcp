"""
Validate Tool - Validación de escenas, scripts, nodos y recursos.

Actions:
- scene: Validar archivo .tscn
- script: Validar script GDScript
- node: Validar nodo en escena
- resource: Validar recurso .tres
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def validate(action: str, session_id: str = None, **kwargs) -> dict:
    """Tool centralizada para validación."""
    session_manager = get_session_manager()
    
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if not daemon:
        return {"success": False, "error": "Validación requiere daemon activo"}
    
    actions_map = {
        "scene": _action_scene,
        "script": _action_script,
        "node": _action_node,
        "resource": _action_resource,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](daemon, **kwargs)
    except Exception as e:
        logger.error(f"Error en validate({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_scene(daemon, scene_path: str, **kwargs) -> dict:
    """Validar escena .tscn"""
    return daemon.call("validate_scene", {"scene_path": scene_path})


def _action_script(daemon, script_path: str, **kwargs) -> dict:
    """Validar script GDScript"""
    return daemon.call("validate_script", {"script_path": script_path})


def _action_node(daemon, scene_path: str, node_path: str, **kwargs) -> dict:
    """Validar nodo en escena"""
    return daemon.call("validate_node", {
        "scene_path": scene_path,
        "node_path": node_path
    })


def _action_resource(daemon, resource_path: str, **kwargs) -> dict:
    """Validar recurso .tres"""
    return daemon.call("validate_resource", {"resource_path": resource_path})
