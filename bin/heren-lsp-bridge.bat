@echo off
REM Wrapper LSP bridge para OpenCode (Windows).
REM
REM OpenCode tiene un bug al pasar arrays `command` con paths con espacios:
REM ejecuta solo el primer elemento (el path del .bat) e ignora los args
REM adicionales. Workaround: hardcodeamos `lsp-bridge` aquí y usamos %~dp0
REM (directorio del propio script) para evitar que cmd.exe rompa el path
REM por los espacios.
REM
REM Uso desde OpenCode JSONC:
REM   "command": ["D:\\ruta\\a\\bin\\heren-lsp-bridge.bat"]
REM
REM Uso desde shell:
REM   heren-lsp-bridge.bat                          # auto-detecta todo
REM   heren-lsp-bridge.bat -v                      # verbose
REM   heren-lsp-bridge.bat --no-auto-launch-godot  # sin auto-launch

"%~dp0..\target\release\heren-server.exe" lsp-bridge %*
