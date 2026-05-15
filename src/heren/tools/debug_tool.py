"""
Debug Tool - Depuración de escenas Godot.

Actions:
- breakpoint: Setear breakpoint en script GDScript (requiere daemon en editor)
- stack_trace: Obtener stack trace (requiere daemon en editor)
- watch: Watch variable (requiere daemon en editor)
- console: Capturar output de consola
- run_scene: Ejecutar escena (subprocess - no requiere daemon)
- stop_scene: Detener ejecución (requiere daemon en editor)
- get_editor_errors: Obtener errores del editor
- execute_editor_script: Ejecutar GDScript arbitrario (subprocess o Expression)
- check_script_syntax: Verificar sintaxis GDScript (subprocess - no requiere daemon)

Basado en el enfoque del MCP anterior: subprocess.run para operaciones standalone.
"""

import logging
import os
import re
import subprocess
import tempfile
from typing import Any, Optional

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)

# Rutas comunes donde buscar el ejecutable de Godot
GODOT_SEARCH_PATHS = [
    r"D:\Mis Juegos\Godot",
    r"C:\Program Files\Godot",
    r"C:\Program Files (x86)\Godot",
    "/usr/local/bin",
    "/usr/bin",
    "/Applications",
]

GODOT_EXECUTABLE_NAMES = [
    "Godot_v4.6.1-stable_win64_console.exe",
    "Godot_v4.6.1-stable_win64.exe",
    "Godot_v4.5.1-stable_win64_console.exe",
    "Godot_v4.5.1-stable_win64.exe",
    "Godot_v4.5-stable_win64_console.exe",
    "Godot_v4.5-stable_win64.exe",
    "godot",
    "Godot",
]


def _find_godot_executable() -> Optional[str]:
    """Find Godot executable in common locations."""
    import shutil
    
    godot_in_path = shutil.which("godot") or shutil.which("Godot")
    if godot_in_path:
        return godot_in_path
    
    for search_path in GODOT_SEARCH_PATHS:
        if not os.path.exists(search_path):
            continue
        for exe_name in GODOT_EXECUTABLE_NAMES:
            candidate = os.path.join(search_path, exe_name)
            if os.path.isfile(candidate):
                return candidate
    
    return None


def _parse_log_output(log_content: str) -> dict[str, list[str]]:
    """Parse Godot log output into categorized messages."""
    errors = []
    warnings = []
    prints = []
    info = []
    stack_traces = []
    
    for line in log_content.splitlines():
        line = line.strip()
        if not line:
            continue
        
        if line.startswith("ERROR:") or line.startswith("ERROR "):
            errors.append(line)
        elif line.startswith("At:"):
            stack_traces.append(line)
        elif line.startswith("WARNING:") or line.startswith("WARNING "):
            warnings.append(line)
        elif line.startswith("USER SCRIPT:") or line.startswith("   at"):
            prints.append(line)
        elif line.startswith("SCRIPT ERROR:"):
            errors.append(line)
        elif line.startswith("   "):
            stack_traces.append(line)
        else:
            info.append(line)
    
    return {
        "errors": errors,
        "warnings": warnings,
        "prints": prints,
        "info": info,
        "stack_traces": stack_traces,
    }


def debug(action: str, session_id: str = None, **kwargs) -> dict:
    """
    Tool centralizada para debugging.
    
    Soporta dos modos:
    1. Daemon mode: Para breakpoints, stack traces, watch (requiere daemon en editor)
    2. Subprocess mode: Para run_scene, execute_script, check_syntax (standalone)
    """
    
    actions_map = {
        "breakpoint": _action_breakpoint,
        "stack_trace": _action_stack_trace,
        "watch": _action_watch,
        "console": _action_console,
        "run_scene": _action_run_scene_subprocess,
        "stop_scene": _action_stop_scene,
        "get_editor_errors": _action_get_editor_errors,
        "execute_editor_script": _action_execute_script_subprocess,
        "check_script_syntax": _action_check_script_syntax,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_id=session_id, **kwargs)
    except Exception as e:
        logger.error(f"Error en debug({action}): {e}")
        return {"success": False, "error": str(e)}


def _get_daemon_or_none(session_id: str = None):
    """Obtiene el daemon si está disponible, sino None."""
    session_manager = get_session_manager()
    
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    if not session:
        return None
    
    daemon = session_manager.get_godot_daemon(session.id)
    return daemon


# ============================================================
# OPERACIONES QUE REQUIEREN DAEMON EN EDITOR
# ============================================================

