@echo off
REM Heren MCP Launcher para OpenCode
REM v4: bridge server (FastMCP stdio <-> WebSocket <-> EditorPlugin Godot).
REM Si el bridge v4 falla (dependencias), fallback a server v3 legacy.

cd /d "D:\Mis Juegos\GodotMCP\heren-mcp"
set PYTHONPATH=D:\Mis Juegos\GodotMCP\heren-mcp\src

python -m heren.v4.bridge 2>NUL
if errorlevel 1 (
    echo [Heren] bridge v4 no disponible, usando server v3 legacy... 1>&2
    python -m heren.server
)
