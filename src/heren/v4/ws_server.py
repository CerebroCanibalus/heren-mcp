"""Heren MCP v4 - WebSocket server (bridge core).

The EditorPlugin is the WS CLIENT (ADR-003); this server accepts connections,
registers ConnectedEditors[project_path], and routes tools/call requests to
the connected editor(s), correlating JSON-RPC ids.

The plugin sends `notifications/godot_ready` on connect (with project_path)
and responds to `tools/call` with `{"jsonrpc":"2.0","id":..., "result":...}`.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Any

import websockets

logger = logging.getLogger(__name__)

# Max time to wait for a tool response from the editor.
_TOOL_TIMEOUT = 30.0


def normalize_project_path(path: str) -> str:
    """Canonical key for a project path: forward slashes, no trailing slash.

    The plugin reports Godot-style paths (D:/proj/, forward slashes, trailing
    slash); agents may pass Windows backslashes with or without trailing.
    All map to the same canonical key so has_editor/register are consistent.
    """
    if not path:
        return ""
    import os as _os
    if _os.name == "nt":
        p = path.replace("/", "\\")
        normalized = str(Path(p).resolve())
        return normalized.replace("\\", "/").rstrip("/")
    return str(Path(path).resolve()).rstrip("/")


class EditorConnection:
    """A live editor (project_path -> websocket)."""

    __slots__ = ("project_path", "ws", "connected_at", "last_seen")

    def __init__(self, project_path: str, ws: Any) -> None:
        self.project_path = project_path
        self.ws = ws
        self.connected_at = time.time()
        self.last_seen = time.time()


class WsServer:
    """WebSocket server that speaks MCP JSON-RPC with the EditorPlugin."""

    def __init__(self, port: int = 9099, host: str = "127.0.0.1") -> None:
        self.port = port
        self.host = host
        self._editors: dict[str, EditorConnection] = {}
        self._pending: dict[str, asyncio.Future] = {}
        self._next_id = 1
        self._server: Any = None

    # ---------------------------------------------------------- lifecycle

    async def start(self) -> None:
        self._server = await websockets.serve(self._handle_ws, self.host, self.port)
        logger.info("WS server listening on ws://%s:%s", self.host, self.port)

    async def stop(self) -> None:
        if self._server:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel()
        self._pending.clear()

    # ------------------------------------------------------ connections

    async def _handle_ws(self, ws: Any) -> None:
        logger.info("editor connected")
        conn: EditorConnection | None = None
        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    logger.warning("invalid JSON frame from editor, closing")
                    continue
                if not isinstance(msg, dict):
                    continue
                method = msg.get("method", "")

                if method == "notifications/godot_ready":
                    params = msg.get("params", {}) or {}
                    project_path = normalize_project_path(params.get("project_path", ""))
                    if conn:
                        self._editors.pop(conn.project_path, None)
                    conn = EditorConnection(project_path, ws)
                    if project_path:
                        self._editors[project_path] = conn
                    logger.info("godot_ready project=%s", project_path)
                    # Re-announce to the MCP layer (used by session/list).
                    self._on_editor_ready(project_path)
                elif method == "notifications/ping":
                    if conn:
                        conn.last_seen = time.time()
                elif method == "notifications/pong":
                    if conn:
                        conn.last_seen = time.time()
                else:
                    # JSON-RPC response to a tools/call request.
                    req_id = msg.get("id")
                    if req_id is not None:
                        fut = self._pop_pending(req_id)
                        if fut and not fut.done():
                            fut.set_result(msg)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if conn:
                self._editors.pop(conn.project_path, None)
                self._on_editor_left(conn.project_path)
            logger.info("editor disconnected")

    # --------------------------------------------------------- callbacks

    def _on_editor_ready(self, project_path: str) -> None:  # overridable
        pass

    def _on_editor_left(self, project_path: str) -> None:  # overridable
        pass

    # ----------------------------------------------------------- queries

    def connected_projects(self) -> list[dict[str, Any]]:
        return [
            {
                "project_path": c.project_path,
                "connected_at": c.connected_at,
                "last_seen": c.last_seen,
            }
            for c in self._editors.values()
        ]

    def has_editor(self, project_path: str | None = None) -> bool:
        if project_path:
            return normalize_project_path(project_path) in self._editors
        return bool(self._editors)

    # --------------------------------------------------------- tool calls

    def _pop_pending(self, req_id: Any) -> asyncio.Future | None:
        """Find a pending future for a request id, tolerant of the plugin's
        id handling. The GDScript plugin does str(id) on what it receives and
        echoes it back; JSON ints may arrive as "1" or "1.0" depending on how
        the editor serialized them. Try exact, then float-normalized."""
        candidates = [req_id]
        # normalize numeric strings: "1.0" -> "1", 1 -> "1"
        for base in list(candidates):
            key = str(base)
            if key not in candidates:
                candidates.append(key)
            try:
                f = float(base)
                if f.is_integer():
                    int_key = str(int(f))
                    if int_key not in candidates:
                        candidates.append(int_key)
            except (TypeError, ValueError):
                pass
        for key in candidates:
            fut = self._pending.pop(str(key), None)
            if fut is not None:
                return fut
        return None

    async def call_tool(
        self,
        tool_name: str,
        args: dict[str, Any] | None = None,
        project_path: str | None = None,
        timeout: float = _TOOL_TIMEOUT,
    ) -> dict[str, Any]:
        """Send tools/call to an editor and await the result.

        Returns the JSON-RPC response message ({"result":...} or {"error":...}).
        """
        args = args or {}
        conn = self._pick_editor(project_path)
        if conn is None:
            return {
                "error": {
                    "code": -32001,
                    "message": "no editor connected"
                    + (f" for project: {project_path}" if project_path else ""),
                }
            }

        req_id = self._next_id
        self._next_id += 1
        fut: asyncio.Future = asyncio.get_event_loop().create_future()
        self._pending[str(req_id)] = fut

        try:
            await conn.ws.send(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": args},
            }))
            return await asyncio.wait_for(fut, timeout=timeout)
        except asyncio.TimeoutError:
            self._pending.pop(str(req_id), None)
            return {
                "error": {"code": -32002, "message": f"tool timeout: {tool_name}"}
            }
        except websockets.exceptions.ConnectionClosed as e:
            self._pending.pop(str(req_id), None)
            return {"error": {"code": -32003, "message": f"editor closed: {e}"}}

    def _pick_editor(self, project_path: str | None) -> EditorConnection | None:
        if project_path:
            key = normalize_project_path(project_path)
            if key in self._editors:
                return self._editors[key]
        # No explicit project: return any (first) connected editor.
        for conn in self._editors.values():
            return conn
        return None


# --------------------------------------------------------------- helpers

def unwrap_result(response: dict[str, Any]) -> dict[str, Any]:
    """Convert a WS JSON-RPC response into a plain result dict.

    Success: {"result": {"content": [{"type":"text","text":"..."}]}}
    -> parsed text. Error -> {"ok": false, "error": message}.
    """
    if "error" in response:
        err = response["error"]
        return {"ok": False, "error": err.get("message", str(err))}
    result = response.get("result", {})
    content = result.get("content", []) if isinstance(result, dict) else []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            text = item.get("text", "")
            try:
                parsed = json.loads(text)
                if isinstance(parsed, dict):
                    return parsed
            except json.JSONDecodeError:
                pass
            return {"ok": True, "text": text}
    return {"ok": True, "raw": result}
