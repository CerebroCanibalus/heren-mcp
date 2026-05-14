"""
Heren MCP - Global Tool (Centralizada)

Tool para gestión global del proyecto: autoloads, settings y shader globals.
Modifica project.godot directamente cuando el daemon no está disponible.

Actions:
- autoload: Añadir/quitar/listar autoloads
- project_setting: Leer/escribir settings de project.godot
- shader_global: Gestión de shader globals
"""

import logging
import os
import re
from typing import Optional

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def global_tool(
    action: str,
    session_id: str = "",
    autoload_name: str = "",
    script_path: str = "",
    setting_name: str = "",
    value = None,
    global_name: str = "",
    **kwargs,
) -> dict:
    """
    Tool centralizada para configuración global del proyecto.
    
    Actions:
        - "autoload": Añade, quita o lista autoloads
            - Para añadir: proporciona autoload_name y script_path
            - Para quitar: proporciona autoload_name (script_path vacío)
            - Para listar: no proporciones autoload_name
        - "project_setting": Lee o escribe un setting de project.godot
            - Para leer: proporciona solo setting_name
            - Para escribir: proporciona setting_name y value
        - "shader_global": Gestiona shader globals del proyecto
            - Para setear: proporciona global_name y value
            - Para obtener: proporciona solo global_name
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        autoload_name: Nombre del autoload (para autoload)
        script_path: Ruta al script del autoload (para autoload añadir)
        setting_name: Nombre del setting en formato "section/key" (ej: "display/window/size/viewport_width")
        value: Valor a escribir (None para leer)
        global_name: Nombre del shader global
    
    Returns:
        Dict con resultado de la operación
    
    Examples:
        # Añadir autoload
        global_tool("autoload", session_id="abc", autoload_name="GameManager", script_path="res://autoloads/game_manager.gd")
        
        # Quitar autoload
        global_tool("autoload", session_id="abc", autoload_name="GameManager")
        
        # Listar autoloads
        global_tool("autoload", session_id="abc")
        
        # Leer setting
        global_tool("project_setting", session_id="abc", setting_name="display/window/size/viewport_width")
        
        # Escribir setting
        global_tool("project_setting", session_id="abc", setting_name="display/window/size/viewport_width", value=1920)
    """
    
    manager = get_session_manager()
    
    # Para algunas operaciones no necesitamos sesión (modo directo de project.godot)
    if action == "autoload":
        if autoload_name and script_path:
            return _action_add_autoload(manager, session_id, autoload_name, script_path)
        elif autoload_name:
            return _action_remove_autoload(manager, session_id, autoload_name)
        else:
            return _action_list_autoloads(manager, session_id)
    
    elif action == "project_setting":
        if value is not None:
            return _action_set_project_setting(manager, session_id, setting_name, value)
        else:
            return _action_get_project_setting(manager, session_id, setting_name)
    
    elif action == "shader_global":
        if value is not None:
            return _action_set_shader_global(manager, session_id, global_name, value)
        else:
            return _action_get_shader_global(manager, session_id, global_name)
    
    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: autoload, project_setting, shader_global"
        }


def _get_project_godot_path(manager, session_id: str) -> str:
    """Obtiene la ruta a project.godot."""
    session = manager.get_session(session_id)
    if session:
        return os.path.join(session.project_path, "project.godot")
    
    # Fallback: buscar project.godot en directorio actual
    cwd = os.getcwd()
    project_godot = os.path.join(cwd, "project.godot")
    if os.path.exists(project_godot):
        return project_godot
    
    # Buscar hacia arriba
    current = cwd
    while current != os.path.dirname(current):
        project_godot = os.path.join(current, "project.godot")
        if os.path.exists(project_godot):
            return project_godot
        current = os.path.dirname(current)
    
    return ""


def _read_project_godot(project_godot_path: str) -> dict:
    """Lee project.godot y retorna sus secciones."""
    if not os.path.exists(project_godot_path):
        return {"error": f"project.godot no encontrado: {project_godot_path}"}
    
    sections = {}
    current_section = None
    
    with open(project_godot_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            
            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1]
                sections[current_section] = {}
            elif current_section and "=" in line:
                key, val = line.split("=", 1)
                sections[current_section][key.strip()] = val.strip()
    
    return sections


