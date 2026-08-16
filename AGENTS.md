# 🐉 Heren MCP — AGENTS.md

> Biblia del agente. Léelo antes de tocar código.
>
> **ESTADO: v4.7** — EditorPlugin (GDScript→EditorInterface) + heren-server.exe Rust/FlojoMCP.
> 17 tools centralizadas (19 con split), WS plugin server (patrón gopeak), auto-launch, NDJSON por stdio.
> Workspace Rust local (`crates/heren-server`); FlojoMCP = framework SOLO (flojo-mcp/macros/session @ crates.io, consumido por version, no path).
> Bridge Python y daemon v3 **archivados en rama `archive/v3`**. **Cambios nuevos → v4/Rust.**
> Plugin SIEMPRE ENCENDIDO + sync incremental por contenido + `session/diagnose` (debugger unificado).
> **Limpieza 2026-08-10→14**: Fases A-F + UI-1/2/3 COMPLETADAS (historial en CHANGELOG.md). Plan de limpieza por fases eliminado (todo [x]).
> **E2E 2026-08-15**: escena compleja real → 11 problemas encontrados → **§0.1 Plan de Mejoría E2E** (P1-P11).
> **Detección/Apertura/Debug 2026-08-15**: feedback General → **§0.3 Plan D1-D4** (wmic eliminado en Win11 24H2+, open fire-and-forget, debug con sleep fijo).

---

## 0. 🚨 Pendientes

### Bugs conocidos (pre-E2E)
- **M1** `node/array_remove`: borra el primer elemento, no el `value` (int vs float en `find`). Fix: tipar/normalizar.
- **M2** `visual/summary`: `node_count:0` inconsistente (by_type OK). Handler cuenta mal.
- **M3** `validate/node`: `script_cannot_instantiate` — scripts MCP no se compilan. Falta re-import/scan.
- **Visual**: `coords` incompleto (3 nodos, paths ".."). `budget`/`cache` ELIMINADOS del toolset (v4.6) — handlers inexistentes; re-implementar si se necesita presupuesto.
- **Gaps tool**: `node_query` no expone `by` (find por tipo) ni `owner_path`/`script` en get_info (usar `orchestrate`); `resource` exige requireds irrelevantes en create_script/edit_script (hacerlos opcionales).

### 🔴 Críticos del E2E (2026-08-15) — ver §0.1
- **P1** `orchestrate` roto (Unknown error en TODAS las ops) — el batch es inútil. **[FIXED: método resolución ordenado en dispatcher.gd; verificado con sesión nueva]**
- **P2** `create_player` ignora `player_path` (crea en ROOT). **[FIXED: player_path respetado como parent; AnimationPlayer creado en nodo pedido]**
- **P3** `add_key` fallo SILENCIOSO con `rotation_3d` + Vector3 (`key_idx:-1`, `keys:0`, devuelve `ok:true` (Godot espera Quaternion)). **[FIXED: handler valida track type y normaliza Quaternion; Quaternion directo funciona. Vector3→Quaternion auto-conversión: pending debug - error "Unknown error" en pipeline Godot]**
- **P11** `add_key` inserta Quaternion NO normalizado → warning Godot. **[FIXED: handler normaliza Quaternion antes de track_insert_key; verificado con Quaternion {"x":1,"y":0,"z":0,"w":0} y key_idx:0]**

### ✅ Completado (historial en CHANGELOG.md)
- **Fases A-F** (2026-08-10→14): limpieza repo, poda v3, refactor handlers, tests+CI, UX/contribución, tipos semánticos. 51 tests Rust + 10 GDScript verdes.
- **Fase UI v1** (2026-08-14): sistema transversal de templates (6 .tscn 2D + `template_registry.gd`) + tool `ui` (6 acciones) + docs v4.7. Detalle §0.2.

---

## 0.1 Plan de Mejoría E2E (2026-08-15) — SEVERO

> **Origen**: E2E real contra editor vivo — escena 3D compleja (20 nodos, meshes, materiales, animaciones, shader, script, UI) construida SOLO con tools MCP en `.temp/e2e_complex/`. Reporte completo: `.temp/E2E_REPORT.md`. **11 problemas encontrados** (3 críticos, 3 altos, 4 medios, 1 bajo). El General evalúa la calidad visual de la escena.

### 🔴 Críticos (bloquean el flujo real)

| # | Problema | Fix sugerido |
|---|----------|--------------|
| **P1** | `orchestrate` falla SIEMPRE con "Unknown error" en TODAS las ops (ambas formas de tool: `node`+action y `node/add`) | Depurar `handle_orchestrate`; test E2E que ejecute 2 ops reales y verifique `ok:true` |
| **P2** | `create_player` ignora `player_path` — crea el player en el ROOT (`./AnimationPlayer`), no en el nodo pedido; luego `create` con `player_path:"Robot"` falla `animation_player_not_found` | Respetar `player_path` como parent; o documentar que el player va SIEMPRE al root |
| **P3** | `add_key` fallo SILENCIOSO con `rotation_3d` + Vector3: `key_idx:-1`, `keys:0`, devuelve `ok:true` (Godot espera Quaternion) | Validar tipo de valor por track + error claro; auto-convertir Vector3→Quaternion; documentar |
| **P11** | `add_key` inserta Quaternion NO normalizado (`{x,y,z,w}` con norma ≠1) → Godot advierte `contains unnormalized Quaternion key` | Normalizar quaternion antes de `track_insert_key`; o aceptar Euler y convertir a unitario |

### 🟠 Altos

