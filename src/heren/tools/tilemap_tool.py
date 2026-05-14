"""
TileMap Tool - Gestión centralizada de TileMaps y TileSets.

Actions:
- inspect_set: Inspeccionar TileSet
- inspect_map: Inspeccionar TileMap
- set_cell: Setear celda
- terrain: Aplicar terrain
- pattern: Crear/aplicar pattern
"""

import logging
from heren.core.session_manager import get_session_manager

logger = logging.getLogger(__name__)


def tilemap(action: str, **kwargs) -> dict:
    """Tool centralizada para TileMaps."""
    session_manager = get_session_manager()
    
    actions_map = {
        "inspect_set": _action_inspect_set,
        "inspect_map": _action_inspect_map,
        "set_cell": _action_set_cell,
        "terrain": _action_terrain,
        "pattern": _action_pattern,
    }
    
    if action not in actions_map:
        return {
            "success": False,
            "error": f"Acción desconocida: {action}. Disponibles: {list(actions_map.keys())}"
        }
    
    try:
        return actions_map[action](session_manager, **kwargs)
    except Exception as e:
        logger.error(f"Error en tilemap({action}): {e}")
        return {"success": False, "error": str(e)}


def _action_inspect_set(session_manager, tileset_path: str, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("inspect_tileset", {"tileset_path": tileset_path})
    return {"success": False, "error": "Daemon no disponible"}


def _action_inspect_map(session_manager, scene_path: str, tilemap_path: str, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("inspect_tilemap", {
            "scene_path": scene_path,
            "tilemap_path": tilemap_path
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_set_cell(session_manager, scene_path: str, tilemap_path: str, layer: int = 0, coords: dict = None, atlas_coords: dict = None, source_id: int = 0, alternative_tile: int = 0, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("set_tilemap_cell", {
            "scene_path": scene_path,
            "tilemap_path": tilemap_path,
            "layer": layer,
            "coords": coords or {},
            "atlas_coords": atlas_coords or {},
            "source_id": source_id,
            "alternative_tile": alternative_tile
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_terrain(session_manager, scene_path: str, tilemap_path: str, layer: int = 0, cells: list = None, terrain_set: int = 0, terrain: int = 0, **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("apply_terrain", {
            "scene_path": scene_path,
            "tilemap_path": tilemap_path,
            "layer": layer,
            "cells": cells or [],
            "terrain_set": terrain_set,
            "terrain": terrain
        })
    return {"success": False, "error": "Daemon no disponible"}


def _action_pattern(session_manager, scene_path: str, tilemap_path: str, layer: int = 0, region: dict = None, pattern_name: str = "Pattern", **kwargs) -> dict:
    session = session_manager.get_active_session()
    if not session:
        return {"success": False, "error": "No hay sesión activa"}
    
    daemon = session_manager.get_godot_daemon(session.id)
    if daemon:
        return daemon.call("create_tile_pattern", {
            "scene_path": scene_path,
            "tilemap_path": tilemap_path,
            "layer": layer,
            "region": region or {},
            "pattern_name": pattern_name
        })
    return {"success": False, "error": "Daemon no disponible"}
