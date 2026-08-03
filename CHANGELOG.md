# Changelog — Heren MCP

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