| # | Problema | Fix sugerido |
|---|----------|--------------|
| **P4** | `track_type` no documentado: `rotation`/`transform` → `invalid_track_type`; valores reales `value`/`position_3d`/`rotation_3d`/`scale_3d`/`method`/`bezier`/`audio` | Documentar enum en schema/description |
| **P5** | `resource/create` devuelve ~100 props del material (4 materiales ≈ 400 líneas de contexto) | Devolver solo props cambiadas + resumen; flag `verbose:false` default |
| **P6** | `visual/summary` `node_count:0` (M2) + NO recursivo (faltan 9 nodos de 20) | Arreglar M2 + contar recursivo |

### 🟡 Medios / 🟢 Bajo

| # | Problema | Fix sugerido |
|---|----------|--------------|
| **P7** | `resource_incrusted_inline` en meshes primitivos — sin alternativa clara para meshes .tres | Soportar `resource/create` para tipos mesh; o aceptar inline como válido para primitivos |
| **P8** | Tool `ui` y `node/instantiate {template}` NO existen en server en ejecución (binario viejo 4.4.2) | `session/info` debe exponer versión del toolset del server; recordar sesión nueva tras recompilar |
| **P9** | `parent_path:"Main"` se normaliza a `"."` (root = `.`) — confuso | Normalizar a nombre del root en respuesta |
| **P10** | `animation/get_animation` listada en schema pero NO implementada (`tool method not found`) | Implementar o quitar del schema |

### ⚡ Optimizaciones (tras arreglar críticos)

1. **Arreglar `orchestrate` (P1)** = 1 llamada batch (verificado con sesión nueva).
2. **Templates para meshes primitivos** (robot, obstáculo, suelo) — el sistema transversal de templates puede cubrirlo.
3. **`add_key` normalización Quaternion** (P3+P11): Quaternion directo y normalizado funciona; Vector3→Quaternion auto-conversión pending debug.
4. **`resource/create` resumen compacto** (P5) — ahorra ~100 líneas por material.
5. **Schema `animation` con enum `track_type`** (P4).
6. **`summary` recursivo** (P6) — visión real sin imagen.

### ✅ Lo que funcionó bien (no romper)
`node/add` con coords proactivas (aabb/size/height) · `resource/create` para materiales .tres · `shader/create`+`material` en 2 llamadas · `add_track`+`add_key` con Quaternion correcto · `set_prop` para script · `scene/save`+`validate/scene` · `visual_image/capture` off-screen real · `visual_text/ascii` completo · anchors/offsets en `get_info` (UI-2) · `orchestrate` batch (1 llamada, P1 arreglado) · `create_player` con `player_path` (P2 arreglado).

### 📌 Nota log de sesión (no es del MCP)
`failed to load plugin path=list error="Plugin export is not a function"` en TODAS las sesiones desde 2026-07-10 → **config global OpenCode**: `C:\Users\Lord Gatito\.opencode\opencode.json` tiene `"plugin": ["list"]` pero el paquete "list" NO existe (solo `@opencode-ai/plugin`). NO es del MCP de Godot. Fix: quitar `"list"` de la config o instalar el paquete.

---

## 0.2 Plan UI v1 — Sistema transversal de templates + tool `ui` (2026-08-14) ✅ COMPLETADA

**Decisión del General (2026-08-14):** mezcla de Opción B (tool específica `ui`) + Opción C (templates). El sistema de templates es **transversal** (patrón `coords.gd`: RefCounted + funciones estáticas, cualquier handler lo usa), NO acoplado a la tool `ui`. **2D-only** (toda la UI vive sobre viewports). **Híbrido**: templates .tscn + params por nombre de nodo canónico (el registry instancia y setea `Fill.color`, `Label.text`, etc. según `metadata.json`). NUNCA templates 100% código — "eso sería pésimo" (General).

### Fase UI-1 — Infraestructura transversal — ✅ COMPLETADA (2026-08-14)

- **[x] `templates/`** — 6 .tscn 2D (health_bar, crosshair, dialogue_box, score_label, boss_bar, inventory_slot) + `metadata.json` (params con target/targets/property/resource)
- **[x] `template_registry.gd`** — `list_templates()` / `instantiate(name, params)` / `template_exists(name)`, cache RAM, deserializa params con coords.gd
- **[x] `node/instantiate` acepta `template`** — si viene, usa registry; si no, `instance_path` como hoy
- **[x] Tests** — 9 tests GDScript verdes (5 viejos + 4 templates); CI grep 9 passed

### Fase UI-2 — Tool `ui` (modular, 1 tool N acciones) — ✅ COMPLETADA (2026-08-14)

`ui_handlers.gd` (hereda `heren_handler.gd`), todas `Option<>` salvo `action`:
- `ui/create` — Control desde template O desde cero (`node_type` obligatorio si no viene `template`) + `layout` preset
- `ui/layout` — presets de anchors: `full_rect`, `bottom_center`, `top_left`, `top_right`, `center`, `bottom_left`, `bottom_right`, `center_left`, `center_right`
- `ui/canvas_layer` — CanvasLayer (layer, follow_viewport) para HUD overlay
- `ui/templates` — lista templates con params
- `ui/get_info` — anchors/offsets/size_flags/min_size de un Control
- `ui/theme` — **AL FINAL** de UI-2, tras validar las otras 5 → ✅ hecho: crea/modifica Theme .tres (`colors`, `styleboxes`, `font_sizes`, `constants` con claves `ThemeType/item`) + aplica a Control vía `node_path`

Server Rust: tool `ui` con schema minimal (patrón v4.6 split) + registro en `editor_plugin.gd`. **Enriquecer lecturas**: `node_query/get_info` serializa anchors/offsets/size_flags cuando el nodo es Control; `_node_coords` añade `anchors`/`offsets` para Control (cierra la ceguera de UI).