def _write_project_godot(project_godot_path: str, sections: dict) -> bool:
    """Escribe project.godot desde sus secciones."""
    try:
        with open(project_godot_path, "w", encoding="utf-8") as f:
            for section_name, keys in sections.items():
                f.write(f"[{section_name}]\n")
                for key, value in keys.items():
                    f.write(f"{key}={value}\n")
                f.write("\n")
        return True
    except Exception as e:
        logger.error(f"Error escribiendo project.godot: {e}")
        return False


def _action_add_autoload(manager, session_id: str, autoload_name: str, script_path: str) -> dict:
    """Añade un autoload al proyecto."""
    # Intentar via daemon primero
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, "add_autoload", {
                "autoload_name": autoload_name,
                "script_path": script_path
            })
            if result.get("success"):
                return result
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon add_autoload falló: {e}")
    
    # Modo directo: editar project.godot
    project_godot = _get_project_godot_path(manager, session_id)
    if not project_godot:
        return {"success": False, "error": "No se pudo encontrar project.godot"}
    
    sections = _read_project_godot(project_godot)
    if "error" in sections:
        return {"success": False, "error": sections["error"]}
    
    # Asegurar que existe la sección autoload
    if "autoload" not in sections:
        sections["autoload"] = {}
    
    # Añadir autoload
    sections["autoload"][autoload_name] = f'"*{script_path}"'
    
    if _write_project_godot(project_godot, sections):
        return {
            "success": True,
            "action": "add_autoload",
            "autoload_name": autoload_name,
            "script_path": script_path,
            "message": f"Autoload '{autoload_name}' añadido (modo directo)"
        }
    else:
        return {"success": False, "error": "No se pudo escribir project.godot"}


def _action_remove_autoload(manager, session_id: str, autoload_name: str) -> dict:
    """Quita un autoload del proyecto."""
    # Intentar via daemon primero
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, "remove_autoload", {
                "autoload_name": autoload_name
            })
            if result.get("success"):
                return result
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon remove_autoload falló: {e}")
    
    # Modo directo
    project_godot = _get_project_godot_path(manager, session_id)
    if not project_godot:
        return {"success": False, "error": "No se pudo encontrar project.godot"}
    
    sections = _read_project_godot(project_godot)
    if "error" in sections:
        return {"success": False, "error": sections["error"]}
    
    if "autoload" not in sections or autoload_name not in sections["autoload"]:
        return {"success": False, "error": f"Autoload '{autoload_name}' no encontrado"}
    
    del sections["autoload"][autoload_name]
    
    if _write_project_godot(project_godot, sections):
        return {
            "success": True,
            "action": "remove_autoload",
            "autoload_name": autoload_name,
            "message": f"Autoload '{autoload_name}' eliminado"
        }
    else:
        return {"success": False, "error": "No se pudo escribir project.godot"}


def _action_list_autoloads(manager, session_id: str) -> dict:
    """Lista todos los autoloads del proyecto."""
    project_godot = _get_project_godot_path(manager, session_id)
    if not project_godot:
        return {"success": False, "error": "No se pudo encontrar project.godot"}
    
    sections = _read_project_godot(project_godot)
    if "error" in sections:
        return {"success": False, "error": sections["error"]}
    
    autoloads = sections.get("autoload", {})
    
    # Parsear autoloads
    result = []
    for name, value in autoloads.items():
        is_singleton = value.startswith('"*')
        path = value.strip('"').lstrip('*')
        result.append({
            "name": name,
            "path": path,
            "singleton": is_singleton
        })
    
    return {
        "success": True,
        "autoloads": result,
        "count": len(result)
    }


def _action_get_project_setting(manager, session_id: str, setting_name: str) -> dict:
    """Lee un setting de project.godot."""
    if not setting_name:
        return {"success": False, "error": "setting_name requerido"}
    
    # Intentar via daemon
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, "get_project_setting", {
                "setting_name": setting_name
            })
            if result.get("success"):
                return result
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon get_project_setting falló: {e}")
    
    # Modo directo
    project_godot = _get_project_godot_path(manager, session_id)
    if not project_godot:
        return {"success": False, "error": "No se pudo encontrar project.godot"}
    
    sections = _read_project_godot(project_godot)
    if "error" in sections:
        return {"success": False, "error": sections["error"]}
    
    # Parsear setting_name (formato: "section/key")
    parts = setting_name.split("/")
    if len(parts) < 2:
        return {"success": False, "error": "setting_name debe tener formato 'section/key'"}
    
    section = parts[0]
    key = "/".join(parts[1:])
    
    if section not in sections:
        return {"success": False, "error": f"Sección '{section}' no encontrada"}
    
    if key not in sections[section]:
        return {"success": False, "error": f"Setting '{key}' no encontrado en sección '{section}'"}
    
    raw_value = sections[section][key]
    
    # Intentar parsear el valor
    parsed_value = _parse_godot_value(raw_value)
    
    return {
        "success": True,
        "setting_name": setting_name,
        "value": parsed_value,
        "raw_value": raw_value
    }


