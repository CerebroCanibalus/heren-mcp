"""
Heren MCP Server

Servidor MCP usando FastMCP para OpenCode.
Expone las tools de Heren Godot MCP.

Filosofia: Poder. Eficiencia. Rapidez.
"""

import argparse
import logging
import sys

from typing import Any, Optional

from fastmcp import FastMCP

from heren.core.session_manager import get_session_manager
from heren.tools.scene_tools import heren_start_session, heren_end_session, heren_get_scene_tree, heren_save_scene
from heren.tools.node_tools import heren_add_node, heren_remove_node, heren_set_property
from heren.tools.batch_tools import heren_batch
from heren.tools.visual_tools import (
    heren_screenshot,
    heren_capture_viewport,
    heren_performance_metrics,
    heren_daemon_health,
    heren_load_scene,
    heren_unload_scene,
    heren_get_loaded_scenes,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# Crear servidor MCP
mcp = FastMCP("heren-godot")


@mcp.tool()
def start_session(project_path: str) -> dict:
    """
    Inicia una sesion con Godot.
    
    Args:
        project_path: Ruta absoluta al proyecto Godot
    
    Returns:
        {"success": True, "session_id": "..."} o error
    """
    return heren_start_session(project_path)


@mcp.tool()
def end_session(session_id: str) -> dict:
    """
    Termina una sesion.
    
    Args:
        session_id: ID de la sesion
    
    Returns:
        {"success": True} o error
    """
    return heren_end_session(session_id)


@mcp.tool()
def get_scene_tree(session_id: str, scene_path: str) -> dict:
    """
    Obtiene el arbol de nodos de una escena.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena (res:// o absoluta)
    
    Returns:
        Estructura JSON del arbol de nodos
    """
    return heren_get_scene_tree(session_id, scene_path)


@mcp.tool()
def save_scene(session_id: str, scene_path: str) -> dict:
    """
    Guarda una escena.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena
    
    Returns:
        {"success": True} o error
    """
    return heren_save_scene(session_id, scene_path)


@mcp.tool()
def add_node(
    session_id: str,
    scene_path: str,
    parent_path: str,
    node_type: str,
    node_name: str,
    properties: dict = None,
) -> dict:
    """
    Anade un nodo a una escena.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena
        parent_path: Ruta al nodo padre ("." para root)
        node_type: Tipo de nodo (Sprite2D, Node, etc.)
        node_name: Nombre del nuevo nodo
        properties: Propiedades iniciales
    
    Returns:
        {"success": True, "node_path": "..."} o error
    """
    return heren_add_node(session_id, scene_path, parent_path, node_type, node_name, properties)


@mcp.tool()
def remove_node(session_id: str, scene_path: str, node_path: str) -> dict:
    """
    Elimina un nodo de una escena.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo a eliminar
    
    Returns:
        {"success": True} o error
    """
    return heren_remove_node(session_id, scene_path, node_path)


@mcp.tool()
def set_property(
    session_id: str,
    scene_path: str,
    node_path: str,
    property_name: str,
    value: Any,
) -> dict:
    """
    Cambia una propiedad de un nodo.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo
        property_name: Nombre de la propiedad
        value: Nuevo valor
    
    Returns:
        {"success": True} o error
    """
    return heren_set_property(session_id, scene_path, node_path, property_name, value)


@mcp.tool()
def batch(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta múltiples operaciones en batch.
    
    Optimiza rendimiento ejecutando varias operaciones en una sola llamada.
    
    Args:
        session_id: ID de sesion activa
        operations: Lista de operaciones
            Cada operacion es un dict con:
            - "operation": str - Nombre de la operacion
            - "params": dict - Parametros de la operacion
        stop_on_error: Si True, detiene en el primer error
    
    Returns:
        {
            "success": bool,
            "results": list[dict],
            "errors": list[dict],
            "success_count": int,
            "error_count": int,
        }
    
    Example:
        batch(session_id, [
            {"operation": "add_node", "params": {"scene_path": "...", "parent_path": ".", "node_type": "Sprite2D", "node_name": "Player"}},
            {"operation": "set_property", "params": {"scene_path": "...", "node_path": "Player", "property_name": "position", "value": {"x": 100, "y": 200}}},
            {"operation": "save_scene", "params": {"scene_path": "..."}},
        ])
    """
    return heren_batch(session_id, operations, stop_on_error)


# ============================================================
# VISUAL TOOLS (Requieren GodotDaemon)
# ============================================================

@mcp.tool()
def screenshot(
    session_id: str,
    scene_path: str,
    output_path: str = None,
    resolution: tuple = (1920, 1080),
    wait_frames: int = 3,
    format: str = "png",
    quality: float = 0.9,
) -> dict:
    """
    Captura un screenshot de una escena usando rendering GPU.
    
    REQUIERE GodotDaemon activo. Si no lo tienes, inicia sesion con use_daemon=True.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena (res://scenes/Main.tscn)
        output_path: Ruta de salida. None = temp directory
        resolution: (width, height)
        wait_frames: Frames a esperar antes de capturar
        format: "png", "jpeg" o "webp"
        quality: Calidad JPEG/WebP (0.0-1.0)
    
    Returns:
        {"success": True, "image_path": "...", "resolution": [1920, 1080]}
    """
    return heren_screenshot(session_id, scene_path, output_path, resolution, wait_frames, format, quality)


@mcp.tool()
def capture_viewport(
    session_id: str,
    output_path: str = None,
    format: str = "png",
    quality: float = 0.9,
) -> dict:
    """
    Captura el viewport actual del daemon Godot.
    
    Muestra lo que el daemon "ve" en su ventana en tiempo real.
    
    Args:
        session_id: ID de sesion activa
        output_path: Ruta de salida. None = temp directory
        format: "png", "jpeg" o "webp"
        quality: Calidad JPEG/WebP
    
    Returns:
        {"success": True, "image_path": "...", "resolution": [1920, 1080]}
    """
    return heren_capture_viewport(session_id, output_path, format, quality)


@mcp.tool()
def performance_metrics(session_id: str) -> dict:
    """
    Obtiene metricas de rendimiento en tiempo real del daemon.
    
    Args:
        session_id: ID de sesion activa
    
    Returns:
        {"success": True, "metrics": {"fps": 60, "memory_mb": 150, ...}}
    """
    return heren_performance_metrics(session_id)


@mcp.tool()
def daemon_health(session_id: str) -> dict:
    """
    Verifica la salud del daemon Godot.
    
    Args:
        session_id: ID de sesion activa
    
    Returns:
        {"success": True, "status": "healthy", "scenes_cached": 5, ...}
    """
    return heren_daemon_health(session_id)


@mcp.tool()
def load_scene(session_id: str, scene_path: str) -> dict:
    """
    Carga una escena en el cache del daemon para operaciones rapidas.
    
    Una vez cargada, get_scene_tree y modificaciones son ~20ms.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena (res://scenes/Player.tscn)
    
    Returns:
        {"success": True, "cached": true, "node_count": 42}
    """
    return heren_load_scene(session_id, scene_path)


@mcp.tool()
def unload_scene(session_id: str, scene_path: str) -> dict:
    """
    Descarga una escena del cache del daemon.
    
    Args:
        session_id: ID de sesion activa
        scene_path: Ruta a la escena
    
    Returns:
        {"success": True}
    """
    return heren_unload_scene(session_id, scene_path)


@mcp.tool()
def get_loaded_scenes(session_id: str) -> dict:
    """
    Lista las escenas cargadas en el cache del daemon.
    
    Args:
        session_id: ID de sesion activa
    
    Returns:
        {"success": True, "scenes": [{"path": "...", "type": "Node2D", "valid": true}]}
    """
    return heren_get_loaded_scenes(session_id)


def main():
    parser = argparse.ArgumentParser(description="Heren Godot MCP Server")
    parser.add_argument("--project-path", help="Ruta al proyecto Godot (opcional)")
    
    args = parser.parse_args()
    
    logger.info("HEREN MCP Server iniciando...")
    
    if args.project_path:
        result = heren_start_session(args.project_path)
        if result.get("success"):
            logger.info(f"Sesion iniciada: {result['session_id']}")
        else:
            logger.error(f"Error iniciando sesion: {result.get('error')}")
    
    # Iniciar servidor MCP
    mcp.run()


if __name__ == "__main__":
    main()
