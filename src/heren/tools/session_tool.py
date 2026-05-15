"""
Heren MCP - Session Tool (Centralizada)

Una sola tool para TODAS las operaciones de sesión.
Filosofía: Centralizada. Modular. Potente.

Modos:
- open: Inicia sesión
- close: Cierra sesión  
- list: Lista sesiones activas
- info: Obtiene info de una sesión
- health: Verifica salud del daemon
"""

import logging
from typing import Optional

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def session_tool(
    action: str,
    project_path: str = None,
    session_id: str = None,
    godot_path: str = None,
    use_daemon: bool = True,
) -> dict:
    """
    Tool centralizada para gestión de sesiones Heren MCP.
    
    Args:
        action: Operación a realizar
            - "open": Inicia nueva sesión
            - "close": Cierra sesión existente
            - "list": Lista todas las sesiones activas
            - "info": Obtiene información de una sesión
            - "health": Verifica salud del daemon de una sesión
        project_path: (para action="open") Ruta al proyecto Godot
        session_id: (para action="close|info|health") ID de sesión
        godot_path: (opcional) Ruta al ejecutable Godot
        use_daemon: (para action="open") Si True, usa GodotDaemon WebSocket
    
    Returns:
        Según el action:
        - open: {"success": True, "session_id": "...", "project_path": "..."}
        - close: {"success": True}
        - list: {"success": True, "sessions": [{"id": "...", "project": "..."}]}
        - info: {"success": True, "session": {...}}
        - health: {"success": True, "status": "healthy", ...}
    
    Examples:
        # Abrir sesión
        session_tool("open", project_path="D:/MiJuego")
        
        # Cerrar sesión
        session_tool("close", session_id="abc123")
        
        # Listar sesiones
        session_tool("list")
        
        # Info de sesión
        session_tool("info", session_id="abc123")
        
        # Health check
        session_tool("health", session_id="abc123")
    """
    
    manager = get_session_manager()
    
    if action == "open":
        return _action_open(manager, project_path, godot_path, use_daemon)
    
    elif action == "close":
        return _action_close(manager, session_id)
    
    elif action == "list":
        return _action_list(manager)
    
    elif action == "info":
        return _action_info(manager, session_id)
    
    elif action == "health":
        return _action_health(manager, session_id)
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: open, close, list, info, health"
        }


def _action_open(manager, project_path: str, godot_path: Optional[str], use_daemon: bool) -> dict:
    """Inicia una nueva sesión."""
    if not project_path:
        return {
            "success": False,
            "error": "project_path requerido para action='open'"
        }
    
    try:
        session = manager.start_session(
            project_path=project_path,
            godot_path=godot_path,
            use_daemon=use_daemon
        )
        
        daemon_active = session.godot_daemon is not None
        
        result = {
            "success": True,
            "session_id": session.id,
            "project_path": session.project_path,
            "daemon_active": daemon_active,
        }
        
        if session.godot_daemon:
            result["daemon_port"] = session.godot_daemon.port
        elif session.daemon_error:
            result["daemon_error"] = session.daemon_error
            result["recommendation"] = (
                "Ejecuta: project('setup_daemon', project_path='" 
                + session.project_path + "') para configurar el daemon."
            )
        
        logger.info(f"[SessionTool] Sesión abierta: {session.id} | daemon_active={daemon_active}")
        return result
        
    except Exception as e:
        logger.error(f"[SessionTool] Error abriendo sesión: {e}")
        return {"success": False, "error": str(e)}


def _action_close(manager, session_id: str) -> dict:
    """Cierra una sesión."""
    if not session_id:
        return {
            "success": False,
            "error": "session_id requerido para action='close'"
        }
    
    try:
        success = manager.end_session(session_id)
        if success:
            logger.info(f"[SessionTool] Sesión cerrada: {session_id}")
            return {"success": True}
        else:
            return {
                "success": False,
                "error": f"Sesión no encontrada: {session_id}"
            }
    except Exception as e:
        logger.error(f"[SessionTool] Error cerrando sesión: {e}")
        return {"success": False, "error": str(e)}


def _action_list(manager) -> dict:
    """Lista todas las sesiones activas."""
    try:
        sessions = []
        for sid, session in manager._sessions.items():
            sessions.append({
                "id": sid,
                "project": session.project_path,
                "created_at": session.created_at,
                "last_activity": session.last_activity,
                "daemon_active": session.godot_daemon is not None,
            })
        
        return {
            "success": True,
            "count": len(sessions),
            "sessions": sessions
        }
    except Exception as e:
        logger.error(f"[SessionTool] Error listando sesiones: {e}")
        return {"success": False, "error": str(e)}


def _action_info(manager, session_id: str) -> dict:
    """Obtiene información de una sesión específica."""
    if not session_id:
        return {
            "success": False,
            "error": "session_id requerido para action='info'"
        }
    
    session = manager.get_session(session_id)
    if not session:
        return {
            "success": False,
            "error": f"Sesión no encontrada: {session_id}"
        }
    
    return {
        "success": True,
        "session": {
            "id": session.id,
            "project_path": session.project_path,
            "created_at": session.created_at,
            "last_activity": session.last_activity,
            "daemon_active": session.godot_daemon is not None,
            "server_active": session.godot_server is not None,
            "scene_cache_size": len(session.scene_cache._cache),
            "resource_cache_size": len(session.resource_cache._cache),
        }
    }


def _action_health(manager, session_id: str) -> dict:
    """Verifica salud del daemon de una sesión."""
    if not session_id:
        return {
            "success": False,
            "error": "session_id requerido para action='health'"
        }
    
    session = manager.get_session(session_id)
    if not session:
        return {
            "success": False,
            "error": f"Sesión no encontrada: {session_id}"
        }
    
    if not session.godot_daemon:
        return {
            "success": False,
            "error": "daemon_not_running",
            "message": "No hay daemon activo para esta sesión"
        }
    
    try:
        health = session.godot_daemon.health()
        return health
    except Exception as e:
        logger.error(f"[SessionTool] Error verificando health: {e}")
        return {"success": False, "error": str(e)}
