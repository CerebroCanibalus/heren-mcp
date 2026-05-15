"""
Heren MCP Server

Servidor MCP usando FastMCP para OpenCode.
Expone las tools de Heren Godot MCP.

FILOSOFÍA DE TOOLS:
- Centralizadas: 10 tools que agrupan TODO
- Modulares: múltiples modos via parámetro 'action'
- Potentes: Godot hace el trabajo pesado

Tools:
1. session   - Gestión de sesiones (open, close, list, info, health)
2. scene     - Operaciones de escenas (get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, add_ext_resource, set_editable_paths)
3. node      - Operaciones de nodos (add, remove, set_prop, get_prop, duplicate, rename, move, array_append, array_remove)
4. batch     - Ejecución batch de múltiples operaciones
5. resource  - Recursos .tres y .gd (create, read, update, delete, list, create_script, read_script, edit_script)
6. animation - Animaciones (create_player, create, add_track, add_key, state_machine)
7. skeleton  - Esqueletos (create, add_bone, set_rest, skin, attachment)
8. shader    - Shaders (create, edit, validate, material, uniform)
9. tilemap   - TileMaps (inspect_set, inspect_map, set_cell, terrain, pattern)
10. project  - Configuración (create, setting, autoload, remove_autoload, shader_global)
11. debug    - Depuración (breakpoint, stack_trace, watch, console, run_scene, stop_scene, get_editor_errors, execute_editor_script)
12. validate - Validación (scene, script, node, resource)
13. signal   - Señales entre nodos (connect, disconnect, list, set_script)
14. global   - Configuración global (autoload, project_setting, shader_global)
15. index    - Índice de tools (list, info, example)

Filosofia: Poder. Eficiencia. Rapidez.
"""

import argparse
import logging
import sys

from typing import Any, Optional

from fastmcp import FastMCP

from heren.core.session_manager import get_session_manager
from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool
from heren.tools.node_tool import node_tool
from heren.tools.batch_tools import heren_batch
from heren.tools.resource_tool import resource
from heren.tools.animation_tool import animation
from heren.tools.skeleton_tool import skeleton
from heren.tools.shader_tool import shader
from heren.tools.tilemap_tool import tilemap
from heren.tools.project_tool import project
from heren.tools.debug_tool import debug
from heren.tools.validate_tool import validate
from heren.tools.signal_tool import signal_tool as _signal_tool_impl
from heren.tools.global_tool import global_tool as _global_tool_impl
from heren.tools.tools_index import list_tools, get_tool_info, get_action_example

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# Crear servidor MCP
mcp = FastMCP("heren-godot")


# ============================================================
# TOOL 1: SESSION TOOL (Gestión de Sesiones)
# ============================================================

@mcp.tool()
def session(
    action: str,
    project_path: str = None,
    session_id: str = None,
    godot_path: str = None,
    use_daemon: bool = True,
) -> dict:
    """
    Tool centralizada para TODAS las operaciones de sesión.
    
    FILOSOFÍA: Una tool, múltiples modos. Centralizada pero modular.
    
    Args:
        action: Operación a realizar
            - "open": Inicia nueva sesión con Godot
            - "close": Cierra sesión existente
            - "list": Lista todas las sesiones activas
            - "info": Obtiene información de una sesión
            - "health": Verifica salud del daemon
        project_path: (para action="open") Ruta absoluta al proyecto Godot
        session_id: (para action="close|info|health") ID de sesión
        godot_path: (opcional) Ruta al ejecutable Godot
        use_daemon: (para action="open") Si True, usa GodotDaemon WebSocket (recomendado)
    
    Returns:
        - open: {"success": True, "session_id": "...", "project_path": "...", "daemon_active": True}
        - close: {"success": True}
        - list: {"success": True, "count": 2, "sessions": [{"id": "...", "project": "..."}]}
        - info: {"success": True, "session": {"id": "...", "daemon_active": True, ...}}
        - health: {"success": True, "status": "healthy", "fps": 60, ...}
    
    Examples:
        # Abrir sesión (inicia daemon automáticamente)
        session("open", project_path="D:/MiJuego")
        
        # Cerrar sesión
        session("close", session_id="abc123")
        
        # Listar sesiones
        session("list")
        
        # Ver info
        session("info", session_id="abc123")
        
        # Health check del daemon
        session("health", session_id="abc123")
    """
    return session_tool(action, project_path, session_id, godot_path, use_daemon)


