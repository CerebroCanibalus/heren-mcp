"""
Heren MCP - Scene Tool (Centralizada)

Una sola tool para TODAS las operaciones de escenas.
Filosofía: Centralizada. Modular. Potente.

Modos:
- get_tree: Obtiene árbol de nodos
- save: Guarda escena
- load: Carga en cache del daemon
- unload: Descarga del cache
- list_loaded: Lista escenas cargadas
- create: Crea nueva escena
- set_editable_paths: Marca paths como editables
"""

import logging
from typing import Optional

from heren.core.session_manager import get_session_manager
from heren.interfaces.godot_cli import create_interface

logger = logging.getLogger(__name__)


def scene_tool(
    action: str,
    session_id: str,
    scene_path: str = None,
    output_path: str = None,
    resolution: tuple = (1920, 1080),
    wait_frames: int = 3,
    format: str = "png",
    quality: float = 0.9,
    **kwargs,
) -> dict:
    """
    Tool centralizada para operaciones de escenas.
    
    Args:
        action: Operación a realizar
            - "get_tree": Obtiene árbol de nodos
            - "save": Guarda escena
            - "load": Carga escena en cache del daemon
            - "unload": Descarga escena del cache
            - "list_loaded": Lista escenas cargadas
            - "screenshot": Captura screenshot (requiere daemon)
        session_id: ID de sesión activa
        scene_path: Ruta a la escena (res:// o absoluta)
        output_path: (para screenshot) Ruta de salida
        resolution: (para screenshot) Resolución
        wait_frames: (para screenshot) Frames a esperar
        format: (para screenshot) "png", "jpeg" o "webp"
        quality: (para screenshot) Calidad 0.0-1.0
    
    Returns:
        Según el action:
        - get_tree: {"success": True, "tree": {...}}
        - save: {"success": True}
        - load: {"success": True, "cached": True, "node_count": 42}
        - unload: {"success": True}
        - list_loaded: {"success": True, "scenes": [...]}
        - screenshot: {"success": True, "image_path": "...", "resolution": [...]}
    
    Examples:
        # Obtener árbol
        scene_tool("get_tree", session_id="abc", scene_path="res://Player.tscn")
        
        # Guardar
        scene_tool("save", session_id="abc", scene_path="res://Player.tscn")
        
        # Cargar en cache
        scene_tool("load", session_id="abc", scene_path="res://Player.tscn")
        
        # Screenshot
        scene_tool("screenshot", session_id="abc", scene_path="res://Player.tscn")
    """
    
    manager = get_session_manager()
    
    # Validar sesión
    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesión no encontrada: {session_id}"}
    
    # Validaciones específicas por acción
    if action in ["get_tree", "save", "load", "unload", "screenshot", "create", "delete", "add_ext_resource", "set_editable_paths"]:
        if not scene_path:
            return {
                "success": False,
                "error": "missing_scene_path",
                "message": f"action='{action}' requiere scene_path"
            }
    
    if action == "get_tree":
        return _execute_via_daemon_or_fallback(
            manager, session_id, "get_scene_tree", {"scene_path": scene_path}
        )
    
    elif action == "save":
        return _execute_via_daemon_or_fallback(
            manager, session_id, "save_scene", {"scene_path": scene_path}
        )
    
    elif action == "load":
        return _action_load(manager, session_id, scene_path)
    
    elif action == "unload":
        return _action_unload(manager, session_id, scene_path)
    
    elif action == "list_loaded":
        return _action_list_loaded(manager, session_id)
    
    elif action == "screenshot":
        return _action_screenshot(
            manager, session_id, scene_path, output_path, 
            resolution, wait_frames, format, quality
        )
    
    elif action == "create":
        return _execute_via_daemon_or_fallback(
            manager, session_id, "create_scene", {
                "scene_path": scene_path,
                "root_type": kwargs.get("root_type", "Node2D"),
                "root_name": kwargs.get("root_name", "Root")
            }
        )
    
    elif action == "delete":
        return _execute_via_daemon_or_fallback(
            manager, session_id, "delete_scene", {"scene_path": scene_path}
        )
    
    elif action == "rename":
        if not scene_path or not kwargs.get("new_path"):
            return {
                "success": False,
                "error": "missing_params",
                "message": "action='rename' requiere scene_path y new_path"
            }
        return _execute_via_daemon_or_fallback(
            manager, session_id, "rename_scene", {
                "scene_path": scene_path,
                "new_path": kwargs.get("new_path", "")
            }
        )
    
    elif action == "add_ext_resource":
        if not kwargs.get("resource_path"):
            return {
                "success": False,
                "error": "missing_resource_path",
                "message": "action='add_ext_resource' requiere resource_path"
            }
        return _execute_via_daemon_or_fallback(
            manager, session_id, "add_ext_resource", {
                "scene_path": scene_path,
                "resource_path": kwargs.get("resource_path", ""),
                "resource_type": kwargs.get("resource_type", "Script")
            }
        )
    
    elif action == "set_editable_paths":
        if not kwargs.get("paths"):
            return {
                "success": False,
                "error": "missing_paths",
                "message": "action='set_editable_paths' requiere paths (lista)"
            }
        return _execute_via_daemon_or_fallback(
            manager, session_id, "set_editable_paths", {
                "scene_path": scene_path,
                "paths": kwargs.get("paths", []),
                "editable": kwargs.get("editable", True)
            }
        )
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, add_ext_resource, set_editable_paths"
        }


