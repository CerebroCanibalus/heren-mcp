@echo off
REM Heren MCP v4 - Setup plugin en proyecto Godot
REM Uso: setup_plugin.bat [ruta\del\proyecto]
REM Si no se da ruta, instala en LAIKA (banco de pruebas).

set PYTHONPATH=D:\Mis Juegos\GodotMCP\heren-mcp\src

if "%1"=="" (
    echo [Heren] Sin argumento. Instalando en LAIKA (banco de pruebas)...
    python "D:\Mis Juegos\GodotMCP\heren-mcp\tools\install_plugin.py" --project "D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"
) else (
    echo [Heren] Instalando plugin en %1...
    python "D:\Mis Juegos\GodotMCP\heren-mcp\tools\install_plugin.py" --project "%1"
)