def _action_breakpoint(session_id: str = None, script_path: str = "", line: int = 0, enabled: bool = True, **kwargs) -> dict:
    """Setear breakpoint en script (requiere daemon en editor)."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "breakpoint requiere daemon activo en el editor"}
    
    return daemon.call("set_breakpoint", {
        "script_path": script_path,
        "line": line,
        "enabled": enabled
    })


def _action_stack_trace(session_id: str = None, **kwargs) -> dict:
    """Obtener stack trace (requiere daemon en editor)."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "stack_trace requiere daemon activo en el editor"}
    
    return daemon.call("get_stack_trace", {})


def _action_watch(session_id: str = None, variable_name: str = "", **kwargs) -> dict:
    """Watch variable (requiere daemon en editor)."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "watch requiere daemon activo en el editor"}
    
    return daemon.call("watch_variable", {"variable_name": variable_name})


def _action_console(session_id: str = None, lines: int = 100, **kwargs) -> dict:
    """Capturar output de consola."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "console requiere daemon activo"}
    
    return daemon.call("get_console_output", {"lines": lines})


def _action_stop_scene(session_id: str = None, **kwargs) -> dict:
    """Detener ejecución (requiere daemon en editor)."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "stop_scene requiere daemon activo en el editor"}
    
    return daemon.call("stop_scene", {})


def _action_get_editor_errors(session_id: str = None, **kwargs) -> dict:
    """Obtener errores del editor (requiere daemon en editor)."""
    daemon = _get_daemon_or_none(session_id)
    if not daemon:
        return {"success": False, "error": "get_editor_errors requiere daemon activo en el editor"}
    
    return daemon.call("get_editor_errors", {})


# ============================================================
# OPERACIONES STANDALONE (SUBPROCESS - NO REQUIEREN DAEMON)
# ============================================================

def _action_run_scene_subprocess(
    session_id: str = None,
    project_path: str = None,
    scene_path: str = None,
    godot_path: str = None,
    timeout: int = 30,
    debug_collisions: bool = False,
    debug_paths: bool = False,
    debug_navigation: bool = False,
    **kwargs
) -> dict:
    """
    Ejecutar escena usando subprocess (standalone, no requiere daemon).
    
    Basado en el MCP anterior: ejecuta Godot con --headless y captura logs.
    """
    # Si no se proporciona project_path, intentar obtenerlo de la sesión
    if not project_path and session_id:
        session_manager = get_session_manager()
        session = session_manager.get_session(session_id)
        if session:
            project_path = session.project_path
    
    if not project_path:
        return {"success": False, "error": "Se requiere project_path o session_id válido"}
    
    project_path = os.path.abspath(project_path)
    if not os.path.isdir(project_path):
        return {"success": False, "error": f"Proyecto no encontrado: {project_path}"}
    
    project_godot = os.path.join(project_path, "project.godot")
    if not os.path.isfile(project_godot):
        return {"success": False, "error": f"No es un proyecto Godot válido: {project_path}"}
    
    # Encontrar Godot
    godot_exe = godot_path or _find_godot_executable()
    if not godot_exe:
        return {
            "success": False,
            "error": "Godot no encontrado. Proporciona godot_path o instala Godot.",
            "searched_paths": GODOT_SEARCH_PATHS,
        }
    
    # Crear log temporal
    log_file = os.path.join(tempfile.gettempdir(), f"heren_debug_{os.getpid()}.log")
    
    # Construir comando
    cmd = [
        godot_exe,
        "--headless",
        "--path",
        project_path,
        "--log-file",
        log_file,
        "--quit-after",
        "1",
    ]
    
    if scene_path:
        cmd.append(scene_path)
    
    if debug_collisions:
        cmd.append("--debug-collisions")
    if debug_paths:
        cmd.append("--debug-paths")
    if debug_navigation:
        cmd.append("--debug-navigation")
    
    logger.info(f"[Debug] Ejecutando: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        
        # Leer log
        log_content = ""
        if os.path.exists(log_file):
            with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()
        
        # Combinar output
        combined = log_content + "\n" + (result.stdout or "") + "\n" + (result.stderr or "")
        parsed = _parse_log_output(combined)
        
        return {
            "success": result.returncode == 0,
            "errors": parsed["errors"],
            "warnings": parsed["warnings"],
            "prints": parsed["prints"],
            "info": parsed["info"],
            "stack_traces": parsed["stack_traces"],
            "exit_code": result.returncode,
            "godot_path": godot_exe,
            "log_file": log_file,
            "scene_path": scene_path,
            "project_path": project_path,
            "mode": "subprocess_standalone",
        }
        
    except subprocess.TimeoutExpired:
        return {"success": False, "error": f"Timeout después de {timeout}s", "godot_path": godot_exe}
    except FileNotFoundError as e:
        return {"success": False, "error": f"Godot no encontrado: {e}", "godot_path": godot_exe}
    except Exception as e:
        return {"success": False, "error": f"Error ejecutando Godot: {e}", "godot_path": godot_exe}


def _action_execute_script_subprocess(
    session_id: str = None,
    project_path: str = None,
    script_code: str = "",
    godot_path: str = None,
    timeout: int = 30,
    **kwargs
) -> dict:
    """
    Ejecutar GDScript arbitrario usando subprocess.
    
    Crea un archivo .gd temporal y lo ejecuta con godot --script.
    Soporta FileAccess, ClassDB, ResourceSaver, etc.
    """
    if not script_code:
        return {"success": False, "error": "Se requiere script_code"}
    
    # Obtener project_path de la sesión si no se proporciona
    if not project_path and session_id:
        session_manager = get_session_manager()
        session = session_manager.get_session(session_id)
        if session:
            project_path = session.project_path
    
    if not project_path:
        return {"success": False, "error": "Se requiere project_path o session_id válido"}
    
    project_path = os.path.abspath(project_path)
    
    # Encontrar Godot
    godot_exe = godot_path or _find_godot_executable()
    if not godot_exe:
        return {"success": False, "error": "Godot no encontrado"}
    
    # Crear script temporal
    script_file = os.path.join(tempfile.gettempdir(), f"heren_script_{os.getpid()}_{hash(script_code) & 0xFFFF}.gd")
    
    # Guardar el codigo del usuario tal cual (el ya debe incluir extends SceneTree y func _init)
    # NOTA: No usar f-string con script_code porque puede contener {} que Python interpreta
    
    try:
        with open(script_file, "w", encoding="utf-8") as f:
            f.write(script_code)
        
        # Ejecutar
        cmd = [
            godot_exe,
            "--headless",
            "--path",
            project_path,
            "--script",
            script_file,
        ]
        
        logger.info(f"[Debug] Ejecutando script: {script_file}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        
        # Parsear output
        output = result.stdout or ""
        errors = []
        script_result = None
        
        for line in output.splitlines():
            if line.startswith("SCRIPT_ERROR:"):
                errors.append(line[13:].strip())
            elif line.startswith("SCRIPT_RESULT:"):
                script_result = line[14:].strip()
            elif line.startswith("TEST_OUTPUT:"):
                script_result = line[12:].strip()
        
        return {
            "success": len(errors) == 0 and result.returncode == 0,
            "errors": errors,
            "result": script_result,
            "stdout": output,
            "stderr": result.stderr,
            "exit_code": result.returncode,
            "mode": "subprocess_script",
        }
        
    except subprocess.TimeoutExpired:
        return {"success": False, "error": f"Timeout después de {timeout}s"}
    except Exception as e:
        return {"success": False, "error": f"Error: {e}"}
    finally:
        # Limpiar archivo temporal
        try:
            if os.path.exists(script_file):
                os.remove(script_file)
        except:
            pass


def _action_check_script_syntax(
    session_id: str = None,
    project_path: str = None,
    script_path: str = "",
    godot_path: str = None,
    timeout: int = 30,
    **kwargs
) -> dict:
    """
    Verificar sintaxis GDScript usando --check-only.
    """
    if not script_path:
        return {"success": False, "error": "Se requiere script_path"}
    
    # Obtener project_path de la sesión
    if not project_path and session_id:
        session_manager = get_session_manager()
        session = session_manager.get_session(session_id)
        if session:
            project_path = session.project_path
    
    if not project_path:
        return {"success": False, "error": "Se requiere project_path o session_id válido"}
    
    project_path = os.path.abspath(project_path)
    
    # Encontrar Godot
    godot_exe = godot_path or _find_godot_executable()
    if not godot_exe:
        return {"success": False, "error": "Godot no encontrado"}
    
    log_file = os.path.join(tempfile.gettempdir(), f"heren_syntax_{os.getpid()}.log")
    
    cmd = [
        godot_exe,
        "--headless",
        "--path",
        project_path,
        "--log-file",
        log_file,
        "--check-only",
        "--script",
        script_path,
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        
        log_content = ""
        if os.path.exists(log_file):
            with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()
        
        combined = log_content + "\n" + (result.stdout or "") + "\n" + (result.stderr or "")
        parsed = _parse_log_output(combined)
        
        return {
            "success": result.returncode == 0,
            "errors": parsed["errors"],
            "warnings": parsed["warnings"],
            "exit_code": result.returncode,
            "script_path": script_path,
            "godot_path": godot_exe,
            "mode": "subprocess_check",
        }
        
    except subprocess.TimeoutExpired:
        return {"success": False, "error": f"Timeout después de {timeout}s"}
    except Exception as e:
        return {"success": False, "error": f"Error: {e}"}