def _execute_via_daemon_or_fallback(manager, session_id: str, operation: str, params: dict) -> dict:
    """Ejecuta via daemon si está disponible, sino fallback a scripts."""
    # Intentar daemon primero
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, operation, params)
            if result.get("success") or "error" not in result:
                return result
        except Exception as e:
            logger.warning(f"[SceneTool] Daemon falló: {e}")
    
    # Fallback a scripts temporales
    try:
        interface = create_interface(session_id)
        
        if operation == "get_scene_tree":
            return interface.get_scene_tree(params.get("scene_path", ""))
        elif operation == "save_scene":
            return interface.save_scene(params.get("scene_path", ""))
        elif operation == "create_scene":
            return interface.create_scene(
                params.get("scene_path", ""),
                params.get("root_type", "Node2D"),
                params.get("root_name", "Root")
            )
        elif operation == "delete_scene":
            return interface.delete_scene(params.get("scene_path", ""))
        elif operation == "rename_scene":
            return interface.rename_scene(
                params.get("scene_path", ""),
                params.get("new_path", "")
            )
        else:
            return {"success": False, "error": f"Operación no soportada en fallback: {operation}"}
            
    except Exception as e:
        logger.error(f"[SceneTool] Fallback falló: {e}")
        return {"success": False, "error": str(e)}


def _action_load(manager, session_id: str, scene_path: str) -> dict:
    """Carga escena en cache del daemon."""
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='load'"}
    
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Esta operación requiere GodotDaemon. Inicia sesión con use_daemon=True"
        }
    
    try:
        result = daemon.call("load_scene", {"scene_path": scene_path})
        return result
    except Exception as e:
        logger.error(f"[SceneTool] Error cargando escena: {e}")
        return {"success": False, "error": str(e)}


def _action_unload(manager, session_id: str, scene_path: str) -> dict:
    """Descarga escena del cache."""
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='unload'"}
    
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Esta operación requiere GodotDaemon"
        }
    
    try:
        result = daemon.call("unload_scene", {"scene_path": scene_path})
        return result
    except Exception as e:
        logger.error(f"[SceneTool] Error descargando escena: {e}")
        return {"success": False, "error": str(e)}


def _action_list_loaded(manager, session_id: str) -> dict:
    """Lista escenas cargadas en el daemon."""
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Esta operación requiere GodotDaemon"
        }
    
    try:
        result = daemon.call("get_loaded_scenes", {})
        return result
    except Exception as e:
        logger.error(f"[SceneTool] Error listando escenas: {e}")
        return {"success": False, "error": str(e)}


def _action_screenshot(
    manager, session_id: str, scene_path: str, output_path: str,
    resolution: tuple, wait_frames: int, format: str, quality: float
) -> dict:
    """Captura screenshot via daemon."""
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='screenshot'"}
    
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Screenshot requiere GodotDaemon con rendering GPU"
        }
    
    try:
        result = daemon.call("screenshot", {
            "scene_path": scene_path,
            "output_path": output_path,
            "resolution": resolution,
            "wait_frames": wait_frames,
            "format": format,
            "quality": quality
        })
        return result
    except Exception as e:
        logger.error(f"[SceneTool] Error en screenshot: {e}")
        return {"success": False, "error": str(e)}