# ============================================================
# TOOL 2: SCENE TOOL (Operaciones de Escenas)
# ============================================================

@mcp.tool()
def scene(
    action: str,
    session_id: str,
    scene_path: str = None,
    output_path: str = None,
    resolution: tuple = (1920, 1080),
    wait_frames: int = 3,
    format: str = "png",
    quality: float = 0.9,
    root_type: str = None,
    root_name: str = None,
) -> dict:
    """
    Tool centralizada para TODAS las operaciones de escenas.
    
    CON DAEMON: Operaciones en ~20ms (cache en RAM)
    SIN DAEMON: Fallback a scripts temporales (~370ms)
    
    Args:
        action: Operación a realizar
            - "get_tree": Obtiene árbol de nodos de la escena
            - "save": Guarda escena en disco
            - "load": Carga escena en cache del daemon (rápido)
            - "unload": Descarga escena del cache
            - "list_loaded": Lista escenas cargadas en cache
            - "screenshot": Captura screenshot con rendering GPU
            - "create": Crea nueva escena (acepta root_type, root_name)
            - "set_editable_paths": Marca paths de instancias como editables
        session_id: ID de sesión activa
        scene_path: Ruta a la escena (res://Player.tscn)
        output_path: (para screenshot) Ruta de salida. None = temp
        resolution: (para screenshot) Resolución
        wait_frames: (para screenshot) Frames a esperar
        format: (para screenshot) "png", "jpeg" o "webp"
        quality: (para screenshot) Calidad 0.0-1.0
        **kwargs: Parámetros adicionales como root_type, root_name para create
    
    Returns:
        - get_tree: {"success": True, "tree": {"name": "Root", "type": "Node2D", "children": [...]}}
        - save: {"success": True}
        - load: {"success": True, "cached": True, "node_count": 15}
        - unload: {"success": True}
        - list_loaded: {"success": True, "scenes": [{"path": "...", "type": "Node2D"}]}
        - screenshot: {"success": True, "image_path": "...", "resolution": [1920, 1080]}
        - set_editable_paths: {"success": True, "paths": [...], "editable": true}
    
    Examples:
        # Obtener árbol de nodos
        scene("get_tree", session_id="abc", scene_path="res://Player.tscn")
        
        # Crear escena con tipo específico
        scene("create", session_id="abc", scene_path="res://Level.tscn", root_type="Node3D", root_name="Main")
        
        # Screenshot con rendering GPU
        scene("screenshot", session_id="abc", scene_path="res://Player.tscn", resolution=(1920, 1080))
    """
    return scene_tool(action, session_id, scene_path, output_path, resolution, wait_frames, format, quality, root_type=root_type, root_name=root_name)


# ============================================================
# TOOL 3: NODE TOOL (Operaciones de Nodos)
# ============================================================

