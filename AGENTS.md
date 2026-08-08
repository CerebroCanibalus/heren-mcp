# 🐉 Heren MCP - AGENTS.md

> **Filosofía Global: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
> **Filosofía de Tools: Centralizadas. Modulares. Potentes.**

Biblia para agentes que operan Heren MCP. Léelo antes de tocar código.

> 🚧 **ESTADO: v4.4.1 OPERATIVO (EditorPlugin + heren-server.exe Rust/FlojoMCP).**
> Migración GodotDaemon(v3)→EditorPlugin(v4) completada 2026-08-03. Fase 4 (Rust) 2026-08-04.
> **15 tools centralizadas**, WS plugin server (patrón gopeak), auto-launch del editor.
> El .exe habla **NDJSON** por stdio (framing real de OpenCode, verificado con stdin-spy).
> Bridge Python (`python -m heren.v4.bridge`) = fallback/referencia, NO el MCP activo.
> **Los cambios nuevos van a v4/Rust. No ampliar v3 salvo bugs críticos.**
>
> **v4.4.1 (2026-08-07)**: `visual/capture` + `visual/node` YA NO devuelven 2×2 px.
> Render OFF-SCREEN de la ESCENA real en SubViewport dedicado (`source:"scene"` default,
> framing replicado de la cámara del editor) o viewport del editor (`source:"viewport"`,
> fallback automático a scene si da 2×2). Dispatcher/editor_plugin con soporte de handlers
> coroutine (`await`). Schema `visual` expone `source`. Verificado: `--check-only` + grafo
> completo headless sin errores, 24+2+1 tests Rust OK, clippy limpio, release 9.4MB.
>
> **v4.4.2 (2026-08-07)**: **workspace Rust PROPIO + FlojoMCP publicado a crates.io**.
> `crates/heren-server` se movió de FlojoMCP a heren-mcp (Cargo.toml workspace local,
> `heren-build.bat`, `run.bat` → binario local). La config de OpenCode apunta a
> `heren-mcp\target\release\heren-server.exe`. FlojoMCP queda SOLO como framework
> (flojo-mcp/flojo-macros/flojo-session @ crates.io) — heren-server lo consume por
> version (no path). Persistencia: cierre inesperado con 0 dirty = benigno.
>
> **v4.4 (2026-08-06)**: **Plugin SIEMPRE ENCENDIDO + actualización inteligente**.
> - `enable_plugin_in_project` **IDEMPOTENTE y NORMALIZADORA**: reemplaza cualquier `enabled=` en `[editor_plugins]`
>   (vacío `PackedStringArray()`, nombre desnudo `"heren"`, duplicadas) por la única canónica
>   `enabled=PackedStringArray("res://addons/heren/plugin.cfg")`. Solo escribe si difiere; verifica post-escritura.
> - `ensure_plugin_installed` → **sync INCREMENTAL por contenido** (solo diffs, borra huérfanos).
>   NO reinstala todo entre versiones: `plugin up-to-date` = cero trabajo.
> - `launch_editor` política: editor conectado + sin cambios → `reuse up-to-date` (no relanza);
>   conectado + cambió → avisa `plugin_changed` (el agente hace `session/reopen` para recargar);
>   zombie → mata PRIMERO, escribe enable DESPUÉS (nadie pisa project.godot → adiós lost-update).
> - **Reporte de versión al agente**: el plugin manda `plugin_version` en `godot_ready`;
>   `session/info` → `plugin_version_source/installed/editor` + `plugin_stale` + `plugin_stale_remedy`;
>   `session/health` → `stale_editors[]`.
> - El plugin se habilita UNA vez (`setup_plugin`/`create`); NO se "reenciende" en cada open.
> - **15/15 tests Rust** (6 nuevos de enable), clippy -D warnings limpio, release 9.3MB.
>
> **v4.3 (2026-08-04)**: `setting` con `op` get/set/list/delete/set_multi + `restart_required`/`applied_runtime`;
> `input_map` con **persistencia REAL** (`input/<action>` en project.godot, tipos add/get/list/add_event/set_events/remove_event/set_deadzone);
> `session/reopen` (mata + relanza limpio sin repetir path); `node/instantiate` (escena .tscn como hijo ExtResource).
> **C1/C2 + H1-H4 + S1-S6 RESUELTOS Y VALIDADOS E2E EN VIVO.**

---

## 0. 🚨 PRIORIDAD INMEDIATA — Bugs/mejoras del E2E (minijuego platformer, 2026-08-04)

> Hallazgos de la prueba E2E completa (`.temp/e2e_minigame`, ~44 nodos, juego funcional).
> **Estado 2026-08-04**: C1/C2, H1-H4 **RESUELTOS Y VALIDADOS E2E EN VIVO**. Pendientes: M1-M3, visual 4/7, gaps.
> Fuente: `crates/heren-server/src/server.rs` (args) + `addons/heren/handlers/*.gd`.

### Bugs críticos (rompen datos) — ✅ RESUELTOS
| # | Tool | Bug | Fix |
|---|------|-----|-----|
| **C1** | `project/setting` get | **Borraba el setting** (op:"set", value:null). | `server.rs args()` **omite keys None** (antes `Value::Null`). + `project_handlers.gd`: null explícito = get. |
| **C2** | Sistémico | `str(null)`="<null>" rompía guards `if x == ""`. | Misma raíz C1: keys None ya no se inyectan. |

### Bugs altos (crashes) — ✅ RESUELTOS
| # | Tool | Bug | Fix |
|---|------|-----|-----|
| **H1** | `signal/list` | Crash con conexiones entrantes. | Loop defensivo (`.get()`, aísla por conexión). **Bonus**: key `"signal"` (no `signal_name`). |
| **H2** | `shader/material` | "Unknown error" siempre. | **CAUSA RAÍZ**: `material.name =` (Resource no tiene `name`). Fix: `material.resource_name =`. |
| **H3** | `skeleton/skin` | Crash. | `set_bone_weigths`→`set_bone_weights` + **índice int** (`find_bone`), no nombre. |
| **H4** | `skeleton` 2D | set_rest/attachment exigían Skeleton3D. | Ramificar por tipo: Skeleton2D→`Transform2D`/Node2D hijo, Skeleton3D→`Transform3D`/`BoneAttachment3D`. |
| **S1** | `scene/create` | Ignoraba `scene_path`: inyectaba en la pestaña activa (rama de archivo solo corría sin escena abierta). | `scene_path` explícito → **SIEMPRE** crea archivo (`_create_scene_file`), pestaña activa o no. |
| **S2** | `scene/save` | Éxito falso: guardaba la pestaña activa, nunca el path pedido (no-op silencioso). | `scene_path` opcional → pack+save del root actual a ese path. |
| **S3** | **Contexto de escena inestable** | 86 call sites en 8 handlers resolvían contra `get_edited_scene_root()` (pestaña activa) — cambiaba sola entre llamadas. | `apply_scene_context` (server, por proyecto) + `_scene_root(args)` (plugin) activa la escena objetivo. VER §10 decisión. |
| **S4** | `orchestrate` | "Unknown error" genérico. | (a) `tool:"node/add"` ahora se normaliza a tool+action; (b) errores por op en `results` (no abortan el batch), con `errors` count. |
| **S5** | `shader/resource/scene create` | `write_failed` si la carpeta no existe. | `_ensure_parent_dir()` (DirAccess.make_dir_recursive) antes de escribir. |
| **S6** | **Escena "fantasma" en memoria que save no persiste** | `scene create` podía dejar un árbol en RAM (open_scene_from_path falla silencioso → no es pestaña del editor → `save_scene()` guarda la pestaña activa, no la fantasma → no-op). | **SceneRegistry** (`addons/heren/scene_registry.gd`): registro `scene_path → root` en RAM como fuente de verdad del flujo MCP. `scene save` NUNCA usa `save_scene()`: pack directo del root del registry + `ensure_owner_recursive` (PackedScene omite nodos sin owner) + `ResourceSaver`. `create` abre pestaña primero, si falla mantiene árbol vivo en registry. Los 6 handlers con `_scene_root` resuelven: registry → pestaña → disco. server.rs: `remember_scene_context` registra el path de `create`; `scene/save|open` usan contexto (agente no repite scene_path). |

