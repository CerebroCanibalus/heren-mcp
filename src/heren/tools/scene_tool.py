"""
Heren MCP - Scene Tool (Centralizada)

Una sola tool para TODAS las operaciones de escenas.
Modo UNICO: GodotDaemon. Todas las operaciones via WebSocket ~20ms.
"""

import logging

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def scene_tool(
    action: str,
    session_id: str,
    scene_path: str | None = None,
    output_path: str | None = None,
    resolution: tuple = (1920, 1080),
    wait_frames: int = 3,
    format: str = "png",
    quality: float = 0.9,
    instance_path: str | None = None,
    parent_path: str | None = None,
    node_name: str | None = None,
    **kwargs,
) -> dict:
    manager = get_session_manager()

    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": f"Sesión no encontrada: {session_id}"}

    if action in ["get_tree", "save", "load", "unload", "screenshot", "create", "delete", "add_ext_resource", "set_editable_paths", "undo"]:
        if not scene_path:
            return {
                "success": False,
                "error": "missing_scene_path",
                "message": f"action='{action}' requiere scene_path"
            }

    # Verify daemon is available for ALL scene operations
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {
            "success": False,
            "error": "daemon_required",
            "message": "Scene operations requieren GodotDaemon activo"
        }

    if action == "get_tree":
        return _execute_daemon(manager, session_id, "get_scene_tree", {"scene_path": scene_path})

    elif action == "save":
        return _execute_daemon(manager, session_id, "save_scene", {"scene_path": scene_path})

    elif action == "load":
        return _action_load(manager, session_id, scene_path)

    elif action == "unload":
        return _action_unload(manager, session_id, scene_path)

    elif action == "list_loaded":
        return _action_list_loaded(manager, session_id)

    elif action == "screenshot":
        return _action_screenshot(
            manager, session_id, scene_path, output_path,
            resolution, wait_frames, format, quality
        )

    elif action == "create":
        return _execute_daemon(manager, session_id, "create_scene", {
            "scene_path": scene_path,
            "root_type": kwargs.get("root_type", "Node2D"),
            "root_name": kwargs.get("root_name", "Root")
        })

    elif action == "delete":
        return _execute_daemon(manager, session_id, "delete_scene", {"scene_path": scene_path})

    elif action == "rename":
        if not scene_path or not kwargs.get("new_path"):
            return {
                "success": False,
                "error": "missing_params",
                "message": "action='rename' requiere scene_path y new_path"
            }
        return _execute_daemon(manager, session_id, "rename_scene", {
            "scene_path": scene_path,
            "new_path": kwargs.get("new_path", "")
        })

    elif action == "instantiate":
        if not instance_path:
            return {
                "success": False,
                "error": "missing_instance_path",
                "message": "action='instantiate' requiere instance_path"
            }
        return _execute_daemon(manager, session_id, "instantiate_scene", {
            "scene_path": scene_path,
            "instance_path": instance_path,
            "parent_path": parent_path or ".",
            "node_name": node_name or ""
        })

    elif action == "add_ext_resource":
        if not kwargs.get("resource_path"):
            return {
                "success": False,
                "error": "missing_resource_path",
                "message": "action='add_ext_resource' requiere resource_path"
            }
        return _execute_daemon(manager, session_id, "add_ext_resource", {
            "scene_path": scene_path,
            "resource_path": kwargs.get("resource_path", ""),
            "resource_type": kwargs.get("resource_type", "Script")
        })

    elif action == "set_editable_paths":
        if not kwargs.get("paths"):
            return {
                "success": False,
                "error": "missing_paths",
                "message": "action='set_editable_paths' requiere paths (lista)"
            }
        return _execute_daemon(manager, session_id, "set_editable_paths", {
            "scene_path": scene_path,
            "paths": kwargs.get("paths", []),
            "editable": kwargs.get("editable", True)
        })

    elif action == "undo":
        return _action_undo(manager, session_id, scene_path)

    else:
        return {
            "success": False,
            "error": f"Action no soportada: '{action}'. Use: get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, instantiate, add_ext_resource, set_editable_paths"
        }


def _execute_daemon(manager, session_id: str, operation: str, params: dict) -> dict:
    return manager.execute_via_daemon(session_id, operation, params)


def _action_load(manager, session_id: str, scene_path: str) -> dict:
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='load'"}

    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {"success": False, "error": "daemon_required", "message": "Esta operacion requiere GodotDaemon"}

    try:
        return daemon.call("load_scene", {"scene_path": scene_path})
    except Exception as e:
        logger.error(f"[SceneTool] Error cargando escena: {e}")
        return {"success": False, "error": str(e)}


def _action_unload(manager, session_id: str, scene_path: str) -> dict:
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='unload'"}

    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {"success": False, "error": "daemon_required", "message": "Esta operacion requiere GodotDaemon"}

    try:
        return daemon.call("unload_scene", {"scene_path": scene_path})
    except Exception as e:
        logger.error(f"[SceneTool] Error descargando escena: {e}")
        return {"success": False, "error": str(e)}


def _action_list_loaded(manager, session_id: str) -> dict:
    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {"success": False, "error": "daemon_required", "message": "Esta operacion requiere GodotDaemon"}

    try:
        return daemon.call("get_loaded_scenes", {})
    except Exception as e:
        logger.error(f"[SceneTool] Error listando escenas: {e}")
        return {"success": False, "error": str(e)}


def _action_undo(manager, session_id: str, scene_path: str) -> dict:
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='undo'"}

    import glob
    import shutil

    session = manager.get_session(session_id)
    if not session:
        return {"success": False, "error": "Sesion no encontrada"}

    backup_pattern = scene_path + ".backup.*"
    backups = glob.glob(backup_pattern)

    if not backups:
        return {"success": False, "error": "no_backups_found", "message": "No hay backups para esta escena"}

    backups.sort(reverse=True)
    latest_backup = backups[0]

    try:
        shutil.copy2(latest_backup, scene_path)

        daemon = manager.get_godot_daemon(session_id)
        if daemon:
            try:
                daemon.call("load_scene", {"scene_path": scene_path})
            except Exception as e:
                logger.warning(f"[Undo] No se pudo recargar en daemon: {e}")

        return {
            "success": True,
            "scene_path": scene_path,
            "restored_from": latest_backup,
            "backups_available": len(backups)
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def _action_screenshot(
    manager, session_id: str, scene_path: str, output_path: str,
    resolution: tuple, wait_frames: int, format: str, quality: float
) -> dict:
    if not scene_path:
        return {"success": False, "error": "scene_path requerido para action='screenshot'"}

    daemon = manager.get_godot_daemon(session_id)
    if not daemon:
        return {"success": False, "error": "daemon_required", "message": "Screenshot requiere GodotDaemon con rendering GPU"}

    try:
        return daemon.call("screenshot", {
            "scene_path": scene_path,
            "output_path": output_path,
            "resolution": resolution,
            "wait_frames": wait_frames,
            "format": format,
            "quality": quality
        })
    except Exception as e:
        logger.error(f"[SceneTool] Error en screenshot: {e}")
        return {"success": False, "error": str(e)}