@mcp.tool()
def node(
    action: str,
    session_id: str,
    scene_path: str,
    node_path: str = None,
    node_type: str = None,
    node_name: str = None,
    properties: dict = None,
    property_name: str = None,
    value: Any = None,
    new_name: str = None,
    new_parent: str = None,
    index: int = -1,
) -> dict:
    """
    Tool centralizada para TODAS las operaciones de nodos.
    
    CON DAEMON: ~20ms por operación
    SIN DAEMON: Fallback automático a scripts (~370ms)
    
    Args:
        action: Operación a realizar
            - "add": Añade nodo a la escena
            - "remove": Elimina nodo
            - "set_prop": Cambia propiedad del nodo
            - "get_prop": Obtiene propiedad del nodo
            - "duplicate": Duplica nodo
            - "rename": Renombra nodo
            - "move": Mueve nodo a otro padre
            - "array_append": Añade elemento a array property
            - "array_remove": Remueve elemento de array property
        session_id: ID de sesión activa
        scene_path: Ruta a la escena (res://Player.tscn)
        node_path: Ruta al nodo (ej: "Player/Sprite2D")
        node_type: (para add) Tipo de nodo (Sprite2D, Area2D, etc.)
        node_name: (para add) Nombre del nuevo nodo
        properties: (para add) Propiedades iniciales {"position": {"x": 100, "y": 200}}
        property_name: (para set_prop/get_prop/array_*) Nombre de la propiedad
        value: (para set_prop/array_append/array_remove) Nuevo valor
        new_name: (para rename) Nuevo nombre
        new_parent: (para move) Nueva ruta padre
        index: (para array_remove) Índice del elemento a remover
    
    Returns:
        - add: {"success": True, "node_path": "Player/Sprite2D"}
        - remove: {"success": True}
        - set_prop: {"success": True}
        - get_prop: {"success": True, "value": ...}
        - duplicate: {"success": True, "node_path": "..."}
        - rename: {"success": True}
        - move: {"success": True}
        - array_append: {"success": True, "array_size": N}
        - array_remove: {"success": True, "removed_value": ...}
    
    Examples:
        # Añadir Sprite2D
        node("add", session_id="abc", scene_path="res://Player.tscn",
             node_path=".", node_type="Sprite2D", node_name="Hat",
             properties={"position": {"x": 0, "y": -50}})
        
        # Cambiar posición
        node("set_prop", session_id="abc", scene_path="res://Player.tscn",
             node_path="Player", property_name="position", value={"x": 100, "y": 200})
        
        # Eliminar nodo
        node("remove", session_id="abc", scene_path="res://Player.tscn",
             node_path="Player/OldNode")
        
        # Añadir a array
        node("array_append", session_id="abc", scene_path="res://Player.tscn",
             node_path="Player", property_name="inventory", value="sword")
    """
    return node_tool(action, session_id, scene_path, node_path, node_type, node_name,
                     properties, property_name, value, new_name, new_parent, index)


# ============================================================
# TOOL 4: BATCH TOOL (Operaciones en Batch)
# ============================================================

@mcp.tool()
def batch(
    session_id: str,
    operations: list[dict],
    stop_on_error: bool = False,
) -> dict:
    """
    Ejecuta múltiples operaciones en batch optimizado.
    
    CON DAEMON: Envía todas las operaciones en UNA sola llamada WebSocket
    SIN DAEMON: Ejecuta secuencialmente via scripts
    
    PERFECTO para:
    - Crear escenas complejas (múltiples nodos)
    - Refactorizaciones (mover, renombrar, modificar)
    - Importaciones (crear estructura completa)
    
    Args:
        session_id: ID de sesión activa
        operations: Lista de operaciones
            Cada operación es un dict con:
            - "action": str - Tipo de operación (add, remove, set_prop, etc.)
            - "params": dict - Parámetros específicos
        stop_on_error: Si True, detiene en el primer error
    
    Returns:
        {
            "success": bool,
            "results": list[dict],  # Resultados de cada operación
            "errors": list[dict],   # Errores si los hubo
            "success_count": int,
            "error_count": int,
        }
    
    Example:
        batch(session_id="abc", operations=[
            {
                "action": "add",
                "params": {
                    "scene_path": "res://Player.tscn",
                    "parent_path": ".",
                    "node_type": "Sprite2D",
                    "node_name": "Body",
                    "properties": {"position": {"x": 100, "y": 200}}
                }
            },
            {
                "action": "add",
                "params": {
                    "scene_path": "res://Player.tscn",
                    "parent_path": "Body",
                    "node_type": "CollisionShape2D",
                    "node_name": "Hitbox"
                }
            },
            {
                "action": "save",
                "params": {"scene_path": "res://Player.tscn"}
            }
        ])
    """
    return heren_batch(session_id, operations, stop_on_error)


# ============================================================
# TOOL 5: RESOURCE TOOL (Gestión de Recursos)
# ============================================================

