"""
Heren MCP - Session Tool (Centralizada)

Una sola tool para TODAS las operaciones de sesion.
Modo UNICO: GodotDaemon. Sin fallback.
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
) -> dict:
    manager = get_session_manager()

    if action == "open":
        return _action_open(manager, project_path, godot_path)
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


def _action_open(manager, project_path: str, godot_path: Optional[str]) -> dict:
    if not project_path:
        return {"success": False, "error": "project_path requerido para action='open'"}

    try:
        session = manager.start_session(
            project_path=project_path,
            godot_path=godot_path,
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

        logger.info(f"[SessionTool] Sesion abierta: {session.id} | daemon_active={daemon_active}")
        return result

    except Exception as e:
        logger.error(f"[SessionTool] Error abriendo sesion: {e}")
        return {"success": False, "error": str(e)}


def _action_close(manager, session_id: str) -> dict:
    if not session_id:
        return {"success": False, "error": "session_id requerido para action='close'"}

    try:
        success = manager.end_session(session_id)
        if success:
            logger.info(f"[SessionTool] Sesion cerrada: {session_id}")
            return {"success": True}
        else:
            return {"success": False, "error": f"Sesion no encontrada: {session_id}"}
    except Exception as e:
        logger.error(f"[SessionTool] Error cerrando sesion: {e}")
        return {"success": False, "error": str(e)}


def _action_list(manager) -> dict:
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

        return {"success": True, "count": len(sessions), "sessions": sessions}
    except Exception as e:
        logger.error(f"[SessionTool] Error listando sesiones: {e}")
        return {"success": False, "error": str(e)}


def _action_info(manager, session_id: str) -> dict:
    if not session_id:
        return {"success": False, "error": "session_id requerido para action='info'"}

    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesion no encontrada: {session_id}"}

    return {
        "success": True,
        "session": {
            "id": session.id,
            "project_path": session.project_path,
            "created_at": session.created_at,
            "last_activity": session.last_activity,
            "daemon_active": session.godot_daemon is not None,
            "scene_cache_size": len(session.scene_cache._cache),
            "resource_cache_size": len(session.resource_cache._cache),
        }
    }


def _action_health(manager, session_id: str) -> dict:
    if not session_id:
        return {"success": False, "error": "session_id requerido para action='health'"}

    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesion no encontrada: {session_id}"}

    if not session.godot_daemon:
        return {"success": False, "error": "daemon_not_running", "message": "No hay daemon activo para esta sesion"}

    try:
        return session.godot_daemon.health()
    except Exception as e:
        logger.error(f"[SessionTool] Error verificando health: {e}")
        return {"success": False, "error": str(e)}
