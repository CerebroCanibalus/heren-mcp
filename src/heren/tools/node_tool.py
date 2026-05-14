"""
Heren MCP - Node Tool (Centralizada)

Una sola tool para TODAS las operaciones de nodos.
Filosofía: Centralizada. Modular. Potente.

Modos:
- add: Añade nodo
- remove: Elimina nodo
- set_prop: Cambia propiedad
- get_prop: Obtiene propiedad
- duplicate: Duplica nodo
- rename: Renombra nodo
- move: Mueve nodo en el árbol
"""

import logging
from typing import Optional, Any

from heren.core.session_manager import get_session_manager
from heren.interfaces.godot_cli import create_interface

logger = logging.getLogger(__name__)


def node_tool(
    action: str,
    session_id: str,
    scene_path: str,
    node_path: str = None,
    node_type: str = None,
    node_name: str = None,
    properties: dict = None,
    property_name: str = None,
    value: Any = None,
    new_name: str = None,
    new_parent: str = None,
    **kwargs,
) -> dict:
    """
    Tool centralizada para operaciones de nodos.
    
    Args:
        action: Operación a realizar
            - "add": Añade nodo a la escena
            - "remove": Elimina nodo
            - "set_prop": Cambia propiedad de nodo
            - "get_prop": Obtiene propiedad de nodo
            - "duplicate": Duplica nodo
            - "rename": Renombra nodo
            - "move": Mueve nodo a otro padre
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo (ej: "Player/Sprite2D")
        node_type: (para add) Tipo de nodo (Sprite2D, Node, etc.)
        node_name: (para add) Nombre del nuevo nodo
        properties: (para add) Propiedades iniciales
        property_name: (para set_prop/get_prop) Nombre de propiedad
        value: (para set_prop) Nuevo valor
        new_name: (para rename) Nuevo nombre
        new_parent: (para move) Nueva ruta padre
    
    Returns:
        Según el action:
        - add: {"success": True, "node_path": "..."}
        - remove: {"success": True}
        - set_prop: {"success": True}
        - get_prop: {"success": True, "value": ...}
        - duplicate: {"success": True, "node_path": "..."}
        - rename: {"success": True}
        - move: {"success": True}
    
    Examples:
        # Añadir nodo
        node_tool("add", session_id="abc", scene_path="res://Player.tscn",
                  parent_path=".", node_type="Sprite2D", node_name="Hat")
        
        # Cambiar propiedad
        node_tool("set_prop", session_id="abc", scene_path="res://Player.tscn",
                  node_path="Player", property_name="position", value={"x": 100, "y": 200})
    """
    
    manager = get_session_manager()
    
    # Validar sesión
    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesión no encontrada: {session_id}"}
    
    if action == "add":
        return _action_add(manager, session_id, scene_path, node_path, node_type, node_name, properties)
    
    elif action == "remove":
        return _action_remove(manager, session_id, scene_path, node_path)
    
    elif action == "set_prop":
        return _action_set_prop(manager, session_id, scene_path, node_path, property_name, value)
    
    elif action == "get_prop":
        return _action_get_prop(manager, session_id, scene_path, node_path, property_name)
    
    elif action == "duplicate":
        return _action_duplicate(manager, session_id, scene_path, node_path)
    
    elif action == "rename":
        return _action_rename(manager, session_id, scene_path, node_path, new_name)
    
    elif action == "move":
        return _action_move(manager, session_id, scene_path, node_path, new_parent)
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: add, remove, set_prop, get_prop, duplicate, rename, move"
        }


def _action_add(manager, session_id: str, scene_path: str, parent_path: str,
                node_type: str, node_name: str, properties: dict) -> dict:
    """Añade nodo a la escena."""
    if not all([scene_path, parent_path, node_type, node_name]):
        return {
            "success": False,
            "error": "scene_path, parent_path, node_type y node_name requeridos para action='add'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "add_node",
        {
            "scene_path": scene_path,
            "parent_path": parent_path,
            "node_type": node_type,
            "node_name": node_name,
            "properties": properties or {}
        }
    )


def _action_remove(manager, session_id: str, scene_path: str, node_path: str) -> dict:
    """Elimina nodo."""
    if not all([scene_path, node_path]):
        return {
            "success": False,
            "error": "scene_path y node_path requeridos para action='remove'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "remove_node",
        {"scene_path": scene_path, "node_path": node_path}
    )


def _action_set_prop(manager, session_id: str, scene_path: str, node_path: str,
                     property_name: str, value: Any) -> dict:
    """Cambia propiedad de nodo."""
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='set_prop'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "set_property",
        {
            "scene_path": scene_path,
            "node_path": node_path,
            "property_name": property_name,
            "value": value
        }
    )


def _action_get_prop(manager, session_id: str, scene_path: str, node_path: str,
                     property_name: str) -> dict:
    """Obtiene propiedad de nodo."""
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='get_prop'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "get_node_properties",
        {"scene_path": scene_path, "node_path": node_path}
    )


def _action_duplicate(manager, session_id: str, scene_path: str, node_path: str) -> dict:
    """Duplica nodo."""
    if not all([scene_path, node_path]):
        return {
            "success": False,
            "error": "scene_path y node_path requeridos para action='duplicate'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "duplicate_node",
        {"scene_path": scene_path, "node_path": node_path}
    )


def _action_rename(manager, session_id: str, scene_path: str, node_path: str,
                   new_name: str) -> dict:
    """Renombra nodo."""
    if not all([scene_path, node_path, new_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y new_name requeridos para action='rename'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "rename_node",
        {"scene_path": scene_path, "node_path": node_path, "new_name": new_name}
    )


def _action_move(manager, session_id: str, scene_path: str, node_path: str,
                 new_parent: str) -> dict:
    """Mueve nodo a otro padre."""
    if not all([scene_path, node_path, new_parent]):
        return {
            "success": False,
            "error": "scene_path, node_path y new_parent requeridos para action='move'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "move_node",
        {"scene_path": scene_path, "node_path": node_path, "new_parent": new_parent}
    )


def _execute_via_daemon_or_fallback(manager, session_id: str, operation: str, params: dict) -> dict:
    """Ejecuta via daemon si está disponible, sino fallback a scripts."""
    # Intentar daemon PRIMERO (rápido ~20ms)
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, operation, params)
            if result.get("success") or "error" not in result:
                logger.debug(f"[NodeTool] Daemon: {operation} en ~20ms")
                return result
        except Exception as e:
            logger.warning(f"[NodeTool] Daemon falló: {e}")
    
    # Fallback a scripts temporales (lento ~370ms)
    try:
        interface = create_interface(session_id)
        
        if operation == "add_node":
            return interface.add_node(
                params["scene_path"],
                params["parent_path"],
                params["node_type"],
                params["node_name"],
                params.get("properties")
            )
        elif operation == "remove_node":
            return interface.remove_node(params["scene_path"], params["node_path"])
        elif operation == "set_property":
            return interface.set_property(
                params["scene_path"],
                params["node_path"],
                params["property_name"],
                params["value"]
            )
        else:
            return {"success": False, "error": f"Operación no soportada en fallback: {operation}"}
            
    except Exception as e:
        logger.error(f"[NodeTool] Fallback falló: {e}")
        return {"success": False, "error": str(e)}