@mcp.tool()
def resource_tool(
    action: str,
    resource_path: str = None,
    resource_type: str = "Resource",
    properties: dict = None,
    directory: str = "res://",
    extension: str = "",
    recursive: bool = False,
) -> dict:
    """
    Tool centralizada para TODOS los recursos Godot (.tres, materiales, etc.)
    
    Actions:
        - "create": Crear nuevo recurso .tres
        - "read": Leer recurso existente
        - "update": Actualizar propiedades
        - "delete": Eliminar recurso
        - "list": Listar recursos del proyecto
    
    Args:
        action: Operación a realizar
        resource_path: Ruta al recurso (res://materials/my_material.tres)
        resource_type: Tipo de recurso (ShaderMaterial, PhysicsMaterial, etc.)
        properties: Propiedades del recurso
        directory: Directorio para listar
        extension: Filtro de extensión
        recursive: Buscar recursivamente
    
    Returns:
        Dict con resultado de la operación
    """
    return resource(action=action, resource_path=resource_path, resource_type=resource_type,
                   properties=properties, directory=directory, extension=extension, recursive=recursive)


# ============================================================
# TOOL 6: ANIMATION TOOL (Animaciones y State Machines)
# ============================================================

@mcp.tool()
def animation_tool(
    action: str,
    scene_path: str = None,
    player_path: str = None,
    anim_name: str = None,
    length: float = 1.0,
    loop: bool = False,
    track_type: str = "value",
    node_path: str = None,
    property: str = None,
    track_idx: int = 0,
    time: float = 0.0,
    value = None,
    transition: float = 1.0,
    states: list = None,
    transitions: list = None,
) -> dict:
    """
    Tool centralizada para animaciones y state machines.
    
    Actions:
        - "create_player": Crear AnimationPlayer
        - "create": Crear Animation
        - "add_track": Añadir track
        - "add_key": Añadir keyframe
        - "state_machine": Crear AnimationNodeStateMachine
    
    Args:
        action: Operación a realizar
        scene_path: Ruta a la escena
        player_path: Ruta al AnimationPlayer
        anim_name: Nombre de la animación
        length: Duración en segundos
        loop: Si loop o no
        track_type: Tipo de track (value, position_3d, rotation_3d, scale_3d, method)
        node_path: Ruta al nodo a animar
        property: Propiedad a animar
        track_idx: Índice del track
        time: Tiempo del keyframe
        value: Valor del keyframe
        transition: Curva de transición
        states: Lista de estados para state machine
        transitions: Lista de transiciones
    """
    return animation(action=action, scene_path=scene_path, player_path=player_path,
                    anim_name=anim_name, length=length, loop=loop, track_type=track_type,
                    node_path=node_path, property=property, track_idx=track_idx,
                    time=time, value=value, transition=transition, states=states,
                    transitions=transitions)


# ============================================================
# TOOL 7: SKELETON TOOL (Esqueletos 2D/3D)
# ============================================================

@mcp.tool()
def skeleton_tool(
    action: str,
    scene_path: str = None,
    parent_path: str = ".",
    skeleton_name: str = "Skeleton2D",
    is_3d: bool = False,
    skeleton_path: str = None,
    bone_name: str = None,
    rest_transform: dict = None,
    length: float = 32.0,
    bone_angle: float = 0.0,
    polygon_path: str = None,
    bone_weights: dict = None,
    attachment_name: str = "Attachment",
) -> dict:
    """
    Tool centralizada para esqueletos y rigging.
    
    Actions:
        - "create": Crear Skeleton2D/3D
        - "add_bone": Añadir hueso
        - "set_rest": Setear rest pose
        - "skin": Configurar skinning Polygon2D
        - "attachment": Añadir BoneAttachment3D
    
    Args:
        action: Operación a realizar
        scene_path: Ruta a la escena
        parent_path: Ruta al padre
        skeleton_name: Nombre del skeleton
        is_3d: True para Skeleton3D
        skeleton_path: Ruta al skeleton existente
        bone_name: Nombre del hueso
        rest_transform: Transform de rest (dict con x, y, z, rotation)
        length: Longitud del hueso (2D)
        bone_angle: Ángulo del hueso (2D)
        polygon_path: Ruta al Polygon2D para skinning
        bone_weights: Pesos de huesos para skinning
        attachment_name: Nombre del attachment
    """
    return skeleton(action=action, scene_path=scene_path, parent_path=parent_path,
                   skeleton_name=skeleton_name, is_3d=is_3d, skeleton_path=skeleton_path,
                   bone_name=bone_name, rest_transform=rest_transform, length=length,
                   bone_angle=bone_angle, polygon_path=polygon_path,
                   bone_weights=bone_weights, attachment_name=attachment_name)


