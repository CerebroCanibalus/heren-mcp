@echo off
REM Heren MCP Launcher para OpenCode
REM v4.1: framing bridge (Content-Length <-> NDJSON) + heren-server.exe (Rust)
REM OpenCode 1.18 usa Content-Length framing; FlojoMCP/rmcp usa NDJSON.
REM El bridge traduce entre ambos.

cd /d "D:\Mis Juegos\GodotMCP\heren-mcp"
set PYTHONPATH=D:\Mis Juegos\GodotMCP\heren-mcp\src
python -m heren.v4.framing_bridge