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

# ⚡ Heren Godot MCP v4.2

🔥 **Heren Godot MCP** — *Plus Ultra*: go beyond. 🌍

High-performance MCP server for **Godot Engine 4.x** that lets AI agents control the **real editor** directly: create scenes, manipulate nodes, manage resources, connect signals, animate, rig skeletons, shaders and validate code. **All against the live editor, with real Undo/Redo.**

**📢 v4.2**: MCP is now 100% **Rust** (~7 MB, no runtime), built on **[FlojoMCP](https://github.com/CerebroCanibalus/flojomcp)** — the high-performance MCP framework in Rust. Direct connection to the **Godot Editor** via an EditorPlugin with auto-reconnect and auto-launch.

---

## 🚀 Features

| Feature | Description |
|---|---|
| ⚡ **Rust server (FlojoMCP)** | `heren-server.exe` ~**7 MB**, no Python or Node.js. Instant startup, compile-time schemas |
| 🎯 **Real editor, not a daemon** | Connects to the **EditorPlugin** inside the open Godot — Undo/Redo, real 2D/3D viewports, EditorFileSystem |
| 🔄 **Editor auto-launch** | `session/open` launches Godot, installs the plugin, enables `[editor_plugins]` and waits for the WS connection. Reuses an open editor; cleanly relaunches if a zombie one exists |
| 🛠️ **15 centralized tools** | Scenes, nodes, resources, scripts, signals, animations, skeletons, shaders, tilemaps, validation, debug |
| 👀 **Vision system** | Cost hierarchy: textual coordinates → summary/ASCII → capture of the real editor 2D/3D viewports, with a token budget |
| ↩️ **Built-in Undo/Redo** | Every mutation goes through `EditorUndoRedoManager` — Ctrl+Z undoes what the AI created |
| ⚡ **`orchestrate`** | Runs multiple operations in one call, with a plan file for complex plans |
| 🏗️ **Create projects from scratch** | `project/create` generates project.godot + main scene without needing an editor |

---

## 🆚 Versus other Godot MCPs

**Coding-Solo** and **GoPeak** are good projects, but they either launch Godot from scratch per operation, or rely on an external daemon that can't touch the real editor.

**Heren Godot MCP v4** lives **inside** the real editor: an EditorPlugin that talks to the Rust server over a local WebSocket. It's not "operating blindly on files", it's **controlling the editor the user sees**.

| Capability | Coding-Solo | GoPeak | **Heren v4** |
|---|---|---|---|
| **Server** | Node.js | Node.js | **Rust (7 MB, no runtime)** |
| **Undo/Redo** | ❌ | ❌ | **✅ EditorUndoRedoManager** |
| **Real editor** | ❌ | ❌ | **✅ EditorPlugin** |
| **Editor auto-launch** | ❌ | ❌ | **✅** |
| **Vision (real viewports)** | ❌ | ❌ | **✅ 2D/3D + budget** |
| **Session** | ❌ | ❌ | **✅ live connected editor** |
| **2D/3D skeletons** | ❌ | ⚡ | **✅** |
| **Reliable schemas** | runtime | runtime | **✅ compile-time** |

---

## 📦 Installation

### Requirements

- 🦀 **Rust** (to compile) — or download a prebuilt `.exe`
- ⚙️ **Godot** >= 4.2 (4.6+ recommended)
- 💻 **Windows / Linux / macOS**

### From source

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp

# Option A: automatic installer (compiles + registers MCP + verifies)
python install_mcp.py

# Option B: manual
cargo build --release
# → target/release/heren-server.exe
```

> `install_mcp.py` compiles the server, registers the `heren` MCP in your
> `opencode.jsonc` (auto-detects paths) and verifies startup. See
> [docs/INSTALL.md](docs/INSTALL.md).

### MCP configuration (OpenCode, Claude Desktop, Cursor, etc.)

```json
{
  "mcpServers": {
    "heren": {
      "command": "path/to/heren-server.exe",
      "environment": {
        "GODOT_EXE": "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe"
      }
    }
  }
}
```

> The server speaks **NDJSON over stdio** (the standard MCP framing). The editor auto-launches on `session/open`.

### Environment variables

| Variable | Description |
|----------|-------------|
| `GODOT_EXE` | Path to the Godot executable |
| `GODOT_PATH` | Alias for `GODOT_EXE` |
| `HEREN_PLUGIN_SOURCE` | Path to the source plugin (default `addons/heren/`) |
| `HEREN_LOG_FILE` | Log file (optional; the server never floods stderr) |

---

## 🚀 Quick Start

```python
# Open a session: launches the editor (if needed), installs the plugin, connects
session(action="open", project_path="D:/MyGame")
# → {"launched": true, "message": "launched", "ok": true}

# Create a scene
scene(action="create", project_path="D:/MyGame", scene_path="res://Player.tscn")

# Add a node (with Undo/Redo)
node(
    action="add",
    project_path="D:/MyGame",
    parent_path=".",
    node_type="CharacterBody2D",
    node_name="Player"
)

# Save
scene(action="save", project_path="D:/MyGame")
```

> ⚠️ In OpenCode the tools appear with a `godot_` prefix (e.g. `godot_session`, `godot_node`, `godot_scene`).

### 🔹 Batch with `orchestrate`

```python
# Multiple operations in a single call
orchestrate(
    project_path="D:/MyGame",
    plan={"ops": [
        {"tool": "node", "args": {"action": "add", "node_type": "Sprite2D", "node_name": "Body"}},
        {"tool": "node", "args": {"action": "add", "node_type": "CollisionShape2D", "node_name": "Hitbox"}},
        {"tool": "scene", "args": {"action": "save"}}
    ]},
    on_error="stop"
)
```

---

## 🛠️ The 15 Tools (60+ Actions)

| Tool | Actions | What it does |
|------|----------|-----------|
| **session** | open, close, list, info, health | Session management; open/close/relaunch the editor |
| **scene** | get_open_scenes, get_edited_scene_root, open, save, create, unload | Scenes against the real editor |
| **node** | add, remove, set_prop, get_prop, get_info, get_children, find, duplicate, rename, move, set_owner, reorder, array_append, array_remove | Node CRUD with proactive coordinates |
| **resource** | create, read, update, delete, list, create_script, read_script, edit_script | `.tres` resources and `.gd` scripts |
| **project** | create, setup_plugin, setting, autoload, remove_autoload, input_map, shader_global | Project config and creation |
| **shader** | create, edit, validate, material, uniform | `.gdshader` shaders and ShaderMaterial |
| **animation** | create_player, create, add_track, add_key, state_machine | Animations and state machines |
| **skeleton** | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment | 2D/3D skeletons |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps/TileSets |
| **signal** | connect, disconnect, list, set_script | Signals (CONNECT_PERSIST) |
| **validate** | scene, script, node, resource | Validation against the live scene |
| **debug** | run_scene, stop_scene, is_playing, get_editor_errors | Debugging with the real editor |
| **orchestrate** | (multiple ops) | Batch operations, plan file |
| **visual** | coords, summary, ascii, capture, node, budget, cache | Vision system (cost hierarchy) |
| **health** | server + editor | Health check with connected projects |

---

## 🧠 Architecture

```
OpenCode / Claude / Cursor (MCP client)
        │  stdio · NDJSON
        ▼
HerenServer.exe  (Rust · FlojoMCP · ~7 MB)
        │  local WebSocket (127.0.0.1)
        ▼
HerenEditorPlugin  (EditorPlugin GDScript)
   ├── editor_plugin.gd      # extends EditorPlugin, lifecycle
   ├── ws_client.gd          # WS client with auto-reconnect
   ├── dispatcher.gd         # routes tools/call → handlers
   ├── undo_redo_wrapper.gd  # EditorUndoRedoManager
   └── handlers/             # scene, node, resource, animation+skeleton,
                             # shader, project, signal, validate, debug,
                             # tilemap, visual, coords
```

**The lifecycle:**

1. **`session/open`** → the server finds Godot, installs the plugin, enables it in `project.godot` and launches `godot --editor`.
2. **The plugin connects** to the server over WebSocket (`HEREN_MCP_PORT`) and registers by project.
3. **The tools** route to the right handler, operate on the real editor (with Undo/Redo) and return coordinates/results.
4. **`health`** tells you which projects have a connected editor.

**Connection robustness:** if a project editor is open but **disconnected** (outdated plugin or hung editor), `session/open` cleanly relaunches it. The plugin has auto-reconnect with backoff.

---

## 📚 Documentation

- 🤖 [AGENTS.md](AGENTS.md) — Full guide for AI agents (includes bugs/status)
- 📦 [docs/INSTALL.md](docs/INSTALL.md) — Detailed installation
- 📋 [docs/API.md](docs/API.md) — API reference
- 🏗️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Technical architecture
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute
- 📝 [CHANGELOG.md](CHANGELOG.md) — Change history

---

## 🔬 Built with FlojoMCP

Heren v4 is built on **[FlojoMCP](https://github.com/CerebroCanibalus/flojomcp)**, the Rust MCP server framework that generates schemas at **compile-time** (impossible to break at runtime), exposes a local WebSocket server for external plugins to connect to (like this Godot EditorPlugin), and sends images as standard MCP `image_content`. Fast, small, no runtime.

---

## 🤝 Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) for:

- 📥 How to clone and install
- 📥 How to run tests
- 📥 How to report bugs
- 🎨 Code style
- 📥 How to propose features

---

## 📄 License

[MIT](LICENSE) © 2026 Heren MCP Contributors

---

<div align="center">

⭐ [Star on GitHub](https://github.com/CerebroCanibalus/heren-mcp) · 🐛 [Report a bug](https://github.com/CerebroCanibalus/heren-mcp/issues) · 💡 [Propose a feature](https://github.com/CerebroCanibalus/heren-mcp/issues)

---

**For the workers and the Ibero-pahones of the world** 🌍

🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥

*Because creation shouldn't be limited to English.*

⚡ **Plus Ultra: go beyond.** 🌍

</div>

---

```
多謝垂注
⠀⣏⡱ ⣏⡉ ⣏⡱ ⡇ ⣎⣱   ⡷⢾ ⢇⡸
⠀⠧⠜ ⠧⠤ ⠇⠱ ⠇ ⠇⠸   ⠇⠸ ⠇⠸
https://ko-fi.com/general_beria
```
