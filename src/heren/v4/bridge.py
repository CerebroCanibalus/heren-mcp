"""Heren MCP v4 - Bridge server (FastMCP entry).

OpenCode (MCP stdio) <-> this server <-> EditorPlugin v4 (WebSocket).

The 14 tools mirror the v3 API (same names/actions) so agents keep working,
but there is no session_id: the connected editor IS the session. Session
tool manages which project the editor is open on and auto-launches Godot.

Run: python -m heren.v4.bridge
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from typing import Any

from fastmcp import FastMCP

from heren.v4 import godot_launcher
from heren.v4.ws_server import WsServer, unwrap_result

logging.basicConfig(level=logging.INFO, stream=sys.stdout)
logger = logging.getLogger(__name__)

mcp = FastMCP("heren-godot-v4")

# ---- shared state --------------------------------------------------------

_ws: WsServer | None = None


def _ws_server() -> WsServer:
    global _ws
    if _ws is None:
        port = int(os.environ.get("HEREN_MCP_PORT", "9099"))
        _ws = WsServer(port=port)
    return _ws


async def _tool(tool_name: str, args: dict[str, Any] | None = None,
          project_path: str | None = None) -> dict[str, Any]:
    """Send a tool call to the editor and return the result dict."""
    try:
        coro = _ws_server().call_tool(tool_name, args, project_path)
        resp = await coro
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"bridge call failed: {e}"}
    return unwrap_result(resp)


def _require_editor(project_path: str | None = None) -> tuple[bool, str]:
    """Ensure an editor is connected; auto-launch if possible."""
    if _ws_server().has_editor(project_path):
        return True, ""
    if not project_path:
        # Any connected editor works.
        if _ws_server().has_editor():
            return True, ""
        project_path = godot_launcher.read_last_project(project_path or "")
    if not project_path or not os.path.isdir(project_path):
        return False, "no editor connected and no project_path given"
    ok, msg = godot_launcher.launch_editor(project_path, _ws_server().port)
    if not ok:
        return False, msg
    return True, f"launched editor ({msg})"


# ============================================================
# SESSION TOOL
# ============================================================


@mcp.tool()
async def session(
    action: str,
    project_path: str | None = None,
    godot_path: str | None = None,
) -> dict:
    """
    Gestión de sesiones v4. Actions: open(project_path, godot_path) | list | info(project_path) | health
    open: lanza el editor Godot con el plugin en el proyecto dado (auto-launch).
    list: proyectos con editor vivo conectado. info/health: estado.
    """
    if action == "open":
        if not project_path:
            return {"ok": False, "error": "project_path required"}
        ok, msg = godot_launcher.launch_editor(project_path, _ws_server().port, godot_path or "")
        return {"ok": ok, "message": msg, "project_path": project_path,
                "daemon_active": _ws_server().has_editor(project_path),
                "session_id": project_path}
    if action == "list":
        return {"ok": True, "sessions": _ws_server().connected_projects(),
                "count": len(_ws_server().connected_projects())}
    if action == "info":
        projects = _ws_server().connected_projects()
        if project_path:
            projects = [p for p in projects if p["project_path"] == project_path]
        if not projects:
            return {"ok": False, "error": "no editor connected" + (f": {project_path}" if project_path else "")}
        return {"ok": True, "session": projects[0]}
    if action == "health":
        return {"ok": True, "editors": _ws_server().connected_projects(),
                "active": len(_ws_server().connected_projects()) > 0}
    return {"ok": False, "error": f"unknown action: {action}"}


# ============================================================
# SCENE TOOL
# ============================================================


@mcp.tool()
async def scene(
    action: str,
    project_path: str | None = None,
    scene_path: str | None = None,
    output_path: str | None = None,
    root_type: str | None = None,
    root_name: str | None = None,
) -> dict:
    """
    Escenas (v4): get_tree|save|load|unload|list_loaded|create(root_type,root_name)|get_edited_scene_root|get_open_scenes
    scene_path: res://ruta.tscn. project_path opcional (auto-launch si no hay editor).
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"scene_path": scene_path, "output_path": output_path,
            "root_type": root_type, "root_name": root_name}
    return await _tool(f"scene/{action}", args, project_path)