### Bugs medios — ⚠️ PENDIENTES
| # | Tool | Bug | Causa raíz / Fix |
|---|------|-----|------------------|
| **M1** | `node/array_remove` | Elimina el primer elemento, no el `value` pedido (int vs float en `find`). | `current.find(deserialize_value(value))` — tipar/normalizar. |
| **M2** | `visual/summary` | `node_count:0` inconsistente (by_type sí correcto). | handler cuenta mal. |
| **M3** | `validate/node` | `script_cannot_instantiate` — scripts creados por MCP no se compilan. | `efs.update_file()` no basta; falta re-import/scan. |

### Visual roto (4/7 acciones)
| Acción | Estado |
|--------|--------|
| `ascii` | ✅ árbol completo |
| `summary` | ⚠️ by_type OK, node_count:0 |
| `coords` | ❌ solo 3 nodos, paths ".." (incompleto) |
| `capture` | ✅ **escena off-screen** (SubViewport dedicado; `source: "scene"` default) con framing de la cámara del editor; `source: "viewport"` fallback automático si da 2×2 |
| `node` | ✅ igual que capture (escena off-screen) + bbox/pos correctos |
| `budget` | ❌ **handler `handle_vision_budget` NO existe** en el plugin |
| `cache` | ❌ **handler `handle_vision_cache` NO existe** en el plugin |

### Gaps de exposición (tool vs handler)
- Tool `node` **no expone** `query`, `by`, `recursive`, `owner_path`, `script` → `find`, `get_children(recursive)`, `set_owner`, `add(script)` solo vía `orchestrate` (args crudos). Fix: añadir params al schema.
- Tool `resource` **no crea directorios padre** → "save_failed: Can't open" si la carpeta no existe; no hay tool de mkdir. Fix: crear dirs en create/create_script o exponer mkdir.
- Tool `resource` exige params **required irrelevantes** (append/directory/extension/recursive/resource_type/template) en create_script/edit_script. Fix: hacerlos opcionales.

### Workaround actual
- Para `find`/`set_owner`/`get_children(recursive)`/`add(script)`: usar `orchestrate` con args crudos (funciona perfecto).
- Para carpetas: crear los dirs antes (`resource/create` también falla sin dir). Setup manual.

---

## 1. Filosofía de Hierro

| Pilar | Significado | Aplicación |
|-------|-------------|------------|
| **PODER** | Acceso total a Godot. Cero limitaciones. | Si Godot puede hacerlo, Heren puede hacerlo. |
| **EFICIENCIA** | Cada operación óptima. Sin desperdicio. | Cache agresiva, scripts temporales limpios, sin huérfanos. |
| **RAPIDEZ** | Tiempo de respuesta mínimo. | Cache LRU + TTL, invalidación inteligente, reutilización de sesiones. |

| Pilar Tools | Significado | Aplicación |
|-------------|-------------|------------|
| **CENTRALIZADAS** | Pocas tools que agrupan funcionalidad relacionada. | Una tool maneja TODO lo de su dominio. |
| **MODULARES** | Una tool con múltiples modos/comandos. | `action="get_tree"` o `action="save"`. Un punto de entrada, múltiples operaciones. |
| **POTENTES** | Máximo poder con mínima cantidad de tools. | Una tool crea, modifica, elimina y consulta. Godot hace el trabajo pesado. |

**Decisiones derivadas:** GodotDaemon ÚNICAMENTE (sin fallback CLI) → *v4: EditorPlugin real*. Session Manager primero. Daemon persistente (~20ms/op). Cache en RAM. Fail-fast. Tools multifuncionales.

---

## 2. Arquitectura (v4 — EditorPlugin + Rust)

```
OpenCode (cliente MCP)
    │  STDIO (MCP protocol, NDJSON)
    ▼
HerenServer.exe  (FlojoMCP — Rust, 7MB, sin runtime)
    │  WebSocket server local (127.0.0.1:PUERTO)  ← patrón gopeak
    ▼
HerenEditorPlugin  (EditorPlugin GDScript → EditorInterface)
    ├── editor_plugin.gd         # extends EditorPlugin, lifecycle
    ├── ws_client.gd             # cliente WS con auto-reconnect
    ├── dispatcher.gd            # recibe tool_invoke → ejecuta handler
    ├── undo_redo_wrapper.gd     # envuelve ops en EditorUndoRedoManager
    └── handlers/                # scene, node, resource, animation(+skeleton),
                                 # shader, tilemap, project, debug, visual,
                                 # signal, validate + coords.gd
```

**Flujo:** `session/open` (auto-launch Godot con plugin) → `godot_ready` → WS registra `ConnectedEditors[project_path]` → tools enrutan al editor vivo (~20ms) → mutaciones con undo/redo.

**Módulos ELIMINADOS de v3:** `godot_daemon.py`, `session_manager.py` (Python), `heren_daemon.gd` orquestador, `heren_window_manager.gd`, `heren_server_manager.gd`, `heren_tscn_serializer.gd` (la serialización .tscn la hace Godot nativamente al guardar).

---

## 3. Reglas de Oro para Agentes

1. **Session Manager es el Rey.** SIEMPRE `session/open` primero. NUNCA operar sin sesión. NUNCA cerrar hasta terminar.
2. **Godot hace el trabajo pesado.** NUNCA parsear .tscn a mano. El editor/daemon devuelve JSON perfecto en ~20ms.
3. **Tools centralizadas.** 15 tools cubren TODO Godot. NO dispersar en 50 tools con 1 función.
4. **Tools modulares.** Una tool, múltiples modos vía `action`.
5. **Tools potentes.** Una tool hace TODO un flujo. El agente dice QUÉ, no CÓMO.
6. **Cache es tu amigo.** Primera vez lee de disco (~3s), luego memoria (~0ms).
7. **Fail-fast.** Si Godot no responde → error inmediato. NUNCA silenciar errores. NUNCA retornar None sin explicación.
8. **LAIKA es SOLO PRUEBAS.** El plugin v4 FUENTE vive en `heren-mcp/addons/heren/`. NUNCA commitear a LAIKA. Para validar: copiar addon → LAIKA/proyecto temporal. Cambios → commit SOLO en heren-mcp.

---

## 4. Estructura de Directorios (v4)

```
D:\Mis Juegos\GodotMCP\heren-mcp\
├── AGENTS.md                 # Este archivo
├── README.md / README.en.md  # Usuarios finales
├── CHANGELOG.md              # Historial de versiones
├── Cargo.toml                # 🆕 workspace Rust (crates/heren-server) — 2026-08-07
├── crates/heren-server/      # 🆕 server Rust (MCP stdio NDJSON + WS plugin bridge, FlojoMCP)
│   ├── src/                  # editor, launcher, registry, server, ws_plugin_server
│   └── tests/                # tools_parity, ws_plugin
├── heren-build.bat           # 🆕 compila server (debug+test+release+clippy, VsDevCmd)
├── install_mcp.py            # Instalador 1-comando (compila + registra MCP + verifica)
├── run.bat                   # Launcher para OpenCode (heren-server.exe local)
├── addons/heren/             # 🆕 FUENTE del plugin v4 (GDScript, copiable a cualquier proyecto)
│   ├── plugin.cfg
│   ├── editor_plugin.gd      # EditorPlugin core (WS client + dispatcher + registro)
│   ├── ws_client.gd          # Cliente WS MCP JSON-RPC (auto-reconnect)
│   ├── dispatcher.gd         # Rutea tools/call → handlers por prefijo (soporta coroutine)
│   ├── undo_redo_wrapper.gd
│   └── handlers/             # scene, node, resource, project, signal, validate,
│                             # debug, shader, animation(+skeleton), tilemap, visual, coords
├── src/heren/                # Bridge Python (fallback/referencia, NO activo)
├── .temp/                    # Archivos temporales (auto-limpieza)
├── tests/                    # Tests por capa
└── benchmarks/               # Benchmarks de rendimiento
```

> **FlojoMCP ya NO contiene el crate heren-server** (2026-08-07): el server vive
> aquí. FlojoMCP es solo el framework (flojo-mcp, flojo-macros, flojo-session),
> publicado a crates.io; heren-server lo consume por version (no path).

---

## 5. Performance (Real - GodotDaemon, 2026-05-13)

| Operación | Primera vez | Cache hit | Speedup vs Scripts |
|-----------|-------------|-----------|-------------------|
| `session_start` | ~3.5s | — | — |
| `load_scene` | ~3.0s | ~20ms | 150x |
| `get_scene_tree` | ~3.0s | ~20ms | 18x |
| `add_node` / `set_property` / `save_scene` | — | ~20ms | 18x |
| `screenshot` | — | ~60ms | — |
| `batch (11 ops)` | — | ~200ms | 18x |