# ============================================================
# TOOL 8: SHADER TOOL (Shaders y Materiales)
# ============================================================

@mcp.tool()
def shader_tool(
    action: str,
    session_id: str = None,
    shader_path: str = None,
    shader_type: str = "canvas_item",
    code: str = "",
    append: bool = False,
    scene_path: str = None,
    node_path: str = None,
    material_name: str = "",
    uniforms: dict = None,
    uniform_name: str = None,
    value = None,
) -> dict:
    """
    Tool centralizada para shaders y materiales.
    
    Actions:
        - "create": Crear .gdshader
        - "edit": Editar código de shader
        - "validate": Validar compilación
        - "material": Crear ShaderMaterial
        - "uniform": Setear uniform
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        shader_path: Ruta al shader
        shader_type: Tipo (canvas_item, spatial, particles)
        code: Código GDShader
        append: True para añadir al final
        scene_path: Ruta a la escena (para material/uniform)
        node_path: Ruta al nodo (para material/uniform)
        material_name: Nombre del material
        uniforms: Dict de uniforms
        uniform_name: Nombre del uniform
        value: Valor del uniform
    """
    return shader(action=action, session_id=session_id, shader_path=shader_path, shader_type=shader_type,
                 code=code, append=append, scene_path=scene_path, node_path=node_path,
                 material_name=material_name, uniforms=uniforms, uniform_name=uniform_name,
                 value=value)


# ============================================================
# TOOL 9: TILEMAP TOOL (TileMaps y TileSets)
# ============================================================

@mcp.tool()
def tilemap_tool(
    action: str,
    tileset_path: str = None,
    scene_path: str = None,
    tilemap_path: str = None,
    layer: int = 0,
    coords: dict = None,
    atlas_coords: dict = None,
    source_id: int = 0,
    alternative_tile: int = 0,
    cells: list = None,
    terrain_set: int = 0,
    terrain: int = 0,
    region: dict = None,
    pattern_name: str = "Pattern",
) -> dict:
    """
    Tool centralizada para TileMaps y TileSets.
    
    Actions:
        - "inspect_set": Inspeccionar TileSet
        - "inspect_map": Inspeccionar TileMap
        - "set_cell": Setear celda individual
        - "terrain": Aplicar terrain painting
        - "pattern": Crear/aplicar pattern
    
    Args:
        action: Operación a realizar
        tileset_path: Ruta al TileSet
        scene_path: Ruta a la escena
        tilemap_path: Ruta al TileMap
        layer: Índice de layer
        coords: Coordenadas de celda {x, y}
        atlas_coords: Coordenadas de atlas {x, y}
        source_id: ID de source
        alternative_tile: Tile alternativo
        cells: Lista de celdas para terrain
        terrain_set: Índice de terrain set
        terrain: Índice de terrain
        region: Región para pattern {x, y, w, h}
        pattern_name: Nombre del pattern
    """
    return tilemap(action=action, tileset_path=tileset_path, scene_path=scene_path,
                  tilemap_path=tilemap_path, layer=layer, coords=coords,
                  atlas_coords=atlas_coords, source_id=source_id,
                  alternative_tile=alternative_tile, cells=cells,
                  terrain_set=terrain_set, terrain=terrain, region=region,
                  pattern_name=pattern_name)


# ============================================================
# TOOL 10: PROJECT TOOL (Configuración del Proyecto)
# ============================================================

