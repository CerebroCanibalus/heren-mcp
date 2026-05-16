"""
Animation Tool - Gestión centralizada de animaciones.

Actions:
- create_player: Crear AnimationPlayer
- create_animation: Crear Animation
- add_track: Añadir track
- add_key: Añadir keyframe
- state_machine: Crear AnimationNodeStateMachine
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def animation(action: str, session_id: str = None, **kwargs) -> dict:
    """Tool centralizada para animaciones."""
    session_manager = get_session_manager()
    
    # Obtener sesión explícita o activa
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    actions_map = {
        "create_player": _action_create_player,
        "create": _action_create_animation,
        "add_track": _action_add_track,
        "add_key": _action_add_key,
        "state_machine": _action_state_machine,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, session, **kwargs)
    except Exception as e:
        logger.error(f"Error en animation({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_create_player(session_manager, session, scene_path: str, parent_path: str = ".", player_name: str = "AnimationPlayer", **kwargs) -> dict:
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_animation_player", {
            "scene_path": scene_path,
            "parent_path": parent_path,
            "player_name": player_name
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_create_animation(session_manager, session, scene_path: str, player_path: str, anim_name: str, length: float = 1.0, loop: bool = False, **kwargs) -> dict:
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_animation", {
            "scene_path": scene_path,
            "player_path": player_path,
            "anim_name": anim_name,
            "length": length,
            "loop": loop
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_add_track(session_manager, session, scene_path: str, player_path: str, anim_name: str, track_type: str, node_path: str, property: str, **kwargs) -> dict:
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_animation_track", {
            "scene_path": scene_path,
            "player_path": player_path,
            "anim_name": anim_name,
            "track_type": track_type,
            "node_path": node_path,
            "property": property
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_add_key(session_manager, session, scene_path: str, player_path: str, anim_name: str, track_idx: int, time: float, value, transition: float = 1.0, **kwargs) -> dict:
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_animation_key", {
            "scene_path": scene_path,
            "player_path": player_path,
            "anim_name": anim_name,
            "track_idx": track_idx,
            "time": time,
            "value": value,
            "transition": transition
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_state_machine(session_manager, session, scene_path: str, player_path: str, states: list = None, transitions: list = None, **kwargs) -> dict:
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_state_machine", {
            "scene_path": scene_path,
            "player_path": player_path,
            "states": states or [],
            "transitions": transitions or []
        })
    return {"success": False, "error": "Daemon no disponible"}