**Promedio:** ~20ms por operación con daemon. **Sin daemon: ELIMINADO (v3.0).** 18x más rápido.

---

## 6. Las 15 Tools de Heren MCP v4.3

| # | Tool | Actions | Dominio | Estado | Notas |
|---|------|---------|---------|--------|-------|
| 1 | `session` | open, close, list, info, health | Sesiones | ✅ 100% | close_editor opcional (default false) |
| 2 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas | ✅ 100% | EditorPlugin real |
| 3 | `node` | add, instantiate, remove, set_prop, get_prop, get_info, get_children, find, duplicate, rename, move, set_owner, reorder, array_append, array_remove | Nodos | ✅ 100% | instantiate = `.tscn` como hijo (PackedScene.instantiate GEN_EDIT_STATE_INSTANCE → ExtResource externo, no copia inline). coords proactivas en mutaciones |
| 4 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd | ✅ 100% | EditorFileSystem |
| 5 | `project` | create, setup_plugin, setting, autoload, remove_autoload, input_map, shader_global | Configuración | ✅ 100% | **v4.3**: setting con `op` get/set/list/delete/set_multi + `restart_required`/`applied_runtime`; input_map con persistencia REAL (`input/<action>` en project.godot) + add_event/set_events/remove_event/set_deadzone + JoypadMotion; create sin editor + main.tscn automática |
| 6 | `shader` | create, edit, get, inspect, validate, material, uniform, apply | Shaders | ✅ 100% | **v4.3**: `apply` one-shot (shader+material+uniforms en 1 llamada), `inspect` (uniforms vía `get_shader_uniform_list`), `get` (leer código), `validate` real (`get_errors`), template en create |
| 7 | `animation` | create_player, create, add_track, add_key, state_machine, play, stop, seek, speed, get_animations, get_tracks, get_keyframes, get_state_machine, remove_track, remove_key, update_key, update_props, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, tree_activate, tree_travel, tree_set_param, tree_get_param, duplicate, delete, rename, reverse, blend_pose, retarget | Animaciones | ✅ 100% | AnimationLibrary + playback + edición + procedural + tree control + gestión (§9) |
| 8 | `skeleton` | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment, skeleton_get_bones, skeleton_get_pose, skeleton_set_pose, skeleton_ik, skeleton_fabrik, capture_pose | Esqueletos 2D/3D | ✅ 100% | fusionado en animation_handlers; IK 2D FABRIK + IK 3D |
| 9 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps | ✅ 100% | requiere TileSet |
| 10 | `debug` | run_scene, stop_scene, is_playing, get_editor_errors | Depuración | ✅ 100% | editor real, no subprocess |
| 11 | `validate` | scene, script, node, resource | Validación | ✅ 100% | contra escena viva |
| 12 | `signal` | connect, disconnect, list, set_script | Señales | ✅ 100% | CONNECT_PERSIST |
| 13 | `orchestrate` | (múltiples ops en una llamada) | Batch | ✅ 100% | plan_file evita dicts anidados |
| 14 | `visual` | coords, summary, ascii, capture, node, budget, cache | Visión §7 | ✅ 100% | 1 tool, 7 acciones (consolidada) |
| 15 | `health` | server + editor status | Health | ✅ 100% | connected_projects |

**Filosofía:** 15 tools cubren TODO Godot. NO dispersar. Una tool con múltiples modos vía `action`. Las tools de visión se consolidaron en UNA (`visual`).

**Comparativa vs competidores (README §"Frente a otros MCPs")**: basada en datos VERIFICADOS de `.competitors/` (coding-solo, gopeak). Reglas: (1) NUNCA marcar ❌ una capacidad que el competidor SÍ tiene (ej: GoPeak tiene editor bridge, Coding-Solo tiene auto-launch/run); (2) usar sus propios análisis (gopeak `ANALYSIS.md` documenta sus GAPS: animación, señales, tilemap) en vez de asumir; (3) al actualizar, re-verificar contra los repos en `.competitors/`, no copiar la tabla vieja. Si un competidor añade algo, actualizar la tabla.

---

## 7. Sistema de Coordenadas (ADR-005) + Visión

### Coordenadas unificadas (heredado + expansión)
Auto-detección por keys (v3 éxito): `x`+`y`→Vector2; `x`+`y`+`z`→Vector3; `r`+`g`+`b`→Color; `origin`+`x_axis`+`y_axis`→Transform2D; `origin`+`basis`→Transform3D; `normal`+`d`→Plane; `position`+`size`→Rect2/AABB. Expansión v4: Vector2i/3i, Quaternion, StringName. `deserialize_resource`: `{"type": "RectangleShape2D", "size": {...}}` → instancia por ClassDB.

### Sistema de Visión — "Ojos con Control" (§13.6)
**Pull, no push.** Jerarquía de costo (la clave):
```
NIVEL 0: Coords textuales (siempre, proactivo en mutaciones)   ~20-100 tok
NIVEL 1: visual_summary + visual_ascii (sin imagen)            ~50-150 tok
NIVEL 2: visual_capture low-res (viewports reales 2D/3D)        ~200-400 tok
NIVEL 3: visual_capture full + visual_node (framing)            ~800+ tok
```
**Regla de oro:** consultar NIVEL 0 primero. Las coords textuales bastan para la mayoría de operaciones. La imagen (NIVEL 2-3) es el zoom cuando el texto no basta.

**Coords proactivas en mutaciones:** cada tool que crea/elimina/edita nodos devuelve las coordenadas del nodo afectado (`position`, `global_position`, `bbox` si aplica, `parent_path`).

**Tool `visual` (centralizada, 1 tool con acciones):**
| action | Costo | Qué devuelve |
|--------|-------|--------------|
| `coords` | ~20-100 tok | Mapa de coordenadas de la escena (textual) |
| `summary` | ~50 tok | Contador por tipo, bbox total, dirty flags |
| `ascii` | ~150 tok | Árbol ASCII colapsado/expandido |
| `capture` | alto | **`Image` base64 MCP** — **escena OFF-SCREEN** (SubViewport dedicado; `source:"scene"` default, framing de la cámara del editor) o viewport del editor (`source:"viewport"`, fallback auto si da 2×2) + metadatos |
| `node` | alto | `Image` de la escena (misma fuente que capture) + bbox/pos del nodo |
| `budget` | ~30 tok | Consultar/establecer presupuesto de tokens |
| `cache` | ~30 tok | Ver/limpiar cache de visión |

**Formato captura:** `{"image": <base64 PNG — image_content MCP, NO path>, "metadata": {tokens_estimate, resolution, viewport, scene_hash, cached, node_count, selected}}`.

**Implementación (2026-08-07):** `visual_handlers.gd` ya NO usa `get_editor_viewport_2d/3d().get_texture().get_image()` (devuelve 2×2, placeholder): `_render_scene_offscreen()` clona el root sin scripts en un `SubViewport` dedicado (UPDATE_ALWAYS, World3D propio en 3D, transparent en 2D), replica el framing de la cámara del editor (`get_camera_2d/3d`), `await` 2× `RenderingServer.frame_post_draw` y captura. `source:"scene"` (default) | `source:"viewport"` (editor, con fallback automático a scene si la imagen sale 2×2). Dispatcher/editor_plugin soportan handlers coroutine (`await`). `ws_client.gd` pasa `__image_base64` + `__image_format`. Eventos push (`selection_changed` via `_edit()`, rate-limit 1/s).

---

## 8. Sesiones (arquitectura corregida 2026-08-03)

**Sesión = editor vivo conectado (runtime, en RAM del server).** No es session.json, no es un daemon.

```
ConnectedEditors: { project_path → conexión WS }
Ciclo:
1. El editor arranca con el plugin → conecta al server → envía godot_ready
2. El server registra: ConnectedEditors[project_path] = conexión
3. Operación sobre proyecto X → usa el editor vivo de X (~20ms, sin arranque)
4. Sin editor vivo para X → lanzar Godot con X una vez (3-5s) o avisar
5. El editor se cierra → conexión cae → el server des-registra
```

**Propósitos:** Descubrimiento (`ConnectedEditors` expone qué hay abierto), Enrutamiento multi-proyecto (operación lleva `project_path`), Auto-lanzamiento (`last_project` en disco), Re-sincronización (`godot_ready` re-envía estado al reconectar), Presupuesto de visión (State en RAM del Context).

**Lo que NO es sesión:** presupuesto de visión/preferencias → State efímero en RAM (muere con la sesión). `open_scenes`/`selected_nodes` → se consultan al editor vivo bajo demanda. NO se persisten.

