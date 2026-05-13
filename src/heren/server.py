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
