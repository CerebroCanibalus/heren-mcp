"""
Heren MCP - Orchestrate Tool (reemplaza batch)

Ejecuta un plan de operaciones multi-escena en una sola llamada.
Agrupa operaciones por escena y maneja create/load/save automáticamente.
"""

import logging

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def orchestrate(
    session_id: str,
    plan: dict,
    on_error: str = "stop",
    auto_save: bool = True,
) -> dict:
    """
    Ejecuta un plan de operaciones multi-escena.

    Args:
        session_id: ID de sesión activa
        plan: Dict con scene_path como key, cada uno con:
            - ops: lista de operaciones [{action: params}, ...]
            - create?: {root_type, root_name} para crear escena si no existe
            - save?: bool, guardar esta escena después de sus ops
        on_error: "stop" (default) | "continue"
        auto_save: guardar todas las escenas dirty al final
    """
    session_manager = get_session_manager()

    if not session_id:
        session = session_manager.get_active_session()
        if not session:
            return {"success": False, "error": "No hay sesión activa"}
        session_id = session.id

    daemon = session_manager.get_godot_daemon(session_id)
    if not daemon:
        return {"success": False, "error": "Daemon no disponible"}

    if not plan or not isinstance(plan, dict):
        return {"success": False, "error": "plan es requerido (dict con scene_path como keys)"}

    return daemon.call("orchestrate", {
        "plan": plan,
        "on_error": on_error,
        "auto_save": auto_save,
    })
