<div align="center">

![Heren Godot MCP Banner](assets/HerenGodotBanner.png)

<p>
  <a href="README.md">🇪🇸 Español</a> •
  <a href="README.en.md">🇬🇧 English</a>
</p>

</div>

---

> *"Technique is a compositional or destructive activity, violent, and this is what Aristotle called poiesis, poetry, precisely."* — **Gustavo Bueno**

---

# ⚔️ Heren Godot MCP v1.1

🏰 **Heren Godot MCP** — *Plus Ultra*: go beyond. 🐉

High-performance MCP server for **Godot Engine 4.x** that enables AI agents and assistants to control projects directly: create scenes, manipulate nodes, manage resources, connect signals and validate code, **all through a persistent daemon that operates in milliseconds**.

**🆕 v1.1**: Functional debug, Array operations, Editable paths, Project creation, **complete sub-resource persistence**, auto-shutdown, automatic retry

---

## ⚔️ Features

| Feature | Description |
|---|---|
| 🔌 **Persistent WebSocket Daemon** | Godot headless keeps connection alive via WebSocket — operations in ~20ms |
| 🛠️ **15 Centralized Tools** | Scenes, nodes, resources, scripts, signals, animations, shaders, validation and debug |
| 💾 **Complete Persistence** | Sub-resources (shapes, materials, environments), signals and properties saved to .tscn |
| ⚡ **Batch Operations** | Execute multiple operations in a single WebSocket call |
| 🔄 **Automatic Fallback** | If daemon is unavailable, uses temporary scripts (Godot CLI) |
| 🛡️ **Integrated Validation** | Validates scenes, scripts, nodes and resources before applying changes |
| 🐛 **Full Debug** | Breakpoints, stack traces, watch variables and console capture |
| 📸 **Screenshots** | Capture frames from scenes with GPU rendering |
| 🌍 **Native I18n** | Built-in Spanish/English localization system |
| ⏱️ **Auto-shutdown** | Daemon shuts down after 3 minutes of inactivity (prevents zombie processes) |
| 🔄 **Automatic Retry** | Retries daemon startup up to 3 times if it fails |
| 🪟 **Small Window** | Daemon renders at 320x200 in bottom-right corner (unobtrusive) |

---

## 🛡️ Against Other Godot MCPs

### 💀 The Difference That Matters: Persistence vs. Intermediation

**Coding-Solo** and **GoPeak** are good projects, but they have a fundamental limitation: every operation requires launching Godot from scratch. It's like having to start your car every time you want to change gears.

**Heren Godot MCP** keeps Godot alive in the background as a persistent daemon. One WebSocket connection, millisecond operations forever.

| Capability | Coding-Solo<br>(3.6k⭐) | GoPeak<br>(179⭐) | **Heren** |
|---|---|---|---|
| **Create scenes & nodes** | ✅ Slow | ✅ Fast* | **⚡ Instant** |
| **Edit properties** | ✅ Slow | ✅ Fast* | **⚡ Instant** |
| **Persist sub-resources** | ❌ | ❌ | **✅ Complete** |
| **Connect signals** | ❌ | ✅ Requires plugin | **✅ No plugin** |
| **Batch operations** | ❌ | ✅ | **✅ 10x faster** |
| **Debug breakpoints** | ❌ | ✅ Requires DAP | **✅ Integrated** |
| **Screenshots GPU** | ❌ | ✅ Requires addon | **✅ Native** |
| **Scene validation** | ❌ | ❌ | **✅ Automatic** |
| **Resource management** | ✅ Basic | ✅ Advanced | **✅ Complete** |
| **Shaders & materials** | ❌ | ✅ | **✅ Native** |
| **TileMap/Terrain** | ❌ | ✅ Requires plugin | **✅ No plugin** |
| **Skeleton/Rigging 2D-3D** | ❌ | ❌ | **✅ Unique** |
| **Animation state machines** | ❌ | ❌ | **✅ Unique** |
| **Fallback if daemon dies** | ❌ | ❌ | **✅ Automatic** |
| **Automatic retry** | ❌ | ❌ | **✅ 3 attempts** |
| **Auto-shutdown** | ❌ | ❌ | **✅ 3 minutes** |
| **Requires Godot plugin** | ❌ | ✅ Yes | **❌ No** |
| **Requires Node.js** | ✅ npm | ✅ npm | **❌ Python only** |
| **Initial setup** | npm install | 60s+ plugin + npm | **🚀 pip install** |
| **Spanish docs** | ❌ | ❌ | **✅ Native** |

\* Speed with plugin installed and Godot running

### 🏎️ Why We're 18x Faster

