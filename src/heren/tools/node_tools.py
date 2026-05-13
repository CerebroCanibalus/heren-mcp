"""
Heren MCP - Node Tools (Capa 2)

Tools MCP para operaciones de nodos.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import logging
from typing import Any, Optional

from heren.interfaces.godot_cli import create_interface

logger = logging.getLogger(__name__)


def heren_add_node(
    session_id: str,
    scene_path: str,
    parent_path: str,
    node_type: str,
    node_name: str,
    properties: dict = None,
) -> dict:
    """
    Añade un nodo a una escena.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        parent_path: Ruta al nodo padre ("." para root)
        node_type: Tipo de nodo (Sprite2D, Node, etc.)
        node_name: Nombre del nuevo nodo
        properties: Propiedades iniciales
    
    Returns:
        {"success": True, "node_path": "..."} o error
    """
    interface = create_interface(session_id)
    return interface.add_node(scene_path, parent_path, node_type, node_name, properties)


def heren_remove_node(session_id: str, scene_path: str, node_path: str) -> dict:
    """
    Elimina un nodo de una escena.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo a eliminar
    
    Returns:
        {"success": True} o error
    """
    interface = create_interface(session_id)
    return interface.remove_node(scene_path, node_path)


def heren_set_property(
    session_id: str,
    scene_path: str,
    node_path: str,
    property_name: str,
    value: Any,
) -> dict:
    """
    Cambia una propiedad de un nodo.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo
        property_name: Nombre de la propiedad
        value: Nuevo valor
    
    Returns:
        {"success": True} o error
    """
    interface = create_interface(session_id)
    return interface.set_property(scene_path, node_path, property_name, value)


def heren_get_node_properties(session_id: str, scene_path: str, node_path: str) -> dict:
    """
    Obtiene todas las propiedades editables de un nodo.
    
    Args:
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo
    
    Returns:
        {"success": True, "properties": {...}} o error
    """
    interface = create_interface(session_id)
    return interface.get_node_properties(scene_path, node_path)
