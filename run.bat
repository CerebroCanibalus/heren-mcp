@echo off
REM Heren MCP Launcher para OpenCode
REM v4.1: framing bridge (Content-Length <-> NDJSON) + heren-server.exe (Rust)
REM OpenCode 1.18 usa Content-Length framing; FlojoMCP/rmcp usa NDJSON.
REM El bridge traduce entre ambos.
REM HEREN_LOG_FILE: log del bridge a archivo para debugging.

cd /d "D:\Mis Juegos\GodotMCP\heren-mcp"
set PYTHONPATH=D:\Mis Juegos\GodotMCP\heren-mcp\src
if not defined HEREN_LOG_FILE set HEREN_LOG_FILE=D:\Mis Juegos\GodotMCP\heren-mcp\.temp\bridge.log
python -m heren.v4.framing_bridge