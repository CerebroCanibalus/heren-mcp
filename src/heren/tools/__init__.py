"""
Heren MCP Tools

Tools centralizadas siguiendo la filosofía:
- Centralizadas: 4 tools que agrupan TODO
- Modulares: múltiples modos via 'action'
- Potentes: Godot hace el trabajo pesado

Tools disponibles:
- session_tool: Gestión de sesiones
- scene_tool: Operaciones de escenas
- node_tool: Operaciones de nodos
- batch_tool: Ejecución batch
"""

from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool
from heren.tools.node_tool import node_tool
from heren.tools.batch_tools import heren_batch
from heren.tools.signal_tool import signal_tool
from heren.tools.global_tool import global_tool

__all__ = [
    "session_tool",
    "scene_tool",
    "node_tool",
    "heren_batch",
    "signal_tool",
    "global_tool",
]
