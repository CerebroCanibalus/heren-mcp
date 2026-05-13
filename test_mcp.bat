@echo off
REM Test MCP communication with Heren

cd /d "D:\Mis Juegos\GodotMCP\heren-mcp"
set PYTHONPATH=D:\Mis Juegos\GodotMCP\heren-mcp\src

REM Iniciar servidor y enviar mensaje de inicialización
echo {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}} | python -m heren.server