### Fase UI-3 — Tests + docs — ✅ COMPLETADA (2026-08-14)

- `cargo test` (parity: description no vacía, action en schema) + `cargo clippy --all -- -D warnings` ✅
- Grafo headless + `run_tests.gd` (instanciar cada template sin SCRIPT ERROR) ✅
- README/CONTRIBUTING: documentar tool `ui` + "cómo añadir un template" ✅

### 🔮 Templates FUTUROS para otras tools (mismo patrón híbrido — para futuros agentes)

El registry es transversal; queda listo para templates de cualquier tool. NO hacer todo a código — .tscn + params:
- `resource/create_script` → templates de scripts: `player.gd`, `enemy.gd`, `state_machine.gd`, `inventory.gd`
- `shader` → templates base: `sprite_outline.gdshader`, `dissolve.gdshader`, `water.gdshader`
- `tilemap` → patrones de terreno/cueva
- `animation` → curvas de easing, poses de blend
- `ui` (expansión) → minimap (requiere SubViewport+cámara, más código), hotbar, quest_log, tooltip

**Nota para agentes futuros:** al añadir un template, tocar (1) `.tscn` en `templates/<cat>/`, (2) entrada en `metadata.json`, (3) test de instanciación en `run_tests.gd`. NUNCA generar el árbol con código GDScript a menos que el template requiera lógica runtime (ej: minimap).

---

## 0.3 Plan Detección/Apertura/Debug (D1-D4) — APROBADO por el General (2026-08-15)

> **Origen**: feedback del General tras el E2E: (a) abrir editor es "malón", (b) detección de editor abierto "aún muy pésimo — he tenido situaciones donde no lo detecta", (c) debug tool "sigue siendo una mierda" y debe arreglarse ANTES de los críticos E2E. Diagnóstico con código leído + investigación en línea. Fases D1→D2→D3 (detección primero: D2 depende de D1 para saber si esperar o relanzar), D4 tests+docs.

### 🚨 Causa raíz D1 — wmic ELIMINADO en Windows 11 24H2+
`godot_processes_detailed()` (launcher.rs L331) usa `wmic` — **deprecado desde Windows 10 21H1 y ELIMINADO en Windows 11 24H2+** (Microsoft Support). En máquinas modernas el comando falla silencioso → `procs` vacío → editor no detectado → session/open duplica editor o dice "no editor connected". Parsing CSV además frágil (`splitn(3, ',')` se rompe con comas en CommandLine).

### D1 — Detección de editor: CIM + fallbacks — ✅ COMPLETADA (2026-08-15)
- Reemplazar wmic por **PowerShell `Get-CimInstance Win32_Process`** (reemplazo oficial MS, no deprecado, CommandLine completo) → fallback `tasklist /v /fo csv` → fallback wmic (sistemas viejos).
- A FAVOR CIM: oficial, rápido, CommandLine completo. EN CONTRA: requiere PowerShell (ya en Win10+), output a veces UTF-16.
- A FAVOR tasklist: nativo. EN CONTRA: lento ~1s, CommandLine puede truncarse.
- **Criterio de éxito**: `session/health` detecta editor abierto en Win11 24H2+. ✅ Verificado: CIM detectó el editor vivo del E2E (PID 12284, cmdline completa con `--editor --path`). Output real de PowerShell escapa comillas como `""` → parser CSV robusto (`parse_csv_line`) + `decode_win_output` (UTF-16LE con BOM). 21 tests launcher verdes (8 nuevos D1).

### D2 — session/open espera conexión (fire-and-forget → polling) — ✅ COMPLETADA (2026-08-15)
- `launch_editor()` (launcher.rs L426) hace `cmd.spawn()` y devuelve `launched:true` INMEDIATO; el editor tarda 3-5s en arrancar+conectar → la siguiente tool falla "no editor connected". Y si el editor crashea al cargar, "launched" fue mentira.
- Fix: `session/open` (server.rs L183) espera polling `registry.has_editor` cada 500ms con **timeout 15s**, reportando progreso (`connected`, `connect_wait_ms`). Si no conecta → error con sugerencia `session/diagnose`.
- A FAVOR esperar en server: elimina la carrera, detecta crash al arrancar. EN CONTRA: open tarda hasta 15s si falla. Alternativa descartada (devolver `waiting_for_connection` → agente polling manual, peor UX).

### D3 — Debug tool: 3 problemas concretos
1. **`handle_vars` usa sleep fijo** `await get_tree().create_timer(0.3).timeout` (debug_handlers.gd L124) — si la respuesta tarda más, devuelve vars vacías. Fix: esperar señal real con timeout 2s.
2. **`handle_get_editor_errors` solo captura runtime del juego** — errores del editor en reposo (parse errors, script errors) NO accesibles por API pública. **PERO** `EditorLog` (panel Output, editor_log.h Godot) los captura vía `_error_handler` estático — el plugin ya localiza docks por clase (`_find_class` con EditorDebuggerNode), puede hacer lo mismo con `EditorLog` y leer sus mensajes. Fix: añadir lectura EditorLog + mantener runtime.
3. **`ensure_hooked` con 30 retries × 1s** — si el dock no está montado, debug/status se cuelga 30s. Fix: retries reducidos (10) + lazy (solo cuando se necesita).
- Extra: `handle_output` añadir `source: editor|game` para leer el EditorLog también.