# ============================================================
# NODE TOOL
# ============================================================


@mcp.tool()
async def node(
    action: str,
    project_path: str | None = None,
    node_path: str | None = None,
    node_type: str | None = None,
    node_name: str | None = None,
    properties: dict | None = None,
    property_name: str | None = None,
    value: Any = None,
    new_name: str | None = None,
    new_parent: str | None = None,
    index: int = -1,
) -> dict:
    """
    Nodos (v4): add(properties) | remove | set_prop(property_name,value) | set_props | get_prop | get_info | get_children | find | duplicate | rename(new_name) | move(new_parent) | set_owner | reorder | array_append | array_remove
    node_path: ruta al nodo en la escena viva. node_type: Sprite2D|Area2D|...
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"node_path": node_path, "node_type": node_type, "node_name": node_name,
            "properties": properties, "property_name": property_name, "value": value,
            "new_name": new_name, "new_parent": new_parent, "index": index}
    return await _tool(f"node/{action}", args, project_path)


# ============================================================
# RESOURCE TOOL
# ============================================================


@mcp.tool()
async def resource_tool(
    action: str,
    project_path: str | None = None,
    resource_path: str | None = None,
    resource_type: str = "Resource",
    properties: dict | None = None,
    directory: str = "res://",
    extension: str = "",
    recursive: bool = False,
    script_path: str | None = None,
    content: str | None = None,
    append: bool = False,
    template: str = "",
) -> dict:
    """
    Recursos .tres y scripts .gd (v4). Actions: create|read|update|delete|list|create_script|read_script|edit_script
    resource_path: res://ruta, resource_type: ShaderMaterial|PhysicsMaterial|...
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"resource_path": resource_path, "resource_type": resource_type,
            "properties": properties, "directory": directory, "extension": extension,
            "recursive": recursive, "script_path": script_path,
            "content": content, "append": append, "template": template}
    return await _tool(f"resource/{action}", args, project_path)


# ============================================================
# PROJECT TOOL
# ============================================================


@mcp.tool()
async def project_tool(
    action: str,
    project_path: str | None = None,
    setting_name: str | None = None,
    value: Any = None,
    autoload_name: str | None = None,
    script_path: str | None = None,
    global_name: str | None = None,
    type: str | None = None,
    action_name: str | None = None,
    event: dict | None = None,
) -> dict:
    """
    Config proyecto (v4). Actions: setting(setting_name,value opcional get/set) | autoload(autoload_name,script_path) | remove_autoload | input_map(type,action_name,event) | shader_global(global_name,value)
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"setting_name": setting_name, "value": value,
            "autoload_name": autoload_name, "script_path": script_path,
            "global_name": global_name, "type": type,
            "action_name": action_name, "event": event}
    return await _tool(f"project/{action}", args, project_path)


# ============================================================
# SHADER TOOL
# ============================================================


@mcp.tool()
async def shader_tool(
    action: str,
    project_path: str | None = None,
    shader_path: str | None = None,
    shader_type: str = "canvas_item",
    code: str | None = None,
    append: bool = False,
    node_path: str | None = None,
    material_name: str = "",
    uniforms: dict | None = None,
    uniform_name: str | None = None,
    value: Any = None,
) -> dict:
    """
    Shaders y materiales (v4). Actions: create|edit|validate|material(uniforms)|uniform(uniform_name,value)
    shader_type: canvas_item|spatial|particles, shader_path: res://.gdshader
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"shader_path": shader_path, "shader_type": shader_type, "code": code,
            "append": append, "node_path": node_path, "material_name": material_name,
            "uniforms": uniforms, "uniform_name": uniform_name, "value": value}
    return await _tool(f"shader/{action}", args, project_path)


