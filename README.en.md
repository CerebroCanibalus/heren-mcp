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

<div align="center">

# ⚡ Heren Godot MCP v5.0

**Plus Ultra: the agent no longer asks WHICH tool — it writes the code.**

A high-performance MCP server for Godot Engine 4.x, written in Rust.
Plugs an AI agent into the live editor — not into files, not into throwaway CLI calls —
so it can build scenes, mutate nodes, animate skeletons, write UI, validate, and `Ctrl+Z`
its way out of anything it made up.

<p>
  <a href="https://github.com/CerebroCanibalus/heren-mcp"><b>★ Star</b></a> ·
  <a href="https://github.com/CerebroCanibalus/heren-mcp/issues">🐛 Issues</a> ·
  <a href="CHANGELOG.md">📋 CHANGELOG</a> ·
  <a href="AGENTS.md">📖 AGENTS.md</a>
</p>

</div>

---

## 🐉 Why v5.0 changes the rules

The old problem was a maze. Pick among 30+ typed tools. Guess args per action. Pray the schema accepted the structure. The coder→handler translator ate half the fix-loop.

**v5.0 introduces Worker-First (W4)** — the heart of the break from v4.9: the
agent writes a short GDScript worker against Godot's real API, and we run it
under a transactional safety net.

```
parse-check first
   ↓
snapshot the .tscn → .heren/backup/
   ↓
worker.run(ctx)         ← ctx.own · ctx.instance_scene · ctx.template · ctx.coords
   ↓
did it mark_modified?   ← if NO, NOTHING is saved (original scene intact)
   ↓
post-validation
   ↓
if fail → restore snapshot → receipt with diagnostics
```

One bad call won't break your scene. And `scene_script/inspect` (W4b) gives the agent the tree + bones + animations + materials **before** it writes the worker. No blind round-trips.

> *"If `run_scene_edit_script` saves us from ALMOST ALL the tools, so be it."* — Design philosophy adopted v5.0.

---

## 🎯 What makes Heren different

| Capability | How Heren solves it |
|---|---|
| **Live editor, not headless** | A real `EditorPlugin` inside Godot. Real 2D/3D viewports, real Undo/Redo, real EditorFileSystem. |
| **Transactional GDScript worker** | The agent writes code against Godot's API — no translator. Failure ⇒ scene intact. |
| **Proactive every reply** | Every mutation returns coords at the right tier and errors with `parent_children[]`. |
| **3-tier vision** | Textual coords (~20-100 tok) → ASCII → real viewports. Image only if text isn't enough. |
| **Trap-free schemas** | Only `action` is required. No `-32602` for params that don't apply. |
| **Rust on FlojoMCP** | ~11 MB release binary, instant startup, compile-time schemas. |
| **Zero telemetry** | Nothing leaves your machine. By default and forever. |
| **LSP bridge included** | `heren-server lsp-bridge` for OpenCode — GDScript diagnostics with backoff and reconnect. |

---

## 🆚 Versus other Godot MCPs (July 2026)

Verified data from each repo (`.competitors/` + `godot-mcp-runtime/comparison.md`). A ❌
means **the competitor's repo doesn't expose that capability** — not "it's worse", but
"another MCP covers it".