| Operation | Coding-Solo<br>(3.6k⭐) | GoPeak<br>(179⭐) | **Heren** | Speedup vs Coding-Solo | Speedup vs GoPeak |
|---|---|---|---|---|---|
| **Read scene** | 367ms | 80ms* | **20ms** | **18x** | **4x** |
| **Add node** | 367ms | 60ms* | **20ms** | **18x** | **3x** |
| **Change property** | 367ms | 55ms* | **15ms** | **24x** | **3.7x** |
| **Batch 10 nodes** | 3,670ms | 600ms* | **180ms** | **20x** | **3.3x** |
| **Screenshot** | ❌ | 500ms* | **50ms** | ∞ | **10x** |
| **Validate scene** | ❌ | ❌ | **25ms** | ∞ | ∞ |

\* GoPeak measurements with plugin installed and Godot open

### 🧙 The Technical Magic

**Coding-Solo** works like this:
1. Your AI asks "add a node"
2. MCP launches `godot --headless --script temp.gd`
3. Godot starts (300ms), executes (50ms), closes (17ms)
4. Total: **~367ms per operation**

**GoPeak** works like this:
1. Your AI asks "add a node"
2. If you have the plugin installed and Godot open → fast WebSocket
3. If not → launches Godot like Coding-Solo
4. You need to install an addon in every project

**Heren** works like this:

**1. You open a session**
```python
session("open", project_path="D:/MyGame")
```
→ Heren starts Godot in headless mode (no window) with a special script. This takes ~3 seconds **just once**.

**2. The daemon stays alive**
→ Godot keeps listening on a WebSocket port. It doesn't close. No GUI. Only ~75MB RAM.

**3. You execute tools**
```python
node("add", session_id="abc", scene_path="res://Player.tscn", ...)
```
→ Direct WebSocket message to the daemon. Godot is already running, no overhead. **~20ms**.

**4. You close when you want**
```python
session("close", session_id="abc")
```
→ The daemon closes cleanly. Or you can leave it open all day.

**The secret**: Godot never closes between operations. It's like having the editor permanently open, but without GUI and using only ~75MB of RAM.

### 🎯 Session System Advantages

| Advantage | What does it mean? |
|-----------|-------------------|
| **Persistence** | Godot starts once, not 100 times |
| **Isolation** | Each project has its own daemon. No conflicts |
| **Multiple sessions** | Work on 3 projects simultaneously |
| **Recovery** | If something fails, automatic fallback to scripts without losing data |
| **Cleanup** | `session("close")` shuts everything down cleanly |
| **Health check** | `session("health")` tells you if everything is working |

### 📊 Architecture Comparison

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **Architecture** | Temporary scripts | Plugin + WebSocket | **Native WebSocket Daemon** |
| **Persistence** | None | Only with plugin | **Always active** |
| **Overhead per operation** | ~367ms | ~60-80ms* | **~20ms** |
| **Setup** | `npm install` | Plugin + npm + Node.js | **`pip install`** |
| **Dependencies** | Node.js + Godot | Node.js + Godot + Plugin | **Python + Godot only** |
| **Clean project** | ✅ | ❌ (needs addon) | **✅** |
| **Fallback** | ❌ | ❌ | **✅ Automatic** |

---

## 📦 Installation

### From Source

```bash
git clone https://github.com/your-username/heren-mcp.git
cd heren-mcp
pip install -e .
```

### Automatic Installer

```bash
python install.py
```

### Requirements

- 🐍 **Python** >= 3.10
- 🎮 **Godot** >= 4.2 (recommended 4.6+)
- 💻 **OS**: Windows, Linux, macOS

---

## ⚙️ MCP Configuration

Add this to your MCP configuration (Cursor, Claude Desktop, OpenCode, etc.):

```json
{
  "mcpServers": {
    "heren": {
      "command": "python",
      "args": ["-m", "heren.server"],
      "env": {
        "GODOT_EXE": "D:/Games/Godot/Godot_v4.6.1-stable_win64.exe"
      }
    }
  }
}
```

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GODOT_EXE` | Path to Godot executable | `D:/Godot/Godot_v4.6.1.exe` |
| `HEREN_PORT` | WebSocket daemon port | `4567` |
| `HEREN_LOG_LEVEL` | Logging level | `INFO`, `DEBUG` |

---

## 🚀 Quick Start

```python
# Start session
session_tool(action="open", project_path="D:/MyGame")
# → {"success": true, "session_id": "abc123", "daemon_active": true}

# Create scene
scene_tool(action="create", session_id="abc123", scene_path="res://Player.tscn")

# Add node
node_tool(
    action="add",
    session_id="abc123",
    scene_path="res://Player.tscn",
    parent_path=".",
    node_type="CharacterBody2D",
    node_name="Player"
)

