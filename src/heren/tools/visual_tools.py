"""
Heren MCP - Visual Tools (Capa 2)

Tools MCP para operaciones visuales y de rendering.
REQUIERE GodotDaemon (sin --headless) para funcionar.

Filosof�a: Poder. Eficiencia. Rapidez.
"""

import logging
import os
import tempfile
from typing import Optional, Tuple

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


VISUAL_ACCESS_WARNING = (
    "\u26a0\ufe0f  ATENCI�N AGENTE: No tienes acceso visual directo a la imagen generada. "
    "El archivo se guard� en disco pero NO fue transmitido a tu contexto. "
    "Si necesitas analizar contenido visual (colores, formas, disposici�n), "
    "DEBES pedirle al usuario que adjunte/pegue la imagen en el chat. "
    "NO intentes describir o inferir el contenido visual bas�ndote �nicamente en metadatos."
)


def _requires_daemon(session_id: str) -> tuple[bool, Optional[dict]]:
    """Verifica si el daemon est� disponible."""
    session_manager = get_session_manager()
    daemon = session_manager.get_godot_daemon(session_id)
    if not daemon:
        return False, {
            "success": False,
            "error": "daemon_required",
            "message": "Esta tool requiere GodotDaemon. Inicia la sesi�n con use_daemon=True. "
                      "Las tools visuales no funcionan con scripts temporales porque requieren rendering GPU.",
            "hint": "El daemon se inicia autom�ticamente por defecto (use_daemon=True). "
                    "Si no est� disponible, puede que Godot no se haya iniciado correctamente."
        }
    return True, None


def heren_screenshot(
    session_id: str,
    scene_path: str,
    output_path: Optional[str] = None,
    resolution: Tuple[int, int] = (1920, 1080),
    wait_frames: int = 3,
    format: str = "png",
    quality: float = 0.9,
) -> dict:
    """
    Captura un screenshot de una escena usando rendering GPU.
    
    REQUIERE: GodotDaemon activo (use_daemon=True en start_session)
    
    Args:
        session_id: ID de sesi�n activa
        scene_path: Ruta a la escena (ej: "res://scenes/Main.tscn")
        output_path: Ruta de salida. Si es None, usa temp directory
        resolution: (width, height) del screenshot
        wait_frames: Frames a esperar antes de capturar (para shaders/animaciones)
        format: "png", "jpeg" o "webp"
        quality: Calidad JPEG/WebP (0.0-1.0)
    
    Returns:
        Dict con success, image_path, resolution, file_size_bytes
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    if not output_path:
        ext = ".jpg" if format in ("jpeg", "jpg") else (".webp" if format == "webp" else ".png")
        output_path = os.path.join(tempfile.gettempdir(), f"heren_screenshot_{session_id}{ext}")
    
    session_manager = get_session_manager()
    result = session_manager.execute_via_daemon(session_id, "screenshot", {
        "scene_path": scene_path,
        "output_path": output_path.replace("\\", "/"),
        "resolution": list(resolution),
        "wait_frames": wait_frames,
        "format": format,
        "quality": quality
    })
    
    if result.get("success"):
        result["visual_access"] = False
        result["agent_note"] = VISUAL_ACCESS_WARNING
    
    return result


def heren_capture_viewport(
    session_id: str,
    output_path: Optional[str] = None,
    format: str = "png",
    quality: float = 0.9,
) -> dict:
    """
    Captura el viewport actual del daemon Godot.
    
    REQUIERE: GodotDaemon activo
    
    Args:
        session_id: ID de sesi�n activa
        output_path: Ruta de salida. Si es None, usa temp directory
        format: "png", "jpeg" o "webp"
        quality: Calidad JPEG/WebP (0.0-1.0)
    
    Returns:
        Dict con success, image_path, resolution
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    if not output_path:
        ext = ".jpg" if format in ("jpeg", "jpg") else (".webp" if format == "webp" else ".png")
        output_path = os.path.join(tempfile.gettempdir(), f"heren_viewport_{session_id}{ext}")
    
    session_manager = get_session_manager()
    result = session_manager.execute_via_daemon(session_id, "capture_viewport", {
        "output_path": output_path.replace("\\", "/"),
        "format": format,
        "quality": quality
    })
    
    if result.get("success"):
        result["visual_access"] = False
        result["agent_note"] = VISUAL_ACCESS_WARNING
    
    return result


def heren_performance_metrics(session_id: str) -> dict:
    """
    Obtiene m�tricas de rendimiento en tiempo real del daemon Godot.
    
    REQUIERE: GodotDaemon activo
    
    Args:
        session_id: ID de sesi�n activa
    
    Returns:
        Dict con success y m�tricas:
            - fps, frame_time, memory_static, memory_max
            - objects, nodes, orphan_nodes
            - draw_calls, vertices
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    session_manager = get_session_manager()
    return session_manager.execute_via_daemon(session_id, "performance_metrics", {})


def heren_daemon_health(session_id: str) -> dict:
    """
    Verifica la salud del daemon Godot.
    
    Args:
        session_id: ID de sesi�n activa
    
    Returns:
        Dict con status, uptime, memoria, peers conectados, escenas cacheadas
    """
    session_manager = get_session_manager()
    daemon = session_manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_not_running",
            "message": "No hay daemon activo para esta sesi�n"
        }
    
    return daemon.health()


def heren_load_scene(session_id: str, scene_path: str) -> dict:
    """
    Carga una escena en el cache del daemon para operaciones r�pidas.
    
    Una vez cargada, las operaciones sobre esa escena son ~20ms en vez de ~370ms.
    
    Args:
        session_id: ID de sesi�n activa
        scene_path: Ruta a la escena (ej: "res://scenes/Player.tscn")
    
    Returns:
        Dict con success, cached, node_count
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    session_manager = get_session_manager()
    return session_manager.execute_via_daemon(session_id, "load_scene", {
        "scene_path": scene_path
    })


def heren_unload_scene(session_id: str, scene_path: str) -> dict:
    """
    Descarga una escena del cache del daemon.
    
    Args:
        session_id: ID de sesi�n activa
        scene_path: Ruta a la escena
    
    Returns:
        Dict con success
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    session_manager = get_session_manager()
    return session_manager.execute_via_daemon(session_id, "unload_scene", {
        "scene_path": scene_path
    })


def heren_get_loaded_scenes(session_id: str) -> dict:
    """
    Lista las escenas actualmente cargadas en el cache del daemon.
    
    Args:
        session_id: ID de sesi�n activa
    
    Returns:
        Dict con success, scenes[] (path, type, valid)
    """
    has_daemon, error = _requires_daemon(session_id)
    if not has_daemon:
        return error
    
    session_manager = get_session_manager()
    return session_manager.execute_via_daemon(session_id, "get_loaded_scenes", {})
