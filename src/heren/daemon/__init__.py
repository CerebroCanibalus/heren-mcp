"""
Heren Daemon - Proceso Godot persistente via WebSocket.

Este m�dulo proporciona comunicaci�n de alta velocidad con Godot
manteniendo el proyecto cargado en memoria.
"""

from .godot_daemon import GodotDaemon

__all__ = ["GodotDaemon"]
