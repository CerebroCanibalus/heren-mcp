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


def heren_start_session(
    project_path: str,
    godot_path: Optional[str] = None,
) -> dict:
    """
    Inicia una sesión con Godot.
    
    Args:
        project_path: Ruta absoluta al proyecto Godot
        godot_path: Ruta al ejecutable de Godot (opcional)
    
    Returns:
        {"success": True, "session_id": "..."} o {"success": False, "error": "..."}
    """
    try:
        manager = get_session_manager()
        session = manager.start_session(project_path, godot_path)
        
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
    interface = create_interface(session_id)
    return interface.get_scene_tree(scene_path)


def heren_save_scene(session_id: str, scene_path: str) -> dict:
    """
    Guarda una escena.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
    
    Returns:
        {"success": True} o error
    """
    interface = create_interface(session_id)
    return interface.save_scene(scene_path)


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
