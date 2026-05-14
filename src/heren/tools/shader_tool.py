"""
Shader Tool - Gestión centralizada de shaders.

Actions:
- create: Crear .gdshader
- edit: Editar código
- validate: Validar compilación
- material: Crear ShaderMaterial
- uniform: Setear uniform
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def shader(action: str, **kwargs) -> dict:
    """Tool centralizada para shaders."""
    session_manager = get_session_manager()
    
    actions_map = {
        "create": _action_create,
        "edit": _action_edit,
        "validate": _action_validate,
        "material": _action_material,
        "uniform": _action_uniform,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, **kwargs)
    except Exception as e:
        logger.error(f"Error en shader({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_create(session_manager, shader_path: str, shader_type: str = "canvas_item", code: str = "", **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_shader", {
            "shader_path": shader_path,
            "shader_type": shader_type,
            "code": code
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_edit(session_manager, shader_path: str, code: str, append: bool = False, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("edit_shader", {
            "shader_path": shader_path,
            "code": code,
            "append": append
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_validate(session_manager, shader_path: str, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("validate_shader", {"shader_path": shader_path})
    return {"success": False, "error": "Daemon no disponible"}


def _action_material(session_manager, scene_path: str, node_path: str, shader_path: str = "", material_name: str = "", uniforms: dict = None, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_shader_material", {
            "scene_path": scene_path,
            "node_path": node_path,
            "shader_path": shader_path,
            "material_name": material_name,
            "uniforms": uniforms or {}
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_uniform(session_manager, scene_path: str, node_path: str, uniform_name: str, value, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("set_shader_uniform", {
            "scene_path": scene_path,
            "node_path": node_path,
            "uniform_name": uniform_name,
            "value": value
        })
    return {"success": False, "error": "Daemon no disponible"}