def _action_set_project_setting(manager, session_id: str, setting_name: str, value) -> dict:
    """Escribe un setting en project.godot."""
    if not setting_name:
        return {"success": False, "error": "setting_name requerido"}
    
    # Intentar via daemon
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            result = manager.execute_via_daemon(session_id, "set_project_setting", {
                "setting_name": setting_name,
                "value": value
            })
            if result.get("success"):
                return result
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon set_project_setting falló: {e}")
    
    # Modo directo
    project_godot = _get_project_godot_path(manager, session_id)
    if not project_godot:
        return {"success": False, "error": "No se pudo encontrar project.godot"}
    
    sections = _read_project_godot(project_godot)
    if "error" in sections:
        return {"success": False, "error": sections["error"]}
    
    # Parsear setting_name
    parts = setting_name.split("/")
    if len(parts) < 2:
        return {"success": False, "error": "setting_name debe tener formato 'section/key'"}
    
    section = parts[0]
    key = "/".join(parts[1:])
    
    # Asegurar que existe la sección
    if section not in sections:
        sections[section] = {}
    
    # Convertir valor a formato Godot
    godot_value = _value_to_godot_string(value)
    sections[section][key] = godot_value
    
    if _write_project_godot(project_godot, sections):
        return {
            "success": True,
            "setting_name": setting_name,
            "value": value,
            "message": f"Setting '{setting_name}' actualizado"
        }
    else:
        return {"success": False, "error": "No se pudo escribir project.godot"}


def _action_set_shader_global(manager, session_id: str, global_name: str, value) -> dict:
    """Setea un shader global."""
    if not global_name:
        return {"success": False, "error": "global_name requerido"}
    
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            return manager.execute_via_daemon(session_id, "set_shader_global", {
                "global_name": global_name,
                "value": value
            })
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon shader_global falló: {e}")
    
    return {
        "success": False,
        "error": "shader_global requiere GodotDaemon activo"
    }


def _action_get_shader_global(manager, session_id: str, global_name: str) -> dict:
    """Obtiene un shader global."""
    if not global_name:
        return {"success": False, "error": "global_name requerido"}
    
    daemon = manager.get_godot_daemon(session_id)
    if daemon:
        try:
            return manager.execute_via_daemon(session_id, "get_shader_global", {
                "global_name": global_name
            })
        except Exception as e:
            logger.warning(f"[GlobalTool] Daemon shader_global falló: {e}")
    
    return {
        "success": False,
        "error": "shader_global requiere GodotDaemon activo"
    }


def _parse_godot_value(raw_value: str):
    """Parsea un valor de Godot a tipo Python."""
    raw_value = raw_value.strip()
    
    # Booleanos
    if raw_value.lower() == "true":
        return True
    if raw_value.lower() == "false":
        return False
    
    # Números
    try:
        if "." in raw_value:
            return float(raw_value)
        return int(raw_value)
    except ValueError:
        pass
    
    # Strings
    if raw_value.startswith('"') and raw_value.endswith('"'):
        return raw_value[1:-1]
    
    # Arrays
    if raw_value.startswith("[") and raw_value.endswith("]"):
        # Simplificación: retornar como string
        return raw_value
    
    # Por defecto, retornar como string
    return raw_value


def _value_to_godot_string(value) -> str:
    """Convierte un valor Python a string de Godot."""
    if isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, (int, float)):
        return str(value)
    elif isinstance(value, str):
        # Verificar si ya está en formato Godot
        if value.startswith('"') and value.endswith('"'):
            return value
        return f'"{value}"'
    elif isinstance(value, list):
        items = [_value_to_godot_string(item) for item in value]
        return f"[{', '.join(items)}]"
    else:
        return f'"{str(value)}"'
