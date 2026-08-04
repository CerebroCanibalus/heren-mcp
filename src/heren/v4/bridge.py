"""Heren MCP v4 - Bridge server (FastMCP entry).

OpenCode (MCP stdio) <-> this server <-> EditorPlugin v4 (WebSocket).

The 14 tools mirror the v3 API (same names/actions) so agents keep working,
but there is no session_id: the connected editor IS the session. Session
tool manages which project the editor is open on and auto-launches Godot.

Run: python -m heren.v4.bridge
"""

from __future__ import annotations

import asyncio
import base64
import logging
import os
import sys
import threading
import time
from typing import Any

from fastmcp import FastMCP

from heren.v4 import godot_launcher
from heren.v4.ws_server import WsServer, unwrap_result

logging.basicConfig(level=logging.INFO, stream=sys.stdout)
logger = logging.getLogger(__name__)

mcp = FastMCP("heren-godot-v4")

# ---- shared state --------------------------------------------------------

_ws: WsServer | None = None
_ws_loop: asyncio.AbstractEventLoop | None = None
_ws_thread: threading.Thread | None = None

# ---- vision state (Fase 3, §13.6 — RAM efímera, ADR-004) ----------------

_VISION_BUDGET: dict[str, float] = {}          # project_path -> tokens budget
_VISION_SPENT: dict[str, float] = {}           # project_path -> tokens spent
_VISION_CACHE: dict[str, dict[str, Any]] = {}  # key -> {"tokens": n, "result": {...}}


def _vision_key(project_path: str | None, tool_name: str, args: dict[str, Any]) -> str:
    """Cache key: project + tool + args, so a capture with different max_side
    or viewport gets its own entry (different cost/resolution)."""
    import json as _json

    project = project_path or "default"
    stable = _json.dumps(args, sort_keys=True, default=str)
    return f"{project}|{tool_name}|{stable}"


def _vision_check(project_path: str | None, tool_name: str,
                  args: dict[str, Any]) -> dict[str, Any] | None:
    """Return cached result if present (cache hit), else None."""
    key = _vision_key(project_path, tool_name, args)
    entry = _VISION_CACHE.get(key)
    if entry:
        result = dict(entry["result"])
        result["_cache"] = {"hit": True, "tokens_saved": entry["tokens"]}
        return result
    return None


