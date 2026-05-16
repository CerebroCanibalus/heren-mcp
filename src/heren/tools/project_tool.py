"""
Project Tool - Gestión centralizada de configuración del proyecto.

Actions:
- create: Crear nuevo proyecto Godot
- setting: Leer/escribir project setting
- autoload: Añadir/quitar autoload
- group: Gestión de grupos globales
- shader_global: Setear shader global
"""

import logging
import os
import shutil
from pathlib import Path

from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def project(action: str, session_id: str = None, **kwargs) -> dict:
    """Tool centralizada para configuración del proyecto."""
    session_manager = get_session_manager()
    
    # Obtener sesión explícita o activa
    if session_id:
        session = session_manager.get_session(session_id)
    else:
        session = session_manager.get_active_session()
    
    actions_map = {
        "create": _action_create,
        "setup_daemon": _action_setup_daemon,
        "setting": _action_setting,
        "autoload": _action_autoload,
        "remove_autoload": _action_remove_autoload,
        "shader_global": _action_shader_global,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, session, **kwargs)
    except Exception as e:
        logger.error(f"Error en project({action}): {e}")
        return {"success": False, "error": str(e)}


def _get_daemon_source_dir() -> str:
    """Encuentra la ruta al directorio del daemon en el paquete."""
    # Buscar relativo a este archivo
    package_dir = Path(__file__).parent.parent
    daemon_dir = package_dir / "daemon"
    
    if (daemon_dir / "heren_daemon.gd").exists():
        return str(daemon_dir)
    
    # Fallback: buscar en src/heren/daemon/
    src_daemon = package_dir.parent / "src" / "heren" / "daemon"
    if (src_daemon / "heren_daemon.gd").exists():
        return str(src_daemon)
    
    return ""


def _action_setup_daemon(session_manager, project_path: str, **kwargs) -> dict:
    """
    Configura el daemon Heren en un proyecto Godot existente.
    
    Copia TODOS los archivos del daemon (heren_daemon.gd + módulos) al proyecto.
    Esto permite que session('open') funcione correctamente con el daemon modular.
    """
    project_path = os.path.abspath(project_path)
    
    # Verificar que el proyecto existe
    if not os.path.exists(project_path):
        return {"success": False, "error": f"Proyecto no encontrado: {project_path}"}
    
    project_file = os.path.join(project_path, "project.godot")
    if not os.path.exists(project_file):
        return {"success": False, "error": f"No es un proyecto Godot válido: {project_path}"}
    
    # Encontrar el directorio fuente del daemon
    daemon_source_dir = _get_daemon_source_dir()
    if not daemon_source_dir:
        return {
            "success": False, 
            "error": "No se encontró el directorio del daemon en el paquete heren-mcp. "
                     "Reinstala el paquete."
        }
    
    # Crear estructura de directorios en el proyecto
    addon_dir = os.path.join(project_path, "addons", "heren", "daemon")
    os.makedirs(addon_dir, exist_ok=True)
    
    # Copiar TODOS los archivos .gd del daemon (principal + módulos)
    copied_files = []
    try:
        for filename in os.listdir(daemon_source_dir):
            if filename.endswith(".gd"):
                source_path = os.path.join(daemon_source_dir, filename)
                dest_path = os.path.join(addon_dir, filename)
                shutil.copy2(source_path, dest_path)
                copied_files.append(filename)
                logger.info(f"[SetupDaemon] Copiado: {filename}")
    except Exception as e:
        return {"success": False, "error": f"Error copiando archivos del daemon: {e}"}
    
    # NOTA: NO registramos autoload porque heren_daemon.gd extiende SceneTree
    # y causaría conflicto al ejecutar el proyecto. El daemon se ejecuta via
    # --script desde el directorio del proyecto.
    
    return {
        "success": True,
        "project_path": project_path,
        "daemon_path": os.path.join(addon_dir, "heren_daemon.gd"),
        "copied_files": copied_files,
        "message": (
            f"Daemon y {len(copied_files)-1} módulos copiados al proyecto. "
            "Ahora puedes abrir una sesión con session('open', project_path='...')"
        )
    }


