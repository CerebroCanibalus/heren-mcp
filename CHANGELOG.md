# Changelog — Heren MCP

# Changelog - Heren MCP

## [4.6.0] - 2026-08-08 - 🧭 REDISEÑO DEL TOOLSET (fin del laberinto)

### ✅ 18 tools, solo action required

El agente ya no adivina qué args aplican a qué acción: TODOS los parámetros son
opcionales (Option<>) con defaults por action en el plugin. Antes visual exigía
clear/viewport en summary; animation exigía 39 requireds; ahora solo action es
required (verificado en el binario desplegado).

### 🔀 Split de tools (el server mapea al MISMO handler interno - plugin intacto)

- node → node (mutaciones: add/instantiate/remove/duplicate/rename/move/set_owner/reorder)
  + node_query (lecturas: get_info/get_children/get_prop/find - no marcan dirty)
  + node_props (props: set_prop/set_props/array_*)
- visual → visual_text (coords/summary/ascii - NIVEL 0-1, sin imagen)
  + visual_image (capture/node - NIVEL 2-3, image_content base64)
- budget/cache ELIMINADOS (handlers inexistentes - eran action fantasma)

### 🔍 Debug con errores reales (verificado contra source Godot 4.7)

- debug/get_editor_errors → errores estructurados + output_errors (texto del
  panel Output: E hh:mm:ss:mmm file:line @ func(): msg + stack)
- NUEVA action debug/output (filter=error|all, limit)
- Hook robusto: reintentos 30x1s + conecta a TODOS los ScriptEditorDebugger
  (multi-sesión). EditorDebuggerPlugin._capture NO recibe mensajes sin : - el
  camino real es el signal debug_data (sed.cpp _parse_message).

### 🧭 Orientación continua

- Errores node_not_found incluyen parent_children[] del padre resoluble más
  cercano - el agente se recupera sin llamada extra.
- rename/move devuelven previous_path/old_parent.

### 🛡️ Anti-incrustado de recursos

- Recursos inline sin resource_path → warning resource_incrusted_inline en
  node/add y node_props/set_prop (nunca fallo silencioso).