| Capability | Coding-Solo<br>4.5k★ MIT | Hi-godot<br>868★ MIT | GoPeak<br>227★ MIT | Fennara<br>191★ MIT | Godot MCP Pro<br>473★ $15 | **Heren v5.0**<br>Rust 11MB |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Mode of operation | Headless CLI | Editor WS | `npx` + addon | Addon + daemon | Editor (paid) | **EditorPlugin live via WS** |
| **Real Undo/Redo** | ❌ | ✅ | ❌ | ✅ transactional | ✅ | **✅ `EditorUndoRedoManager`** |
| **Signal connect/list** | ❌ | ✅ | ❌ | ✅ | ✅ | **✅ `signal`** |
| **AnimationPlayer/Tree** | ❌ | partial | ❌ | partial | ✅ 6 tools | **✅ 25+ actions** |
| **2D/3D skeletons + IK** | ❌ | partial | ❌ | ❌ | partial | **✅ pose, rest, skin, FABRIK, IK 3D** |
| **.gdshader shaders** | ❌ | ✅ | partial | ✅ | ✅ | **✅ + material/uniform/apply** |
| **Tilemap** | ❌ | ✅ | ❌ | partial | ✅ | **✅ set_cell/terrain/pattern** |
| **2D UI + Themes** | ❌ | partial | ❌ | partial | ✅ | **✅ `ui` + 6 templates + theme** |
| **Scene vision** | ❌ | screenshots | runtime | ❌ | screenshots | **✅ cost tier: coords → ASCII → real** |
| **LSP diagnostics** | ❌ | ❌ | ✅ own LSP | ❌ | ❌ | **✅ `lsp-bridge` for OpenCode** |
| **Batch / orchestration** | ❌ | ❌ | ❌ | ✅ loop | ✅ | **✅ `orchestrate` + `scene_script`** |
| **Agent GDScript worker** | ❌ | ❌ | ❌ | ✅ patch-rerun | ❌ | **✅ `scene_script/run` with snapshot** |
| **READ-ONLY view without worker** | ❌ | ❌ | ❌ | ❌ | ❌ | **✅ `scene_script/inspect` (W4b)** |
| **Proactive receipt** | ❌ | ❌ | ❌ | ❌ | ❌ | **✅ `aggregates` + dynamic tier** |
| **Runtime required** | Node.js | Python | Node.js | Python | Node.js | **Native Rust** |
| **Telemetry** | opt-in | opt-out ⚠️ | none | none | yes | **none, forever** |
| **License** | MIT | MIT | MIT | MIT | Proprietary | **MIT** |

**Honest reading**

- **Coding-Solo** (4.5k★, clean, MIT) is the file-level reference. If you only want to read `.gd`/`.tscn` without touching the editor, it works.
- **GoPeak** shines where we don't: ships LSP + DAP out-of-the-box. Solid for pure runtime debugging.
- **Fennara** was our philosophical inspiration. Their GDScript worker convinced the General that paradigm beats tool count. We cite them in §0.12 of AGENTS.md.
- **Hi-godot/godot-ai** (868★) is the most popular with editor-live mode. Its opt-out telemetry and Python dep sit ill with Heren's ethos.
- **Godot MCP Pro** ($15, 175 self-declared tools, unaudited) is the commercial play. Closed.
- **Heren** wins where the agent **writes code against Godot**, not invokes individual tools. One call replaces five.

---

## ⚡ Quickstart

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp

# Option A: auto-installer (compile + register MCP + verify)
python scripts/install_mcp.py

# Option B: manual
cargo build --release
# → target/release/heren-server.exe (~11 MB)
```

### MCP configuration

```jsonc
{
  "mcpServers": {
    "heren": {
      "command": "path/to/heren-server.exe",
      "environment": {
        "GODOT_EXE": "D:/Godot/Godot_v4.6.1-stable_win64.exe"
      }
    }
  }
}
```

> The server speaks **NDJSON over stdio** (standard MCP framing). The first tool call
> with `project_path` auto-launches Godot and loads the plugin — no prior session tool.
> `HEREN_AUTO_LAUNCH=0` to open Godot manually.

### Environment variables

| Variable | Default | Use |
|----------|---------|-----|
| `GODOT_EXE` | — | Path to Godot (required) |
| `HEREN_AUTO_LAUNCH` | `1` | `0` disables editor auto-launch |
| `HEREN_DEFAULT_PROJECT` | — | Default project (else falls back to `last_project`) |
| `HEREN_PLUGIN_SOURCE` | `addons/heren/` | Source plugin path |
| `HEREN_LOG_FILE` | — | Optional log (server never floods stderr) |

---

## 🚀 Real-world flow

### 1. Agent's GDScript worker (recommended for everything)

```gdscript
# res://.heren/tmp/workers/character.gd  (agent writes this)
@tool
extends RefCounted
func run(ctx) -> void:
    var root := ctx.get_scene_root()
    var rig := Node3D.new()
    rig.name = "Rig"
    ctx.own(root.add_child(rig))            # transactional
    var skel := Skeleton3D.new()
    skel.name = "Skel"
    ctx.own(rig.add_child(skel))
    for bone_name in ["Hip", "Spine", "Head", "L_Arm", "R_Arm"]:
        skel.add_bone(NamedBone(bone_name))
    ctx.mark_modified()                     # required to actually save
    ctx.snapshot_subtree("./Rig", 2)       # attach to receipt