**session.json en disco (mínimo):** `.heren/session.json` → solo `last_project` (1 clave, para auto-lanzamiento).

---

## 9. 🎬 PLAN DE MEJORA — ANIMATION TOOLS (2026-08-04)

> **Objetivo:** llevar `animation`/`skeleton` de "básico funcional" a "potente e innovador".
> Auditoría completa vs competencia (Better Godot MCP, satelliteoflove/godot-mcp, tugcantopaloglu/godot-mcp 149 tools, Unity MCP, unreal-animation-mcp 62 tools, Blender MCP).
> Handler actual: `addons/heren/handlers/animation_handlers.gd` (1598 líneas). Tool Rust: `server.rs`.
>
> **ESTADO 2026-08-04**: **Fases 1-4 IMPLEMENTADAS** (playback, inspección, edición, one_shot, tween,
> skeleton pose/ik, state_machine ampliado, record/from_path/loop_pose/preview/curve).
> **P1 COMPLETADA**: `capture_pose` (con captura en cadena bones/chain/from_bone+depth), `bone` tracks por nombre,
> `tree_travel`/`tree_set_param`/`tree_get_param`/`tree_activate` (control AnimationTree runtime),
> `skeleton_fabrik` (IK 2D procedural FABRIK con pesos), IK 3D ampliado (magnet/influence/target_position),
> `visual/capture` con seek automático (`animation:{player_path,anim_name,time}`), `preview` devuelve imagen,
> `skeleton_get_pose` con `global` + AABB de la pose.
> **P2/P3 COMPLETADAS**: `duplicate`/`delete`/`rename` (gestión), `reverse` (copiar invertida), `blend_pose` (blend procedural),
> `retarget` (por nombre de hueso, solo rigs compatibles). API verificada contra docs oficiales 4.7.
> 12/12 handlers `--check-only` OK. Binario release compilado con todas las acciones.
> **PENDIENTE: validación E2E en vivo** (requiere sesión MCP nueva).

### 9.1 Problemas MUY mejorables (auditoría)

| # | Problema | Impacto |
|---|----------|---------|
| 1 | **No hay playback control** (play/stop/seek/speed) | El agente crea a ciegas, sin verificar. Todos los competidores lo tienen. |
| 2 | **No hay inspección/lectura** (get_animations, get_tracks, get_keyframes, get_state_machine) | No puede ver qué hay antes de editar. |
| 3 | **`add_track` de bajo nivel** — requiere track_type manual + node_path + property; NO soporta `TYPE_BEZIER` ni `TYPE_AUDIO` | Torpe; el agente debe saber el tipo exacto. |
| 4 | **`add_key` de bajo nivel** — requiere `track_idx` (int); `transition` es solo float, sin easing curves | Debe poder referenciar por (node_path+property) o nombre de track. |
| 5 | **`state_machine` limitadísimo** — solo AnimationNodeStateMachine; NO hay BlendSpace2D/3D, BlendTree, OneShot, TimeScale, Transition; NO hay parámetros del AnimationTree ni travel | No puede construir grafos complejos. |
| 6 | **No hay Tween** (runtime) | Godot Tween es la forma más común de animar en runtime. |
| 7 | **Skeleton incompleto** — no hay get_bones, get_pose, set_pose, SkeletonIK3D | No puede animar huesos proceduralmente. |
| 8 | **No hay edición** (remove_track, remove_key, update_key, update_props) | Solo add. |
| 9 | **Bug: `create` con `loop=true` borra tracks** | Re-crea la animación vacía. Falta setter de loop_mode post-hoc. |
| 10 | **No hay batch "one-shot"** | Crear animación completa requiere N llamadas. |

### 9.2 Ideas INNOVADORAS (utilidad real, nadie lo hace)

| # | Idea | Por qué es innovador |
|---|------|---------------------|
| **A** | **`animation/record` — grabación en vivo** | "Graba mientras muevo el nodo en el editor" → el plugin captura el estado cada frame y genera la animación. Como el modo record de Unity, en el editor de Godot. **Nadie lo hace en Godot MCP.** |
| **B** | **`animation/from_path` — bake desde Path2D/Curve2D** | El agente da un `Path2D` y el plugin genera la animación de posición siguiendo el path. Ideal para enemigos, plataformas, cámaras. **Nadie lo hace.** |
| **C** | **`animation/loop_pose` — animación de bucle procedural** | "idle bob de 10px a 2Hz" → el plugin genera los keyframes de bucle (breathing, walk simple, idle). Prototipado instantáneo. |
| **D** | **`animation/preview` — captura visual de un frame** | `seek(t)` + `visual/capture` → el agente **ve** el pose en un instante. Combina con el sistema de visión §7. **Nadie lo hace.** |
| **E** | **`animation/one_shot` — batch completo** | `{anim_name, length, loop, tracks:[{node, property, keys:[{time, value, easing}]}]}` → todo en UNA llamada. Lo que el agente realmente quiere. |
| **F** | **`state_machine` con blend spaces + parámetros** | Grafo completo: BlendSpace2D (walk/run por velocidad), parámetros, travel. |
| **G** | **`animation/curve` — easing curves** | Interpolación por easing (linear/cubic/elastic/bounce) en vez de transition float. |
| **H** | **`skeleton/pose` + `skeleton/ik`** | Leer/escribir pose de todos los huesos + configurar SkeletonIK3D con target. |

### 9.3 Plan por fases

**Fase 1 — Playback + Inspección (✅ IMPLEMENTADA):**
- ✅ `animation/play`, `stop`, `seek`, `speed`
- ✅ `animation/get_animations`, `get_tracks`, `get_keyframes`, `get_state_machine`

**Fase 2 — Edición + One-shot (✅ IMPLEMENTADA):**
- ✅ `remove_track`, `remove_key`, `update_key`, `update_props`
- ✅ `animation/one_shot` (batch completo)
- ✅ Fix bug loop=true (via `update_props` post-hoc)

**Fase 3 — Avanzado (✅ IMPLEMENTADA):**
- ✅ `state_machine` con blend spaces 1D/2D + blend_tree + parámetros
- ✅ `animation/tween`
- ✅ `skeleton/pose` (get/set), `skeleton/ik`

**Fase 4 — Innovación pura (✅ IMPLEMENTADA):**
- ✅ `record`, `from_path`, `loop_pose`, `preview`, `curve`

**P1 — Flujo "personaje entero" + IK profundo (✅ IMPLEMENTADA):**
- ✅ `skeleton/capture_pose` — snapshot de pose completa en keyframe, con **captura en cadena** (`bones` exacta | `chain` ordenada | `from_bone`+`depth` | todos)
- ✅ `bone` track en `add_track`/`one_shot` — animar hueso por NOMBRE (3D: `bones/<idx>/pose`; 2D: Bone2D `rotation`/`position`)
- ✅ `tree_travel`/`tree_set_param`/`tree_get_param`/`tree_activate` — control runtime del AnimationTree (blend positions, travel entre estados)
- ✅ `skeleton_fabrik` — IK 2D procedural FABRIK (cadena de Bone2D → objetivo, con `weights` por hueso)
- ✅ `skeleton_ik` ampliado — `target_position` (sin nodo target), `use_magnet`/`magnet`, `influence`, `min_distance`
- ✅ `visual/capture` con `animation:{player_path,anim_name,time}` — seek automático antes de capturar
- ✅ `preview` con `with_image:true` — devuelve la imagen del frame directamente
- ✅ `skeleton_get_pose` con `global` (posición mundial por hueso) + `aabb` de la pose

**P2 — Gestión + P3 — Avanzado (✅ IMPLEMENTADAS):**
- ✅ `duplicate`/`delete`/`rename` — gestión de animaciones (iterar sin recrear)
- ✅ `reverse` — copia invertida (walk → walk_rev, ciclos)
- ✅ `blend_pose` — blend procedural: interpola pose actual → target_pose por hueso con `factor` (0..1), desde `rest` o pose actual
- ✅ `retarget` — copia animación a otro Skeleton3D mapeando por NOMBRE de hueso (solo rigs compatibles: hips/spine/upper_arm_L...)
- ✅ API verificada en línea (docs.godotengine.org 4.7): Animation.track_insert_key/transition, AnimationLibrary.rename_animation/remove_animation, AnimationNodeStateMachinePlayback.travel, AnimationTree parameters, Skeleton3D.get_bone_global_pose

**Coordenadas enriquecidas (§9.4) — ✅ IMPLEMENTADA en `node_handlers.gd _node_coords()`.**