@mcp.tool()
def project_tool(
    action: str,
    setting_name: str = None,
    value = None,
    autoload_name: str = None,
    script_path: str = None,
    global_name: str = None,
    project_path: str = None,
    project_name: str = None,
    renderer: str = "forward_plus",
    viewport_width: int = 1280,
    viewport_height: int = 720,
    window_mode: str = "windowed",
    fps_max: int = 0,
    vsync: bool = True,
    scale_mode: str = "canvas_items",
) -> dict:
    """
    Tool centralizada para configuración del proyecto Godot.
    
    Actions:
        - "create": Crear nuevo proyecto Godot (configura daemon automáticamente)
        - "setup_daemon": Configurar daemon Heren en proyecto existente
        - "setting": Leer/escribir project setting
        - "autoload": Añadir autoload
        - "remove_autoload": Quitar autoload
        - "shader_global": Setear shader global
    
    Args:
        action: Operación a realizar
        project_path: (para create/setup_daemon) Ruta del proyecto
        project_name: (para create) Nombre del proyecto
        renderer: (para create) Renderer: "forward_plus", "mobile", "compatibility"
        viewport_width: (para create) Ancho de ventana
        viewport_height: (para create) Alto de ventana
        window_mode: (para create) Modo: "windowed", "fullscreen", "exclusive_fullscreen"
        fps_max: (para create) FPS máximo (0 = ilimitado)
        vsync: (para create) Activar VSync
        scale_mode: (para create) Modo de escala: "canvas_items", "viewport", "disabled"
        setting_name: Nombre del setting (ej: "display/window/size/viewport_width")
        value: Valor a escribir (None para leer)
        autoload_name: Nombre del autoload
        script_path: Ruta al script del autoload
        global_name: Nombre del shader global
    
    Returns:
        Dict con resultado de la operación
    """
    return project(action=action, setting_name=setting_name, value=value,
                  autoload_name=autoload_name, script_path=script_path,
                  global_name=global_name, project_path=project_path,
                  project_name=project_name, renderer=renderer,
                  viewport_width=viewport_width, viewport_height=viewport_height,
                  window_mode=window_mode, fps_max=fps_max, vsync=vsync,
                  scale_mode=scale_mode)


# ============================================================
# TOOL 11: DEBUG TOOL (Depuración)
# ============================================================

@mcp.tool()
def debug_tool(
    action: str,
    session_id: str = None,
    script_path: str = None,
    line: int = 0,
    variable_name: str = None,
    lines: int = 100,
    scene_path: str = None,
    script_code: str = None,
    context: dict = None,
    project_path: str = None,
    godot_path: str = None,
    timeout: int = 30,
    debug_collisions: bool = False,
    debug_paths: bool = False,
    debug_navigation: bool = False,
) -> dict:
    """
    Tool centralizada para depuración de escenas Godot.
    
    Soporta dos modos:
    1. Daemon mode (requiere daemon en editor): breakpoint, stack_trace, watch, console, stop_scene, get_editor_errors
    2. Subprocess mode (standalone): run_scene, execute_editor_script, check_script_syntax
    
    Actions:
        - "breakpoint": Setear/quitar breakpoint (requiere daemon)
        - "stack_trace": Obtener stack trace (requiere daemon)
        - "watch": Watch variable (requiere daemon)
        - "console": Capturar output de consola (requiere daemon)
        - "run_scene": Ejecutar escena vía subprocess (standalone)
        - "stop_scene": Detener ejecución (requiere daemon)
        - "get_editor_errors": Obtener errores del editor (requiere daemon)
        - "execute_editor_script": Ejecutar GDScript vía subprocess (standalone, soporta FileAccess, ClassDB, etc.)
        - "check_script_syntax": Verificar sintaxis GDScript vía subprocess (standalone)
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa (requerido para daemon mode, opcional para subprocess si se da project_path)
        script_path: Ruta al script (para breakpoint o check_script_syntax)
        line: Número de línea (para breakpoint)
        variable_name: Nombre de variable (para watch)
        lines: Cantidad de líneas de consola a capturar
        scene_path: Ruta a la escena (para run_scene, opcional)
        script_code: Código GDScript a ejecutar (para execute_editor_script)
        context: Variables de contexto (para execute_editor_script)
        project_path: Ruta al proyecto (para subprocess mode, alternativa a session_id)
        godot_path: Ruta al ejecutable de Godot (opcional, auto-detecta)
        timeout: Timeout en segundos (para subprocess, default 30)
        debug_collisions: Activar debug de colisiones (para run_scene)
        debug_paths: Activar debug de paths (para run_scene)
        debug_navigation: Activar debug de navegación (para run_scene)
    """
    return debug(action=action, session_id=session_id, script_path=script_path,
                line=line, variable_name=variable_name, lines=lines, scene_path=scene_path,
                script_code=script_code, context=context, project_path=project_path,
                godot_path=godot_path, timeout=timeout, debug_collisions=debug_collisions,
                debug_paths=debug_paths, debug_navigation=debug_navigation)


