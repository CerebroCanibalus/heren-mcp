"""
Heren MCP - Signal Tool (Centralizada)

Tool para gestionar señales, conexiones y scripts de nodos.

Actions:
- connect: Conectar señal entre nodos
- disconnect: Desconectar señal
- list: Listar señales de un nodo
- set_script: Asignar script a un nodo
"""

import logging
from typing import Optional

from heren.core.session_manager import get_session_manager
from heren.interfaces.godot_cli import create_interface

logger = logging.getLogger(__name__)


def signal_tool(
    action: str,
    session_id: str,
    scene_path: str = "",
    from_node: str = "",
    signal_name: str = "",
    to_node: str = "",
    method: str = "",
    node_path: str = "",
    script_path: str = "",
    **kwargs,
) -> dict:
    """
    Tool centralizada para operaciones de señales y scripts.
    
    Actions:
        - "connect": Conecta una señal de un nodo a un método de otro nodo
        - "disconnect": Desconecta una señal previamente conectada
        - "list": Lista todas las señales de un nodo (conectadas y disponibles)
        - "set_script": Asigna un script GDScript a un nodo
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        from_node: Ruta del nodo emisor (para connect/disconnect/list)
        signal_name: Nombre de la señal (para connect/disconnect)
        to_node: Ruta del nodo receptor (para connect/disconnect)
        method: Nombre del método a llamar (para connect/disconnect)
        node_path: Ruta del nodo a modificar (para set_script)
        script_path: Ruta al script .gd (para set_script)
    
    Returns:
        Dict con resultado de la operación
    
    Examples:
        # Conectar señal
        signal_tool("connect", session_id="abc", scene_path="res://Player.tscn",
                   from_node="Player/Area2D", signal_name="body_entered",
                   to_node="Player", method="_on_area_body_entered")
        
        # Listar señales
        signal_tool("list", session_id="abc", scene_path="res://Player.tscn",
                   from_node="Player/Area2D")
        
        # Asignar script
        signal_tool("set_script", session_id="abc", scene_path="res://Player.tscn",
                   node_path="Player", script_path="res://scripts/player.gd")
    """
    
    manager = get_session_manager()
    
    # Validar sesión
    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesión no encontrada: {session_id}"}
    
    if action == "connect":
        return _action_connect(manager, session_id, scene_path, from_node, signal_name, to_node, method)
    
    elif action == "disconnect":
        return _action_disconnect(manager, session_id, scene_path, from_node, signal_name, to_node, method)
    
    elif action == "list":
        return _action_list(manager, session_id, scene_path, from_node)
    
    elif action == "set_script":
        return _action_set_script(manager, session_id, scene_path, node_path, script_path)
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: connect, disconnect, list, set_script"
        }


def _action_connect(manager, session_id: str, scene_path: str, from_node: str,
                    signal_name: str, to_node: str, method: str) -> dict:
    """Conecta una señal entre nodos."""
    if not all([scene_path, from_node, signal_name, to_node, method]):
        return {
            "success": False,
            "error": "scene_path, from_node, signal_name, to_node y method requeridos para action='connect'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "connect_signal",
        {
            "scene_path": scene_path,
            "from_node": from_node,
            "signal_name": signal_name,
            "to_node": to_node,
            "method": method
        }
    )


def _action_disconnect(manager, session_id: str, scene_path: str, from_node: str,
                       signal_name: str, to_node: str, method: str) -> dict:
    """Desconecta una señal entre nodos."""
    if not all([scene_path, from_node, signal_name, to_node, method]):
        return {
            "success": False,
            "error": "scene_path, from_node, signal_name, to_node y method requeridos para action='disconnect'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "disconnect_signal",
        {
            "scene_path": scene_path,
            "from_node": from_node,
            "signal_name": signal_name,
            "to_node": to_node,
            "method": method
        }
    )


def _action_list(manager, session_id: str, scene_path: str, from_node: str) -> dict:
    """Lista señales de un nodo."""
    if not all([scene_path, from_node]):
        return {
            "success": False,
            "error": "scene_path y from_node requeridos para action='list'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "list_signals",
        {
            "scene_path": scene_path,
            "node_path": from_node
        }
    )


def _action_set_script(manager, session_id: str, scene_path: str,
                       node_path: str, script_path: str) -> dict:
    """Asigna un script a un nodo."""
    if not all([scene_path, node_path, script_path]):
        return {
            "success": False,
            "error": "scene_path, node_path y script_path requeridos para action='set_script'"
        }
    
    return _execute_via_daemon_or_fallback(
        manager, session_id, "set_script",
        {
            "scene_path": scene_path,
            "node_path": node_path,
            "script_path": script_path
        }
    )


def _execute_via_daemon_or_fallback(manager, session_id: str, operation: str, params: dict) -> dict:
    """Ejecuta via daemon si está disponible, sino fallback a scripts temporales."""
    # Intentar daemon PRIMERO (rápido ~20ms)
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, operation, params)
            if result.get("success") or "error" not in result:
                logger.debug(f"[SignalTool] Daemon: {operation} en ~20ms")
                return result
        except Exception as e:
            logger.warning(f"[SignalTool] Daemon falló: {e}")
    
    # Fallback a scripts temporales (lento ~370ms)
    try:
        interface = create_interface(session_id)
        
        if operation == "connect_signal":
            return interface.connect_signal(
                params["scene_path"],
                params["from_node"],
                params["signal_name"],
                params["to_node"],
                params["method"]
            )
        elif operation == "disconnect_signal":
            return interface.disconnect_signal(
                params["scene_path"],
                params["from_node"],
                params["signal_name"],
                params["to_node"],
                params["method"]
            )
        elif operation == "list_signals":
            return interface.list_signals(params["scene_path"], params["node_path"])
        elif operation == "set_script":
            return interface.set_script(
                params["scene_path"],
                params["node_path"],
                params["script_path"]
            )
        else:
            return {"success": False, "error": f"Operación no soportada en fallback: {operation}"}
            
    except Exception as e:
        logger.error(f"[SignalTool] Fallback falló: {e}")
        return {"success": False, "error": str(e)}