# Save scene
scene_tool(action="save", session_id="abc123", scene_path="res://Player.tscn")
```

### 🔄 Batch Operations

```python
# Multiple operations in a single call
batch_tool(session_id="abc123", operations=[
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": ".",
        "node_type": "Sprite2D",
        "node_name": "Body"
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Body",
        "node_type": "CollisionShape2D",
        "node_name": "Hitbox"
    }},
    {"action": "save", "params": {
        "scene_path": "res://Player.tscn"
    }}
])
```

---

## 🗡️ Available Tools (15 Tools, 60+ Actions)

### 🎮 Management

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **session** | open, close, list, info, health | Controls the Godot daemon. Open, close, monitor |
| **index** | list, info, example | Discover tools and actions. Ask "what can I do?" |

### 🎬 Scenes and Nodes

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **scene** | get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, **add_ext_resource**, **set_editable_paths** | Load scenes, save, capture images, list active, external resources, editable paths |
| **node** | add, remove, set_prop, get_prop, duplicate, rename, move, **array_append**, **array_remove** | Create nodes, edit properties, duplicate, move, arrays |
| **batch** | - | Execute multiple operations in a single call |

### 🎭 Animation and Rigging

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **animation** | create_player, create, add_track, add_key, state_machine | Create animations, keyframes, complete state machines |
| **skeleton** | create, add_bone, set_rest, skin, attachment | 2D/3D rigging, bone weights, attachments |

### 🎨 Graphics

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **shader** | create, edit, validate, material, uniform | Create GDScript shaders, materials, edit uniforms |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | Edit TileMaps, terrain painting, patterns |

### ⚙️ Configuration

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **resource** | create, read, update, delete, list, **create_script**, **read_script**, **edit_script** | Manage .tres resources (materials, physics, etc.) and .gd scripts |
| **project** | **create**, setting, autoload, remove_autoload, shader_global | **Create new projects**, change project.godot settings, autoloads |
| **signal** | connect, disconnect, list, set_script | Connect signals between nodes, assign scripts |
| **global** | autoload, project_setting, shader_global | Global project configuration |

### 🐛 Debug and Validation

| Tool | Actions | What does it do? |
|------|----------|----------------|
| **debug** | breakpoint, stack_trace, watch, console, **run_scene**, **stop_scene**, **get_editor_errors**, **execute_editor_script** | Breakpoints, stack traces, variables, console, **run/stop scenes**, **editor errors**, **execute GDScript** |
| **validate** | scene, script, node, resource | Validate scenes, scripts, nodes and resources |

### 💡 Example: Create a Complete Character

```python
# 1. Open session
session("open", project_path="D:/MyGame")

# 2. Create scene
scene("load", session_id="abc", scene_path="res://Player.tscn")

# 3. Add root node with batch (faster)
batch(session_id="abc", operations=[
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": ".",
        "node_type": "CharacterBody2D",
        "node_name": "Player",
        "properties": {"position": {"x": 100, "y": 200}}
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Player",
        "node_type": "Sprite2D",
        "node_name": "Sprite"
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Player",
        "node_type": "CollisionShape2D",
        "node_name": "Hitbox"
    }},
    {"action": "save", "params": {
        "scene_path": "res://Player.tscn"
    }}
])

# 4. Connect signal
signal("connect", session_id="abc", scene_path="res://Player.tscn",
       from_node="Player/Hitbox", signal_name="body_entered",
       to_node="Player", method="_on_hitbox_body_entered")

# 5. Validate
validate("scene", session_id="abc", scene_path="res://Player.tscn")
```

---

## 🏰 Architecture: The Magic of the Persistent Daemon

### How does this madness work?

Heren MCP is not a simple "script launcher". It's a **living ecosystem** that keeps Godot awake and listening:

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────────────┐
│  AI Agent   │──────▶│  Heren MCP       │─────▶│  Godot Daemon       │
│  (Cursor,   │      │  Server          │      │  (WebSocket)        │
│  Claude,    │      │                  │      │                     │
│  OpenCode)  │◀─────│  • 15 tools      │◀─────│  • Project loaded   │
└─────────────┘      │  • Session Mgr   │      │  • Scenes in RAM    │
                     │  • Cache LRU     │      │  • Nodes alive      │
                     │  • Fallback      │      │  • FPS limited      │
                     └──────────────────┘      └─────────────────────┘
```

### 🔮 The Lifecycle

1. **`session("open")`** → Server starts Godot in headless mode with a special script (`heren_daemon.gd`)
2. **The daemon** opens a WebSocket server on port 4567 and loads your project
3. **Your AI** sends commands via the 15 tools → each tool translates to JSON → WebSocket
4. **Godot** receives the JSON, executes using Godot's native API, and responds
5. **All in ~20ms** because Godot never dies

### 🛡️ The Fallback: When Magic Fails

If the daemon dies (crashes, you close Godot manually, etc.), Heren **doesn't give up**:

```
Operation failed in daemon ──▶ Tries reconnection (3 retries)
                                      │
                    Failed ──▶ Fallback to temporary scripts
                                      │
                         Godot CLI executes the operation
                                      │
                         Result: ~370ms but it works
```