# ============================================================
# TOOL 12: VALIDATE TOOL (Validación)
# ============================================================

@mcp.tool()
def validate_tool(
    action: str,
    session_id: str = None,
    scene_path: str = None,
    script_path: str = None,
    node_path: str = None,
    resource_path: str = None,
) -> dict:
    """
    Tool centralizada para validación de escenas, scripts y recursos.
    
    Actions:
        - "scene": Validar archivo .tscn
        - "script": Validar script GDScript
        - "node": Validar nodo en escena
        - "resource": Validar recurso .tres
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        script_path: Ruta al script
        node_path: Ruta al nodo
        resource_path: Ruta al recurso
    """
    return validate(action=action, session_id=session_id, scene_path=scene_path,
                   script_path=script_path, node_path=node_path,
                   resource_path=resource_path)


# ============================================================
# TOOL 13: SIGNAL TOOL (Señales entre Nodos)
# ============================================================

@mcp.tool()
def signal(
    action: str,
    session_id: str,
    scene_path: str = "",
    from_node: str = "",
    signal_name: str = "",
    to_node: str = "",
    method: str = "",
    node_path: str = "",
    script_path: str = "",
) -> dict:
    """
    Tool centralizada para gestión de señales y scripts de nodos.
    
    Actions:
        - "connect": Conecta una señal de un nodo a un método de otro
        - "disconnect": Desconecta una señal previamente conectada
        - "list": Lista todas las señales (built-in y conectadas) de un nodo
        - "set_script": Asigna un script GDScript a un nodo
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        scene_path: Ruta a la escena
        from_node: Ruta del nodo emisor (para connect/disconnect/list)
        signal_name: Nombre de la señal (para connect/disconnect)
        to_node: Ruta del nodo receptor (para connect/disconnect)
        method: Nombre del método callback (para connect/disconnect)
        node_path: Ruta del nodo a modificar (para set_script)
        script_path: Ruta al script .gd (para set_script)
    
    Returns:
        Dict con resultado de la operación
    
    Examples:
        # Conectar señal body_entered de Area2D a método del Player
        signal("connect", session_id="abc", scene_path="res://Player.tscn",
               from_node="Player/Area2D", signal_name="body_entered",
               to_node="Player", method="_on_area_body_entered")
        
        # Listar señales de un nodo
        signal("list", session_id="abc", scene_path="res://Player.tscn",
               from_node="Player/Area2D")
        
        # Asignar script a un nodo
        signal("set_script", session_id="abc", scene_path="res://Player.tscn",
               node_path="Player", script_path="res://scripts/player.gd")
    """
    return _signal_tool_impl(
        action=action,
        session_id=session_id,
        scene_path=scene_path,
        from_node=from_node,
        signal_name=signal_name,
        to_node=to_node,
        method=method,
        node_path=node_path,
        script_path=script_path,
    )


# ============================================================
# TOOL 14: GLOBAL TOOL (Configuración Global del Proyecto)
# ============================================================