```

```python
# From the agent
godot_scene_script(action="run", code=<code>, save=True, tier=2)
# → {
#     "ok": true, "ran": true, "scene_saved": true,
#     "coords": {
#       "root": {<coord tier 2>},
#       "touched": ["./Rig", "./Rig/Skel"],
#       "aggregates": {
#         "skeletons_3d": [{"path": "./Rig/Skel", "bone_count": 5,
#                           "bones": ["Hip","Spine","Head","L_Arm","R_Arm"]}],
#         "subtrees": [{"path": "./Rig", "tier": 2, "tree": {...}}]
#       }
#     }
#   }
```

The agent doesn't re-inspect. The receipt already tells which bones exist, which
materials, which animations. And if it touched a `Skeleton3D`, the effective tier
auto-bumps to 3.

### 2. READ-ONLY inspect before writing

```python
godot_scene_script(action="inspect", scene_path="res://levels/forest.tscn", tier=1)
# → { "opaque_packed_scenes": [],
#     "aggregates": { "skeletons_3d": [...], "animations": [...], ... },
#     "scene_node_count": 87 }
```

### 3. 2D UI with templates (1 call)

```python
godot_ui(action="create", template="health_bar", parent_path="CanvasLayer",
         layout="bottom_center",
         properties={"color": {"r": 0.9, "g": 0.2, "b": 0.2, "a": 1.0},
                     "label": "HP 100/100"})

