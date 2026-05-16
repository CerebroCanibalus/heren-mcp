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
- array_append: Añade elemento a array
- array_remove: Remueve elemento de array
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
    index: int = -1,
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
            - "array_append": Añade elemento a array property
            - "array_remove": Remueve elemento de array property
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        node_path: Ruta al nodo (ej: "Player/Sprite2D")
        node_type: (para add) Tipo de nodo (Sprite2D, Node, etc.)
        node_name: (para add) Nombre del nuevo nodo
        properties: (para add) Propiedades iniciales
        property_name: (para set_prop/get_prop/array_*) Nombre de propiedad
        value: (para set_prop/array_append/array_remove) Nuevo valor
        new_name: (para rename) Nuevo nombre
        new_parent: (para move) Nueva ruta padre
        index: (para array_remove) Índice del elemento a remover
    
    Returns:
        Según el action:
        - add: {"success": True, "node_path": "..."}
        - remove: {"success": True}
        - set_prop: {"success": True}
        - get_prop: {"success": True, "value": ...}
        - duplicate: {"success": True, "node_path": "..."}
        - rename: {"success": True}
        - move: {"success": True}
        - array_append: {"success": True, "array_size": N}
        - array_remove: {"success": True, "removed_value": ...}
    
    Examples:
        # Añadir nodo
        node_tool("add", session_id="abc", scene_path="res://Player.tscn",
                  parent_path=".", node_type="Sprite2D", node_name="Hat")
        
        # Cambiar propiedad
        node_tool("set_prop", session_id="abc", scene_path="res://Player.tscn",
                  node_path="Player", property_name="position", value={"x": 100, "y": 200})
        
        # Añadir a array
        node_tool("array_append", session_id="abc", scene_path="res://Player.tscn",
                  node_path="Player", property_name="inventory", value="sword")
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
    
    elif action == "array_append":
        return _action_array_append(manager, session_id, scene_path, node_path, property_name, value)
    
    elif action == "array_remove":
        return _action_array_remove(manager, session_id, scene_path, node_path, property_name, value, index)
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: add, remove, set_prop, get_prop, duplicate, rename, move, array_append, array_remove"
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
            "property": property_name,
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


def _action_array_append(manager, session_id: str, scene_path: str, node_path: str,
                         property_name: str, value: Any) -> dict:
    """Añade elemento a array property."""
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='array_append'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "array_append",
        {
            "scene_path": scene_path,
            "node_path": node_path,
            "property_name": property_name,
            "value": value
        }
    )


def _action_array_remove(manager, session_id: str, scene_path: str, node_path: str,
                         property_name: str, value: Any, index: int) -> dict:
    """Remueve elemento de array property."""
    if not all([scene_path, node_path, property_name]):
        return {
            "success": False,
            "error": "scene_path, node_path y property_name requeridos para action='array_remove'"
        }
    
    params = {
        "scene_path": scene_path,
        "node_path": node_path,
        "property_name": property_name
    }
    
    if index >= 0:
        params["index"] = index
    elif value is not None:
        params["value"] = value
    else:
        return {
            "success": False,
            "error": "index o value requerido para action='array_remove'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "array_remove", params
    )


def _execute_via_daemon_or_fallback(manager, session_id: str, operation: str, params: dict) -> dict:
    """Ejecuta via daemon si está disponible, sino fallback a scripts."""
    # Intentar daemon PRIMERO (rápido ~20ms)
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, operation, params)
            # B8 FIX: Aceptar respuesta del daemon si:
            # 1. success=true, O
            # 2. Contiene datos relevantes (properties, value, etc.) aunque no tenga "success"
            # No caer al fallback si el daemon devolvió datos útiles
            has_success = result.get("success") == True
            has_data = "properties" in result or "value" in result or "node_type" in result
            has_error = "error" in result and result.get("error") != ""
            
            if has_success or (has_data and not has_error):
                logger.debug(f"[NodeTool] Daemon: {operation} en ~20ms")
                return result
            # B5 FIX: Si hay error explícito del daemon, retornar el error directamente
            # No caer al fallback - el daemon ya dio el mejor error posible
            elif has_error:
                daemon_error = result.get("error", "")
                logger.debug(f"[NodeTool] Daemon error, retornando directamente: {daemon_error}")
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
            # Compatibilidad: aceptar "property" o "property_name"
            prop_name = params.get("property_name") or params.get("property", "")
            return interface.set_property(
                params["scene_path"],
                params["node_path"],
                prop_name,
                params["value"]
            )
        elif operation == "get_node_properties":
            # B8 FIX: Implementar get_node_properties en fallback
            return interface.get_node_properties(
                params["scene_path"],
                params["node_path"]
            )
        elif operation == "array_append":
            return interface.array_append(
                params["scene_path"],
                params["node_path"],
                params["property_name"],
                params["value"]
            )
        elif operation == "array_remove":
            return interface.array_remove(
                params["scene_path"],
                params["node_path"],
                params["property_name"],
                params.get("index", -1),
                params.get("value")
            )
        elif operation == "duplicate_node":
            return interface.duplicate_node(
                params["scene_path"],
                params["node_path"]
            )
        elif operation == "rename_node":
            return interface.rename_node(
                params["scene_path"],
                params["node_path"],
                params.get("new_name", "")
            )
        elif operation == "move_node":
            return interface.move_node(
                params["scene_path"],
                params["node_path"],
                params.get("new_parent", "")
            )
        else:
            return {"success": False, "error": f"Operación no soportada en fallback: {operation}"}
            
    except Exception as e:
        logger.error(f"[NodeTool] Fallback falló: {e}")
        return {"success": False, "error": str(e)}
