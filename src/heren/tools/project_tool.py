"""
Project Tool - Gestión centralizada de configuración del proyecto.

Actions:
- setting: Leer/escribir project setting
- autoload: Añadir/quitar autoload
- group: Gestión de grupos globales
- shader_global: Setear shader global
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def project(action: str, **kwargs) -> dict:
    """Tool centralizada para configuración del proyecto."""
    session_manager = get_session_manager()
    
    actions_map = {
        "setting": _action_setting,
        "autoload": _action_autoload,
        "remove_autoload": _action_remove_autoload,
        "shader_global": _action_shader_global,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, **kwargs)
    except Exception as e:
        logger.error(f"Error en project({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_setting(session_manager, setting_name: str = None, value = None, **kwargs) -> dict:
    """Leer o escribir un project setting."""
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if not daemon:
        return {"success": False, "error": "Daemon no disponible"}
    
    if value is not None:
        # Write
        return daemon.call("set_project_setting", {
            "setting_name": setting_name,
            "value": value
        })
    else:
        # Read
        return daemon.call("get_project_setting", {"setting_name": setting_name})


def _action_autoload(session_manager, autoload_name: str, script_path: str, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_autoload", {
            "autoload_name": autoload_name,
            "script_path": script_path
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_remove_autoload(session_manager, autoload_name: str, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("remove_autoload", {"autoload_name": autoload_name})
    return {"success": False, "error": "Daemon no disponible"}


def _action_shader_global(session_manager, global_name: str, value, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("set_shader_global", {
            "global_name": global_name,
            "value": value
        })
    return {"success": False, "error": "Daemon no disponible"}
