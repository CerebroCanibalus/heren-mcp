@echo off
chcp 65001 > nul
echo ==========================================
echo Heren-Server - Deploy fix 2026-08-08
echo ==========================================
echo.

set "SRC=%~dp0.temp\target-fix\release\heren-server.exe"
set "DST=%~dp0target\release\heren-server.exe"

if not exist "%SRC%" (
    echo [ERROR] No existe el binario fix: %SRC%
    echo         Compila primero: heren-build.bat ^(release^) o cargo build --release -p heren-server
    exit /b 1
)

echo [1/2] Renombrando binario en uso (los procesos activos siguen con su imagen)...
if exist "%DST%.old" del /f /q "%DST%.old" > nul 2>&1
ren "%DST%" "heren-server.exe.old"
if errorlevel 1 (
    echo [ERROR] No se pudo renombrar %DST%
    exit /b 1
)
echo      OK - viejo guardado como heren-server.exe.old

echo [2/2] Instalando binario fix (release 2026-08-08)...
copy /Y "%SRC%" "%DST%" > nul
if errorlevel 1 (
    echo [ERROR] No se pudo copiar el binario. Restaurando...
    ren "%DST%.old" "heren-server.exe"
    exit /b 1
)
echo      OK - binario nuevo instalado

echo.
echo ==========================================
echo Deploy exitoso: target\release\heren-server.exe
echo.
echo IMPORTANTE:
echo  - Las sesiones MCP ABIERTAS siguen con el codigo viejo en RAM.
echo  - Abre una sesion NUEVA de OpenCode para usar el fix.
echo  - Cuando nadie use heren-server.exe.old, borralo:
echo      del target\release\heren-server.exe.old
echo ==========================================