> ⚠️ Nota API descubierta: `AnimationNodeBlendSpace3D` NO existe en Godot 4.7 (solo 1D/2D).
> `SkeletonIK3D` usa `target_node` (NodePath), NO `target` (Transform heredado).
> `AnimationNodeBlendTree.connect_node(input_node, input_index, output_node)` — 3 args.

### 9.4 Coordenadas enriquecidas (conocimiento espacial)

El `_node_coords` actual solo da `pos` + `bbox` (y solo para Sprite2D y CollisionShape2D). Enriquecer:

| Campo | Qué aporta | Tipos |
|-------|-----------|-------|
| `size` | Tamaño real (px/units) | Sprite2D, Label, Polygon2D, Line2D, AnimatedSprite2D, TextureRect, Control, MeshInstance3D (AABB) |
| `height` | Altura (3D: AABB.y; 2D: h) | Node3D, Sprite2D, Control |
| `scale` | Escala actual | CanvasItem, Node3D |
| `rotation` | Rotación en **grados** (más legible) + rad | CanvasItem, Node3D |
| `z_index` | Orden de dibujo 2D | CanvasItem |
| `visible` | Visibilidad | Node |
| `aabb` | Bounding box 3D completo | Node3D con mesh |

Esto da al agente **conocimiento espacial completo** sin llamadas extra. Beneficia a TODAS las tools, no solo animación.

---

## 10. Decisiones Registry (v4 relevantes)