# 6 templates ready: health_bar · crosshair · dialogue_box ·
#                    score_label · boss_bar · inventory_slot
```

### 4. Debug with real errors

```python
godot_debug(action="run_scene")              # play
godot_debug(action="output", filter="error") # runtime + editor errors
# → "E 0:00:06:695 global.gd:7 @ get_playstate(): Node not found..."
```

---

## 🛠️ The 15 tools (90+ actions)

> v5.0: the tools the agent rarely invoked directly (`animation/tree_*`,
> `skeleton/*`, `tilemap/*`, `shader/material`, `node/move`...) got **archived**.
> The worker covers them with ~10 lines of GDScript instead of a handler + schema
> + dispatcher. Hence: 19 → 15.

| # | Tool | Key actions |
|---|------|-------------|
| 1 | `scene` | open, save, create, plan, orchestrate, validate, status, list |
| 2 | `node` | add, instantiate, remove, duplicate, rename |
| 2b | `node_query` | get_prop, get_info, get_children, find, **class_info**, **props_diff** |
| 2c | `node_props` | set_prop, set_props, array_append, array_remove |
| 3 | `resource` | create, read, update, delete, create_script, read_script, edit_script |
| 4 | `project` | create, setup_plugin, setting, autoload, input_map, shader_global |
| 5 | `shader` | create, edit, get, inspect, validate |
| 6 | `animation` | create_player, add_track, state_machine, one_shot, tween, record, … |
| 7 | `debug` | run_scene, stop_scene, output, breakpoint, vars, stack, profiler |
| 8 | `validate` | scene, script (with `parse_hints`), node, resource |
| 9 | `signal` | connect, disconnect, list |
| 10 | `visual` | coords, summary, ascii, spatial |
| 11 | `ui` | create, layout, canvas_layer, templates, get_info, theme |
| 12 | `filesystem` | scan, status, import_errors, exists, import |
| 13 | `health` | server + editor (+ `diagnose=true`) |
| 14 | `scene_script` | **run, list, inspect** — W4 Worker-First + W4b proactive inspect |

📖 Full table (all actions) in [AGENTS.md §6](AGENTS.md).

> **Tool pattern**: 1 tool = N actions via `action`. Only `action` is required. End of the schema maze.

---

## 🧠 Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  OpenCode · Claude · Cursor · Codex  (MCP client)                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │  stdio · NDJSON
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  heren-server.exe  ·  Rust · FlojoMCP  ·  ~11 MB                    │
│  compile-time schemas · 0 runtime deps                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐   │
│  │  LSP bridge      │  │  .heren/server_  │  │  WS server      │   │
│  │  stdio↔TCP :6005 │  │  port.json       │  │  127.0.0.1:9099 │   │
│  └──────────────────┘  └──────────────────┘  └────────┬────────┘   │
└─────────────────────────────────────────────────────────┼───────────┘
                                                          │  WebSocket
                                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  HerenEditorPlugin  ·  extends the Godot EditorPlugin               │
│  ws_client · dispatcher · handlers/ (scene · node · resource ·     │
│          project · animation · shader · signal · … · scene_script)  │
└─────────────────────────────────────────────────────────────────────┘
```

**Lifecycle**

1. Client sends `tools/call` with `action=...` over NDJSON.
2. Server validates the schema (compile-time), resolves `project_path`, finds editor or auto-launches.
3. Forward to the plugin over WebSocket. `dispatcher.gd` routes `(tool_prefix, action) → handler_method` — **no magic fallbacks**.
4. The handler operates against the real editor under `EditorUndoRedoManager`. `Ctrl+Z` undoes anything.
5. The receipt includes **coords** (system §7). The agent knows what happened without re-inspecting.

**No `session` tool** since v5.0. The connected editor **is** the session. The first
tool call with `project_path` pays the auto-launch; subsequent calls are ~20ms.
The server never kills the editor.

📖 Details: [AGENTS.md §2](AGENTS.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## 🧪 Tests

77 GDScript + 100+ Rust tests, all green:

```bash
scripts/validate_plugin.bat    # Windows 1-click

# Manual equivalent (4 steps):
python scripts/install_plugin.py --project fixtures/empty_project --force
godot --headless --editor --path fixtures/empty_project --quit-after 5
godot --headless --path fixtures/empty_project --script res://addons/heren/tests/run_tests.gd
cargo test -p heren-server
```

Results: `RESULT: 77 passed, 0 failed` · `cargo test: 85 passed, 0 failed`.

---

## 🔬 Built with FlojoMCP

Heren runs on [FlojoMCP](https://github.com/CerebroCanibalus/flojomcp), the Rust MCP
framework that generates compile-time schemas, exposes a local WebSocket for external
plugins, and sends images as standard MCP `image_content`. No runtime. No Node. No Python.

---

## 📚 Documentation

- 📖 [AGENTS.md](AGENTS.md) — Agent bible: open bugs, decisions, lessons, gotchas.
- 📋 [CHANGELOG.md](CHANGELOG.md) — Iteration history.
- 📦 [docs/INSTALL.md](docs/INSTALL.md) — Detailed installation.
- 🔌 [opencode.lsp.example.jsonc](opencode.lsp.example.jsonc) — LSP bridge for OpenCode.
- 🏗️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Technical architecture.
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute.

---

## 📄 License · 🤝 Contributing

[MIT](LICENSE) © 2026 Heren MCP Contributors. Read [CONTRIBUTING.md](CONTRIBUTING.md):
every `.gd` change runs through `scripts/validate_plugin.bat` before commit.

---

<div align="center">

**For the workers and the iberophones of the world** 🌍

🇪🇸 🇲🇽 🇦🇷 🇨🇴 🇨🇱 🇵🇪 🇻🇪 🇪🇨 🇬🇹 🇨🇺 🇧🇴 🇩🇴 🇭🇳 🇵🇾 🇸🇻 🇳🇮 🇨🇷 🇵🇦 🇺🇾 🇪🇶 🇵🇷 🇬🇶 🇵🇹 🇧🇷 🇲🇿 🇦🇴 🇨🇻 🇲🇴 🇬🇼 🇸🇹 🇹🇱

*Creation shouldn't be locked to English.*

⚡ **Plus Ultra: go beyond.** 🌍

</div>

---

```
多謝垂注
⠀⣏⡱ ⣏⡉ ⣏⡱ ⡇ ⣎⣱   ⡷⢾ ⢇⡸
⠀⠧⠜ ⠧⠤ ⠇⠱ ⠇ ⠇⠸   ⠇⠸ ⠇⠸
https://ko-fi.com/general_beria
```
