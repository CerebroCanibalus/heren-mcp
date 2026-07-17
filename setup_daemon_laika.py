import sys
sys.path.insert(0, r"D:\Mis Juegos\GodotMCP\heren-mcp\src")

from heren.tools.project_tool import _action_setup_daemon
from heren.core.session_manager import get_session_manager

PROJECT = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"
result = _action_setup_daemon(get_session_manager(), PROJECT)
print(result)