# ============================================================
# ANIMATION TOOL
# ============================================================


@mcp.tool()
async def animation_tool(
    action: str,
    project_path: str | None = None,
    parent_path: str = ".",
    player_name: str = "AnimationPlayer",
    player_path: str | None = None,
    anim_name: str | None = None,
    length: float = 1.0,
    loop: bool = False,
    track_type: str = "value",
    node_path: str | None = None,
    property: str | None = None,
    track_idx: int = 0,
    time: float = 0.0,
    value: Any = None,
    transition: float = 1.0,
    states: list | None = None,
    transitions: list | None = None,
) -> dict:
    """
    Animaciones (v4). Actions: create_player|create|add_track|add_key|state_machine
    player_path: ruta AnimationPlayer, anim_name, track_type: value|position_3d|rotation_3d|scale_3d|method
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"parent_path": parent_path, "player_name": player_name,
            "player_path": player_path, "anim_name": anim_name, "length": length,
            "loop": loop, "track_type": track_type, "node_path": node_path,
            "property": property, "track_idx": track_idx, "time": time,
            "value": value, "transition": transition, "states": states,
            "transitions": transitions}
    return await _tool(f"animation/{action}", args, project_path)


# ============================================================
# SKELETON TOOL
# ============================================================


@mcp.tool()
async def skeleton_tool(
    action: str,
    project_path: str | None = None,
    parent_path: str = ".",
    skeleton_name: str = "Skeleton2D",
    is_3d: bool = False,
    skeleton_path: str | None = None,
    bone_name: str | None = None,
    rest_transform: dict | None = None,
    length: float = 32.0,
    bone_angle: float = 0.0,
    polygon_path: str | None = None,
    bone_weights: dict | None = None,
    attachment_name: str = "Attachment",
) -> dict:
    """
    Esqueletos 2D/3D (v4). Actions: skeleton_create(is_3d) | skeleton_add_bone(length,bone_angle) | skeleton_set_rest(rest_transform) | skeleton_skin | skeleton_attachment
    skeleton_path, bone_name, rest_transform: dict{x,y,z,rotation}
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"parent_path": parent_path, "skeleton_name": skeleton_name,
            "is_3d": is_3d, "skeleton_path": skeleton_path, "bone_name": bone_name,
            "rest_transform": rest_transform, "length": length,
            "bone_angle": bone_angle, "polygon_path": polygon_path,
            "bone_weights": bone_weights, "attachment_name": attachment_name}
    return await _tool(f"skeleton/{action}", args, project_path)


# ============================================================
# TILEMAP TOOL
# ============================================================


@mcp.tool()
async def tilemap_tool(
    action: str,
    project_path: str | None = None,
    tileset_path: str | None = None,
    tilemap_path: str | None = None,
    layer: int = 0,
    coords: dict | None = None,
    atlas_coords: dict | None = None,
    source_id: int = 0,
    alternative_tile: int = 0,
    cells: list | None = None,
    terrain_set: int = 0,
    terrain: int = 0,
    region: dict | None = None,
    pattern_name: str = "Pattern",
) -> dict:
    """
    TileMaps/TileSets (v4). Actions: inspect_set|inspect_map|set_cell(atlas_coords)|terrain|pattern
    coords{x,y}, atlas_coords{x,y}, layer, source_id, cells para terrain
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"tileset_path": tileset_path, "tilemap_path": tilemap_path,
            "layer": layer, "coords": coords, "atlas_coords": atlas_coords,
            "source_id": source_id, "alternative_tile": alternative_tile,
            "cells": cells, "terrain_set": terrain_set, "terrain": terrain,
            "region": region, "pattern_name": pattern_name}
    return await _tool(f"tilemap/{action}", args, project_path)


# ============================================================
# DEBUG TOOL
# ============================================================


@mcp.tool()
async def debug_tool(
    action: str,
    project_path: str | None = None,
    scene_path: str | None = None,
) -> dict:
    """
    Depuración (v4, editor real). Actions: run_scene(scene_path opcional)|stop_scene|is_playing|get_editor_errors
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"scene_path": scene_path}
    return await _tool(f"debug/{action}", args, project_path)