| Fecha | Decisión | Razón |
|-------|----------|-------|
| 2026-08-03 | **EditorPlugin sobre GodotDaemon (ADR-002)** | El daemon corre `Engine.is_editor_hint()=false` → nunca toca el editor real. EditorPlugin gana: undo/redo, viewports reales, EditorFileSystem, play con breakpoints. |
| 2026-08-03 | **WS con plugin=cliente (ADR-003, patrón gopeak)** | El MCP server abre WS; el plugin se conecta con auto-reconnect. El editor NO depende del server. Permite push de eventos. |
| 2026-08-03 | **Sesión = editor vivo (ADR-004)** | `ConnectedEditors` en RAM + `last_project` en disco. Se descartó vision/preferences/workspace_state (era especulación). |
| 2026-08-03 | **Coordenadas unificadas heredadas (ADR-005)** | `serialize_value`/`deserialize_value` con auto-detección por keys. Gran éxito. Expansión backward-compatible. |
| 2026-08-03 | **FlojoMCP sobre FastMCP (ADR-001)** | FastMCP genera schemas por introspection runtime → decoradores rompen firma → schemas vacíos. FlojoMCP schemas en compile-time. |
| 2026-08-04 | **NDJSON, NO Content-Length** | OpenCode 1.18 envía NDJSON puro (verificado con stdin-spy). `flojo_run_stdio_cl` era la causa del timeout. |
| 2026-08-04 | **Schemas booleanos `true` → "Failed to get tools"** | `schemars` genera `true` para `serde_json::Value`. Fix: `normalize_json_schema()` reemplaza booleanos por `{}`. |
| 2026-08-04 | **Single-instance** | `run()` mata otros heren-server.exe (nunca el actual) antes de bindear. |
| 2026-08-06 | **❌ ELIMINADO: `kill_previous_servers()` mataba servers de sesiones OpenCode hermanas** | OpenCode lanza UN heren-server por sesión/chat/agente. Al arrancar, `kill_previous_servers()` hacía `taskkill /F` contra CUALQUIER otro heren-server.exe → mataba el server de la OTRA sesión en plena operación → `MCP connection closed server=godot` + AbortError masivo → agentes de la sesión asesinada NO ven las tools. Evidencia: 4 `starting stdio server` en 30 min (2026-08-06 22:38→23:07 UTC). **Fix (FlojoMCP `c32cd34`)**: kill eliminado; `ws_port()` cachea con OnceLock y busca puerto libre `9099+N` si 9099 está tomado → cada heren-server bindea SU puerto y atiende a SU editor (session/open ya pasa `HEREN_MCP_PORT`). Verificado E2E: 2 instancias con stdin abierto viven simultáneas en 9100/9101. |
| 2026-08-04 | **`[editor_plugins]` formato Godot 4** | `enabled=PackedStringArray(...)`. El formato viejo `enabled_plugins=[...]` NO carga el plugin. |
| 2026-08-04 | **Instalación completa** | `source_files_match()` verifica TODOS los archivos, no solo plugin.cfg. |
| 2026-08-04 | **`project/create` sin editor** | Escribe project.godot directo en disco. Evita la circular dependency (no se podía crear el primer proyecto sin editor). |
| 2026-08-04 | **Skeleton2D API falsa** | Skeleton2D NO tiene find_bone/set_bone_rest (Skeleton3D). Huesos = Bone2D hijos con `.rest=Transform2D`. `BoneAttachment2D` NO existe. |
| 2026-08-04 | **`args()` omite keys None** | Antes insertaba `Value::Null` → `str(null)`="<null>" rompía guards. |
| 2026-08-04 | **`launch_editor` mata zombie** | Recibe `editor_connected`; si hay proceso sin conectar lo mata y relanza limpio. Siempre sincroniza plugin antes. |
| 2026-08-04 | **`node/instantiate` = instancia externa (no copia)** | `PackedScene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)` → add_child + owner=root → pack() serializa `instance=ExtResource(...)` (referencia al .tscn), NO copia inline. **`ensure_owner_recursive` NO baja dentro de nodos con `scene_file_path != ""`** (instancia externa: sus internos viven en el .tscn referenciado; tocarlos los copiaría inline y duplicaría recursos). E2E validado en sandbox (`parent_out.tscn` con `instance=ExtResource`). |
| 2026-08-04 | **`node/instantiate` con `instance_path`** | Tool `node` acepta `instance_path` (la .tscn/.res a instanciar) + `node_path`/`parent_path` (padre) + `node_name` + `properties` + `script` override. `node_type` sigue para clases nativas (backward-compatible). |
| 2026-08-04 | **`input_map` persistencia REAL** | `InputMap.add_action()`/`action_add_event()` solo modifican memoria runtime; `ProjectSettings.save()` guardaba project.godot SIN `input/*` → las acciones desaparecían al recargar. Fix: `_persist_input_action()` escribe `ProjectSettings.set_setting("input/<action>", {"deadzone":…,"events":[…]})` con el formato exacto que Godot espera. E2E validado: project.godot contiene `[input] test_jump={"deadzone":0.35,"events":[…]}`. |
| 2026-08-04 | **`setting` con `op` + restart-aware** | `op`: get/set/list (prefix)/delete/set_multi. `restart_required` por prefijos read-at-startup (display/, rendering/, application/config/, input/…); `applied_runtime` para settings con equivalente vivo (viewport → DisplayServer.window_set_size, max_fps → Engine.max_fps). |
| 2026-08-04 | **`session/reopen`** | Mata el editor (conectado o no) y relanza limpio — para settings con `restart_required: true`. Usa el contexto del proyecto: el agente NO repite project_path. `launch_editor(editor_connected=false)` tras kill. |
| 2026-08-04 | **`input_map` ampliado** | types: add/get/list(include_ui,prefix)/add_event(set_events batch)/remove_event(index)/set_deadzone/set_event(backward-compat)/remove. `_create_input_event`: InputEventKey con keycode por nombre ("W","KEY_W","space" vía OS.find_keycode_from_string), MouseButton, MouseMotion, JoypadButton, JoypadMotion(axis/axis_value). |
| 2026-08-04 | **`SkeletonIK3D.magnet` es Vector3, `target_node` es NodePath** | `magnet` es el punto de magnet (no float); `target` es el Transform heredado (no usar). `target_node` recibe NODE PATH. |
| 2026-08-04 | **`AnimationNodeBlendTree.connect_node(input, input_index, output)`** | 3 args en Godot 4.7 (input_node, input_index, output_node) — NO (from, from_port, to, to_port). |
| 2026-08-04 | **IK 2D = FABRIK propio** | Godot no tiene IK nativo 2D. `skeleton_fabrik` implementa FABRIK sobre Bone2D con pesos por hueso. |
| 2026-08-04 | **Contexto de escena estable (S3)** | `apply_scene_context` en server.rs guarda el último `scene_path` por proyecto en RAM y lo inyecta en llamadas de node/animation/shader/signal/tilemap/visual (nunca sobreescribe si ya viene explícito). En el plugin, `_scene_root(args)` activa la escena pedida con `open_scene_from_path`. El agente fija la escena UNA vez (`scene_path` en una llamada) y el resto de la sesión opera contra ella — adiós a los `node_not_found` intermitentes por cambio de pestaña. `validate` NO usa este contexto (su `scene_path` es el archivo a validar). |
| 2026-08-04 | **SceneRegistry = fuente de verdad de escenas (S6)** | `addons/heren/scene_registry.gd`: `scene_path → root` en RAM. `scene/save` es pack directo del root registrado (`ensure_owner_recursive` + `ResourceSaver`), NUNCA `save_scene()` (pestaña). `scene/create` abre pestaña; si `open_scene_from_path` falla silencioso, mantiene el árbol vivo en el registry (la "escena fantasma" deja de ser bug: es el diseño). `_scene_root` en 6 handlers resuelve registry → pestaña → disco. `remember_scene_context` (server) registra el path de `create`; `scene/save|open` inyectan contexto → el agente NO repite `scene_path`. `handle_save` acepta `output_path` como alias. |
| 2026-08-06 | **`Shader.get_errors()` NO EXISTE en Godot 4.7 (API falsa)** | Verificado en runtime: `has_method("get_errors") == false`. `handle_validate`/`handle_inspect` lo llamaban → SCRIPT ERROR → excepción se propagaba por dispatcher → el server nunca respondía → "Unknown error". El fix anterior del AGENTS.md ("tipo explícito `var errors: PackedStringArray = ...`") solo ocultaba la pista: el error de inferencia `:=` ERA porque el método no existe. **Fix**: `_shader_structural_issues()` (shader_type, función principal por modo, llaves) + heurística de compilación real: si declara uniforms pero `get_shader_uniform_list()` sale vacío → error. `sh.mode` → `sh.get_mode()`. Lección: validar APIs contra `has_method()` antes de usarlas. |
| 2026-08-06 | **`scene_path` del agente NO es canónico → normalizar SIEMPRE** | El plugin compara `scene_file_path` (siempre `res://...` normalizado por Godot) contra la key del SceneRegistry. Paths crudos (`scenes/x.tscn`, `res:\...`, trailing `/`) rompían el match → escena fantasma divergente → "no crea / no persiste / no abre". **Fix**: `normalize_scene_path()` en server.rs (aplicado en 8 tools) + `_normalize_scene_path()` defensivo en el plugin + `_norm()` en SceneRegistry. Regla: `res://` prefix, forward slashes, sin trailing; `res:/` (backslashes convertidos) → `res://`. 5 tests Rust. |
| 2026-08-06 | **SceneRegistry: prioridad CORREGIDA = pestaña real → registry → disco** | Antes `resolve_root` daba prioridad al registry (árbol fantasma en RAM) sobre la pestaña real del editor. Si el usuario abría la escena creada por MCP y el registry tenía un fantasma, el agente editaba el fantasma mientras el editor mostraba otra cosa → al recargar se "rehacía" la escena desde disco. **Fix**: pestaña real primero (lo que el usuario ve), luego registry, luego disco. El registro en RAM es caché; el disco es la fuente de verdad persistente. `_create_scene_file` ahora usa `FLAG_BUNDLE_RESOURCES` (paridad con `handle_save`). |
| 2026-08-06 | **Formato `[editor_plugins]` verificado contra source de Godot** | Godot persiste el **path completo** `enabled=PackedStringArray("res://addons/heren/plugin.cfg")` (clave del mapa `addon_name_to_plugin`, `editor_node.cpp` `_update_addon_config` L4493). Acepta al leer también el nombre desnudo `"heren"` (`set_addon_plugin_enabled` L4514 normaliza `res://addons/<name>/plugin.cfg`), pero lo re-escribe como path completo al guardar. El `enabled=PackedStringArray()` vacío = lost-update: un editor VIVO guarda project.godot con su estado en memoria (sin el plugin) y pisa el enable escrito por el server. |
| 2026-08-06 | **`enable_plugin_in_project` IDEMPOTENTE y NORMALIZADORA** | Reemplaza CUALQUIER `enabled=` dentro de `[editor_plugins]` (vacío, `"heren"`, duplicadas) por la única canónica `enabled=PackedStringArray("res://addons/heren/plugin.cfg")`. Solo escribe si difiere; relee y verifica post-escritura (1 línea). 6 tests Rust (`launcher::tests::enable_*`). Antes insertaba duplicados o no corregía el estado vacío. |
| 2026-08-06 | **Plugin SIEMPRE ENCENDIDO + sync INCREMENTAL** | Se habilita UNA vez (`setup_plugin`/`create`); `open` NO lo "reenciende". `ensure_plugin_installed` → sincronización por contenido: copia solo diffs, borra huérfanos, `plugin up-to-date` = cero trabajo. Eliminada la reinstalación total entre versiones (antes `remove_dir_all` + recopia). |
| 2026-08-06 | **`launch_editor` — kill zombie ANTES de escribir project.godot** | Orden correcto: mata editor zombie PRIMERO → sleep → escribe plugin+enable → relanza. Antes escribía enable ANTES de matar → el editor vivo podía pisar project.godot al salir (lost-update → `enabled=PackedStringArray()`). Ahora nadie pisa el archivo recién escrito. |
| 2026-08-06 | **`launch_editor` — no relanzar si no hace falta** | Editor conectado + plugin sin cambios → `reuse up-to-date` (cero trabajo). Editor conectado + plugin cambió → NO relanza (rompería el flujo en marcha): devuelve `plugin_changed=true` y el agente decide `session/reopen`. Zombie → kill + relanzar limpio. |
| 2026-08-06 | **Reporte de versión al agente (plugin_version)** | El plugin lee `plugin.cfg` (`_read_plugin_version`) y lo manda en `godot_ready`. El registry guarda `EditorHandle.plugin_version` (la versión que CORRE en el editor vivo, no la del disco). `session/info` → `plugin_version_source/installed/editor` + `plugin_stale` + `plugin_stale_remedy`; `session/health` → `stale_editors[]`; `open`/`reopen` → `plugin_changed` + versiones. El agente sabe cuándo el editor corre una versión antigua y que `session/reopen` recarga el código nuevo. |
| 2026-08-06 | **Godot NO tiene hot-reload de plugins** | Issue oficial #11612. El EditorPlugin solo se re-instancia con `Project > Reload Current Project` o re-habilitándolo. Por eso la actualización de código del plugin requiere `session/reopen` — pero solo cuando `plugin_changed=true`, no en cada open. |
| 2026-08-06 | **Sub-recursos inline viajan COMPLETOS en serialize_value (StyleBoxFlat/Theme)** | Un recurso SIN `resource_path` (StyleBoxFlat dentro de un Theme .tres, Curve/Gradient en ParticleProcessMaterial) caía a la rama `else` de `serialize_value` → se devolvía el objeto Godot crudo → el JSON no representaba `bg_color`/`border_color` → al `resource/update` se perdían (negro). **Fix**: `serialize_value` serializa inline `{"__type":"Resource","resource_class":X,"props":{...}}` con el MISMO filtro STORAGE que `_serialize_resource_props`; `deserialize_value` rama Resource maneja `resource_class`+`props`; `deserialize_resource` acepta `resource_class` y aplica props desde `props` (recursivo + `deserialize_typed` + `_wrap_curve_gradient` + `ensure_resource_local_recursive`). E2E: Theme → `Panel/styles/panel` con `bg=(0.02,0.03,0.025,0.85)` sobrevive serialize→deserialize→save→reload. Commit `9872546`. |
| 2026-08-07 | **Rediseño persistencia: dirty tracking + flush-before-destroy + error en cierre inesperado** | **3 reglas** (implementadas en FlojoMCP `66812e8`→pendiente): (1) **Dirty set por proyecto** en `registry.rs` (`mark_dirty`/`clean_dirty`/`dirty_scenes`): las mutaciones (`node/*` escritura, `animation/*` escritura, `shader/*` escritura, `signal/*` conexión, `tilemap/*` set) marcan la escena; `scene/save` la limpia; `session/info` y `session/open` exponen `dirty_scenes`. Lecturas (get/inspect/validate/list) NO marcan. (2) **Flush-before-destroy**: `scene/open` de una escena dirty hace `scene/save` ANTES de abrir (no pierde la versión en RAM); `session/close` flushea todas las dirty antes de matar el editor. (3) **Cierre inesperado = ERROR solo si hay trabajo que perder**: si el WS cae sin `session/close`, `mark_unexpected_close` guarda las dirty y TODAS las tools del proyecto fallan con `editor_closed_unexpectedly: ... había N escena(s) con cambios sin guardar: ...` hasta `session/open` (fail-fast, nunca silencio). **Fix 2026-08-07**: con **0 escenas sucias** el cierre es **benigno** — NO se marca el flag (nada que proteger; las tools solo dan `no editor connected` hasta reconectar). `session/close` y `session/reopen` (reinicio deliberado: flush dirty + graceful_close ANTES del kill + clear flag tras relanzar) marcan `graceful_close` para que su desconexión NO marque error. 5 tests de persistencia (incl. `unexpected_close_without_dirty_is_benign`). Costo: ~0ms por mutación (insert HashSet) + ~20ms solo en flush. |
| 2026-08-07 | **visual/capture: render OFF-SCREEN de la ESCENA, NO del viewport del editor** | `get_editor_viewport_2d/3d().get_texture().get_image()` devuelve el placeholder **2×2** (la textura del editor no es un render target accesible) → capturas inservibles. Fix: `_render_scene_offscreen()` en `visual_handlers.gd` — clona el root sin scripts (`duplicate(DUPLICATE_GROUPS)`), lo mete en un `SubViewport` dedicado (`UPDATE_ALWAYS`; `own_world_3d`+Environment BG_COLOR en 3D, `transparent_bg` en 2D), replica el framing del editor (`get_camera_2d/3d()` → cámara nueva en el clon), `await` 2× `RenderingServer.frame_post_draw`, captura y `queue_free`. **`source`**: `"scene"` (default, fiable) | `"viewport"` (editor: gizmos/grid/selección, con fallback automático a scene si sale 2×2). Animación (`animation:` seek) se aplica al player del CLON (escena real intacta) o al real en viewport. **Soporte coroutine en dispatcher**: `dispatcher.execute` completa `GDScriptFunctionState` (detectado por `get_class()`, NO `is` — no es tipo usable en Godot 4) + `editor_plugin._on_tool_invoke` hace `await`. Handlers con `await` = Handler coroutine. Verificado: `--check-only` 3 scripts + grafo completo headless 0 errores; 24+2+1 tests Rust (schema `visual.source`); clippy limpio; release 9.4MB; binario responde initialize+tools/list. |
| 2026-08-07 | **heren-server sale del workspace FlojoMCP → workspace PROPIO en heren-mcp** | El crate Rust (server MCP) era el "dogfooding" del framework FlojoMCP. Decisión del General: (a) el crate vive en `heren-mcp/crates/heren-server` con su propio `Cargo.toml` workspace (deps por `workspace = true`), y (b) **FlojoMCP se publica a crates.io** (`flojo-macros` → `flojo-mcp` → `flojo-session`, @0.1.0) para que heren-server lo consuma por VERSION, no path. Scripts: `heren-build.bat` local (VsDevCmd), `run.bat` → `%~dp0target\release\heren-server.exe`, `install_mcp.py` busca el workspace local. **Config OpenCode actualizada** (`opencode.jsonc` L108): `command` → `D:\Mis Juegos\GodotMCP\heren-mcp\target\release\heren-server.exe` (backup previo). Publicar en orden con `--no-verify` (el verify compila el tarball y la shell sin VsDevCmd usa un linker MSVC roto "VS18 Insiders" sin msvcrt.lib). Tras publicar, cambiar la dep del crate de `path` a `version = "0.1"`. Verificado: 25+2+1 tests OK en el workspace local, clippy limpio, release responde initialize+tools/list. |
| 2026-08-07 | **Cierre inesperado sin dirty = benigno** | El flag `editor_closed_unexpectedly` se marcaba en CUALQUIER desconexión WS sin `session/close`, incluso con **0 escenas sucias** → bloqueaba TODAS las tools (run_scene, validate...) tras un `session/reopen` por actualización del plugin, con mensaje absurdo "(sin escenas sucias)". Fix: `mark_unexpected_close` SOLO marca si hay dirty > 0 (trabajo que se perdería); 0 dirty = desconexión benigna (las tools dan `no editor connected` hasta `session/open`). Y `session/reopen` = reinicio DELIBERADO: flush dirty + `graceful_close` ANTES del kill (patrón de `session/close`) + `clear_unexpected_close` tras relanzar. Test `unexpected_close_without_dirty_is_benign`. |
| 2026-08-08 | **🚨 MISTERIO `enabled=PackedStringArray("heren")` RESUELTO: idempotencia ≠ fallo** | `enable_plugin_in_project` devolvía `false` cuando project.godot **YA tenía la línea canónica** (lo normal tras un editor que guarda) y `launch_editor` interpretaba ese `false` como fallo → `"no editor launched: enable_plugin_in_project failed"` → el server NUNCA lanzaba Godot con la forma canónica. El "workaround" empírico (`"heren"` en vez de la ruta) funcionaba solo porque forzaba una reescritura → `true` → lanzar. **Fix**: contrato `Result<bool, String>` — `Ok(true)`=escribió, `Ok(false)`=ya canónico (éxito), `Err`=fallo REAL. `launch_editor` solo aborta con `Err`; `setup_plugin` propaga `Err` como internal. 7 tests enable_* (nuevo `enable_error_is_real_failure_not_idempotent`). |
| 2026-08-08 | **🚨 Editor abierto por DOBLE CLIC no se detectaba (2 bugs en `godot_processes_for`)** | (1) El filtro exigía `--editor` o `--path` en la CommandLine — el doble clic en project.godot (`Godot.exe "D:\...\project.godot"`) no lleva esas flags → `is_editor_running=false` → session/open lanzaba un editor DUPLICADO o reportaba "no editor connected" con el editor del usuario vivo. Fix: aceptar también `project.godot` en la cmdline. (2) Bug oculto: la CommandLine de Windows usa **backslashes** (`d:\mis juegos\project_rat\project.godot`) pero `proj_norm` es forward-slash (`d:/mis juegos/project_rat`) → `cmd.contains(proj_norm)` NUNCA matcheaba en cmdlines reales. Fix: `cmd.to_lowercase().replace('\\', "/")`. Test `wmic_csv_editor_detected_via_project_dot_godot` (PID 16200 real del incidente). |
| 2026-08-08 | **🚨🚨 BUG RAÍZ del sync: `collect_files` perdía el prefijo de subdirectorio** | La recursión hacía `strip_prefix(p)` (dir anidado) en vez de `strip_prefix(root)` → `handlers/a.gd` salía como `a.gd` → `src.join(rel)` apuntaba a un archivo INEXISTENTE → `files_differ` devolvía true → `copy` fallaba NotFound → `is_ok()` TRAGABA el error → `changed=false` → **"plugin up-to-date (no changes)" MENTIRA** → los handlers NUNCA se actualizaban → mezcla tóxica core-nuevo + handlers-viejos → **SCRIPT ERROR `set_debugger_plugin` inexistente → el editor CRASHEABA al cargar el grafo** (por eso "se rompe con cada update"). Fix: `walk(root, dir)` con el root original + reportar copy failures en el msg. Tests: `collect_files_preserves_subdir_prefix`, `integrity_detects_stale_and_orphan`. |
| 2026-08-08 | **🛠️ DEBUGGER UNIFICADO: `session/diagnose`** | El General: "sin debugging es pura adivinanza". Nueva action de session: (1) `integrity.files[]` — integridad plugin source vs instalado, archivo por archivo (ok/stale/missing/orphan, tamaños); (2) `graph` — valida que el plugin CARGA sin SCRIPT ERROR/Parse Error: copia addons/heren a sandbox temp (`%TEMP%/heren_graph_check_<pid>`), `godot --headless --editor --quit-after 3`, captura errores, limpia SIEMPRE (no toca el proyecto ni el lock .godot); (3) `editor` — procesos vivos con cmdline (`godot_processes_detailed`), conexión WS, puerto. Detecta lo que `--check-only` individual NO ve (grafo completo: métodos inexistentes, inferencia). Verificado: diagnosticó project_rat con el SCRIPT ERROR exacto sin tocar el proyecto. |

