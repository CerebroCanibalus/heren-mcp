<div align="center">

![Heren Godot MCP Banner](assets/HerenGodotBanner.png)

<p>
  <a href="README.md">🇪🇸 Español</a> •
  <a href="README.en.md">🇬🇧 English</a>
</p>

</div>

---

> *"La técnica es una actividad compositora o destructora, violenta, y esto es lo que Aristóteles llamaba la poiesis, la poesía, precisamente."* — **Gustavo Bueno**

---

# ⚡ Heren Godot MCP v4.2

🔥 **Heren Godot MCP** — *Plus Ultra*: ir más allá. 🌍

Servidor MCP de alto rendimiento para **Godot Engine 4.x** que permite a IAs y asistentes controlar el editor real directamente: crear escenas, manipular nodos, gestionar recursos, conectar señales, animar, esqueletos, shaders y validar código. **Todo contra el editor vivo, con Undo/Redo real.**

**📢 v4.2**: MCP 100% **Rust** (7 MB, sin runtime), construido sobre **[FlojoMCP](https://github.com/CerebroCanibalus/flojomcp)** — el framework MCP en Rust de alto rendimiento. Conexión directa al **Editor Godot** mediante un plugin (EditorPlugin) con auto-reconexión y auto-lanzamiento del editor.

---

## 🚀 Características

| Característica | Descripción |
|---|---|
| ⚡ **Server en Rust (FlojoMCP)** | `heren-server.exe` de **~7 MB**, sin Python ni Node.js. Arranque instantáneo, schemas en compile-time |
| 🎯 **Editor real, no daemon** | Se conecta al **EditorPlugin** dentro del Godot abierto — Undo/Redo, viewports 2D/3D reales, EditorFileSystem |
| 🔄 **Auto-launch del editor** | `session/open` lanza Godot, instala el plugin, habilita `[editor_plugins]` y espera la conexión WS. Reutiliza el editor abierto; relanza limpio si hay uno zombie |
| 🛠️ **15 tools centralizadas** | Escenas, nodos, recursos, scripts, señales, animaciones, esqueletos, shaders, tilemaps, validación y debug |
| 👀 **Sistema de visión** | Jerarquía de costo: coordenadas textuales → resumen/ASCII → captura de los viewports 2D/3D reales del editor, con presupuesto de tokens |
| ↩️ **Undo/Redo integrado** | Cada mutación pasa por `EditorUndoRedoManager` — Ctrl+Z deshace lo que la IA creó |
| ⚡ **`orchestrate`** | Ejecuta múltiples operaciones en una sola llamada, con plan en archivo para planes complejos |
| 🏗️ **Crea proyectos desde cero** | `project/create` genera project.godot + escena main sin necesitar editor |

---

## 🆚 Frente a otros MCPs de Godot

**Coding-Solo** y **GoPeak** son buenos proyectos, pero o lanzan Godot desde cero por operación, o dependen de un daemon externo que no puede tocar el editor real.

**Heren Godot MCP v4** vive **dentro** del editor real: un EditorPlugin que habla con el server Rust por WebSocket local. No es "operar a ciegas sobre archivos", es **controlar el editor que el usuario ve**.

| Capacidad | Coding-Solo | GoPeak | **Heren v4** |
|---|---|---|---|
| **Server** | Node.js | Node.js | **Rust (7 MB, sin runtime)** |
| **Undo/Redo** | ❌ | ❌ | **✅ EditorUndoRedoManager** |
| **Editor real** | ❌ | ❌ | **✅ EditorPlugin** |
| **Auto-launch editor** | ❌ | ❌ | **✅** |
| **Visión (viewports reales)** | ❌ | ❌ | **✅ 2D/3D + presupuesto** |
| **Sesión** | ❌ | ❌ | **✅ editor vivo conectado** |
| **Esqueletos 2D/3D** | ❌ | ⚡ | **✅** |
| **Schemas confiables** | runtime | runtime | **✅ compile-time** |

---

## 📦 Instalación

### Requisitos

- 🦀 **Rust** (para compilar) — o descarga el `.exe` precompilado
- ⚙️ **Godot** >= 4.2 (recomendado 4.6+)
- 💻 **Windows / Linux / macOS**

### Desde fuente

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp

# Opcion A: instalador automatico (compila + registra MCP + verifica)
python install_mcp.py

# Opcion B: manual
cargo build --release
# → target/release/heren-server.exe
```

> `install_mcp.py` compila el server, registra el MCP `heren` en tu
> `opencode.jsonc` (detecta rutas) y verifica el arranque. Ver
> [docs/INSTALL.md](docs/INSTALL.md).

### Configuración MCP (OpenCode, Claude Desktop, Cursor, etc.)

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

> El server habla **NDJSON por stdio** (el framing estándar de MCP). El editor se lanza solo en `session/open`.

### Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `GODOT_EXE` | Ruta al ejecutable de Godot |
| `GODOT_PATH` | Alias de `GODOT_EXE` |
| `HEREN_PLUGIN_SOURCE` | Ruta al plugin fuente (por defecto `addons/heren/`) |
| `HEREN_LOG_FILE` | Archivo de log (opcional; el server jamás inunda stderr) |

---

## 🚀 Uso Rápido

```python
# Abrir sesión: lanza el editor (si no está), instala el plugin y conecta
session(action="open", project_path="D:/MiJuego")
# → {"launched": true, "message": "launched", "ok": true}

# Crear escena
scene(action="create", project_path="D:/MiJuego", scene_path="res://Player.tscn")

# Añadir nodo (con Undo/Redo)
node(
    action="add",
    project_path="D:/MiJuego",
    parent_path=".",
    node_type="CharacterBody2D",
    node_name="Player"
)

# Guardar
scene(action="save", project_path="D:/MiJuego")
```

> ⚠️ En OpenCode las tools aparecen con prefijo `godot_` (ej. `godot_session`, `godot_node`, `godot_scene`).

### 🔹 Batch con `orchestrate`

```python
# Multiples operaciones en una sola llamada
orchestrate(
    project_path="D:/MiJuego",
    plan={"ops": [
        {"tool": "node", "args": {"action": "add", "node_type": "Sprite2D", "node_name": "Body"}},
        {"tool": "node", "args": {"action": "add", "node_type": "CollisionShape2D", "node_name": "Hitbox"}},
        {"tool": "scene", "args": {"action": "save"}}
    ]},
    on_error="stop"
)
```

---

## 🛠️ Las 15 Tools (60+ Acciones)

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **session** | open, close, list, info, health | Gestión de sesiones; abre/cierra/relanza el editor |
| **scene** | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas contra el editor real |
| **node** | add, remove, set_prop, get_prop, get_info, get_children, find, duplicate, rename, move, set_owner, reorder, array_append, array_remove | CRUD de nodos con coordenadas proactivas |
| **resource** | create, read, update, delete, list, create_script, read_script, edit_script | Recursos `.tres` y scripts `.gd` |
| **project** | create, setup_plugin, setting, autoload, remove_autoload, input_map, shader_global | Configuración y creación de proyectos |
| **shader** | create, edit, validate, material, uniform | Shaders `.gdshader` y ShaderMaterial |
| **animation** | create_player, create, add_track, add_key, state_machine | Animaciones y state machines |
| **skeleton** | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment | Esqueletos 2D/3D |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps/TileSets |
| **signal** | connect, disconnect, list, set_script | Señales (CONNECT_PERSIST) |
| **validate** | scene, script, node, resource | Validación contra la escena viva |
| **debug** | run_scene, stop_scene, is_playing, get_editor_errors | Depuración con el editor real |
| **orchestrate** | (múltiples ops) | Batch operations, plan en archivo |
| **visual** | coords, summary, ascii, capture, node, budget, cache | Sistema de visión (jerarquía de costo) |
| **health** | server + editor | Health check con proyectos conectados |

---

## 🧠 Arquitectura

```
OpenCode / Claude / Cursor (cliente MCP)
        │  stdio · NDJSON
        ▼
HerenServer.exe  (Rust · FlojoMCP · ~7 MB)
        │  WebSocket local (127.0.0.1)
        ▼
HerenEditorPlugin  (EditorPlugin GDScript)
   ├── editor_plugin.gd      # extends EditorPlugin, lifecycle
   ├── ws_client.gd          # cliente WS con auto-reconnect
   ├── dispatcher.gd         # rutea tools/call → handlers
   ├── undo_redo_wrapper.gd  # EditorUndoRedoManager
   └── handlers/             # scene, node, resource, animation+skeleton,
                             # shader, project, signal, validate, debug,
                             # tilemap, visual, coords
```

**El ciclo de vida:**

1. **`session/open`** → el server encuentra Godot, instala el plugin, lo habilita en `project.godot` y lanza `godot --editor`.
2. **El plugin conecta** al server por WebSocket (`HEREN_MCP_PORT`) y se registra por proyecto.
3. **Las tools** se enrutan al handler correcto, operan sobre el editor real (con Undo/Redo) y devuelven coordenadas/resultados.
4. **`health`** te dice qué proyectos tienen editor conectado.

**Robustez de conexión:** si hay un editor del proyecto abierto pero **desconectado** (plugin obsoleto o editor colgado), `session/open` lo relanza limpio. El plugin tiene auto-reconnect con backoff.

---

## 📚 Documentación

- 🤖 [AGENTS.md](AGENTS.md) — Guía completa para agentes de IA (incluye bugs/estado)
- 📦 [docs/INSTALL.md](docs/INSTALL.md) — Instalación detallada
- 📋 [docs/API.md](docs/API.md) — Referencia de la API
- 🏗️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Arquitectura técnica
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) — Cómo contribuir
- 📝 [CHANGELOG.md](CHANGELOG.md) — Historial de cambios

---

## 🔬 Hecho con FlojoMCP

Heren v4 está construido sobre **[FlojoMCP](https://github.com/CerebroCanibalus/flojomcp)**, el framework de servidores MCP en Rust que genera schemas en **compile-time** (imposible de romper en runtime), expone un server WebSocket local para que se conecten plugins externos (como este EditorPlugin de Godot), y envía imágenes como `image_content` MCP estándar. Rápido, pequeño y sin runtime.

---

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Lee [CONTRIBUTING.md](CONTRIBUTING.md) para:

- 📥 Cómo clonar e instalar
- 📥 Cómo correr tests
- 📥 Cómo reportar bugs
- 🎨 Estilo de código
- 📥 Cómo proponer features

---

## 📄 Licencia

[MIT](LICENSE) © 2026 Heren MCP Contributors

---

<div align="center">

⭐ [Star en GitHub](https://github.com/CerebroCanibalus/heren-mcp) · 🐛 [Reportar bug](https://github.com/CerebroCanibalus/heren-mcp/issues) · 💡 [Proponer feature](https://github.com/CerebroCanibalus/heren-mcp/issues)

---

**Por los trabajadores y los iberófonos del mundo** 🌍

🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥

*Porque la creación no debería estar limitada al inglés.*

⚡ **Plus Ultra: ir más allá.** 🌍

</div>

---

```
多謝垂注
⠀⣏⡱ ⣏⡉ ⣏⡱ ⡇ ⣎⣱   ⡷⢾ ⢇⡸
⠀⠧⠜ ⠧⠤ ⠇⠱ ⠇ ⠇⠸   ⠇⠸ ⠇⠸
https://ko-fi.com/general_beria
```