# ============================================================
# VALIDATE TOOL
# ============================================================


@mcp.tool()
async def validate_tool(
    action: str,
    project_path: str | None = None,
    scene_path: str | None = None,
    script_path: str | None = None,
    node_path: str | None = None,
    resource_path: str | None = None,
) -> dict:
    """
    Validación (v4). Actions: scene|script|node|resource. Verifica integridad contra el editor vivo.
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"scene_path": scene_path, "script_path": script_path,
            "node_path": node_path, "resource_path": resource_path}
    return await _tool(f"validate/{action}", args, project_path)


# ============================================================
# SIGNAL TOOL
# ============================================================


@mcp.tool()
async def signal(
    action: str,
    project_path: str | None = None,
    from_node: str | None = None,
    to_node: str | None = None,
    signal_name: str | None = None,
    method: str | None = None,
    node_path: str | None = None,
    script_path: str | None = None,
) -> dict:
    """
    Señales (v4). Actions: connect(signal_name,from_node,to_node,method)|disconnect|list(node_path)|set_script(node_path,script_path)
    CONNECT_PERSIST flags las señales para que pack() las serialice en save.
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    args = {"from_node": from_node, "to_node": to_node,
            "signal_name": signal_name, "method": method,
            "node_path": node_path, "script_path": script_path}
    return await _tool(f"signal/{action}", args, project_path)


# ============================================================
# BATCH / ORCHESTRATE
# ============================================================


@mcp.tool()
async def orchestrate(
    project_path: str | None = None,
    plan: dict | None = None,
    on_error: str = "stop",
    auto_save: bool = True,
) -> dict:
    """
    Batch v4: ejecuta múltiples ops contra la escena viva.
    plan: {op: {tool: {...}}, ...} o {ops: [{tool, args}]}. Cada op usa el
    nombre completo de tool (scene/save, node/add, ...).
    """
    ok, msg = _require_editor(project_path)
    if not ok:
        return {"ok": False, "error": msg}
    results: dict[str, Any] = {}
    if not isinstance(plan, dict):
        return {"ok": False, "error": "plan required"}
    ops = plan.get("ops", []) if isinstance(plan.get("ops"), list) else []
    if not ops and not plan.get("tools"):
        # Fallback: plan = {tool_name: args, ...}
        for tool_name, args in plan.items():
            if not isinstance(args, dict):
                continue
            results[tool_name] = await _tool(tool_name, args, project_path)
        return {"ok": True, "results": results, "count": len(results)}
    if plan.get("tools"):
        for tool_name, args in plan["tools"].items():
            if not isinstance(args, dict):
                continue
            results[tool_name] = await _tool(tool_name, args, project_path)
        return {"ok": True, "results": results, "count": len(results)}
    for i, op in enumerate(ops):
        if not isinstance(op, dict):
            continue
        tool_name = op.get("tool") or op.get("name")
        op_args = op.get("args", {}) if isinstance(op.get("args"), dict) else {}
        if not tool_name:
            continue
        results[str(i)] = await _tool(tool_name, op_args, project_path)
        if on_error == "stop" and not results[str(i)].get("ok", True):
            break
    return {"ok": True, "results": results, "count": len(results)}


# ============================================================
# MAIN
# ============================================================

def main() -> None:
    """Start the WS server in a background thread + FastMCP stdio loop."""
    ws = _ws_server()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(ws.start())
    logger.info("Heren MCP v4 bridge ready (ws on %s)", ws.port)
    mcp.run()


if __name__ == "__main__":
    main()
