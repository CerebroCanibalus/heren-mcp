@echo off
chcp 65001 > nul
echo ==========================================
echo Heren MCP - Validador automatico (§0.13)
echo ==========================================
echo.

REM Ir al workspace root independientemente de desde donde se llame.
cd /d "%~dp0\.."

set "GODOT=D:\Mis Juegos\Godot\Godot_v4.5-stable_win64.exe"
set "PROJECT=%CD%\fixtures\empty_project"
set "SYNC_SCRIPT=%CD%\.temp\sync_fixtures.ps1"
set "COMPILE_LOG=%CD%\.temp\compile_check.log"
set "TESTS_LOG=%CD%\.temp\tests_run.log"

if not exist "%GODOT%" (
    echo [ERROR] Godot no encontrado en %GODOT%
    echo         Ajusta la variable GODOT en este script.
    exit /b 1
)

echo [1/4] Sincronizando fixtures...
REM Copia inline (sin dependencia de PowerShell) — solo los archivos que cambian.
set "SRC=%CD%\addons\heren"
set "DST=%CD%\fixtures\empty_project\addons\heren"
set SYNCED=0
for %%F in (handlers\heren_handler.gd handlers\validate_handlers.gd handlers\resource_handlers.gd handlers\node_handlers.gd handlers\shader_handlers.gd tests\run_tests.gd) do (
    if exist "%SRC%\%%F" (
        if exist "%DST%\%%F" del /f /q "%DST%\%%F" > nul 2>&1
        copy /Y "%SRC%\%%F" "%DST%\%%F" > nul
        if not errorlevel 1 set /a SYNCED+=1
    )
)
REM Strip .uid sidecars (Godot regenera por proyecto).
for /r "%DST%" %%U in (*.uid) do del /f /q "%%U" > nul 2>&1
echo       OK - %SYNCED% archivos sincronizados (addons/heren a fixtures)

echo.
echo [2/4] Headless compile check (godot --headless --editor --quit-after 5)...
"%GODOT%" --headless --editor --path "%PROJECT%" --quit-after 5 > "%COMPILE_LOG%" 2>&1
set "ERRORS=0"
for /f %%i in ('powershell -NoProfile -Command "(Select-String -Path '%COMPILE_LOG%' -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' | Measure-Object).Count"') do set "ERRORS=%%i"
if "%ERRORS%"=="0" (
    echo       OK - 0 parse errors. Plugin carga limpio.
) else (
    echo [FAIL] %ERRORS% parse errors detectados. Log: %COMPILE_LOG%
    powershell -NoProfile -Command "Select-String -Path '%COMPILE_LOG%' -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' | Select-Object -First 10"
    exit /b 1
)

echo.
echo [3/4] Tests GDScript (run_tests.gd)...
"%GODOT%" --headless --path "%PROJECT%" --script res://addons/heren/tests/run_tests.gd > "%TESTS_LOG%" 2>&1
powershell -NoProfile -Command "Select-String -Path '%TESTS_LOG%' -Pattern 'RESULT|FAIL ' | ForEach-Object { $_.Line }"
for /f "tokens=3,5" %%a in ('findstr /C:"RESULT:" "%TESTS_LOG%"') do (
    set "PASSED=%%a"
    set "FAILED=%%b"
)
if "%FAILED%"=="0" (
    echo       OK - %PASSED% tests passed.
) else (
    echo [FAIL] %FAILED% tests fallaron. Log: %TESTS_LOG%
    exit /b 1
)

echo.
echo [4/4] Verificando binario Rust (cargo build)...
where cargo > nul 2>&1
if errorlevel 1 (
    echo [SKIP] cargo no esta en PATH. Saltando build Rust.
) else (
    if not exist "crates\heren-server\Cargo.toml" (
        echo [SKIP] No hay crate local. Saltando.
    ) else (
        cargo build -p heren-server --quiet
        if errorlevel 1 (
            echo [FAIL] cargo build fallo. Log arriba.
            exit /b 1
        ) else (
            echo       OK - cargo build limpio.
        )
    )
)

echo.
echo ==========================================
echo VALIDACION COMPLETA - todo verde.
echo ==========================================
exit /b 0
