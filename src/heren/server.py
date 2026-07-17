"""
Heren MCP Server

Servidor MCP usando FastMCP para OpenCode.
Expone las tools de Heren Godot MCP.

FILOSOFÍA DE TOOLS:
- Centralizadas: 14 tools que agrupan TODO
- Modulares: múltiples modos via parámetro 'action'  
- Potentes: GodotDaemon hace el trabajo pesado
- Sin fallback: GodotDaemon es el UNICO modo

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

Filosofia: Poder. Eficiencia. Rapidez.
"""

import argparse
import logging
import os
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
) -> dict:
    """
    Gestión de sesiones Godot. Actions: open(project_path, godot_path) | close(session_id) | list | info(session_id) | health(session_id)
    """
    return session_tool(action, project_path, session_id, godot_path)


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
    Escenas: get_tree|save|load|unload|list_loaded|screenshot(output_path,resolution,format,quality)|create(root_type,root_name)|set_editable_paths
    scene_path: res://ruta.tscn
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
    Nodos: add(properties) | remove | set_prop(property_name,value) | get_prop | duplicate | rename(new_name) | move(new_parent) | array_append(value) | array_remove(index/value)
    node_path: ruta al nodo, node_type: Sprite2D|Area2D|..., properties: dict inicial
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
    Multi-operación en 1 llamada. operations: [{action, params}]. stop_on_error: True para abortar en error.
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
    Recursos .tres y scripts .gd. Actions: create|read|update|delete|list|create_script|read_script|edit_script
    resource_path: res://ruta, resource_type: ShaderMaterial|PhysicsMaterial|...
    """
    return resource(action=action, resource_path=resource_path, resource_type=resource_type,
                   properties=properties, directory=directory, extension=extension, recursive=recursive)


# ============================================================
# TOOL 6: ANIMATION TOOL (Animaciones y State Machines)
# ============================================================

@mcp.tool()
def animation_tool(
    action: str,
    session_id: str = None,
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
    Animaciones. Actions: create_player|create|add_track|add_key|state_machine
    player_path: ruta AnimationPlayer, anim_name, track_type: value|position_3d|rotation_3d|scale_3d|method
    states/transitions para state_machine
    """
    return animation(action=action, session_id=session_id, scene_path=scene_path, player_path=player_path,
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
    session_id: str = None,
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
    Esqueletos 2D/3D. Actions: create(is_3d) | add_bone(length,angle) | set_rest(rest_transform) | skin | attachment
    skeleton_path, bone_name, rest_transform: dict{x,y,z,rotation}
    """
    return skeleton(action=action, session_id=session_id, scene_path=scene_path, parent_path=parent_path,
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
    Shaders y materiales. Actions: create|edit|validate|material(uniforms)|uniform(name,value)
    shader_type: canvas_item|spatial|particles, shader_path: res://.gdshader
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
    session_id: str = None,
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
    TileMaps/TileSets. Actions: inspect_set|inspect_map|set_cell(atlas_coords)|terrain|pattern
    coords{x,y}, atlas_coords{x,y}, layer, source_id, cells para terrain
    """
    return tilemap(action=action, session_id=session_id, tileset_path=tileset_path, scene_path=scene_path,
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
    session_id: str = None,
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
    Config proyecto Godot. Actions: create|setup_daemon|setting|autoload|remove_autoload|shader_global
    create: project_path/name/renderer(forward_plus|mobile|compatibility)/viewport_width/height/window_mode/fps_max/vsync
    setting: "display/window/size/viewport_width"
    """
    return project(action=action, session_id=session_id, setting_name=setting_name, value=value,
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
    Depuración. Actions: breakpoint(line)|stack_trace|watch(variable)|console(lines)|run_scene(scene_path)|stop_scene|get_editor_errors|execute_editor_script(script_code,context)|check_script_syntax
    Daemon mode: breakpoint/stack_trace/watch/console/stop_scene/get_editor_errors | Subprocess: run_scene/execute_editor_script/check_script_syntax
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
    Validación. Actions: scene|script|node|resource. Verifica integridad de archivos Godot.
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
    Señales y scripts entre nodos. Actions: connect(signal_name,from_node,to_node,method)|disconnect|list|set_script(script_path)
    CONNECT_PERSIST flags las señales para que pack() las serialice nativamente en save.
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
    Config global del proyecto Godot. Actions: autoload(name,script_path)|project_setting(name,value)|shader_global(name,value)
    setting: "display/window/size/viewport_width" en project.godot. autoload sin name lista autoloads.
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


def main():
    parser = argparse.ArgumentParser(description="Heren Godot MCP Server")
    parser.add_argument("--project-path", help="Ruta al proyecto Godot (opcional)")
    parser.add_argument("--transport", default="stdio", help="Transporte MCP: stdio, http, sse")
    parser.add_argument("--host", default="0.0.0.0", help="Host para transporte HTTP/SSE")
    parser.add_argument("--port", type=int, default=8000, help="Puerto para transporte HTTP/SSE")
    
    args = parser.parse_args()
    
    logger.info("=" * 60)
    logger.info("HEREN MCP Server v2.0 - GodotDaemon Edition")
    logger.info("Filosofia: Centralizado. Modular. Potente.")
    logger.info("=" * 60)
    
    # Proyecto por defecto para discovery: crear uno vacio si no existe
    project_path = args.project_path or os.environ.get("HEREN_PROJECT_PATH")
    if project_path:
        result = session_tool("open", project_path=project_path)
        if result.get("success"):
            logger.info(f"Sesion iniciada: {result['session_id']}")
        else:
            logger.error(f"Error iniciando sesion: {result.get('error')}")
    
    # Iniciar servidor MCP
    logger.info(f"Iniciando servidor MCP (transport={args.transport})...")
    if args.transport == "stdio":
        mcp.run()
    elif args.transport == "http":
        mcp.run(transport="http", host=args.host, port=args.port)
    elif args.transport == "sse":
        mcp.run(transport="sse", host=args.host, port=args.port)
    else:
        raise ValueError(f"Transporte desconocido: {args.transport}")


if __name__ == "__main__":
    main()
