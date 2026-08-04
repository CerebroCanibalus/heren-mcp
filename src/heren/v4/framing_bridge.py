"""Heren MCP framing bridge: Content-Length (OpenCode) <-> NDJSON (heren-server).

OpenCode 1.18 usa Content-Length framing (LSP-style) para MCP stdio.
FlojoMCP/rmcp 1.7 usa NDJSON (newline-delimited). Este bridge traduce
entre ambos sin tocar el server ni OpenCode.

Flujo:
  OpenCode --Content-Length--> stdin(este) --NDJSON--> heren-server stdin
  heren-server stdout --NDJSON--> este --Content-Length--> stdout(OpenCode)
"""
import json
import os
import subprocess
import sys
import threading
import time

BIN = r"D:\Mis Juegos\ClaudeMCPs\FlojoMCP\target\release\heren-server.exe"
HEREN_LOG = os.environ.get("HEREN_LOG_FILE", "")


def log(msg: str) -> None:
    if HEREN_LOG:
        try:
            with open(HEREN_LOG, "a", encoding="utf-8") as f:
                f.write(f"[bridge] {msg}\n")
        except Exception:
            pass


def read_ndjson(pipe) -> bytes | None:
    """Lee un mensaje NDJSON (hasta \n) del server."""
    line = pipe.readline()
    if not line:
        return None
    return line


def read_content_length(pipe) -> bytes | None:
    """Lee un mensaje Content-Length framing de OpenCode."""
    headers = b""
    while b"\r\n\r\n" not in headers:
        c = pipe.read(1)
        if not c:
            return None
        headers += c
    # parsear Content-Length
    clen = 0
    for part in headers.decode(errors="replace").split("\r\n"):
        if part.lower().startswith("content-length:"):
            clen = int(part.split(":")[1].strip())
    body = pipe.read(clen) if clen > 0 else b""
    return body


def main() -> None:
    env = dict(os.environ)
    env["HEREN_WS_ADDR"] = "127.0.0.1:9099"
    server = subprocess.Popen(
        [BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, bufsize=0, env=env,
    )
    log("server lanzado")

    # Thread: drena stderr del server — CRÍTICO. Si no se lee, el pipe de
    # stderr se llena (64KB en Windows) y el server se bloquea escribiendo
    # logs de tracing -> 'tarda demasiado y muere' en OpenCode.
    def drain_stderr() -> None:
        while True:
            chunk = server.stderr.readline()
            if not chunk:
                break
            log(f"server stderr: {chunk.decode(errors='replace').strip()}")

    threading.Thread(target=drain_stderr, daemon=True).start()

    # Thread: lee stdout del server (NDJSON) -> escribe a stdout (Content-Length)
    def server_to_opencode() -> None:
        while True:
            line = server.stdout.readline()
            if not line:
                log("server stdout cerrado")
                break
            # Convertir NDJSON -> Content-Length
            frame = f"Content-Length: {len(line)}\r\n\r\n".encode() + line
            try:
                sys.stdout.buffer.write(frame)
                sys.stdout.buffer.flush()
            except Exception as e:
                log(f"write stdout error: {e}")
                break

    threading.Thread(target=server_to_opencode, daemon=True).start()

    # Main: lee stdin de OpenCode (Content-Length) -> escribe al server (NDJSON)
    stdin = sys.stdin.buffer
    while True:
        msg = read_content_length(stdin)
        if msg is None:
            log("stdin cerrado")
            break
        # Convertir Content-Length -> NDJSON (añadir newline)
        server.stdin.write(msg + b"\n")
        server.stdin.flush()

    server.terminate()


if __name__ == "__main__":
    main()