- Regla de oro: recursos SIEMPRE por PATH (res://...) para ext_resource.

### 🔧 Otros

- session/diagnose (v4.4.2): debugger unificado - integridad plugin
  (ok/stale/missing/orphan) + grafo headless en sandbox + estado editor.
- Fix raíz sync: collect_files preserva prefijo handlers/ (el "plugin
  up-to-date" mentiroso que dejaba handlers viejos → SCRIPT ERROR).
- Detección de editor por doble clic (project.godot en cmdline + backslash).
- deploy-fix.bat con cadena de rename (.old bloqueado → .old2).
- 32 tests Rust OK, clippy limpio, grafo headless OK.

## [4.2.0] — 2026-08-04 — 🦀 SERVER RUST (FlojoMCP) + E2E COMPLETO

### 🏗️ El MCP ahora es Rust

HerenServer.exe reemplaza al bridge Python como MCP activo. Construido sobre
**FlojoMCP** (framework MCP en Rust): schemas en compile-time, ~7 MB, sin runtime.

| | v4.0 (bridge Python) | v4.2 (Rust) |
|---|---|---|
| MCP server | Python FastMCP (bridge temporal) | **heren-server.exe (Rust/FlojoMCP, 7 MB)** |
| Transporte | stdio (bridge) → WS | **stdio NDJSON directo + WS plugin server** |
| Tools | 14 (bridge) | **15 (renombradas sin `_tool`, visión consolidada)** |
| Schemas | runtime | **compile-time (imposible de romper)** |
| Bridge Python | activo | **fallback/referencia** |

### ✨ Features v4.2

- **15 tools**: `session, scene, node, resource, project, shader, animation, skeleton, tilemap, signal, validate, debug, orchestrate, visual, health`
- **Single-instance**: `run()` mata heren-server viejos → el editor conecta al server correcto
- **`[editor_plugins]` normalizado** a `enabled=PackedStringArray(...)` (Godot 4 carga el plugin)
- **Instalación completa**: `source_files_match()` verifica TODOS los archivos del plugin
- **`project/create` sin editor** + main.tscn automática + configurabilidad profunda
- **`project/setup_plugin`**: instala el plugin sin editor (llamable por el agente)
- **`orchestrate` con `plan_file`**: el plan viaja por archivo → arregla el batch de dicts anidados
- **`session.close_editor`** opcional (default false)
- **Sistema de visión** en una tool `visual` (coords/summary/ascii/capture/node/budget/cache)
- **Robustez de conexión**: `launch_editor` mata editor zombie sin conectar y relanza limpio

### ✅ Validado E2E (minijuego platformer, ~44 nodos)

- 10/15 tools impecables. Juego completo creado y ejecutado (`debug/run_scene`).
- `orchestrate`: 31/31 ops en 2 batches (scripts crudos + sub-recursos + arrays Vector2/Color)
- `project/setting` get, `signal/list`, `shader/material`, `skeleton` 2D rest/attachment/skin — **arreglados y validados en vivo**
- Fix de conexión validado: `session/open` contra editor zombie desconectado relanzó limpio y conectó automático

### 🐛 Bugs críticos arreglados

- **C1/C2**: `args()` insertaba `Value::Null` para todo param opcional → `project/setting` get borraba el setting y `str(null)`="<null>" rompía guards. Fix: `args()` omite keys None; `handle_setting` trata null explícito como get.
- **H1**: `signal/list` crasheaba con conexiones entrantes. Fix: loop defensivo + key correcta `"signal"`.
- **H2**: `shader/material` "Unknown error" siempre. Fix: `material.resource_name` (ShaderMaterial es Resource, no `name`).
- **H3**: typo `set_bone_weigths` + nombre en vez de índice. Fix: `set_bone_weights(find_bone(...))`.
- **H4**: skeleton 2D exigía Skeleton3D. Fix: ramificar por tipo real.
- **API Skeleton2D falsa**: Skeleton2D NO tiene `find_bone`/`set_bone_rest`; sus huesos son `Bone2D` hijos (`.rest=Transform2D`). `BoneAttachment2D` NO existe → attachment 2D = Node2D hijo del Bone2D. Este error silencioso rompía todo el plugin (editor no conecta).

### ⚠️ Bugs conocidos / pendientes

- `visual`: 4/7 acciones rotas (`coords` incompleto, `capture`/`node` 2×2 px, `budget`/`cache` sin handler en plugin)
- `node/array_remove` elimina el primer elemento (int vs float)
- `validate/node` `script_cannot_instantiate` (falta re-import/scan)
- Tool `node` no expone `query`/`by`/`recursive`/`owner_path`/`script` (solo vía `orchestrate`)
- Tool `resource` no crea directorios padre; exige params required irrelevantes

---

## [4.0.0] — 2026-08-03 — 🐉 MIGRACIÓN COMPLETADA

### 🏗️ Cambio de arquitectura: GodotDaemon (v3) → EditorPlugin (v4)

La migración masiva que convierte Heren MCP de un daemon standalone (que nunca
podía tocar el editor real) a un **EditorPlugin Godot real** con undo/redo,
editor vivo, y arquitectura cliente/servidor WS.

| | v3 (legacy) | v4 (operativo) |
|---|---|---|
| Acceso a editor | ❌ Daemon standalone (EditorInterface inaccesible) | ✅ EditorPlugin real (`extends EditorPlugin`) |
| Undo/Redo | ❌ Irreversible | ✅ `EditorUndoRedoManager` |
| MCP server | Python FastMCP (~60MB) | Python bridge temporal → Rust FlojoMCP (7MB) |
| Transporte | WS (daemon=server, frágil) | WS (plugin=cliente, auto-reconnect, patrón gopeak) |
| Sesiones | SessionManager Python (LRU, daemon cache) | `ConnectedEditors` (editor vivo en RAM) + `last_project` en disco |
| Coordenadas | serialize/deserialize (éxito) | Heredado + expansión (Transform2D/3D, snaps, relativas) |

### ✨ Features nuevas

- **EditorPlugin núcleo**: `editor_plugin.gd` + `ws_client.gd` (auto-reconnect) + `dispatcher.gd` + `undo_redo_wrapper.gd`
- **10 handlers** en `addons/heren/handlers/`: scene, node, resource, animation+skeleton, shader, tilemap, project, signal, validate, debug
- **Bridge Python v4** (`src/heren/v4/`): FastMCP → WS → EditorPlugin. MCP usable HOY
- **Auto-launch del editor**: `session/open` lanza Godot con el plugin (o reusa uno ya abierto del proyecto)
- **Ciclo de vida de sesión corregido**: `_require_editor` NUNCA lanza; el editor no se duplica por tool call
- **Normalización de paths**: clave canónica (forward slashes, sin trailing) — el plugin y el agente hablan el mismo idioma
- **`scene/create` desde cero**: sin escena abierta crea `.tscn` nuevo; con escena abierta añade nodo
- **`setup_plugin.bat` + `install_plugin.py`**: instalación del plugin en un proyecto en 1 comando

### ✅ Validado E2E (2026-08-03)

- **Escena épica de 39 nodos** creada desde cero: Player (física/script/cámara/luz/trail) + plataformas + monedas + enemigos + luces + estrellas + HUD + shader neón + AnimationPlayer con 2 tracks (6 keys). Guardada, validada y ejecutada.
- `session/open` (auto-launch) → `godot_ready` → tools scene/node/project/validate/debug OK
- Reuso de editor ya abierto: open→tool→close(false)→open = **mismo PID**
- project.godot válido, Godot abre el proyecto sin errores

### 🐛 Bugs críticos arreglados

- **`project/setting` corrompía project.godot con UID sintético**: `deserialize_value()` cargaba strings `res://` → Resource → `ProjectSettings.save()` escribía `Resource("uid://X", ...)` con UID inexistente → Godot descartaba TODO el project.godot → proyecto no abría. Fix: paths en settings se guardan como **string plano**.
- **El plugin devolvía id JSON-RPC como `"1.0"`**: `_pop_pending()` normaliza por float (tolera `1`/`"1"`/`"1.0"`).
- **FastMCP `mcp.run()` y WS no comparten event loop**: WS server en thread daemon con loop propio + `asyncio.run_coroutine_threadsafe`.
- **`scene/create` exigía escena abierta**: sin escena crea `PackedScene` + `pack()` + `ResourceSaver.save()` + `open_scene_from_path()`.

### ⚠️ Bugs conocidos

- `animation/create` con `loop=true` borra tracks existentes (recrea animación vacía). Workaround: crear sin loop, setear loop_mode post-hoc.
- `godot_orchestrate` rompe con dicts anidados (sub-recursos, colores). Workaround: llamadas individuales.
- Godot headless compite por el `.godot` lock con editor vivo — usar headless solo con editor cerrado.

---

## [3.x] — Legacy (GodotDaemon + FastMCP)

Versiones previas basadas en daemon standalone con WebSocket. Historia completa
en AGENTS.md §8 (Decisiones Registry) y §9 (Testing/Benchmarking).
