# API Reference - Heren MCP

Complete reference for all Heren MCP tools and their actions.

## Tools Overview

Heren MCP provides **15 centralized tools** that cover all Godot operations:

| Tool | Description | Actions |
|------|-------------|---------|
| `session` | Session management | `open`, `close`, `list`, `info`, `health` |
| `scene` | Scene operations | `get_tree`, `save`, `load`, `unload`, `list_loaded`, `screenshot`, `create`, `delete`, `rename` |
| `node` | Node operations | `add`, `remove`, `set_prop`, `get_prop`, `duplicate`, `rename`, `move` |
| `batch` | Batch execution | `execute` |
| `resource` | Resource management | `create`, `read`, `update`, `delete`, `list` |
| `animation` | Animations | `create_player`, `create`, `add_track`, `add_key`, `state_machine` |
| `skeleton` | Skeletons 2D/3D | `create`, `add_bone`, `set_rest`, `skin`, `attachment` |
| `shader` | Shaders & materials | `create`, `edit`, `validate`, `material`, `uniform` |
| `tilemap` | TileMaps & TileSets | `inspect_set`, `inspect_map`, `set_cell`, `terrain`, `pattern` |
| `project` | Project configuration | `setting`, `autoload`, `remove_autoload`, `shader_global` |
| `debug` | Debugging | `breakpoint`, `stack_trace`, `watch`, `console` |
| `validate` | Validation | `scene`, `script`, `node`, `resource` |
| `signal` | Node signals | `connect`, `disconnect`, `list`, `set_script` |
| `global` | Global configuration | `autoload`, `project_setting`, `shader_global` |
| `index` | Tool discovery | `list`, `info`, `example` |

---

## Session Tool

Manages connections to Godot projects.

### `session(action="open")`

Opens a new session with a Godot project.

```python
session(
    action="open",
    project_path="D:/YourGame",
    godot_path=None,      # Optional: auto-detected
    use_daemon=True       # Use WebSocket daemon (recommended)
)
```

**Returns:**
```json
{
  "success": true,
  "session_id": "abc123",
  "project_path": "D:/YourGame",
  "daemon_active": true
}
```

### `session(action="close")`

Closes a session.

```python
session(action="close", session_id="abc123")
```

### `session(action="list")`

Lists all active sessions.

```python
session(action="list")
```

### `session(action="health")`

Checks daemon health.

```python
session(action="health", session_id="abc123")
```

---

## Scene Tool

Operates on Godot scene files (.tscn).

### `scene(action="get_tree")`

Gets the node tree of a scene.

```python
scene(
    action="get_tree",
    session_id="abc123",
    scene_path="res://Player.tscn"
)
```

### `scene(action="create")`

Creates a new scene.

```python
scene(
    action="create",
    session_id="abc123",
    scene_path="res://NewScene.tscn",
    root_type="Node2D",
    root_name="Root"
)
```

### `scene(action="screenshot")`

Captures a screenshot (requires daemon).

```python
scene(
    action="screenshot",
    session_id="abc123",
    scene_path="res://Player.tscn",
    output_path="C:/temp/screenshot.png",
    resolution=(1920, 1080)
)
```

---

## Node Tool

Manipulates nodes within scenes.

### `node(action="add")`

Adds a node to a scene.

```python
node(
    action="add",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path=".",           # Parent path
    node_type="Sprite2D",
    node_name="Body",
    properties={
        "position": {"x": 100, "y": 200}
    }
)
```

### `node(action="set_prop")`

Sets a node property.

```python
node(
    action="set_prop",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path="Player",
    property_name="position",
    value={"x": 100, "y": 200}
)
```

---

## Signal Tool

Manages signals between nodes.

### `signal(action="connect")`

Connects a signal from one node to another.

```python
signal(
    action="connect",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D",
    signal_name="body_entered",
    to_node="Player",
    method="_on_area_body_entered"
)
```

### `signal(action="disconnect")`

Disconnects a signal.

```python
signal(
    action="disconnect",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D",
    signal_name="body_entered",
    to_node="Player",
    method="_on_area_body_entered"
)
```

### `signal(action="list")`

Lists all signals of a node.

```python
signal(
    action="list",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D"
)
```

### `signal(action="set_script")`

Assigns a script to a node.

```python
signal(
    action="set_script",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path="Player",
    script_path="res://scripts/player.gd"
)
```

---

## Global Tool

Manages project-wide configuration.

### `global_tool(action="autoload")` - Add

Adds an autoload.

```python
global_tool(
    action="autoload",
    session_id="abc123",
    autoload_name="GameManager",
    script_path="res://autoloads/game_manager.gd"
)
```

### `global_tool(action="autoload")` - Remove

Removes an autoload.

```python
global_tool(
    action="autoload",
    session_id="abc123",
    autoload_name="GameManager"
)
```

### `global_tool(action="autoload")` - List

Lists all autoloads.

```python
global_tool(
    action="autoload",
    session_id="abc123"
)
```

### `global_tool(action="project_setting")`

Reads or writes project settings.

```python
# Read
global_tool(
    action="project_setting",
    session_id="abc123",
    setting_name="display/window/size/viewport_width"
)

# Write
global_tool(
    action="project_setting",
    session_id="abc123",
    setting_name="display/window/size/viewport_width",
    value=1920
)
```

---

## Batch Tool

Executes multiple operations atomically.

```python
batch(
    session_id="abc123",
    operations=[
        {
            "action": "add",
            "params": {
                "scene_path": "res://Player.tscn",
                "parent_path": ".",
                "node_type": "Sprite2D",
                "node_name": "Body"
            }
        },
        {
            "action": "set_prop",
            "params": {
                "scene_path": "res://Player.tscn",
                "node_path": "Body",
                "property_name": "position",
                "value": {"x": 100, "y": 200}
            }
        }
    ],
    stop_on_error=True
)
```

---

## Index Tool

Discovers available tools.

```python
# List all tools
index(action="list")

# Get tool info
index(action="info", tool_name="scene")

# Get usage example
index(action="example", tool_name="node", action_name="add")
```

---

## Common Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `session_id` | `str` | Active session identifier |
| `scene_path` | `str` | Path to scene file (res:// or absolute) |
| `node_path` | `str` | Node path within scene (e.g., "Player/Sprite2D") |
| `action` | `str` | Operation to perform |

## Return Format

All tools return a dictionary:

```json
{
  "success": true,
  "data": { ... }
}
```

On error:

```json
{
  "success": false,
  "error": "Error description"
}
```

## Performance Notes

- **With Daemon**: Operations complete in ~20ms
- **Without Daemon**: Fallback to temporary scripts (~370ms)
- **Cache**: Scene trees are cached for 5 minutes

## Internationalization

Heren MCP supports English and Spanish. The system auto-detects your OS language.

To force a language:

```python
from heren.i18n import set_language
set_language("es")  # or "en"
```

See also: [API Reference (Spanish)](API.es.md)
