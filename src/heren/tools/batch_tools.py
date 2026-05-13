"""
Heren MCP - Batch Tool (Capa 2)

Ejecuta múltiples operaciones en una sola llamada.
Optimiza rendimiento reduciendo overhead de comunicaci�n.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import logging
from typing import Any

from heren.core.session_manager import get_session_manager
from heren.tools.scene_tools import _execute_operation

logger = logging.getLogger(__name__)


def heren_batch(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta m�ltiples operaciones en batch.
    
    Usa GodotServer si est� disponible (1 request HTTP para todas las ops),
    o fallback a scripts temporales (1 script con todas las ops).
    
    Args:
        session_id: ID de sesi�n activa
        operations: Lista de operaciones
            Cada operaci�n es un dict con:
            - "operation": str - Nombre de la operaci�n
            - "params": dict - Par�metros de la operaci�n
        stop_on_error: Si True, detiene en el primer error
    
    Returns:
        {
            "success": bool,
            "results": list[dict],  # Resultado de cada operaci�n
            "errors": list[dict],   # Errores si los hay
            "success_count": int,
            "error_count": int,
        }
    
    Example:
        heren_batch(session_id, [
            {"operation": "add_node", "params": {...}},
            {"operation": "set_property", "params": {...}},
            {"operation": "save_scene", "params": {...}},
        ])
    """
    try:
        session_manager = get_session_manager()
        
        # 1. Intentar GodotDaemon (WebSocket - más rápido)
        daemon = session_manager.get_godot_daemon(session_id)
        if daemon:
            logger.info(f"[Daemon] Ejecutando batch de {len(operations)} operaciones")
            return session_manager.execute_batch_via_daemon(session_id, operations, stop_on_error)
        
        # 2. Intentar GodotServer (HTTP legacy)
        server = session_manager.get_godot_server(session_id)
        if server:
            logger.info(f"Ejecutando batch de {len(operations)} operaciones via GodotServer")
            return server.execute("batch", {
                "operations": operations,
                "stop_on_error": stop_on_error
            })
        
        # 3. Fallback: ejecutar una por una con scripts temporales
        logger.info(f"Ejecutando batch de {len(operations)} operaciones via scripts temporales")
        return _execute_batch_fallback(session_id, operations, stop_on_error)
        
    except Exception as e:
        logger.error(f"Error en batch: {e}")
        return {
            "success": False,
            "error": str(e),
            "results": [],
            "errors": [{"index": 0, "error": str(e)}],
            "success_count": 0,
            "error_count": 1
        }


def _execute_batch_fallback(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta batch usando scripts temporales (fallback).
    """
    results = []
    errors = []
    
    for i, op in enumerate(operations):
        try:
            operation_name = op.get("operation", "")
            params = op.get("params", {})
            
            result = _execute_operation(session_id, operation_name, params)
            results.append(result)
            
            if result.get("error") or not result.get("success", True):
                errors.append({
                    "index": i,
                    "operation": operation_name,
                    "error": result.get("error", "Unknown error")
                })
                
                if stop_on_error:
                    break
                    
        except Exception as e:
            error_info = {
                "index": i,
                "operation": op.get("operation", ""),
                "error": str(e)
            }
            errors.append(error_info)
            results.append({"success": False, "error": str(e)})
            
            if stop_on_error:
                break
    
    return {
        "success": len(errors) == 0,
        "results": results,
        "errors": errors,
        "success_count": len(operations) - len(errors),
        "error_count": len(errors)
    }