@mcp.tool()
def global_tool(
    action: str,
    session_id: str = "",
    autoload_name: str = "",
    script_path: str = "",
    setting_name: str = "",
    value = None,
    global_name: str = "",
) -> dict:
    """
    Tool centralizada para configuración global del proyecto Godot.
    
    Gestiona autoloads, project settings y shader globals.
    Puede funcionar en modo directo (editando project.godot) o via daemon.
    
    Actions:
        - "autoload": Añade, quita o lista autoloads
            - Añadir: proporciona autoload_name + script_path
            - Quitar: proporciona solo autoload_name
            - Listar: no proporciones autoload_name
        - "project_setting": Lee o escribe settings de project.godot
            - Leer: proporciona solo setting_name
            - Escribir: proporciona setting_name + value
        - "shader_global": Gestiona shader globals (requiere daemon)
    
    Args:
        action: Operación a realizar
        session_id: ID de sesión activa
        autoload_name: Nombre del autoload
        script_path: Ruta al script del autoload
        setting_name: Nombre del setting (formato "section/key")
        value: Valor a escribir (None para leer)
        global_name: Nombre del shader global
    
    Returns:
        Dict con resultado de la operación
    
    Examples:
        # Añadir autoload
        global_tool("autoload", session_id="abc", autoload_name="GameManager",
                   script_path="res://autoloads/game_manager.gd")
        
        # Listar autoloads
        global_tool("autoload", session_id="abc")
        
        # Cambiar resolución
        global_tool("project_setting", session_id="abc",
                   setting_name="display/window/size/viewport_width", value=1920)
    """
    return _global_tool_impl(
        action=action,
        session_id=session_id,
        autoload_name=autoload_name,
        script_path=script_path,
        setting_name=setting_name,
        value=value,
        global_name=global_name,
    )


# ============================================================
# TOOL 15: INDEX (Índice de Tools)
# ============================================================

@mcp.tool()
def index(
    action: str = "list",
    tool_name: str = None,
    action_name: str = None,
) -> dict:
    """
    Índice de todas las tools disponibles en Heren MCP.
    
    Usa esta tool para descubrir qué tools existen y cómo usarlas.
    
    Actions:
        - "list": Lista todas las tools disponibles
        - "info": Obtiene información detallada de una tool
        - "example": Obtiene un ejemplo de uso
    
    Args:
        action: Operación a realizar
        tool_name: (para info/example) Nombre de la tool
        action_name: (para example) Nombre del action
    
    Returns:
        Dict con información de las tools
    
    Examples:
        # Listar todas las tools
        index(action="list")
        
        # Info de una tool
        index(action="info", tool_name="scene")
        
        # Ejemplo de uso
        index(action="example", tool_name="scene", action_name="create")
    """
    if action == "list":
        return list_tools()
    
    elif action == "info":
        if not tool_name:
            return {"success": False, "error": "tool_name requerido para action='info'"}
        info = get_tool_info(tool_name)
        if "error" in info:
            return {"success": False, "error": info["error"]}
        return {"success": True, "tool": tool_name, **info}
    
    elif action == "example":
        if not tool_name or not action_name:
            return {"success": False, "error": "tool_name y action_name requeridos para action='example'"}
        example = get_action_example(tool_name, action_name)
        return {"success": True, "tool": tool_name, "action": action_name, "example": example}
    
    else:
        return {"success": False, "error": f"Action no soportada: '{action}'. Use: list, info, example"}


def main():
    parser = argparse.ArgumentParser(description="Heren Godot MCP Server")
    parser.add_argument("--project-path", help="Ruta al proyecto Godot (opcional)")
    
    args = parser.parse_args()
    
    logger.info("=" * 60)
    logger.info("HEREN MCP Server v2.0 - GodotDaemon Edition")
    logger.info("Filosofia: Centralizado. Modular. Potente.")
    logger.info("=" * 60)
    
    if args.project_path:
        result = session_tool("open", project_path=args.project_path)
        if result.get("success"):
            logger.info(f"Sesion iniciada: {result['session_id']}")
        else:
            logger.error(f"Error iniciando sesion: {result.get('error')}")
    
    # Iniciar servidor MCP
    logger.info("Iniciando servidor MCP...")
    mcp.run()


if __name__ == "__main__":
    main()
