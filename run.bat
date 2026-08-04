@echo off
REM Heren MCP Launcher para OpenCode
REM v4.1: heren-server.exe (Rust/FlojoMCP) — stdio MCP <-> WS 9099 <-> EditorPlugin Godot
REM El plugin Godot conecta al WS server (patrón gopeak). El binario usa
REM HEREN_WS_ADDR para el puerto WS (default 9099).

set HEREN_WS_ADDR=127.0.0.1:9099
"D:\Mis Juegos\ClaudeMCPs\FlojoMCP\target\release\heren-server.exe"