### D4 — Tests + docs
- Tests Rust (CIM parse) + GDScript (EditorLog read) + grafo headless + README/AGENTS.md actualizados.
- **Criterio de éxito**: `cargo test` + `cargo clippy --all -- -D warnings` + grafo headless verdes.

---

## 1. Filosofía de Hierro

- **Global**: PODER (Godot hace todo, cero límites) · EFICIENCIA (cada op óptima, sin huérfanos) · RAPIDEZ (~20ms/op).
- **Tools**: CENTRALIZADAS (pocas, por dominio) · MODULARES (1 tool, N acciones vía `action`) · POTENTES (1 llamada = flujo completo).
- **Derivado**: EditorPlugin REAL (v4), sesión = editor vivo, fail-fast, cache RAM, mutaciones con undo/redo.

---

## 2. Arquitectura (EditorPlugin + Rust)

```
OpenCode —STDIO NDJSON→ HerenServer.exe (Rust/FlojoMCP, WS server local 127.0.0.1:PUERTO) —WS→ HerenEditorPlugin
```

- `editor_plugin.gd` (lifecycle) · `ws_client.gd` (auto-reconnect) · `dispatcher.gd` (rutea tools→handlers, soporta coroutine) · `undo_redo_wrapper.gd` · `scene_registry.gd` · `heren_debugger_plugin.gd` · `handlers/` (scene, node, resource, animation+skeleton, shader, tilemap, project, debug, visual, signal, validate, coords).
- **Flujo**: `session/open` (auto-launch) → `godot_ready` → registra `ConnectedEditors[project_path]` → ops enrutan al editor vivo (~20ms).
- **Eliminados v3**: godot_daemon.py, session_manager.py, heren_daemon.gd, window/server_manager.gd, tscn_serializer.gd (Godot serializa .tscn nativamente al guardar).

---

## 3. Reglas de Oro

1. `session/open` SIEMPRE primero; nunca operar sin sesión; `close` al terminar.
2. Godot hace el trabajo pesado — NUNCA parsear .tscn a mano.
3. Tools centralizadas/modulares/potentes: el agente dice QUÉ, no CÓMO.
4. Cache amigo: 1ª vez disco (~3s), luego RAM (~0ms).
5. Fail-fast: NUNCA silenciar errores ni retornar None sin explicación.
6. LAIKA SOLO pruebas: source vive en `addons/heren/`; cambios → commit SOLO en heren-mcp.

---

## 4. Estructura

```
crates/heren-server/    # server Rust (src/: editor, launcher, registry, server, ws_plugin_server; tests/)
addons/heren/           # FUENTE del plugin (copiable a cualquier proyecto)
scripts/                # heren-build.bat (VsDevCmd+debug+test+release+clippy) · run.bat · install_mcp.py · deploy-fix.bat
fixtures/               # proyectos Godot mínimos para tests (empty_project/)
.temp/ · tests/ · benchmarks/  # tests activos en Rust/GUT; Python v3 archivado en rama archive/v3
```

**Notas post-limpieza (v4.4.3):**
- `src/heren/` quedó vacío y se eliminó. El bridge Python v4 y el daemon v3 viven ahora solo en la rama `archive/v3`.
- `scripts/` es el único lugar para build scripts; la raíz contiene documentación y configuración del workspace Rust.
- `tests/` contiene solo `README.md`; los tests activos son `crates/heren-server/tests/` (Rust) y `addons/heren/tests/` (GUT).
- `benchmarks/` contiene solo `README.md`; los benchmarks Python fueron archivados.

---

## 5. Performance

~20ms/op con editor vivo (v4). Sin daemon (v3 ELIMINADO). 1ª vez disco ~3s, cache hit RAM ~20ms.

---

## 6. Las 17 Tools

| # | Tool | Actions | Dominio |
|---|------|---------|---------|
| 1 | `session` | open, close, list, info, health, **diagnose** | Sesiones |
| 2 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas |
| 3 | `node` | add, instantiate, remove, duplicate, rename, move, set_owner, reorder | Nodos (mutaciones) |
| 3b | `node_query` | get_prop, get_info, get_children, find | Nodos (lecturas) |
| 3c | `node_props` | set_prop, set_props, array_append, array_remove | Nodos (propiedades) |
| 4 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd |
| 5 | `project` | create, setup_plugin, setting (op get/set/list/delete/set_multi + restart_required/applied_runtime), autoload, remove_autoload, input_map (persistencia REAL), shader_global | Configuración |
| 6 | `shader` | create, edit, get, inspect, validate, material, uniform, apply (one-shot) | Shaders |
| 7 | `animation` | create_player, create, add_track, add_key, state_machine, play, stop, seek, speed, get_*, remove_*, update_*, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, tree_*, duplicate, delete, rename, reverse, blend_pose, retarget | Animaciones |
| 8 | `skeleton` | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment, skeleton_get_*, skeleton_set_pose, skeleton_ik, skeleton_fabrik, capture_pose | Esqueletos 2D/3D |
| 9 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps |
| 10 | `debug` | status, breakpoint, control, stack, vars, profiler, run_scene, stop_scene, is_playing, get_editor_errors, **output** | Depuración |
| 11 | `validate` | scene, script, node, resource | Validación |
| 12 | `signal` | connect, disconnect, list, set_script | Señales |
| 13 | `orchestrate` | batch multi-op (plan_file evita dicts anidados) | Batch |
| 14 | `visual_text` | coords, summary, ascii (NIVEL 0-1, sin imagen, barato) | Visión textual |
| 14b | `visual_image` | capture, node (NIVEL 2-3, image_content base64) | Visión imagen |
| 14c | `ui` | create, layout, canvas_layer, templates, get_info, **theme** | UI 2D (v4.7): Control desde template o desde cero + presets anchors + CanvasLayer + lista templates + info Control + Theme .tres |
| 15 | `health` | server + editor status | Health |
| 16 | `help` | introspect (lista tools + description + parameters por tool) | Ayuda/introspect |

