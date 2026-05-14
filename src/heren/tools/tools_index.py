"""
Index Tool - Índice de todas las tools disponibles.

Esta tool permite a los subagentes descubrir qué tools existen
y qué actions pueden usar.
"""

TOOLS_INDEX = {
    "session": {
        "description": "Gestión de sesiones con Godot",
        "actions": ["open", "close", "list", "info", "health"],
        "examples": {
            "open": 'session(action="open", project_path="D:/MiProyecto")',
            "close": 'session(action="close", session_id="abc123")',
            "list": 'session(action="list")',
            "info": 'session(action="info", session_id="abc123")',
            "health": 'session(action="health", session_id="abc123")'
        }
    },
    "scene": {
        "description": "Operaciones de escenas",
        "actions": ["get_tree", "save", "load", "unload", "list_loaded", "screenshot", "create", "delete", "rename"],
        "examples": {
            "get_tree": 'scene(action="get_tree", session_id="abc", scene_path="res://Player.tscn")',
            "save": 'scene(action="save", session_id="abc", scene_path="res://Player.tscn")',
            "load": 'scene(action="load", session_id="abc", scene_path="res://Player.tscn")',
            "create": 'scene(action="create", session_id="abc", scene_path="res://NewScene.tscn", root_type="Node2D", root_name="Root")',
            "delete": 'scene(action="delete", session_id="abc", scene_path="res://OldScene.tscn")',
            "rename": 'scene(action="rename", session_id="abc", scene_path="res://Old.tscn", new_path="res://New.tscn")',
            "screenshot": 'scene(action="screenshot", session_id="abc", scene_path="res://Player.tscn", output_path="C:/temp/screenshot.png", resolution=(800, 600))'
        }
    },
    "node": {
        "description": "Operaciones de nodos",
        "actions": ["add", "remove", "set_prop", "get_prop", "duplicate", "rename", "move"],
        "examples": {
            "add": 'node(action="add", session_id="abc", scene_path="res://Player.tscn", node_path=".", node_type="Sprite2D", node_name="Sprite", properties={"position": {"x": 100, "y": 200}})',
            "remove": 'node(action="remove", session_id="abc", scene_path="res://Player.tscn", node_path="Player/OldNode")',
            "set_prop": 'node(action="set_prop", session_id="abc", scene_path="res://Player.tscn", node_path="Player", property_name="position", value={"x": 100, "y": 200})',
            "get_prop": 'node(action="get_prop", session_id="abc", scene_path="res://Player.tscn", node_path="Player", property_name="position")',
            "duplicate": 'node(action="duplicate", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D")',
            "rename": 'node(action="rename", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D", new_name="BodySprite")',
            "move": 'node(action="move", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D", new_parent="Player/Body")'
        }
    },
    "batch": {
        "description": "Ejecución batch de múltiples operaciones",
        "actions": ["execute"],
        "examples": {
            "execute": 'batch(session_id="abc", operations=[{"action": "add", "params": {"scene_path": "res://Player.tscn", "node_path": ".", "node_type": "Sprite2D", "node_name": "Sprite"}}, {"action": "save", "params": {"scene_path": "res://Player.tscn"}}])'
        }
    },
    "resource": {
        "description": "Gestión de recursos .tres",
        "actions": ["create", "read", "update", "delete", "list"],
        "examples": {
            "create": 'resource(action="create", session_id="abc", resource_path="res://materials/my_material.tres", resource_type="ShaderMaterial", properties={"shader": "res://shader.gdshader"})',
            "read": 'resource(action="read", session_id="abc", resource_path="res://materials/my_material.tres")',
            "update": 'resource(action="update", session_id="abc", resource_path="res://materials/my_material.tres", properties={"shader_parameter/outline_color": {"r": 1, "g": 0, "b": 0, "a": 1}})',
            "delete": 'resource(action="delete", session_id="abc", resource_path="res://materials/my_material.tres")',
            "list": 'resource(action="list", session_id="abc", directory="res://materials", extension=".tres", recursive=True)'
        }
    },
    "animation": {
        "description": "Animaciones y state machines",
        "actions": ["create_player", "create", "add_track", "add_key", "state_machine"],
        "examples": {
            "create_player": 'animation(action="create_player", session_id="abc", scene_path="res://Player.tscn", parent_path=".", player_name="AnimationPlayer")',
            "create": 'animation(action="create", session_id="abc", scene_path="res://Player.tscn", player_path="Player/AnimationPlayer", anim_name="idle", length=2.0, loop=True)',
            "add_track": 'animation(action="add_track", session_id="abc", scene_path="res://Player.tscn", player_path="Player/AnimationPlayer", anim_name="idle", track_type="value", node_path="Player/Sprite2D", property="position")',
            "add_key": 'animation(action="add_key", session_id="abc", scene_path="res://Player.tscn", player_path="Player/AnimationPlayer", anim_name="idle", track_idx=0, time=0.0, value={"x": 0, "y": 0})',
            "state_machine": 'animation(action="state_machine", session_id="abc", scene_path="res://Player.tscn", player_path="Player/AnimationPlayer", states=[{"name": "Idle", "animation": "idle"}], transitions=[{"from": "Idle", "to": "Idle"}])'
        }
    },
    "skeleton": {
        "description": "Esqueletos 2D/3D",
        "actions": ["create", "add_bone", "set_rest", "skin", "attachment"],
        "examples": {
            "create": 'skeleton(action="create", session_id="abc", scene_path="res://Player.tscn", parent_path=".", skeleton_name="Skeleton2D", is_3d=False)',
            "add_bone": 'skeleton(action="add_bone", session_id="abc", scene_path="res://Player.tscn", skeleton_path="Player/Skeleton2D", bone_name="RootBone", length=32.0, bone_angle=0.0)',
            "set_rest": 'skeleton(action="set_rest", session_id="abc", scene_path="res://Player.tscn", skeleton_path="Player/Skeleton3D", bone_name="RootBone", rest_transform={"x": 0, "y": 0, "z": 0})',
            "skin": 'skeleton(action="skin", session_id="abc", scene_path="res://Player.tscn", polygon_path="Player/Polygon2D", skeleton_path="Player/Skeleton2D")',
            "attachment": 'skeleton(action="attachment", session_id="abc", scene_path="res://Player.tscn", skeleton_path="Player/Skeleton3D", bone_name="RootBone", attachment_name="Weapon")'
        }
    },
    "shader": {
        "description": "Shaders y materiales",
        "actions": ["create", "edit", "validate", "material", "uniform"],
        "examples": {
            "create": 'shader(action="create", session_id="abc", shader_path="res://shaders/outline.gdshader", shader_type="canvas_item", code="uniform vec4 color : source_color = vec4(1.0, 0.0, 0.0, 1.0);\\nvoid fragment() { COLOR = color; }")',
            "edit": 'shader(action="edit", session_id="abc", shader_path="res://shaders/outline.gdshader", code="// Nuevo código", append=True)',
            "validate": 'shader(action="validate", session_id="abc", shader_path="res://shaders/outline.gdshader")',
            "material": 'shader(action="material", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D", shader_path="res://shaders/outline.gdshader", uniforms={"color": {"r": 1, "g": 0, "b": 0, "a": 1}})',
            "uniform": 'shader(action="uniform", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D", uniform_name="color", value={"r": 0, "g": 1, "b": 0, "a": 1})'
        }
    },
    "tilemap": {
        "description": "TileMaps y TileSets",
        "actions": ["inspect_set", "inspect_map", "set_cell", "terrain", "pattern"],
        "examples": {
            "inspect_set": 'tilemap(action="inspect_set", session_id="abc", tileset_path="res://tilesets/ground.tres")',
            "inspect_map": 'tilemap(action="inspect_map", session_id="abc", scene_path="res://Level.tscn", tilemap_path="Level/TileMap")',
            "set_cell": 'tilemap(action="set_cell", session_id="abc", scene_path="res://Level.tscn", tilemap_path="Level/TileMap", layer=0, coords={"x": 5, "y": 3}, atlas_coords={"x": 1, "y": 0})',
            "terrain": 'tilemap(action="terrain", session_id="abc", scene_path="res://Level.tscn", tilemap_path="Level/TileMap", layer=0, cells=[{"x": 5, "y": 3}, {"x": 6, "y": 3}], terrain_set=0, terrain=0)',
            "pattern": 'tilemap(action="pattern", session_id="abc", scene_path="res://Level.tscn", tilemap_path="Level/TileMap", layer=0, region={"x": 0, "y": 0, "w": 3, "h": 3})'
        }
    },
    "project": {
        "description": "Configuración del proyecto",
        "actions": ["setting", "autoload", "remove_autoload", "shader_global"],
        "examples": {
            "setting": 'project(action="setting", session_id="abc", setting_name="display/window/size/viewport_width", value=1920)',
            "autoload": 'project(action="autoload", session_id="abc", autoload_name="GameManager", script_path="res://autoloads/game_manager.gd")',
            "remove_autoload": 'project(action="remove_autoload", session_id="abc", autoload_name="GameManager")',
            "shader_global": 'project(action="shader_global", session_id="abc", global_name="time", value=0.0)'
        }
    },
    "debug": {
        "description": "Depuración",
        "actions": ["breakpoint", "stack_trace", "watch", "console"],
        "examples": {
            "breakpoint": 'debug(action="breakpoint", session_id="abc", script_path="res://scripts/player.gd", line=42, enabled=True)',
            "stack_trace": 'debug(action="stack_trace", session_id="abc")',
            "watch": 'debug(action="watch", session_id="abc", variable_name="player_health")',
            "console": 'debug(action="console", session_id="abc", lines=50)'
        }
    },
    "validate": {
        "description": "Validación",
        "actions": ["scene", "script", "node", "resource"],
        "examples": {
            "scene": 'validate(action="scene", session_id="abc", scene_path="res://Player.tscn")',
            "script": 'validate(action="script", session_id="abc", script_path="res://scripts/player.gd")',
            "node": 'validate(action="node", session_id="abc", scene_path="res://Player.tscn", node_path="Player/Sprite2D")',
            "resource": 'validate(action="resource", session_id="abc", resource_path="res://materials/my_material.tres")'
        }
    },
    "signal": {
        "description": "Señales entre nodos",
        "actions": ["connect", "disconnect", "list", "set_script"],
        "examples": {
            "connect": 'signal(action="connect", session_id="abc", scene_path="res://Player.tscn", from_node="Player/Area2D", signal_name="body_entered", to_node="Player", method="_on_area_body_entered")',
            "disconnect": 'signal(action="disconnect", session_id="abc", scene_path="res://Player.tscn", from_node="Player/Area2D", signal_name="body_entered", to_node="Player", method="_on_area_body_entered")',
            "list": 'signal(action="list", session_id="abc", scene_path="res://Player.tscn", from_node="Player/Area2D")',
            "set_script": 'signal(action="set_script", session_id="abc", scene_path="res://Player.tscn", node_path="Player", script_path="res://scripts/player.gd")'
        }
    },
    "global": {
        "description": "Configuración global del proyecto",
        "actions": ["autoload", "project_setting", "shader_global"],
        "examples": {
            "autoload": 'global_tool(action="autoload", session_id="abc", autoload_name="GameManager", script_path="res://autoloads/game_manager.gd")',
            "project_setting": 'global_tool(action="project_setting", session_id="abc", setting_name="display/window/size/viewport_width", value=1920)',
            "shader_global": 'global_tool(action="shader_global", session_id="abc", global_name="time", value=0.0)'
        }
    }
}


def get_tool_info(tool_name: str) -> dict:
    """Obtiene información de una tool específica."""
    return TOOLS_INDEX.get(tool_name, {"error": f"Tool no encontrada: {tool_name}"})


def list_tools() -> dict:
    """Lista todas las tools disponibles."""
    return {
        "success": True,
        "tools_count": len(TOOLS_INDEX),
        "tools": [
            {
                "name": name,
                "description": info["description"],
                "actions": info["actions"]
            }
            for name, info in TOOLS_INDEX.items()
        ]
    }


def get_action_example(tool_name: str, action: str) -> str:
    """Obtiene un ejemplo de uso para un action específico."""
    tool = TOOLS_INDEX.get(tool_name)
    if not tool:
        return f"Tool no encontrada: {tool_name}"
    
    examples = tool.get("examples", {})
    return examples.get(action, f"No hay ejemplo para {tool_name}.{action}")
