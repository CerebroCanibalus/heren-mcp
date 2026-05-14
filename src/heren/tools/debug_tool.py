"""
Debug Tool - Depuración de escenas Godot.

Actions:
- breakpoint: Setear breakpoint en script GDScript
- stack_trace: Obtener stack trace
- watch: Watch variable
- console: Capturar output de consola
- run_scene: Ejecutar escena (current o específica)
- stop_scene: Detener ejecución
- get_editor_errors: Obtener errores del editor
- execute_editor_script: Ejecutar GDScript arbitrario en el editor
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def debug(action: str, session_id: str = None, **kwargs) -> dict:
    """Tool centralizada para debugging."""
    session_manager = get_session_manager()
    
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if not daemon:
        return {"success": False, "error": "Debug requiere daemon activo"}
    
    actions_map = {
        "breakpoint": _action_breakpoint,
        "stack_trace": _action_stack_trace,
        "watch": _action_watch,
        "console": _action_console,
        "run_scene": _action_run_scene,
        "stop_scene": _action_stop_scene,
        "get_editor_errors": _action_get_editor_errors,
        "execute_editor_script": _action_execute_editor_script,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](daemon, **kwargs)
    except Exception as e:
        logger.error(f"Error en debug({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_breakpoint(daemon, script_path: str, line: int, enabled: bool = True, **kwargs) -> dict:
    """Setear breakpoint en script."""
    return daemon.call("set_breakpoint", {
        "script_path": script_path,
        "line": line,
        "enabled": enabled
    })


def _action_stack_trace(daemon, **kwargs) -> dict:
    """Obtener stack trace del debugger."""
    return daemon.call("get_stack_trace", {})


def _action_watch(daemon, variable_name: str, **kwargs) -> dict:
    """Watch variable."""
    return daemon.call("watch_variable", {"variable_name": variable_name})


def _action_console(daemon, lines: int = 100, **kwargs) -> dict:
    """Capturar output de consola."""
    return daemon.call("get_console_output", {"lines": lines})


def _action_run_scene(daemon, scene_path: str = "", **kwargs) -> dict:
    """Ejecutar escena. Si scene_path está vacío, ejecuta la escena actual."""
    return daemon.call("run_scene", {"scene_path": scene_path})


def _action_stop_scene(daemon, **kwargs) -> dict:
    """Detener ejecución de la escena."""
    return daemon.call("stop_scene", {})


def _action_get_editor_errors(daemon, **kwargs) -> dict:
    """Obtener errores y warnings del editor."""
    return daemon.call("get_editor_errors", {})


def _action_execute_editor_script(daemon, script_code: str = "", context: dict = None, **kwargs) -> dict:
    """Ejecutar GDScript arbitrario en el editor."""
    return daemon.call("execute_editor_script", {
        "script_code": script_code,
        "context": context or {}
    })