def _action_create(session_manager, project_path: str, project_name: str, 
                   renderer: str = "forward_plus", viewport_width: int = 1280,
                   viewport_height: int = 720, window_mode: str = "windowed",
                   fps_max: int = 0, vsync: bool = True, **kwargs) -> dict:
    """
    Crear un nuevo proyecto Godot.
    
    NO requiere sesión activa. Funciona en modo standalone.
    Si hay sesión activa, usa el daemon. Si no, crea el proyecto manualmente.
    """
    project_path = os.path.abspath(project_path)
    
    # Verificar que el directorio padre existe
    parent_dir = os.path.dirname(project_path)
    if not os.path.exists(parent_dir):
        return {"success": False, "error": f"Directorio padre no existe: {parent_dir}"}
    
    # Crear directorio del proyecto
    try:
        os.makedirs(project_path, exist_ok=True)
    except Exception as e:
        return {"success": False, "error": f"Error creando directorio: {e}"}
    
    # Validar renderer
    renderer_mapping = {
        "forward_plus": "forward_plus",
        "mobile": "mobile",
        "compatibility": "gl_compatibility"
    }
    renderer_value = renderer_mapping.get(renderer, "forward_plus")
    
    # Validar window_mode
    mode_mapping = {
        "windowed": 0,
        "minimized": 1,
        "maximized": 2,
        "fullscreen": 3,
        "exclusive_fullscreen": 4
    }
    mode_value = mode_mapping.get(window_mode, 0)
    
    # Generar project.godot
    config = []
    config.append("; Engine Configuration File.")
    config.append("; Godot version: 4.x")
    config.append("; Check latest documentation for updated values.")
    config.append("")
    config.append("[application]")
    config.append(f'config/name="{project_name}"')
    config.append(f'config/features=PackedStringArray("4.2", "{renderer_value}")')
    config.append("")
    config.append("[display]")
    config.append(f"window/size/viewport_width={viewport_width}")
    config.append(f"window/size/viewport_height={viewport_height}")
    config.append(f"window/size/mode={mode_value}")
    config.append(f"window/vsync/vsync_mode={1 if vsync else 0}")
    config.append("")
    config.append("[rendering]")
    config.append(f'renderer/rendering_method="{renderer_value}"')
    config.append('textures/canvas_textures/default_texture_filter="linear"')
    config.append("")
    config.append("[dotnet]")
    config.append(f'project/assembly_name="{project_name}"')
    
    if fps_max > 0:
        config.append("")
        config.append("[application]")
        config.append(f"run/max_fps={fps_max}")
    
    content = "\n".join(config)
    
    # Guardar archivo
    project_file = os.path.join(project_path, "project.godot")
    try:
        with open(project_file, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        return {"success": False, "error": f"Error escribiendo project.godot: {e}"}
    
    logger.info(f"[ProjectCreate] Proyecto creado: {project_path}")
    
    # Configurar el daemon automáticamente
    logger.info("[ProjectCreate] Configurando daemon...")
    setup_result = _action_setup_daemon(session_manager, project_path=project_path)
    
    result = {
        "success": True,
        "project_path": project_path,
        "project_name": project_name,
        "renderer": renderer,
        "viewport_width": viewport_width,
        "viewport_height": viewport_height,
        "window_mode": window_mode,
    }
    
    if setup_result.get("success", False):
        result["daemon_setup"] = "success"
        result["message"] = (
            f"Proyecto '{project_name}' creado exitosamente. "
            f"Daemon configurado automáticamente. "
            f"Abre una sesión con: session('open', project_path='{project_path}')"
        )
    else:
        result["daemon_setup"] = "failed"
        result["daemon_setup_error"] = setup_result.get("error", "Unknown error")
        result["message"] = (
            f"Proyecto '{project_name}' creado exitosamente. "
            f"NOTA: El daemon no se configuró automáticamente: {setup_result.get('error', 'Unknown error')}. "
            f"Ejecuta manualmente: project('setup_daemon', project_path='{project_path}')"
        )
    
    return result


def _action_setting(session_manager, session, setting_name: str = None, value = None, **kwargs) -> dict:
    """Leer o escribir un project setting."""
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if not daemon:
        return {"success": False, "error": "Daemon no disponible"}
    
    if value is not None:
        # Write
        return daemon.call("set_project_setting", {
            "setting_name": setting_name,
            "value": value
        })
    else:
        # Read
        return daemon.call("get_project_setting", {"setting_name": setting_name})


def _action_autoload(session_manager, session, autoload_name: str, script_path: str, **kwargs) -> dict:
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("add_autoload", {
            "autoload_name": autoload_name,
            "script_path": script_path
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_remove_autoload(session_manager, session, autoload_name: str, **kwargs) -> dict:
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("remove_autoload", {"autoload_name": autoload_name})
    return {"success": False, "error": "Daemon no disponible"}


def _action_shader_global(session_manager, session, global_name: str, value, **kwargs) -> dict:
    if not session:
        return {"success": False, "error": "No hay sesión activa. Proporcione session_id."}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("set_shader_global", {
            "global_name": global_name,
            "value": value
        })
    return {"success": False, "error": "Daemon no disponible"}
