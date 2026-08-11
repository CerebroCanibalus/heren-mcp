@echo off
chcp 65001 > nul
echo ==========================================
echo Heren-Server - Compilador (workspace local)
echo ==========================================
echo.

REM Ir al workspace root independientemente de desde donde se llame el script.
cd /d "%~dp0\.."

REM Configurar entorno de Visual Studio para el linker (MSVC)
set VSCMD_START_DIR=%CD%
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 > nul

if not exist "crates\heren-server\Cargo.toml" (
    echo [ERROR] No se encontró el crate heren-server
    echo [INFO] Ejecuta este script desde la raiz de heren-mcp
    exit /b 1
)

echo [1/4] Compilando heren-server (debug)...
cargo build -p heren-server
if errorlevel 1 (
    echo [ERROR] Falló la compilación debug
    exit /b 1
)

echo [2/4] Ejecutando tests heren-server...
cargo test -p heren-server
if errorlevel 1 (
    echo [ERROR] Fallaron los tests
    exit /b 1
)

echo [3/4] Compilando heren-server (release ~9MB)...
cargo build --release -p heren-server
if errorlevel 1 (
    echo [ERROR] Falló la compilación release
    exit /b 1
)

echo [4/4] Verificando lint (clippy)...
cargo clippy -p heren-server -- -D warnings
if errorlevel 1 (
    echo [WARN] Clippy reportó warnings (revisa)
)

echo.
echo ==========================================
echo Compilación exitosa!
echo Binario: target\release\heren-server.exe
echo ==========================================
