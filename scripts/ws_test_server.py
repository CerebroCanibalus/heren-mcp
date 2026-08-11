"""
Heren MCP v4 - Test WS Server (Fase 1 validation harness).

Acts as the FlojoMCP server for testing the Godot EditorPlugin over
WebSocket. Speaks MCP JSON-RPC: receives `notifications/godot_ready`,
sends `tools/call` requests, receives results.

Usage:
    python tools/ws_test_server.py --port 9099 --command "scene/health"
"""

import argparse
import asyncio
import json
import sys
import websockets

PROJECT_PATH = None  # set from godot_ready notification


def _parse_args(arg_str: str):
    """Parse command args: JSON object, or comma-separated key=value pairs."""
    arg_str = arg_str.strip()
    if not arg_str:
        return {}
    if arg_str.startswith("{"):
        try:
            return json.loads(arg_str)
        except json.JSONDecodeError as e:
            print(f"[ERR] invalid args JSON: {e}", flush=True)
            return None
    args = {}
    for part in arg_str.split(","):
        if "=" in part:
            key, _, val = part.partition("=")
            args[key.strip()] = val.strip()
    return args


async def handle_connection(ws) -> None:
    global PROJECT_PATH
    print("[SERVER] plugin connected", flush=True)
    try:
        while True:
            raw = await ws.recv()
            msg = json.loads(raw)
            method = msg.get("method", "")
            if method == "notifications/godot_ready":
                PROJECT_PATH = msg.get("params", {}).get("project_path")
                print(f"[SERVER] godot_ready project: {PROJECT_PATH}", flush=True)
            elif method == "notifications/ping":
                pass
            else:
                print(f"[SERVER] recv: {json.dumps(msg)[:200]}", flush=True)
    except websockets.exceptions.ConnectionClosed as e:
        print(f"[SERVER] connection closed: {e}", flush=True)


async def run_command(ws, command: str, repeat: int) -> None:
    """Wait for godot_ready, then send tools/call N times."""
    global PROJECT_PATH
    tool_name, _, arg_str = command.partition(" ")
    args = _parse_args(arg_str)
    if args is None:
        sys.exit(1)
    await _run_tool_call(ws, tool_name, args, repeat)


async def run_sequence(ws, commands: list[str]) -> None:
    """Wait for godot_ready, then send a sequence of tools/call requests."""
    global PROJECT_PATH
    try:
        while PROJECT_PATH is None:
            raw = await asyncio.wait_for(ws.recv(), timeout=15)
            msg = json.loads(raw)
            if msg.get("method") == "notifications/godot_ready":
                PROJECT_PATH = msg.get("params", {}).get("project_path")
                print(f"[SERVER] plugin ready, project: {PROJECT_PATH}", flush=True)
    except asyncio.TimeoutError:
        print("[ERR] timeout waiting for godot_ready", flush=True)
        sys.exit(2)

    for i, command in enumerate(commands):
        if command.upper().startswith("SLEEP "):
            delay = float(command.split(" ", 1)[1])
            print(f"[SERVER] sleeping {delay}s", flush=True)
            await asyncio.sleep(delay)
            continue
        tool_name, _, arg_str = command.partition(" ")
        args = _parse_args(arg_str)
        if args is None:
            sys.exit(1)
        await _run_tool_call(ws, tool_name, args, 1, label=str(i))

    print("[SERVER] DONE", flush=True)
    await ws.close()
    asyncio.get_event_loop().stop()


async def _run_tool_call(
    ws, tool_name: str, args: dict, repeat: int, label: str = ""
) -> None:
    next_id = 1
    for i in range(repeat):
        req_id = next_id
        next_id += 1
        await ws.send(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "method": "tools/call",
                    "params": {"name": tool_name, "arguments": args},
                }
            )
        )
        tag = f"#{label}" if label != "" else f"#{i}"
        print(f"[SERVER] sent tools/call {tag}: {tool_name}", flush=True)
        try:
            raw = await asyncio.wait_for(ws.recv(), timeout=15)
            msg = json.loads(raw)
            print(f"[SERVER] response {tag}: {json.dumps(msg, indent=2)}", flush=True)
        except asyncio.TimeoutError:
            print(f"[ERR] timeout waiting for response {tag}", flush=True)
            sys.exit(3)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Heren v4 test WS server")
    parser.add_argument("--port", type=int, default=9099)
    parser.add_argument(
        "--command",
        type=str,
        default=None,
        help="tool name (optionally 'tool args_json') to send once",
    )
    parser.add_argument(
        "--repeat", type=int, default=1, help="send the command N times (test undo)"
    )
    parser.add_argument(
        "--sequence",
        type=str,
        default=None,
        help="semicolon-separated commands to run in order",
    )
    parser.add_argument(
        "--sequence-file",
        type=str,
        default=None,
        help="file with one command per line (avoid shell escaping)",
    )
    args = parser.parse_args()

    if args.sequence_file and not args.sequence:
        # Read lines directly (no ";" join/split — JSON args may contain ";"
        # e.g. shader code, GDScript statements).
        args.sequence_lines = [
            line.strip()
            for line in open(args.sequence_file, "r", encoding="utf-8")
            if line.strip() and not line.strip().startswith("#")
        ]

    print(f"[SERVER] listening on ws://127.0.0.1:{args.port}", flush=True)

    async def server_handler(ws):
        if getattr(args, "sequence_lines", None):
            await run_sequence(ws, args.sequence_lines)
        elif args.sequence:
            commands = [c.strip() for c in args.sequence.split(";") if c.strip()]
            await run_sequence(ws, commands)
        elif args.command:
            await run_command(ws, args.command, args.repeat)
        else:
            await handle_connection(ws)

    done = asyncio.Event()
    async with websockets.serve(server_handler, "127.0.0.1", args.port):
        await done.wait()


if __name__ == "__main__":
    asyncio.run(main())