---

## 11. Bugs Arreglados (v4, resumen)

| Bug | Fix | Fecha |
|-----|-----|-------|
| **Persistencia de sub-resources** | `resource_local_to_scene = true` + `_setup_resource_local_to_scene_recursive()` | 2026-05-14 |
| **Persistencia de señales** | `_collect_connections()` + `_inject_into_tscn()` | 2026-05-14 |
| **Sub-resource ID corrupción en save** | Eliminar sub-resource injection — `pack()`+`FLAG_BUNDLE_RESOURCES` ya los maneja. Solo connections se inyectan. | 2026-07-17 |
| **Pipeline de guardado refactorizado (v3.0)** | `_pre_save_resource_fix → pack() → save(FLAG_BUNDLE_RESOURCES) → verify`. `handle_connect_signal` usa `CONNECT_PERSIST`. | 2026-07-17 |
| **Parse error: palabras reservadas** | `signal`→`sig`, `match`→`is_match` | 2026-07-28 |
| **Parse error: función anidada** | Búsqueda iterativa con pila | 2026-07-28 |
| **Fix: undo_redo_wrapper add_do_method con callv** | `urm.callv(&"add_do_method", [obj, method] + args)` expande el Array. Sin esto, node/add devolvía `node_path: ""`. | 2026-08-03 |
| **Fix: project.godot corrupto en proyecto E2E** | `[System.IO.File]::WriteAllText(path, content, UTF8Encoding($false))` para .gd/.tscn/.godot (sin BOM). | 2026-08-03 |
| **Fix: id JSON-RPC float→string** | `_pop_pending()` tolera `1`, `"1"`, `"1.0"` (normalización float). | 2026-08-03 |
| **Ciclo de vida sesión: SOLO session/open-close** | `_require_editor` NUNCA lanza el editor. El lanzamiento es SOLO `session/open`. | 2026-08-03 |
| **Normalización de paths (clave canónica)** | `normalize_project_path()` = resolve + forward slashes + sin trailing. | 2026-08-03 |
| **Reuso de editor ya abierto (Q3)** | `session/open` detecta proceso Godot vía WMI CommandLine. | 2026-08-03 |
| **🚨 wmic CSV: índices invertidos rompían la detección de editor abierto** | `wmic ... /format:csv` emite `Node,CommandLine,ProcessId` → `splitn(3,',')` da `parts[1]=CommandLine`, `parts[2]=PID`. El código usaba `parts[2]` como cmd (PID → nunca contenía `--editor` → `continue` SIEMPRE) y `parts[1]` como PID (CommandLine → `parse::<u32>()` fallaba). Resultado: `godot_processes_for()` SIEMPRE vacío → `session/open` lanzaba un editor DUPLICADO con el original abierto. Fix: `parts[1]` = cmd, `parts[2]` = pid. Tests `wmic_csv_parse_extracts_pid` + `wmic_csv_editor_detected_for_project`. | 2026-08-04 |
| **🚨 `var errors := sh.get_errors()` rompía TODO el plugin** | `Shader.get_errors()` no tiene tipo estático inferible en Godot 4.7 → `:=` = "Cannot infer the type" → Parse Error en shader_handlers.gd → grafo de dependencias roto → `editor_plugin.gd` "Compilation failed" → **el editor no conecta al WS sin error visible en la UI**. CRÍTICO: `--check-only --script` de un handler suelto NO detecta esto (el editor cargando el grafo completo sí). SIEMPRE validar con `godot --headless --editor --path <proj> --quit-after 3` (carga el plugin entero). Fix: tipo explícito `var errors: PackedStringArray = sh.get_errors()`. | 2026-08-04 |
| **CRÍTICO: project/setting corrompe project.godot con UID sintético** | Strings `res://`/`user://` se guardan como STRING PLANO (no se deserializan). | 2026-08-03 |
| **Fix: deserialize_value no recorría Array** | Rama `elif value is Array` que deserializa cada elemento recursivamente. | 2026-08-03 |
| **Bug macro FlojoMCP: visibilidad no preservada** | `#[flojo_mcp]` redefinía el struct SIN `pub`. Fix: usar `item.vis`. | 2026-08-04 |
| **Build MSVC: requiere VsDevCmd del BuildTools 2022** | `heren-build.bat` carga `VsDevCmd.bat` antes de cargo. | 2026-08-04 |
| **orchestrate con plan_file** | El plan viaja por archivo, no por tool-call. | 2026-08-04 |
| **Deadlock: stderr del server sin drenar** | heren-server NO escribe tracing a stderr — solo a `HEREN_LOG_FILE`. | 2026-08-04 |
| **Fix C1/C2: `args()` omite keys None** | `args()` omite keys None; `handle_setting` trata null explícito como get. | 2026-08-04 |
| **Fix H2: `shader/material` resource_name** | `material.resource_name =` (no `.name`). | 2026-08-04 |
| **Fix H3: `set_bone_weights` + índice int** | `set_bone_weights(find_bone(...), PackedFloat32Array(weights))`. | 2026-08-04 |
| **Fix H4: skeleton set_rest/attachment ramifican por tipo** | Skeleton2D→`Transform2D`/Node2D hijo; Skeleton3D→`Transform3D`/`BoneAttachment3D`. | 2026-08-04 |
| **Fix H1: `signal/list` totalmente defensivo** | Trata cada conn como Dictionary, `.get()`, aísla por conexión. Key `"signal"`. | 2026-08-04 |
| **🚨 Skeleton2D NO tiene find_bone/set_bone_rest (API falsa)** | Ramificar por tipo real; 2D busca Bone2D hijo iterando `get_bone_count()`/`get_bone()`. | 2026-08-04 |
| **🚨 `BoneAttachment2D` inexistente rompía TODO el plugin** | Parse error → plugin no carga → editor no conecta. Fix: Node2D hijo del Bone2D. **Lección: validar con `--check-only` tras editar handlers.** | 2026-08-04 |
| **Mejora conexión: matar editor zombie** | `launch_editor` recibe `editor_connected`; mata zombie y relanza limpio. | 2026-08-04 |

