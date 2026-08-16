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

# ⚡ Heren Godot MCP v4.7

🔥 **Heren Godot MCP** — *Plus Ultra*: ir más allá. 🌍

Servidor MCP de alto rendimiento para **Godot Engine 4.x** que permite a IAs y asistentes controlar el editor real directamente: crear escenas, manipular nodos, gestionar recursos, conectar señales, animar, esqueletos, shaders, validar código y **construir HUDs/UI 2D**. **Todo contra el editor vivo, con Undo/Redo real.**

**📢 v4.7 (UI)**: nueva tool **`ui`** + **sistema transversal de templates** — 6 templates 2D prefabricados (`health_bar`, `crosshair`, `dialogue_box`, `score_label`, `boss_bar`, `inventory_slot`) instanciables con 1 llamada vía `node/instantiate {template: "..."}` o `ui/create`, presets de anchors (`ui/layout`), CanvasLayer para HUD overlay (`ui/canvas_layer`), creación de Themes (`ui/theme`) y lecturas enriquecidas con anchors/offsets para Control (adiós a la ceguera de UI).

**📢 v4.6**: Toolset rediseñado — **18 tools, solo `action` required** (fin del laberinto de schemas: ya no hay parámetros required absurdos; el agente no adivina). `node` dividida en mutaciones/lecturas/props (`node`/`node_query`/`node_props`), `visual` en textual/imagen (`visual_text`/`visual_image`). **`debug/output` + `get_editor_errors`** exponen los errores de runtime del juego con formato del panel (E hh:mm:ss:mmm + stack). **`session/diagnose`** = debugger unificado (integridad plugin + grafo headless + estado editor). Orientación continua: `node_not_found` devuelve `parent_children[]`, `rename`/`move` devuelven `previous_path`/`old_parent`. Anti-incrustado: recursos inline sin path → warning `resource_incrusted_inline`. 100% **Rust** sobre **[FlojoMCP](https://github.com/CerebroCanibalus/flojomcp)**.

---

## 🚀 Características

| Característica | Descripción |
|---|---|
| ⚡ **Server en Rust (FlojoMCP)** | `heren-server.exe` de **~7 MB**, sin Python ni Node.js. Arranque instantáneo, schemas en compile-time |
| 🎯 **Editor real, no daemon** | Se conecta al **EditorPlugin** dentro del Godot abierto — Undo/Redo, viewports 2D/3D reales, EditorFileSystem |
| 🔄 **Auto-launch del editor** | `session/open` lanza Godot, instala el plugin, habilita `[editor_plugins]` y espera la conexión WS. Reutiliza el editor abierto; relanza limpio si hay uno zombie |
| 🛠️ **19 tools centralizadas** | Escenas, nodos (mutaciones/lecturas/props), recursos, scripts, señales, animaciones, esqueletos, shaders, tilemaps, validación, debug y **UI 2D (tool `ui` + templates)** — **solo `action` required**, schemas sin trampas |
| 👀 **Sistema de visión** | `visual_text` (coords/summary/ascii, ~20-150 tok) + `visual_image` (capture/nodo, render off-screen de la escena real) — jerarquía de costo sin quemar contexto |
| 🧩 **UI 2D + templates** | Tool `ui` (create/layout/canvas_layer/templates/get_info/theme) + **sistema transversal de templates**: 6 prefabs .tscn instanciables con 1 llamada (`node/instantiate {template}` o `ui/create`), params por nombre de nodo canónico |
| 🔍 **Debug real con errores** | `debug/output` + `get_editor_errors` exponen los errores de runtime del juego (formato del panel Output, con stack) + `session/diagnose` para integridad del plugin |
| ↩️ **Undo/Redo integrado** | Cada mutación pasa por `EditorUndoRedoManager` — Ctrl+Z deshace lo que la IA creó |
| ⚡ **`orchestrate`** | Ejecuta múltiples operaciones en una sola llamada, con plan en archivo para planes complejos |
| 🏗️ **Crea proyectos desde cero** | `project/create` genera project.godot + escena main sin necesitar editor |

---

## 🆚 Frente a otros MCPs de Godot

Comparamos contra los MCPs de Godot más usados, con datos verificados de sus repos (`.competitors/`).

| Capacidad | Coding-Solo (godot-mcp) | GoPeak | **Heren v4** |
|---|---|---|---|
| **Runtime** | Node.js | Node.js | **Rust (7 MB, sin runtime)** |
| **Modo de operación** | Lanza Godot CLI por operación (`execFileAsync`) | Bridge HTTP/WS + addons | **EditorPlugin vivo conectado por WS** |
| **Undo/Redo real** | ❌ (CLI desde cero) | ❌ | **✅ `EditorUndoRedoManager`** |
| **Señales (connect/list)** | ❌ | ❌ (GAP documentado) | **✅ `signal`** |
| **Animación** | ❌ | ❌ (SIGNIFICANT GAP: no AnimationPlayer/Tree) | **✅ 30+ actions: playback, tracks, state machine, tween, one_shot, record, IK** |
| **Esqueletos 2D/3D** | ❌ | ❌ (solo roadmap) | **✅ pose, rest, skin, attachment, IK 2D FABRIK, IK 3D** |
| **Shaders** | ❌ | ❌ (solo roadmap en su análisis) | **✅ create/edit/validate real/material/apply one-shot** |
| **Tilemap** | ❌ | ❌ (SIGNIFICANT GAP) | **✅ set_cell/terrain/pattern** |
| **Visión** | ❌ | screenshots runtime | **✅ jerarquía de costo: coords → ASCII → viewports 2D/3D reales + presupuesto** |
| **Batch** | ❌ | ❌ | **✅ `orchestrate` con plan en archivo** |
| **Config proyecto** | setting básico | parcial | **✅ setting op (get/set/list/delete/set_multi) + input_map persistente real + autoload** |
| **Crear proyecto desde 0** | ❌ | ❌ | **✅ `project/create` sin editor** |

**Por qué Heren gana donde gana:**
- **Undo/Redo real**: toda mutación pasa por `EditorUndoRedoManager` — el Ctrl+Z del usuario deshace lo que la IA creó. Coding-Solo reescribe archivos desde CLI (sin deshacer); GoPeak no lo expone.
- **Editor real, no archivos**: el plugin vive dentro del editor que el usuario ve (viewports, EditorFileSystem, play con breakpoints). GoPeak también usa bridge con addons, pero sus GAPS en animación/señales/tilemap son nuestros dominios.
- **Profundidad por dominio**: 19 tools centralizadas con ~80+ acciones frente a decenas de tools de 1 función. Una llamada `animation/one_shot` crea animación completa; en GoPeak sería imposible (no hay animación).
- **Sistema de visión con costo**: no solo capturas — jerarquía de costo (coords textuales ~20 tok → ASCII → imagen) con `visual_text`/`visual_image` separadas, para no quemar contexto.
- **Schemas sin trampas**: solo `action` required en todas las tools — el agente nunca recibe `-32602 required` por parámetros que no aplican a su acción.
- **Debug con errores reales**: `debug/get_editor_errors` y `debug/output` muestran los errores de runtime del juego (formato del panel Output con stack), y `session/diagnose` diagnostica la salud del plugin entero.
- **Sin runtime externo**: Rust nativo. Node.js (ambos competidores) exige npm install + versión de Node.

> ⚠️ La comparativa anterior marcaba ❌/⚡ sin verificar. Esta tabla usa datos reales de los repositorios (`.competitors/`). GoPeak es un proyecto sólido en debug/run/LSP/DAP; Coding-Solo es sólido en ejecución de proyectos y captura de output. Donde no competimos es donde ellos destacan; donde competimos, aportamos editor real + undo + dominios profundos.

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
python scripts/install_mcp.py

# Opcion B: manual
cargo build --release
# → target/release/heren-server.exe
```

> `scripts/install_mcp.py` compila el server, registra el MCP `heren` en tu
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

# Leer (node_query no muta) + ver la escena sin imagen
node_query(action="get_children", project_path="D:/MiJuego", node_path=".", recursive=true)
visual_text(action="summary", project_path="D:/MiJuego")

# Guardar
scene(action="save", project_path="D:/MiJuego")

# Correr y ver errores de runtime (formato del panel Output)
debug(action="run_scene", project_path="D:/MiJuego")
debug(action="get_editor_errors", project_path="D:/MiJuego")
# → output_errors: ["E 0:00:06:695 global.gd:7 @ get_playstate(): Node not found..."]
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

### 🔹 HUD en 1 llamada con templates (v4.7)

```python
# Barra de vida completa (fondo + fill + label) con 1 llamada:
node(action="instantiate", project_path="D:/MiJuego",
     template="health_bar", parent_path="CanvasLayer",
     properties={"color": {"r": 0.9, "g": 0.2, "b": 0.2, "a": 1.0}, "label": "HP 100/100"})

# HUD completo: CanvasLayer + barra anclada abajo-centro + theme
ui(action="canvas_layer", project_path="D:/MiJuego", layer=1)
ui(action="create", project_path="D:/MiJuego",
   template="boss_bar", parent_path="CanvasLayer", layout="bottom_center",
   properties={"name": "EL JEFE", "color": {"r": 0.9, "g": 0.15, "b": 0.15, "a": 1.0}})
ui(action="layout", project_path="D:/MiJuego",
   node_path="CanvasLayer/BossBar", layout="bottom_center")
ui(action="theme", project_path="D:/MiJuego", theme_path="res://ui/theme.tres",
   node_path="CanvasLayer",
   properties={"colors": {"Label/font_color": {"r": 1, "g": 0.85, "b": 0.3, "a": 1}}})

# Ver el layout (anchors/offsets) sin imagen:
node_query(action="get_info", project_path="D:/MiJuego", node_path="CanvasLayer/BossBar")
# → ui: {anchors: {...}, offsets: {...}, size_flags: {...}}
```

> 💡 Los templates son un **sistema transversal**: también los consumen `ui/templates` (lista) y en el futuro otras tools (scripts, shaders, tilemaps). Ver `addons/heren/templates/metadata.json`.

---

## 🛠️ Las 19 Tools (80+ Acciones)

> **v4.6**: todas las tools exigen SOLO `action` como required — el resto de args son opcionales con defaults por action en el plugin. Nada de `-32602 required` absurdos.

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **session** | open, **reopen**, close, list, info, health, **diagnose** | Sesiones; `diagnose` = debugger unificado (integridad plugin ok/stale/missing/orphan + grafo headless en sandbox + estado editor) |
| **scene** | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas contra el editor real (SceneRegistry evita escenas fantasma) |
| **node** | add, instantiate, remove, duplicate, rename, move, set_owner, reorder | **Mutaciones** estructurales. `rename`/`move` devuelven `previous_path`/`old_parent`; errores con `parent_children[]` |
| **node_query** | get_info, get_children, get_prop, find | **Lecturas** — no mutan la escena, no marcan dirty |
| **node_props** | set_prop, set_props, array_append, array_remove | **Propiedades** — recursos por PATH (`res://...`); dict inline → warning `resource_incrusted_inline` |
| **resource** | create, read, update, delete, list, create_script, read_script, edit_script | Recursos `.tres` y scripts `.gd` |
| **project** | create, setup_plugin, **setting (op get/set/list/delete/set_multi + restart-aware)**, autoload, remove_autoload, **input_map (persistente real)**, shader_global | Configuración, input mapping y creación de proyectos |
| **shader** | create, edit, get, inspect, validate, material, uniform, apply | Shaders `.gdshader`, materiales y aplicar shader+material+uniforms en 1 llamada |
| **animation** | create_player, create, add_track, add_key, state_machine, play, stop, seek, speed, get_animations, get_tracks, get_keyframes, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, blend_pose, retarget, reverse, duplicate, delete, rename, tree_* | Animaciones completas: playback, edición, procedural, IK, batch one-shot |
| **skeleton** | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment, skeleton_get_bones, skeleton_get_pose, skeleton_set_pose, skeleton_ik, skeleton_fabrik, capture_pose | Esqueletos 2D/3D + IK 2D FABRIK e IK 3D |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps/TileSets |
| **signal** | connect, disconnect, list, set_script | Señales (CONNECT_PERSIST, defensivo) |
| **validate** | scene, script, node, resource | Validación contra la escena viva |
| **debug** | run_scene, stop_scene, is_playing, get_editor_errors, **output**, status, breakpoint, control, stack, vars, profiler | Depuración con el editor real. `get_editor_errors` → errores estructurados + `output_errors` (formato del panel Output); `output` con filter=error\|all |
| **orchestrate** | (múltiples ops) | Batch operations, plan en archivo, errores por op sin abortar |
| **visual_text** | coords, summary, ascii | Visión textual NIVEL 0-1 (sin imagen, ~20-150 tok) — usarla SIEMPRE primero |
| **visual_image** | capture, node | Visión imagen NIVEL 2-3 — render off-screen de la ESCENA real (nunca 2×2), image_content base64 |
| **ui** | create, layout, canvas_layer, templates, get_info, **theme** | **UI 2D** (v4.7): Control desde template o desde cero + presets de anchors (`full_rect`, `bottom_center`, `center`…), CanvasLayer para HUD overlay, lista de templates, info de Control (anchors/offsets/size_flags), Theme .tres (colors/styleboxes/font_sizes/constants) |
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

🇪🇸 🇲🇽 🇦🇷 🇨🇴 🇨🇱 🇵🇪 🇻🇪 🇪🇨 🇬🇹 🇨🇺 🇧🇴 🇩🇴 🇭🇳 🇵🇾 🇸🇻 🇳🇮 🇨🇷 🇵🇦 🇺🇾 🇪🇶 🇵🇷 🇬🇶 🇵🇹 🇧🇷 🇲🇿 🇦🇴 🇨🇻 🇲🇴 🇬🇼 🇸🇹 🇹🇱

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
