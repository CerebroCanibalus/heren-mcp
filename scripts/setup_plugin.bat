@echo off
REM Heren MCP v4 - Setup plugin en proyecto Godot
REM Uso: setup_plugin.bat [ruta\del\proyecto]
REM Si no se da ruta, instala en LAIKA (banco de pruebas).

cd /d "%~dp0.."

if "%1"=="" (
    echo [Heren] Sin argumento. Instalando en LAIKA (banco de pruebas)...
    python "%~dp0install_plugin.py" --project "D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"
) else (
    echo [Heren] Instalando plugin en %1...
    python "%~dp0install_plugin.py" --project "%1"
)