---

## 12. Gotchas y Lecciones (v4)

- **Las tools MCP se cargan al INICIO de la sesión.** Tras recompilar heren-server.exe, el toolset `godot_*` NO se refresca en una conversación en curso. Abrir SESIÓN NUEVA.
- **Un parse error silencioso en un handler rompe TODO el plugin** → el editor no conecta al WS sin error visible. SIEMPRE validar: `godot --headless --path <proj> --check-only --script res://addons/heren/handlers/X.gd`.
- **`--check-only` de un handler suelto NO detecta errores de inferencia de tipo (`:=`)** que el editor cargando el grafo completo SÍ ve ("Cannot infer the type"). Para validar el grafo completo: `godot --headless --editor --path <proj> --quit-after 3` y grep de `SCRIPT ERROR|Parse Error`. Preferir tipos explícitos (`var x: PackedStringArray = ...`) sobre `:=` cuando el método no tenga binding estático (ej: `Shader.get_errors()`).
- **Los handlers source (`addons/heren/handlers/`) NO se sincronizan solos con el E2E** (`.temp/e2e_minigame/addons/heren/handlers/`) — copiar manualmente tras cada cambio.
- **Config MCP local en OpenCode: clave `environment`, NO `env`.** También existe `"timeout"` (ms, default 5000).
- **Godot headless compite por .godot lock** — usar solo con editor cerrado, o contra copia.
- **Archivos MCP no generan .uid sidecar** — paths en settings → string plano; nunca asumir UID disponible.
- **NO definir `func get_editor()` en EditorPlugin** (colisiona). Usar `get_editor_interface()` directo.
- **`add_do_method` de Godot 4.6** espera `(Object, StringName, args)` — NO acepta Callable directo.
- **resource_handlers sin undo/redo** — los recursos son archivos externos; usan `EditorFileSystem.update_file()`.
- **delete usa DirAccess, no ResourceLoader** — `ResourceLoader` no tiene API de borrado.
- **Consola Windows cp1252** — nada de emojis en output de scripts Python (`UnicodeEncodeError`). Forzar UTF-8 con `io.TextIOWrapper`.

---

## 13. Checklist para Agentes

- [ ] ¿El handler usa `EditorUndoRedoManager` para mutaciones de escena?
- [ ] ¿La serialización de coordenadas usa el sistema unificado?
- [ ] ¿La tool devuelve `tokens_estimate` si es visual?
- [ ] ¿Respeta el presupuesto de visión de la sesión?
- [ ] ¿Hay tests en FlojoTester (Rust) y GUT (GDScript)?
- [ ] ¿El evento push tiene rate-limit?
- [ ] ¿Se documentó en AGENTS.md v4?
- [ ] ¿El bridge v4 sigue operativo? (`python -m heren.v4.bridge`)
- [ ] ¿Los cambios al plugin se versionan SOLO en `addons/heren/`? (nunca en LAIKA)
- [ ] ¿Se validó la sintaxis GDScript con `--check-only` tras editar handlers?
- [ ] ¿Se reinició el MCP (sesión nueva) tras recompilar el server?

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*