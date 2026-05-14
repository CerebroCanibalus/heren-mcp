"""
Skeleton Tool - Gestión centralizada de esqueletos.

Actions:
- create: Crear Skeleton2D/3D
- add_bone: Añadir hueso
- set_rest: Setear rest pose
- skin: Configurar skinning
- attachment: Añadir BoneAttachment3D
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def skeleton(action: str, **kwargs) -> dict:
    """Tool centralizada para esqueletos."""
    session_manager = get_session_manager()
    
    actions_map = {
        "create": _action_create,
        "add_bone": _action_add_bone,
        "set_rest": _action_set_rest,
        "skin": _action_skin,
        "attachment": _action_attachment,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, **kwargs)
    except Exception as e:
        logger.error(f"Error en skeleton({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_create(session_manager, scene_path: str, parent_path: str = ".", skeleton_name: str = "Skeleton2D", is_3d: bool = False, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_skeleton", {
            "scene_path": scene_path,
            "parent_path": parent_path,
            "skeleton_name": skeleton_name,
            "is_3d": is_3d
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_add_bone(session_manager, scene_path: str, skeleton_path: str, bone_name: str, rest_transform: dict = None, length: float = 32.0, bone_angle: float = 0.0, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_bone", {
            "scene_path": scene_path,
            "skeleton_path": skeleton_path,
            "bone_name": bone_name,
            "rest_transform": rest_transform or {},
            "length": length,
            "bone_angle": bone_angle
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_set_rest(session_manager, scene_path: str, skeleton_path: str, bone_name: str, rest_transform: dict, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("set_bone_rest", {
            "scene_path": scene_path,
            "skeleton_path": skeleton_path,
            "bone_name": bone_name,
            "rest_transform": rest_transform
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_skin(session_manager, scene_path: str, polygon_path: str, skeleton_path: str, bone_weights: dict = None, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("skin_polygon2d", {
            "scene_path": scene_path,
            "polygon_path": polygon_path,
            "skeleton_path": skeleton_path,
            "bone_weights": bone_weights or {}
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_attachment(session_manager, scene_path: str, skeleton_path: str, bone_name: str, attachment_name: str = "Attachment", **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_bone_attachment", {
            "scene_path": scene_path,
            "skeleton_path": skeleton_path,
            "bone_name": bone_name,
            "attachment_name": attachment_name
        })
    return {"success": False, "error": "Daemon no disponible"}