**Notas:** `node/instantiate` = instancia EXTERNA (`instance=ExtResource`, no copia inline) **o template del registry transversal** (`template:"health_bar"`, params via `properties`). `coords proactivas` en toda mutación (§7). `animation`+`skeleton` comparten `animation_handlers.gd`. `session/diagnose` = integridad plugin (ok/stale/missing/orphan) + grafo headless en sandbox + estado editor. **v4.6 split de tools**: `node_query`/`node_props`/`visual_text`/`visual_image` = schemas MINIMALES (el server mapea al mismo handler interno `node/*`/`visual/*`). **v4.7 UI**: tool `ui` (handler `ui_handlers.gd`) + sistema transversal de templates (`template_registry.gd`, patrón `coords.gd`; templates .tscn + params por nombre de nodo canónico). Errores `node_not_found` incluyen `parent_children` (orientación). `rename`/`move` devuelven `previous_path`/`old_parent`. Recursos: pasar PATH string (`res://...`) para ext_resource; dict inline SIN path → warning `resource_incrusted_inline` (se incrustará al guardar).
**Comparativa competidores** (README "Frente a otros MCPs"): datos VERIFICADOS de `.competitors/`. NUNCA marcar ❌ capacidad que el competidor SÍ tiene; usar sus propios análisis (gopeak `ANALYSIS.md`); re-verificar contra repos al actualizar.

---

## 7. Sistema de Coordenadas (ADR-005) + Visión

### Coordenadas unificadas
Auto-detección por keys: `x`+`y`→Vector2; `x`+`y`+`z`→Vector3; `r`+`g`+`b`→Color; `origin`+`x_axis`+`y_axis`→Transform2D; `origin`+`basis`→Transform3D; `normal`+`d`→Plane; `position`+`size`→Rect2/AABB. Expansión v4: Vector2i/3i, Quaternion, StringName. `deserialize_resource` instancia por ClassDB. **Proactivas en mutaciones**: `position`, `global_position`, `bbox`, `parent_path`.

### Visión — jerarquía de costo (la clave)
```
NIVEL 0: Coords textuales (siempre, proactivo)    ~20-100 tok
NIVEL 1: summary + ascii (sin imagen)             ~50-150 tok
NIVEL 2: capture low-res                          ~200-400 tok
NIVEL 3: capture full + node (framing)            ~800+ tok
```
**Regla de oro:** NIVEL 0 primero; imagen solo cuando el texto no basta.

| action | Costo | Qué devuelve |
|--------|-------|--------------|
| `coords` | ~20-100 tok | Mapa de coordenadas textual |
| `summary` | ~50 tok | Contador por tipo, bbox total, dirty flags |
| `ascii` | ~150 tok | Árbol ASCII |
| `capture` | alto | `Image` base64 MCP (`source:"scene"` default off-screen \| `"viewport"` fallback auto si 2×2) + metadatos |
| `node` | alto | Image + bbox/pos del nodo |
| `budget`/`cache` | ~30 tok | Presupuesto / cache de visión |

**Formato captura:** `{"image": <base64 PNG — image_content MCP, NO path>, "metadata": {tokens_estimate, resolution, viewport, scene_hash, cached, node_count, selected}}`.

**Implementación:** `_render_scene_offscreen()` clona el root sin scripts en SubViewport dedicado (UPDATE_ALWAYS, own_world_3d + Environment en 3D, transparent 2D), replica framing de cámara del editor, `await` 2×`RenderingServer.frame_post_draw`. NUNCA `get_editor_viewport().get_texture().get_image()` (2×2 placeholder). Dispatcher completa `GDScriptFunctionState` (`get_class()`, NO `is`). Push `selection_changed` con rate-limit 1/s. Detalle: §10 Visual.

---

## 8. Sesiones

**Sesión = editor vivo conectado (RAM del server).** No es session.json, no es daemon.

```
ConnectedEditors: {project_path → WS}. Editor arranca→conecta→godot_ready→registra→ops enrutan (~20ms).
Sin editor vivo: lanzar Godot una vez (3-5s) o avisar. Cierre → des-registra.
Multi-proyecto por project_path. Auto-lanzamiento: last_project (disco).
```

`.heren/session.json` → SOLO `last_project` (1 clave). NO se persiste: presupuesto visión/preferencias (efímero RAM), open_scenes/selected_nodes (bajo demanda al editor).

---

## 9. Animación (Fases 1-4 + P1-P3 ✅ IMPLEMENTADAS)

Playback+inspección · edición+one_shot · avanzado (blend spaces 1D/2D, tween, pose/ik) · innovación (record, from_path, loop_pose, preview con imagen, curve) · capture_pose en cadena (bones/chain/from_bone+depth) · bone tracks por nombre (3D `bones/<idx>/pose`, 2D Bone2D rotation/position) · tree_travel/params/activate · FABRIK 2D con pesos · IK3D (target_position, magnet, influence) · gestión (duplicate/delete/rename/reverse) · blend_pose · retarget por nombre de hueso (rigs compatibles).

**Coordenadas enriquecidas** en `node_handlers._node_coords()`: size, height, scale, rotation (grados+rad), z_index, visible, aabb.

