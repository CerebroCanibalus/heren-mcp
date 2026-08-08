@echo off
REM Heren MCP v4 — lanza heren-server.exe (Rust, workspace local heren-mcp).
REM Mata heren-server.exe viejos primero (single-instance del WS server en 9099).
taskkill /F /IM heren-server.exe >nul 2>&1
"%~dp0target\release\heren-server.exe" %*
