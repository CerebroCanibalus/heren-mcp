"""
Resource Tool - Gestión centralizada de recursos Godot.

Actions:
- create: Crear archivo .tres
- read: Leer recurso
- update: Actualizar propiedades
- delete: Eliminar recurso
- list: Listar recursos del proyecto

Filosofía centralizada: Una tool para todo tipo de recurso.
"""

import logging
from typing import Any, Optional

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def resource(action: str, session_id: str = None, **kwargs) -> dict:
    """
    Tool centralizada para gestión de recursos.
    
    Args:
        action: "create", "read", "update", "delete", "list"
        session_id: ID de sesión activa (obligatorio)
        **kwargs: Parámetros específicos del action
        
    Returns:
        Dict con resultado de la operación
    """
    session_manager = get_session_manager()
    
    # Obtener sesión
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    actions_map = {
        "create": _action_create,
        "read": _action_read,
        "update": _action_update,
        "delete": _action_delete,
        "list": _action_list,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, session, **kwargs)
    except Exception as e:
        logger.error(f"Error en resource({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_create(session_manager, session, resource_path: str, resource_type: str = "Resource", properties: dict = None, **kwargs) -> dict:
    """Crear un nuevo recurso .tres"""
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_resource", {
            "resource_path": resource_path,
            "resource_type": resource_type,
            "properties": properties or {}
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_read(session_manager, session, resource_path: str, **kwargs) -> dict:
    """Leer un recurso .tres"""
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("read_resource", {"resource_path": resource_path})
    return {"success": False, "error": "Daemon no disponible"}


def _action_update(session_manager, session, resource_path: str, properties: dict, **kwargs) -> dict:
    """Actualizar propiedades de un recurso"""
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("update_resource", {
            "resource_path": resource_path,
            "properties": properties
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_delete(session_manager, session, resource_path: str, **kwargs) -> dict:
    """Eliminar un recurso"""
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("delete_resource", {"resource_path": resource_path})
    return {"success": False, "error": "Daemon no disponible"}


def _action_list(session_manager, session, directory: str = "res://", extension: str = "", recursive: bool = False, **kwargs) -> dict:
    """Listar recursos del proyecto"""
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("list_resources", {
            "directory": directory,
            "extension": extension,
            "recursive": recursive
        })
    return {"success": False, "error": "Daemon no disponible"}