> ⚠️ API 4.7: `AnimationNodeBlendSpace3D` NO existe (solo 1D/2D). `SkeletonIK3D.target_node` = NodePath, `magnet` = Vector3 (NO `target` heredado). `AnimationNodeBlendTree.connect_node(input, input_index, output)` = 3 args.
> ⚠️ E2E 2026-08-15: `track_type` real = `value`/`position_3d`/`rotation_3d`/`scale_3d`/`method`/`bezier`/`audio` (NO `rotation`/`transform`). `rotation_3d` exige Quaternion `{x,y,z,w}` NORMALIZADO (norma=1) — Vector3 falla silencioso (`key_idx:-1`) y Quaternion sin normalizar da warning Godot. `create_player` crea SIEMPRE en root (ignora `player_path`). Ver §0.1 P2/P3/P4/P11.

---

## 10. Decisiones (fusiona ADR + bugs, las que importan)

| Tema | Decisión / Lección |
|------|--------------------|
| **Arquitectura** | EditorPlugin > GodotDaemon (daemon corre is_editor_hint=false → nunca toca el editor real; plugin gana undo/redo, viewports, EFS, breakpoints). WS plugin=cliente (patrón gopeak: editor NO depende del server, push de eventos). Sesión = editor vivo RAM + last_project disco. FlojoMCP > FastMCP (schemas compile-time; introspection runtime → vacíos). |
| **Protocolo** | NDJSON, NO Content-Length (OpenCode 1.18, verificado con stdin-spy; `flojo_run_stdio_cl` = timeout). Schemas booleanos `true` → `{}` (schemars rompía tools). `args()` omite keys None (`str(null)`="<null>" rompía guards). id JSON-RPC tolera `1`/`"1"`/`"1.0"`. |
| **Multi-instancia** | ❌ `kill_previous_servers()` ELIMINADO — mataba servers de sesiones OpenCode hermanas (`MCP connection closed` + agentes sin tools). `ws_port()` cachea con OnceLock + busca `9099+N` libre → 1 puerto por instancia. E2E: 2 servers simultáneos viven en 9100/9101. |
| **plugin.cfg** | Formato Godot 4: `enabled=PackedStringArray("res://addons/heren/plugin.cfg")` (path completo, verificado contra `editor_node.cpp`). `"heren"` desnudo se acepta al leer pero se re-escribe completo; `PackedStringArray()` vacío = lost-update (editor vivo pisa el enable). |
| **enable idempotente** | Reemplaza CUALQUIER `enabled=` por la canónica; solo escribe si difiere + verifica. Contrato `Result<bool,String>`: Ok(true)=escribió, **Ok(false)=ya canónico = ÉXITO** (antes false → "failed" → nunca lanzaba = misterio "heren"), Err=fallo real. |
| **Sync plugin** | Incremental por contenido: solo diffs, borra huérfanos (.uid), reporta COPY FAILURES (nunca `is_ok()` silencioso). **🚨 BUG RAÍZ**: `collect_files` perdía el prefijo `handlers/` → copy contra ruta inexistente → NotFound tragado → "plugin up-to-date" MENTIRA → core nuevo + handlers viejos → SCRIPT ERROR `set_debugger_plugin` → crash. Fix: `walk(root, dir)` con root original. |
| **launch_editor** | Mata zombie PRIMERO → sleep → escribe plugin+enable → relanza (nadie pisa project.godot). No relanza si no hace falta: `reuse up-to-date` / `plugin_changed=true` → agente decide `session/reopen`. Plugin se habilita UNA vez. Godot NO tiene hot-reload de plugins (#11612). |
| **Detección editor** | `godot_processes_for`: acepta `--editor`, `--path` **o `project.godot`** en cmdline (doble clic); normaliza backslashes→`/` (`d:\...` vs `d:/...` — cmdlines reales de Windows). wmic `/format:csv`: `parts[1]=CommandLine, parts[2]=PID` (estaban invertidos → siempre vacío → editor duplicado). |
| **Versiones** | Plugin manda `plugin_version` en godot_ready (la que CORRE, no disco). `session/info` → source/installed/editor + `plugin_stale` + remedy; `session/health` → `stale_editors[]`. Reopen recarga código nuevo. |
| **Contexto escena (S3)** | `apply_scene_context` (server, por proyecto) + `_scene_root(args)`: el agente fija scene_path UNA vez. Prioridad resuelve: **pestaña real → registry → disco** (RAM=caché, disco=fuente; antes el fantasma en RAM ganaba). `normalize_scene_path` SIEMPRE (`res://`, forward, sin trailing; 8 tools + plugin defensivo). |
| **SceneRegistry (S6)** | `scene_path → root` en RAM = fuente del flujo MCP. `scene/save` = pack directo + `ensure_owner_recursive` + ResourceSaver (NUNCA `save_scene()` de pestaña). `create` abre pestaña; si falla, árbol vivo en registry (fantasma = diseño). `ensure_owner_recursive` NO baja en `scene_file_path != ""` (instancia externa). `handle_save` acepta `output_path` alias. |
| **Persistencia** | Dirty set por proyecto (mutaciones marcan; lecturas no; scene/save limpia; session/info expone). Flush-before-destroy: open de dirty → save previo; close → flush todas. Cierre inesperado = error SOLO si dirty>0 (0 = benigno). `session/reopen` = reinicio deliberado (flush + graceful_close ANTES del kill + clear flag). ~0ms por mutación. |
| **Visual off-screen** | `get_editor_viewport().get_texture().get_image()` = placeholder 2×2 → `_render_scene_offscreen()`: clona root sin scripts en SubViewport (UPDATE_ALWAYS, own_world_3d+Environment BG_COLOR 3D, transparent 2D), framing de la cámara del editor, 2×`frame_post_draw`. `source:"scene"` (default) \| `"viewport"` (fallback auto si 2×2). Dispatcher completa GDScriptFunctionState (`get_class()`, NO `is`). |
| **Shader** | 🚨 `Shader.get_errors()` NO EXISTE en 4.7 (`has_method=false`; `var x := sh.get_errors()` = "Cannot infer" = Parse Error → TODO el plugin muerto). Fix: `_shader_structural_issues()` + heurística uniforms (declara pero lista vacía = error). `sh.get_mode()` no `.mode`. **Lección: validar APIs con `has_method()`.** |
| **Resources** | Sub-recursos inline viajan COMPLETOS (`{"__type":"Resource", resource_class, props}` con filtro STORAGE) — StyleBoxFlat/Curve/Gradient en Theme sobreviven round-trip. Strings `res://`/`user://` → string plano (nunca deserializar: UID sintético corrompía project.godot). |
| **Política UIDs (E5)** | **NO se versionan `.uid`** (`.gitignore: *.uid`). Godot los genera al importar; versionarlos corrompe referencias cross-project (el plugin se copia a proyectos ajenos con sus propios UIDs). El plugin usa paths `res://` estables, no UIDs. |
| **project** | `create` sin editor (escribe project.godot directo — evita circular dependency). `setting` con `op` + `restart_required` (prefijos read-at-startup) / `applied_runtime` (viewport, max_fps). `input_map` persistencia REAL: `ProjectSettings.set_setting("input/<action>", {deadzone, events})` — InputMap/ProjectSettings.save() solo RAM. |
| **Skeleton** | 🚨 Skeleton2D NO tiene find_bone/set_bone_rest (API falsa): huesos = Bone2D hijos `.rest=Transform2D`. `BoneAttachment2D` NO existe (Node2D hijo — Parse Error rompía el plugin). `set_bone_weights(find_bone(), PackedFloat32Array)` (índice, no nombre). IK 2D = FABRIK propio (Godot no tiene nativo). |
| **Handlers** | `signal/list` defensivo (conn as Dictionary, `.get()`, key `"signal"`). `material.resource_name` (Resource NO tiene `.name`). `_ensure_parent_dir()` antes de escribir. `undo_redo add_do_method` con `callv` (expande Array). Escribir .gd/.tscn/.godot sin BOM (`UTF8Encoding($false)`). |
| **diagnose (v4.4.2)** | `session/diagnose`: integrity (ok/stale/missing/orphan por archivo, tamaños) + graph (copia addons/heren a sandbox `%TEMP%/heren_graph_check_<pid>`, `godot --headless --editor --quit-after 3`, captura SCRIPT ERROR/Parse Error, limpia SIEMPRE) + editor (procesos con cmdline, WS, puerto). Detecta lo que `--check-only` individual NO ve. Verificado: diagnosticó el crash real sin tocar el proyecto. |
| **debug output (v4.5)** | 🚨 `EditorDebuggerPlugin._capture` SOLO recibe mensajes con `:` (sed.cpp `plugins_capture`: `colon_index < 1` = invalid) — los mensajes `error`/`output`/`stack_dump` NUNCA llegan al plugin. El camino real: signal `debug_data` del `ScriptEditorDebugger` (emite TODOS los mensajes ANTES del handler integrado, sed.cpp `_parse_message`). Hook one-shot por árbol fallaba silencioso si el dock no estaba montado → 0 errores. Fix: reintentos 30×1s + conecta a TODOS los ScriptEditorDebugger del TabContainer (multi-sesión). El texto `E hh:mm:ss:mmm ...` del panel Output = mensaje `output` con `MESSAGE_TYPE_ERROR=2` (sed.cpp:590) → expuesto como `debug/get_editor_errors → output_errors` y `debug/output` (filter=error\|all). Formato `error` estructurado = OutputError marshall [hr,min,sec,msec,file,func,line,error,descr,warning,stack*3] verificado en debugger_marshalls.cpp 4.7. |
| **v4.6 split tools (2026-08-08)** | El patrón "1 tool N acciones" con schema plano de 15 params hacía el MCP un laberinto: el agente adivinaba qué args aplicaban a qué action → `-32602 required` absurdos (visual exigía `clear`/`viewport` en `summary`) → prefería el .tscn a mano. Fix: (a) **todos los args `Option<>`** con defaults en el plugin (nada required salvo `action`); (b) **split**: `visual` → `visual_text` (coords/summary/ascii, schema 3 args) + `visual_image` (capture/node, 6 args); `node` → `node` (mutaciones) + `node_query` (lecturas) + `node_props` (props); `budget`/`cache` eliminados (handlers inexistentes). El server mapea al MISMO handler interno (`node/get_info` sigue existiendo) → el plugin NO cambió. (c) **Orientación continua**: errores `node_not_found` incluyen `parent_children[]` del padre resoluble más cercano; `rename`/`move` devuelven `previous_path`/`old_parent`. (d) **Anti-incrustado**: recursos inline sin resource_path → warning `resource_incrusted_inline` en add/set_prop (nunca fallo silencioso; el agente pasa `res://...` para ext_resource). Regla de oro: recursos SIEMPRE por PATH. |
| **Fase F tipos semánticos (2026-08-14)** | `Option<serde_json::Value>` genera schema vacío `{}` sin descripción → clientes MCP (OpenCode, APIs de modelos) no pueden validar ni guiar al usuario. Fix: FlojoMCP añade `types.rs` con wrappers semánticos (`GodotVariant`, `GodotDict`, `Vector2`, `Color`, etc.) con `#[schemars(description = "...")]`. heren-mcp migra 42 propiedades `Option<Value>` → `Option<GodotDict>`/`Option<GodotVariant>` + conversiones `.map(Into::into)`. Resultado: de 42 propiedades vacías a 0 vacías; schemas ahora incluyen `definitions` con descripciones claras. Verificado con `tools/list`: todas las propiedades tienen `$ref` a definiciones descriptivas. |

---

## 11. Bugs Arreglados (históricos, v3→v4.1)

| Bug | Fix |
|-----|-----|
| Persistencia sub-recursos / señales | `resource_local_to_scene=true` + `_setup_resource_local_to_scene_recursive()` / `_collect_connections()` + `_inject_into_tscn()` |
| Sub-resource ID corrupción en save | Eliminar inyección — `pack()`+`FLAG_BUNDLE_RESOURCES` lo maneja (solo connections se inyectan) |
| Parse error: palabras reservadas / función anidada | `signal`→`sig`, `match`→`is_match` / búsqueda iterativa con pila |
| wmic CSV índices invertidos | `parts[1]=CommandLine, parts[2]=PID` (duplicaba editor abierto) |
| `var errors := sh.get_errors()` rompía TODO el plugin | Tipo explícito `PackedStringArray`; SIEMPRE validar grafo completo headless |
| `resource` con dir inexistente → write_failed | `_ensure_parent_dir()` (make_dir_recursive) |
| `scene create` con scene_path ignorado | scene_path explícito → SIEMPRE crea archivo |
| `scene save` éxito falso (guardaba pestaña activa) | pack+save del root pedido (§10 SceneRegistry) |
| `orchestrate` "Unknown error" | ⚠️ **REGRESIÓN E2E 2026-08-15**: sigue fallando (P1). El fix previo (tool:"node/add" normalizado) NO funciona en la práctica. Ver §0.1. |
| Deadlock stderr sin drenar | tracing SOLO a `HEREN_LOG_FILE`, nunca stderr |
| Build MSVC | `heren-build.bat` carga VsDevCmd del BuildTools 2022 |
| Macro FlojoMCP visibilidad | `#[flojo_mcp]` usaba `item.vis` (no hardcode) |
| deserialize_value no recorría Array | Rama `elif value is Array` recursiva |
| project.godot corrupto (BOM) | `WriteAllText(..., UTF8Encoding($false))` |
| Undo/redo node/add devolvía path vacío | `callv(&"add_do_method", [obj, method] + args)` |

---

## 12. Gotchas y Lecciones

- **Tools MCP se cargan al INICIO de la sesión** → tras recompilar el server, SESIÓN NUEVA (toolset no refresca en conversación en curso). E2E: la tool `ui` no existía en el server en ejecución (binario viejo).
- **Un parse error en un handler rompe TODO el plugin** → editor no conecta sin error visible. Validar: `--check-only --script` + **grafo completo** `godot --headless --editor --path <proj> --quit-after 3` grep `SCRIPT ERROR|Parse Error` (—check-only NO detecta `:=` "Cannot infer"; preferir tipos explícitos).
- **Handlers source NO se sincronizan solos con E2E** (`.temp/e2e_complex/...`) → copiar manual tras cada cambio.
- **`String.split()` devuelve `PackedStringArray`** (sin `pop_back`) → tipar `var segments: Array`. **`NodePath` no tiene `begins_with`/`trim_prefix`** → `str(path)` primero.
- **`Copy-Item -Recurse` anida contenido si el destino existe** → `Remove-Item` antes de copiar el plugin al fixture.
- Config MCP OpenCode: clave `environment` (NO `env`); existe `"timeout"` (ms, default 5000).
- Godot headless compite por .godot lock → editor cerrado o copia.
- NO definir `func get_editor()` en EditorPlugin (colisiona) → `get_editor_interface()`.
- `add_do_method` Godot 4.6: `(Object, StringName, args)` — NO Callable directo.
- resource_handlers sin undo/redo (archivos externos, `EditorFileSystem.update_file()`). `delete` usa DirAccess (ResourceLoader no borra).
- Consola Windows cp1252 → nada de emojis en output Python (`UnicodeEncodeError`); forzar UTF-8.

---

## 13. Checklist

- [x] ¿Plan de limpieza §0.1 completado hasta Fase E? ¿Fase A verde antes de tocar C? (§0.1 eliminado — historial en CHANGELOG)
- [x] P1 orchestrate: verified (method resolution ordered in dispatcher.gd)
- [x] P2 create_player: verified (player_path respected as parent)
- [ ] P3+P11 add_key: Quaternion works (direct only), Vector3→Quaternion not supported (Godot track_insert_key rejects auto-conversion); handler now returns clear error instead of "Unknown error" silent fail
- [ ] D1-D4: D1 ✅ CIM detección, D2 ✅ open espera conexión, D3 ✅ handle_vars timeout + handle_get_editor_errors EditorLog + ensure_hooked retries 10, pendiente tests+docs D4
- [ ] P4 track_type: documented in handler code (value/position_3d/rotation_3d/scale_3d/method/bezier/audio)
- [ ] P5 resource/create: verbose flag pending (return only changed props default)
- [ ] P6 visual/summary: M2 fixed + counting recursivo implementado
- [ ] P7 resource_incrusted_inline: soporte added en resource handlers (warning en lugar de fallo silencioso)
- [ ] P8 tool ui: implementado v4.7 (6 acciones + templates + theme)
- [ ] P9 parent_path normalization: fixed - now returns root name instead of "."
- [ ] P10 animation/get_animation: pending implementar acción get_animation específica

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