def _vision_store(project_path: str | None, tool_name: str,
                  args: dict[str, Any], result: dict[str, Any], tokens: float) -> None:
    key = _vision_key(project_path, tool_name, args)
    _VISION_CACHE[key] = {"tokens": tokens, "result": result}
    if len(_VISION_CACHE) > 50:
        # Simple LRU-ish: drop oldest 20%.
        keys = list(_VISION_CACHE.keys())
        for k in keys[: max(1, len(keys) // 5)]:
            _VISION_CACHE.pop(k, None)


def _estimate_tokens(result: dict[str, Any]) -> float:
    """Cheap token estimate: images ~= pixels/400, text ~= chars/4."""
    tok = 0.0
    for k, v in result.items():
        if k == "__image_base64":
            continue  # image cost handled via dimensions below
        if isinstance(v, str):
            tok += len(v) / 4.0
        elif isinstance(v, dict):
            tok += _estimate_tokens(v)
        elif isinstance(v, (list, tuple)):
            for item in v:
                if isinstance(item, (dict, str)):
                    tok += _estimate_tokens({"": item}) if isinstance(item, dict) else len(item) / 4.0
    w = int(result.get("__image_w", 0))
    h = int(result.get("__image_h", 0))
    if w and h:
        tok += (w * h) / 400.0  # ~400px² per token (low-res vision standard)
    return max(1.0, round(tok, 1))


def _ws_server() -> WsServer:
    global _ws
    if _ws is None:
        port = int(os.environ.get("HEREN_MCP_PORT", "9099"))
        _ws = WsServer(port=port)
    return _ws


def _ensure_ws_running() -> WsServer:
    """Start the WS server in a dedicated thread + event loop if not running.

    FastMCP's mcp.run() owns the main event loop, so the WS server must live
    on its own loop in a background thread. Otherwise the WS socket accepts
    TCP but never completes the WebSocket handshake (the handshake handler
    never runs) -> the editor connects but never registers.
    """
    global _ws_loop, _ws_thread
    ws = _ws_server()
    if _ws_loop is not None and _ws_thread is not None and _ws_thread.is_alive():
        return ws
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _run() -> None:
        loop.run_until_complete(ws.start())
        loop.run_forever()

    _ws_loop = loop
    _ws_thread = threading.Thread(target=_run, daemon=True, name="heren-ws")
    _ws_thread.start()
    logger.info("WS server thread started on %s", ws.port)
    return ws


def _call_ws(coro_factory):
    """Run a coroutine on the WS server's loop from the MCP (async) context."""
    ws_loop = _ws_loop
    if ws_loop is None:
        return asyncio.run(coro_factory())
    fut = asyncio.run_coroutine_threadsafe(coro_factory(), ws_loop)
    return fut.result(timeout=35)


async def _tool(tool_name: str, args: dict[str, Any] | None = None,
          project_path: str | None = None) -> dict[str, Any]:
    """Send a tool call to the editor and return the result dict."""
    try:
        _ensure_ws_running()
        resp = await asyncio.to_thread(
            _call_ws, lambda: _ws_server().call_tool(tool_name, args, project_path)
        )
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"bridge call failed: {e}"}
    return unwrap_result(resp)


def _require_editor(project_path: str | None = None) -> tuple[bool, str]:
    """Ensure an editor is CONNECTED for routing. Never launches.

    The editor lifecycle is managed ONLY by session/open and session/close.
    If no editor is connected, the agent must open a session first — tools
    never auto-launch (Q3: launch is the MCP's job, via session).
    """
    ws = _ensure_ws_running()
    if ws.has_editor(project_path):
        return True, ""
    if not project_path:
        if ws.has_editor():
            return True, ""
        return False, "no editor connected. Call session/open with project_path first."
    return False, (
        f"no editor connected for project: {project_path}. "
        "Call session/open with project_path first."
    )


async def _wait_for_editor(project_path: str, timeout: float = 45.0) -> bool:
    """Wait until an editor connects for the project (polling, async)."""
    ws = _ensure_ws_running()
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        if ws.has_editor(project_path):
            return True
        await asyncio.sleep(0.5)
    return ws.has_editor(project_path)


# ============================================================
# SESSION TOOL
# ============================================================


@mcp.tool()
async def session(
    action: str,
    project_path: str | None = None,
    godot_path: str | None = None,
    close_editor: bool = False,
) -> dict:
    """
    Gestión de sesiones v4. Actions: open(project_path, godot_path) | close(close_editor) | list | info(project_path) | health
    open: lanza el editor Godot con el plugin (o reusa uno ya abierto del proyecto). Espera a que conecte.
    close: cierra la sesión del MCP. close_editor=true mata el proceso Godot; false (default) deja el editor abierto para reuso.
    list: proyectos con editor vivo conectado. info/health: estado.
    """
    ws = _ensure_ws_running()
    if action == "open":
        if not project_path:
            return {"ok": False, "error": "project_path required"}
        # Already connected? reuse immediately.
        if ws.has_editor(project_path):
            return {"ok": True, "message": "already connected", "project_path": project_path,
                    "daemon_active": True, "session_id": project_path}
        # Editor process already running? wait for it to connect (no duplicate).
        if godot_launcher.is_editor_running(project_path):
            connected = await _wait_for_editor(project_path, timeout=45.0)
            return {"ok": connected, "message": "reused running editor" if connected else "editor running but not connecting",
                    "project_path": project_path, "daemon_active": connected, "session_id": project_path}
        # No editor: launch it.
        ok, msg = godot_launcher.launch_editor(project_path, ws.port, godot_path or "")
        if not ok:
            return {"ok": False, "message": msg, "project_path": project_path,
                    "daemon_active": False}
        connected = await _wait_for_editor(project_path, timeout=45.0)
        return {"ok": connected, "message": msg, "project_path": project_path,
                "daemon_active": connected, "session_id": project_path}
    if action == "close":
        target = project_path
        if not target:
            projects = ws.connected_projects()
            target = projects[0]["project_path"] if projects else ""
        if not target:
            return {"ok": False, "error": "no session to close"}
        if close_editor:
            killed = godot_launcher.close_editor(target)
            return {"ok": True, "message": "editor closed" if killed else "no editor process found",
                    "project_path": target, "closed_editor": killed}
        # Leave the editor running; the WS connection just drops when the
        # plugin reconnects elsewhere. Nothing to kill.
        return {"ok": True, "message": "session closed (editor left open for reuse)",
                "project_path": target, "closed_editor": False}
    if action == "list":
        return {"ok": True, "sessions": ws.connected_projects(),
                "count": len(ws.connected_projects())}
    if action == "info":
        projects = ws.connected_projects()
        if project_path:
            from heren.v4.ws_server import normalize_project_path
            key = normalize_project_path(project_path)
            projects = [p for p in projects if normalize_project_path(p["project_path"]) == key]
        if not projects:
            return {"ok": False, "error": "no editor connected" + (f": {project_path}" if project_path else "")}
        return {"ok": True, "session": projects[0]}
    if action == "health":
        return {"ok": True, "editors": ws.connected_projects(),
                "active": len(ws.connected_projects()) > 0}
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
# VISUAL TOOLS (Fase 3 — "Ojos con Control", §13.6)
# ============================================================

from fastmcp.utilities.types import Image as MCPImage  # noqa: E402


def _tool_visual(tool_name: str, args: dict[str, Any] | None = None,
                 project_path: str | None = None) -> MCPImage | dict[str, Any]:
    """Call a visual tool; if the result carries __image_base64, return the
    image DIRECTLY as MCP image_content (agnostic — the agent SEES it).

    Otherwise return the plain dict (coords/summary/ascii are text).
    Applies vision budget + cache (§13.6): cache hit reuses tokens-free;
    a new capture spends against the session budget.
    """
    args = args or {}
    # Budget check (only for image-level tools).
    if "capture" in tool_name:
        budget = _VISION_BUDGET.get(project_path or "default", float("inf"))
        spent = _VISION_SPENT.get(project_path or "default", 0.0)
        if spent >= budget:
            return {"ok": False, "error": f"vision budget exhausted ({spent:.0f}/{budget:.0f} tokens). "
                                          "Raise it with vision_budget or use scene_coords/visual_ascii."}

    # Cache lookup.
    cached = _vision_check(project_path, tool_name, args)
    if cached is not None:
        return _prepare_visual_result(cached, tool_name)

    resp = _tool(tool_name, args, project_path)
    if isinstance(resp, dict):
        resp.pop("_metadata", None)
        tokens = _estimate_tokens(resp)
        _vision_store(project_path, tool_name, args, resp, tokens)
        _VISION_SPENT[project_path or "default"] = \
            _VISION_SPENT.get(project_path or "default", 0.0) + tokens
        b64 = resp.pop("__image_base64", None)
        if b64:
            try:
                img = MCPImage(data=base64.b64decode(b64), format="png")
                meta = {k: v for k, v in resp.items() if k != "ok"}
                resp["_metadata"] = meta
                return img
            except Exception:  # noqa: BLE001
                return {"ok": False, "error": "image decode failed"}
    return resp


def _prepare_visual_result(result: dict[str, Any], tool_name: str) -> MCPImage | dict[str, Any]:
    """Convert a cached/plain visual result into the final form."""
    if "capture" in tool_name:
        b64 = result.pop("__image_base64", None)
        if b64:
            try:
                img = MCPImage(data=base64.b64decode(b64), format="png")
                meta = {k: v for k, v in result.items() if k != "ok"}
                result["_metadata"] = meta
                return img
            except Exception:  # noqa: BLE001
                return {"ok": False, "error": "image decode failed"}
    return result


@mcp.tool()
async def scene_coords(
    project_path: str | None = None,
    max_depth: int = -1,
) -> dict:
    """NIVEL 0: mapa textual de coordenadas de la escena viva.
    Devuelve {nodo: {pos, bbox, parent, type}} — barato y suficiente para la
    mayoría de operaciones (saber DÓNDE está algo, moverlo, comprobar que existe).
    Consulta SIEMPRE antes de pedir una imagen.
    """
    return await _tool("visual/scene_coords", {"max_depth": max_depth}, project_path)


@mcp.tool()
async def visual_scene_summary(project_path: str | None = None) -> dict:
    """NIVEL 1: resumen textual de la escena — conteo por tipo de nodo."""
    return await _tool("visual/scene_summary", {}, project_path)


@mcp.tool()
async def visual_ascii_scene(project_path: str | None = None, max_depth: int = -1) -> dict:
    """NIVEL 1: árbol ASCII de la escena (colapsado/expandido), sin imagen."""
    return await _tool("visual/scene_ascii", {"max_depth": max_depth}, project_path)


@mcp.tool()
async def visual_capture(
    project_path: str | None = None,
    viewport: str = "2d",
    max_side: int = 0,
) -> MCPImage | dict:
    """NIVEL 2/3: captura el viewport REAL del editor (2d|3d) — la imagen llega
    DIRECTA al agente como image_content MCP estándar (no un path). max_side
    limita la resolución para controlar tokens (0 = full). Incluye metadatos
    en _metadata (resolution, scene, node_count).
    """
    return _tool_visual("visual/capture",
                        {"viewport": viewport, "max_side": max_side}, project_path)


@mcp.tool()
async def visual_node(
    project_path: str | None = None,
    node_path: str = "",
    viewport: str = "2d",
    max_side: int = 0,
) -> MCPImage | dict:
    """NIVEL 3: captura enfocada en un nodo (framing + bbox en metadatos)."""
    return _tool_visual("visual/capture_node",
                        {"node_path": node_path, "viewport": viewport, "max_side": max_side},
                        project_path)


@mcp.tool()
async def vision_budget(
    project_path: str | None = None,
    tokens: float | None = None,
) -> dict:
    """Presupuesto de tokens de visión por sesión (RAM, ADR-004).
    Sin 'tokens' → consulta el estado. Con 'tokens' → lo establece (o lo
    resetea a 0). El agente decide cuánto gasta en imágenes; coords/ascii
    son gratis (nivel 0/1).
    """
    key = project_path or "default"
    if tokens is not None:
        _VISION_BUDGET[key] = tokens
        _VISION_SPENT[key] = 0.0
        return {"ok": True, "project_path": project_path, "budget": tokens, "spent": 0.0}
    return {
        "ok": True,
        "project_path": project_path,
        "budget": _VISION_BUDGET.get(key, float("inf")),
        "spent": _VISION_SPENT.get(key, 0.0),
        "remaining": _VISION_BUDGET.get(key, float("inf")) - _VISION_SPENT.get(key, 0.0),
    }


@mcp.tool()
async def vision_cache(project_path: str | None = None, clear: bool = False) -> dict:
    """Cache de visión: consultar entradas (clave, tokens) o limpiarla (clear=true).
    La cache reusa capturas si la escena no cambió — ahorra tokens y latencia.
    """
    if clear:
        n = len(_VISION_CACHE)
        _VISION_CACHE.clear()
        return {"ok": True, "cleared": n}
    entries = [
        {"key": k, "tokens": v.get("tokens", 0)}
        for k, v in list(_VISION_CACHE.items())[:50]
    ]
    return {"ok": True, "count": len(_VISION_CACHE), "entries": entries}


# ============================================================
# MAIN
# ============================================================

def main() -> None:
    """Start the WS server in a background thread + FastMCP stdio loop."""
    _ensure_ws_running()
    logger.info("Heren MCP v4 bridge ready (ws on %s)", _ws_server().port)
    mcp.run()


if __name__ == "__main__":
    main()