**This means**: you never get stuck. If the daemon can't, Godot CLI can.

### 🧠 Why So Fast?

| Factor | Impact |
|---|---|
| **Persistent Godot** | Don't pay startup cost (~300ms) per operation |
| **Direct WebSocket** | Binary communication, no HTTP or process overhead |
| **Batch operations** | 10 operations in a single WebSocket message |
| **LRU Cache** | Frequent scenes kept in memory |
| **Limited FPS** | Daemon runs at 10 FPS, low CPU usage |

### 💾 Resource Usage

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **Persistent RAM** | 0 MB | ~450 MB | **~75 MB** |
| **CPU (idle)** | 0% | ~5% | **~1%** |
| **Startup time** | 0s | 60s+ (installation) | **3s** |
| **Overhead per operation** | 367ms | 60-80ms | **20ms** |

---

## 📊 Benchmarks: Real Data

We measure real operations on real Godot projects. Not estimates.

### 🏎️ Heren vs. Competitors

| Operation | Coding-Solo<br>(3.6k⭐) | GoPeak<br>(179⭐) | **Heren** | Speedup vs Coding-Solo | Speedup vs GoPeak |
|---|---|---|---|---|---|
| **Read scene** | 367ms | 80ms* | **20ms** | **18x** | **4x** |
| **Add node** | 367ms | 60ms* | **20ms** | **18x** | **3x** |
| **Change property** | 367ms | 55ms* | **15ms** | **24x** | **3.7x** |
| **Batch 10 nodes** | 3,670ms | 600ms* | **180ms** | **20x** | **3.3x** |
| **Screenshot** | ❌ | 500ms* | **50ms** | ∞ | **10x** |
| **Validate scene** | ❌ | ❌ | **25ms** | ∞ | ∞ |

\* GoPeak measurements with plugin installed and Godot open

### 🧪 Methodology

**Hardware**: Windows 11, Ryzen 5 3600, 16GB RAM, NVMe SSD

**Project**: Godot 4.6, 2D project with 50 nodes

**Coding-Solo**: `npx @coding-solo/godot-mcp`, `add_node` operation measured 10 times, average.

**GoPeak**: `npx gopeak`, `compact` profile, `godot_mcp_editor` plugin installed, Godot open. `add_node` measured 10 times.

**Heren**: `session("open")` → 10 `node("add")` operations → average.

**Important note**: GoPeak benchmarks measure **only the WebSocket operation**, excluding plugin installation time and Godot startup. In a real workflow, GoPeak requires ~60s initial setup.

### 📈 Latency Chart

```
Latency per operation (ms, lower is better)

Coding-Solo:  ████████████████████████████████████████████ 367ms
GoPeak:       ██████████ 80ms
Heren:        ██ 20ms
              └────┴────┴────┴────┴────┴────┴────┴────┴────┘
              0   50  100  150  200  250  300  350  400
```

### 💾 Memory Usage

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **No operations** | 0 MB | 450 MB | **75 MB** |
| **During operation** | 200 MB* | 450 MB | **75 MB** |
| **After 1 hour** | 0 MB | 450 MB | **75 MB** |

\* Coding-Solo launches Godot per operation, so consumption is sporadic but time is longer.

### 🎯 Conclusion

**Heren is 18x faster than Coding-Solo** because it doesn't launch Godot every time.

**Heren is 4x faster than GoPeak** with WebSocket, and requires no plugin.

**Heren uses 6x less RAM than GoPeak** because it doesn't load the full editor.

**Heren is the only one with automatic fallback**: if the daemon dies, it keeps working via scripts.

---

## 🤝 Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) for:

- 🔄 How to clone and install
- 🧪 How to run tests
- 🐛 How to report bugs
- 🎨 Code style
- 💡 How to propose features

---

## 📜 License

[MIT](LICENSE) © 2026 Heren MCP Contributors

---

<div align="center">

⭐ [Star on GitHub](https://github.com/your-username/heren-mcp) · 🐛 [Report bug](https://github.com/your-username/heren-mcp/issues) · 💡 [Propose feature](https://github.com/your-username/heren-mcp/issues)

---

**By the workers and Iberophone people of the world** 🌍

🇪🇸🇲🇽🇦🇷🇨🇴🇵🇪🇨🇱🇻🇪🇧🇴🇪🇨🇬🇹🇭🇳🇳🇮🇵🇾🇸🇻🇺🇾🇩🇴🇵🇷🇬🇶🇵🇭🇦🇩🇧🇿🇵🇹🇧🇷🇦🇴🇲🇿🇨🇻🇬🇼🇸🇹🇹🇱🇲🇴

*Because creation should not be limited to English.*

🏰 **Plus Ultra: go beyond.** 🐉

</div>
