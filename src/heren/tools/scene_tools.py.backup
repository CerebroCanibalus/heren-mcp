"""
Heren MCP - Scene Tools (Capa 2)

Tools MCP para operaciones de escenas.
Expone funciones que los agentes pueden llamar directamente.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import logging
from typing import Optional

from heren.core.session_manager import get_session_manager
from heren.interfaces.godot_cli import create_interface

logger = logging.getLogger(__name__)


def _execute_operation(session_id: str, operation: str, params: dict) -> dict:
    """
    Ejecuta una operaci�n usando GodotDaemon si est� disponible,
    luego GodotServer, o fallback a scripts temporales.
    """
    session_manager = get_session_manager()
    
    # 1. Intentar GodotDaemon primero (WebSocket - m�s r�pido)
    daemon = session_manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = session_manager.execute_via_daemon(session_id, operation, params)
            if result.get("success") or "error" not in result:
                return result
            logger.warning(f"[Daemon] Operaci�n {operation} retorn� error: {result.get('error')}")
        except Exception as e:
            logger.warning(f"[Daemon] Error en {operation}: {e}")
    
    # 2. Intentar GodotServer (HTTP legacy)
    server = session_manager.get_godot_server(session_id)
    if server:
        try:
            return server.execute(operation, params)
        except Exception as e:
            logger.warning(f"GodotServer fall�: {e}. Usando fallback.")
    
    # Fallback a scripts temporales
    interface = create_interface(session_id)
    
    # Mapear operaci�n a m�todo de GodotInterface
    method_map = {
        "get_scene_tree": lambda: interface.get_scene_tree(params.get("scene_path", "")),
        "save_scene": lambda: interface.save_scene(params.get("scene_path", "")),
        "add_node": lambda: interface.add_node(
            params.get("scene_path", ""),
            params.get("parent_path", ""),
            params.get("node_type", ""),
            params.get("node_name", ""),
            params.get("properties")
        ),
        "remove_node": lambda: interface.remove_node(
            params.get("scene_path", ""),
            params.get("node_path", "")
        ),
        "set_property": lambda: interface.set_property(
            params.get("scene_path", ""),
            params.get("node_path", ""),
            params.get("property_name", ""),
            params.get("value")
        ),
        "get_node_properties": lambda: interface.get_node_properties(
            params.get("scene_path", ""),
            params.get("node_path", "")
        ),
    }
    
    method = method_map.get(operation)
    if not method:
        return {"success": False, "error": f"Operaci�n no soportada en fallback: {operation}"}
    
    return method()


def heren_start_session(
    project_path: str,
    godot_path: Optional[str] = None,
    use_daemon: bool = True,
) -> dict:
    """
    Inicia una sesión con Godot.
    
    Args:
        project_path: Ruta absoluta al proyecto Godot
        godot_path: Ruta al ejecutable de Godot (opcional)
        use_daemon: Si True, inicia GodotDaemon WebSocket (recomendado)
    
    Returns:
        {"success": True, "session_id": "..."} o {"success": False, "error": "..."}
    """
    try:
        manager = get_session_manager()
        session = manager.start_session(project_path, godot_path, use_daemon=use_daemon)
        
        return {
            "success": True,
            "session_id": session.id,
            "project_path": session.project_path,
        }
    except Exception as e:
        logger.error(f"Error iniciando sesión: {e}")
        return {"success": False, "error": str(e)}


def heren_end_session(session_id: str, save: bool = True) -> dict:
    """
    Termina una sesión.
    
    Args:
        session_id: ID de la sesión
        save: Si True, guarda cambios pendientes
    
    Returns:
        {"success": True} o {"success": False, "error": "..."}
    """
    try:
        manager = get_session_manager()
        
        # TODO: Guardar cambios pendientes si save=True
        
        success = manager.end_session(session_id)
        return {"success": success}
    except Exception as e:
        logger.error(f"Error cerrando sesión: {e}")
        return {"success": False, "error": str(e)}


def heren_get_scene_tree(session_id: str, scene_path: str) -> dict:
    """
    Obtiene el árbol de nodos de una escena.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena (res:// o absoluta)
    
    Returns:
        Estructura JSON del árbol de nodos
    """
    return _execute_operation(session_id, "get_scene_tree", {"scene_path": scene_path})


def heren_save_scene(session_id: str, scene_path: str) -> dict:
    """
    Guarda una escena.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
    
    Returns:
        {"success": True} o error
    """
    return _execute_operation(session_id, "save_scene", {"scene_path": scene_path})


def heren_get_project_info(session_id: str) -> dict:
    """
    Obtiene información del proyecto.
    
    Args:
        session_id: ID de sesión activa
    
    Returns:
        Información del proyecto (nombre, main_scene, etc.)
    """
    interface = create_interface(session_id)
    return interface.get_project_info()
