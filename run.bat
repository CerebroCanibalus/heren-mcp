@echo off
REM Heren MCP Launcher para OpenCode (fallback)
REM v4.2: el MCP activo es heren-server.exe DIRECTAMENTE (Content-Length framing nativo).
REM Este .bat queda como fallback/manual por si hace falta:
REM   "D:\Mis Juegos\ClaudeMCPs\FlojoMCP\target\release\heren-server.exe"

"D:\Mis Juegos\ClaudeMCPs\FlojoMCP\target\release\heren-server.exe" %*
