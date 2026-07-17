"""
Heren MCP - Global Tool (Centralizada)

Tool para configuracion global del proyecto: autoloads, settings y shader globals.
Modo UNICO: GodotDaemon.
"""

import logging

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def global_tool(
    action: str,
    session_id: str = "",
    autoload_name: str = "",
    script_path: str = "",
    setting_name: str = "",
    value=None,
    global_name: str = "",
    **kwargs,
) -> dict:
    manager = get_session_manager()

    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Global operations requieren GodotDaemon activo"
        }

    if action == "autoload":
        if autoload_name and script_path:
            return daemon.call("add_autoload", {
                "autoload_name": autoload_name,
                "script_path": script_path
            })
        elif autoload_name:
            return daemon.call("remove_autoload", {"autoload_name": autoload_name})
        else:
            return daemon.call("list_autoloads", {})

    elif action == "project_setting":
        if value is not None:
            return daemon.call("set_project_setting", {
                "setting_name": setting_name,
                "value": value
            })
        else:
            return daemon.call("get_project_setting", {"setting_name": setting_name})

    elif action == "shader_global":
        if value is not None:
            return daemon.call("set_shader_global", {
                "global_name": global_name,
                "value": value
            })
        else:
            return daemon.call("get_shader_global", {"global_name": global_name})

    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: autoload, project_setting, shader_global"
        }
