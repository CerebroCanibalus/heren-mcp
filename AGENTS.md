# 🐉 Heren MCP - AGENTS.md

> **Filosofía Global: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
> **Filosofía de Tools: Centralizadas. Modulares. Potentes.**

Biblia para agentes que operan Heren MCP. Léelo antes de tocar código.

> 🚧 **ESTADO: v4.2.0 OPERATIVO (EditorPlugin + heren-server.exe Rust/FlojoMCP).**
> Migración GodotDaemon(v3)→EditorPlugin(v4) completada 2026-08-03. Fase 4 (Rust) 2026-08-04.
> **15 tools centralizadas**, WS plugin server (patrón gopeak), auto-launch del editor.
> El .exe habla **NDJSON** por stdio (framing real de OpenCode, verificado con stdin-spy).
> Bridge Python (`python -m heren.v4.bridge`) = fallback/referencia, NO el MCP activo.
> **Los cambios nuevos van a v4/Rust. No ampliar v3 salvo bugs críticos.**
>
> **v4.2 (2026-08-04)**: 15 tools (8 sin `_tool`, 7 visión→`visual`), single-instance (`run()` mata viejos),
> `[editor_plugins]` normalizado a `enabled=PackedStringArray(...)`, instalación completa (verifica TODOS los archivos),
> `project/create` sin editor + main.tscn automática, `project/setup_plugin`, `session.close_editor` opcional (default false).
> **C1/C2 + H1-H4 RESUELTOS Y VALIDADOS E2E EN VIVO** (setting get, signal/list, shader/material, skeleton 2D rest/attachment/skin).
> **Mejora conexión**: `launch_editor` mata editor zombie sin conectar y relanza limpio.

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
| `capture` | ❌ imagen **2×2 px** (viewport 2D no renderiza la escena) |
| `node` | ❌ 2×2 px + pos (0,0) incorrecta |
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
├── install_mcp.py            # Instalador 1-comando (compila + registra MCP + verifica)
├── run.bat                   # Launcher para OpenCode (heren-server.exe)
├── addons/heren/             # 🆕 FUENTE del plugin v4 (GDScript, copiable a cualquier proyecto)
│   ├── plugin.cfg
│   ├── editor_plugin.gd      # EditorPlugin core (WS client + dispatcher + registro)
│   ├── ws_client.gd          # Cliente WS MCP JSON-RPC (auto-reconnect)
│   ├── dispatcher.gd         # Rutea tools/call → handlers por prefijo
│   ├── undo_redo_wrapper.gd
│   └── handlers/             # scene, node, resource, project, signal, validate,
│                             # debug, shader, animation(+skeleton), tilemap, visual, coords
├── src/heren/                # Bridge Python (fallback/referencia, NO activo)
├── .temp/                    # Archivos temporales (auto-limpieza)
├── tests/                    # Tests por capa
└── benchmarks/               # Benchmarks de rendimiento
```

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

## 6. Las 15 Tools de Heren MCP v4.2

| # | Tool | Actions | Dominio | Estado | Notas |
|---|------|---------|---------|--------|-------|
| 1 | `session` | open, close, list, info, health | Sesiones | ✅ 100% | close_editor opcional (default false) |
| 2 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas | ✅ 100% | EditorPlugin real |
| 3 | `node` | add, remove, set_prop, get_prop, get_info, get_children, find, duplicate, rename, move, set_owner, reorder, array_append, array_remove | Nodos | ✅ 100% | coords proactivas en mutaciones |
| 4 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd | ✅ 100% | EditorFileSystem |
| 5 | `project` | create, setup_plugin, setting, autoload, remove_autoload, input_map, shader_global | Configuración | ✅ 100% | create sin editor + main.tscn automática |
| 6 | `shader` | create, edit, validate, material, uniform | Shaders | ✅ 100% | .gdshader + ShaderMaterial |
| 7 | `animation` | create_player, create, add_track, add_key, state_machine, play, stop, seek, speed, get_animations, get_tracks, get_keyframes, get_state_machine, remove_track, remove_key, update_key, update_props, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, tree_activate, tree_travel, tree_set_param, tree_get_param | Animaciones | ✅ 100% | AnimationLibrary + playback + edición + procedural + tree control (§9) |
| 8 | `skeleton` | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment, skeleton_get_bones, skeleton_get_pose, skeleton_set_pose, skeleton_ik, skeleton_fabrik, capture_pose | Esqueletos 2D/3D | ✅ 100% | fusionado en animation_handlers; IK 2D FABRIK + IK 3D |
| 9 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps | ✅ 100% | requiere TileSet |
| 10 | `debug` | run_scene, stop_scene, is_playing, get_editor_errors | Depuración | ✅ 100% | editor real, no subprocess |
| 11 | `validate` | scene, script, node, resource | Validación | ✅ 100% | contra escena viva |
| 12 | `signal` | connect, disconnect, list, set_script | Señales | ✅ 100% | CONNECT_PERSIST |
| 13 | `orchestrate` | (múltiples ops en una llamada) | Batch | ✅ 100% | plan_file evita dicts anidados |
| 14 | `visual` | coords, summary, ascii, capture, node, budget, cache | Visión §7 | ✅ 100% | 1 tool, 7 acciones (consolidada) |
| 15 | `health` | server + editor status | Health | ✅ 100% | connected_projects |

**Filosofía:** 15 tools cubren TODO Godot. NO dispersar. Una tool con múltiples modos vía `action`. Las tools de visión se consolidaron en UNA (`visual`).

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
| `capture` | alto | **`Image` base64 MCP** — viewport 2D/3D real + metadatos |
| `node` | alto | `Image` enfocada en un nodo (framing) |
| `budget` | ~30 tok | Consultar/establecer presupuesto de tokens |
| `cache` | ~30 tok | Ver/limpiar cache de visión |

**Formato captura:** `{"image": <base64 PNG — image_content MCP, NO path>, "metadata": {tokens_estimate, resolution, viewport, scene_hash, cached, node_count, selected}}`.

**Implementación:** `visual_handlers.gd`: `get_editor_viewport_2d/3d()` → `.get_texture().get_image()` → `save_png_to_buffer()` → `Marshalls.raw_to_base64()`. `ws_client.gd` pasa `__image_base64` + `__image_format`. Eventos push (`selection_changed` via `_edit()`, rate-limit 1/s).

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
| 2026-08-04 | **`[editor_plugins]` formato Godot 4** | `enabled=PackedStringArray(...)`. El formato viejo `enabled_plugins=[...]` NO carga el plugin. |
| 2026-08-04 | **Instalación completa** | `source_files_match()` verifica TODOS los archivos, no solo plugin.cfg. |
| 2026-08-04 | **`project/create` sin editor** | Escribe project.godot directo en disco. Evita la circular dependency (no se podía crear el primer proyecto sin editor). |
| 2026-08-04 | **Skeleton2D API falsa** | Skeleton2D NO tiene find_bone/set_bone_rest (Skeleton3D). Huesos = Bone2D hijos con `.rest=Transform2D`. `BoneAttachment2D` NO existe. |
| 2026-08-04 | **`args()` omite keys None** | Antes insertaba `Value::Null` → `str(null)`="<null>" rompía guards. |
| 2026-08-04 | **`launch_editor` mata zombie** | Recibe `editor_connected`; si hay proceso sin conectar lo mata y relanza limpio. Siempre sincroniza plugin antes. |
| 2026-08-04 | **`AnimationNodeBlendSpace3D` NO existe en Godot 4.7** | Solo 1D/2D. Verificado con `ClassDB.get_class_list()`. Usar BlendSpace2D o BlendTree. |
| 2026-08-04 | **`SkeletonIK3D.magnet` es Vector3, `target_node` es NodePath** | `magnet` es el punto de magnet (no float); `target` es el Transform heredado (no usar). `target_node` recibe NODE PATH. |
| 2026-08-04 | **`AnimationNodeBlendTree.connect_node(input, input_index, output)`** | 3 args en Godot 4.7 (input_node, input_index, output_node) — NO (from, from_port, to, to_port). |
| 2026-08-04 | **IK 2D = FABRIK propio** | Godot no tiene IK nativo 2D. `skeleton_fabrik` implementa FABRIK sobre Bone2D con pesos por hueso. |

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