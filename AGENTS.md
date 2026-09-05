# 🐉 Heren MCP — AGENTS.md

> Biblia del agente. Léelo antes de tocar código.
>
> **ESTADO: v4.9** — EditorPlugin (GDScript→EditorInterface) + heren-server.exe Rust/FlojoMCP.
> 18 tools centralizadas, WS plugin server (patrón gopeak), auto-launch, NDJSON por stdio.
> Workspace Rust local (`crates/heren-server`); FlojoMCP = framework SOLO (flojo-mcp/macros/session @ crates.io, consumido por version, no path).
> Bridge Python y daemon v3 **archivados en rama `archive/v3`**. **Cambios nuevos → v4/Rust.**
> Plugin SIEMPRE ENCENDIDO + sync incremental por contenido + `session/diagnose` (debugger unificado).
> **Limpieza 2026-08-10→14**: Fases A-F + UI-1/2/3 COMPLETADAS (historial en CHANGELOG.md). Plan de limpieza por fases eliminado (todo [x]).
> **E2E 2026-08-15**: escena compleja real → 11 problemas encontrados → **§0.1 Plan de Mejoría E2E** (P1-P11).
> **Detección/Apertura/Debug 2026-08-15**: feedback General → **§0.3 Plan D1-D4** (wmic eliminado en Win11 24H2+, open fire-and-forget, debug con sleep fijo).
> **Performance 2026-09-03**: auditoría completa → 5 fixes (ws_client Timer, scene_registry mtime cache, template_registry mtime check, visual_handlers SubViewport pool, server discovery `.heren/server_port.json`). Fix raíz: editor reconecta automáticamente al server correcto cuando OpenCode reinicia.

---

## 0. 🚨 Pendientes

### Bugs conocidos (pre-E2E)
- **M1** `node/array_remove`: borra el primer elemento, no el `value` (int vs float en `find`). Fix: tipar/normalizar.
- **M2** `visual/summary`: `node_count:0` inconsistente (by_type OK). Handler cuenta mal.
- **M3** `validate/node`: `script_cannot_instantiate` — scripts MCP no se compilan. Falta re-import/scan.
- **Visual**: `coords` incompleto (3 nodos, paths ".."). `budget`/`cache` ELIMINADOS del toolset (v4.6) — handlers inexistentes; re-implementar si se necesita presupuesto.
- **Gaps tool**: `node_query` no expone `by` (find por tipo) ni `owner_path`/`script` en get_info; `resource` exige requireds irrelevantes en create_script/edit_script (hacerlos opcionales).

### 🔴 Críticos del E2E (2026-08-15) — ver §0.1
- **P1** `orchestrate` roto (Unknown error en TODAS las ops) — el batch es inútil. **[FIXED: método resolución ordenado en dispatcher.gd; verificado con sesión nueva]**
- **P2** `create_player` ignora `player_path` (crea en ROOT). **[FIXED: player_path respetado como parent; AnimationPlayer creado en nodo pedido]**
- **P3** `add_key` fallo SILENCIOSO con `rotation_3d` + Vector3 (`key_idx:-1`, `keys:0`, devuelve `ok:true` (Godot espera Quaternion)). **[FIXED: handler valida track type y normaliza Quaternion; Quaternion directo funciona. Vector3→Quaternion auto-conversión: pending debug - error "Unknown error" en pipeline Godot]**
- **P11** `add_key` inserta Quaternion NO normalizado → warning Godot. **[FIXED: handler normaliza Quaternion antes de track_insert_key; verificado con Quaternion {"x":1,"y":0,"z":0,"w":0} y key_idx:0]**

### ✅ Completado (historial en CHANGELOG.md)
- **Fases A-F** (2026-08-10→14): limpieza repo, poda v3, refactor handlers, tests+CI, UX/contribución, tipos semánticos. 51 tests Rust + 10 GDScript verdes.
- **Fase UI v1** (2026-08-14): sistema transversal de templates (6 .tscn 2D + `template_registry.gd`) + tool `ui` (6 acciones) + docs v4.7. Detalle §0.2.

### 🐛 Bugs reportados por desarrollador (2026-08-15) — ver §0.4

| # | Problema | Estado | Fix |
|---|----------|--------|-----|
| **BUG 1** | `node/add` con `instance_path` no instancia la escena (crea Node vacío) | ✅ FIXED | `handle_add` delega a `handle_instantiate` cuando viene `instance_path` |
| **BUG 2** | Registro en memoria "stale" de escenas: open/run_scene usan copia vieja | ✅ FIXED | `scene_registry` trackea mtime; invalida cache si disco cambió |
| **BUG 3** | Serialización altera valores de Color (bg_color rojizo → azulado) | ✅ FIXED | `deserialize_value` ahora parsea strings JSON antes de procesar |
| **BUG 4** | `scene/unload` no existe (tool method not found) | ✅ FIXED | Implementado `handle_unload` en scene_handlers.gd |
| **BUG 5** | `set_prop` serializa recursos como vacíos (Shader sin código) | 🔴 NO REPRODUCIDO | No se pudo reproducir; ver §0.4 para detalles de investigación |

---

## 0.4 Bugs reportados por desarrollador (2026-08-15)

> **Origen**: Reporte de desarrollador tras usar el MCP en proyecto real. 5 bugs encontrados (1 crítico, 2 altos, 1 medio, 1 bajo).

### BUG 1 — godot_node add con instance_path NO instancia la escena (CRÍTICO) ✅ FIXED
- **Síntoma**: crea un Node genérico vacío en vez de la instancia del PackedScene
- **Causa**: `handle_add` ignoraba `instance_path`; solo `handle_instantiate` lo manejaba
- **Fix**: `handle_add` ahora delega a `handle_instantiate` cuando viene `instance_path`
- **Verificación**: escena `test_bug1.tscn` con instancia de `child_scene.tscn` → `instance=ExtResource("1_nlyki")` ✓

### BUG 2 — Registro en memoria "stale" de escenas ✅ FIXED
- **Síntoma**: open/run_scene usan copia vieja tras editar .tscn a mano; reopen pisa ediciones manuales
- **Causa**: `scene_registry` no detectaba cambios en disco (sin mtime check)
- **Fix**: `_mtimes` dict trackea mtime al registrar; `get_root` invalida cache si disco cambió; `update_mtime` tras save
- **Verificación**: editar .tscn a mano → siguiente open recarga desde disco ✓

### BUG 3 — Serialización altera valores de Color ✅ FIXED
- **Síntoma**: bg_color = Color(0.1, 0.06, 0.05, 1) → guardado como Color(0.009, 0.003, 0.069, 1)
- **Causa raíz**: `GodotVariant` serializa dicts anidados como strings JSON cuando se envían por WebSocket. El plugin recibe `value` como `String` type, no `Dictionary`. `deserialize_value` no parseaba strings JSON.
- **Fix**: `deserialize_value` ahora verifica si el valor es `String` y lo parsea con `JSON.parse_string` antes de procesar. Esto asegura que Color, Vector y otros tipos complejos se deserialicen correctamente.
- **Verificación**: `set_prop` con Color(0.1, 0.06, 0.05, 1) ahora setea modulate a los valores exactos en vez de Color(0, 0, 0, 1) ✓

### BUG 4 — godot_scene unload no existe ✅ FIXED
- **Síntoma**: `scene/unload` → tool method not found
- **Causa**: handler no implementado
- **Fix**: `handle_unload` en scene_handlers.gd; quita del registry (Godot no tiene API pública para cerrar pestaña)
- **Verificación**: `scene/unload` ejecuta sin error ✓

### BUG 5 — set_prop serializa recursos como vacíos 🔴 NO REPRODUCIDO
- **Síntoma reportado**: Shader → `[sub_resource type="Shader"]` sin código ni path; Theme → colores negros
- **Investigación**: Se probaron múltiples casos:
  1. Shader standalone (.gdshader) → código se serializa correctamente ✓
  2. ShaderMaterial con Shader por path → Shader se referencia correctamente ✓
  3. ShaderMaterial con Shader inline → código se serializa correctamente ✓
- **Conclusión**: No se pudo reproducir el problema. Podría ser:
  - Problema de timing donde el Shader no se carga completamente antes de serializar
  - Problema específico de ciertas versiones de Godot
  - Problema con Shaders cargados desde archivos externos sin PROPERTY_USAGE_STORAGE
- **Nota**: La serialización de recursos usa `PROPERTY_USAGE_STORAGE` filter, que debería incluir `code` en Shader. Si el problema persiste, se necesita más información del entorno del desarrollador.

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
- **D3-s (2026-08-15)**: **`debug/summary` implementado** — snapshot completo en 1 llamada (editor + plugin + game + errors + breakpoints + profiler + console). 🚨 Al implementarlo se descubrieron 3 propiedades INEXISTENTES del debugger plugin que causaban "Unknown error" silencioso: `get_session(i)` → usar `first_session()` (handle_status), `has_frame_vars` → usar `vars_pending` + `last_vars` (handle_vars), `breaked_session_id` → no existe (eliminado). Verificado: summary + status + vars funcionan.

### D4 — Tests + docs
- Tests Rust (CIM parse) + GDScript (EditorLog read) + grafo headless + README/AGENTS.md actualizados.
- **Criterio de éxito**: `cargo test` + `cargo clippy --all -- -D warnings` + grafo headless verdes.

---

## 0.5 Plan Sesiones Estables — Agente Visible con Lock (S + R + U'' + T) — APROBADO (2026-08-22)

> **Origen**: feedback General — sesiones inestables para agentes (desconexión editor↔agente), usuario bloqueado mientras agente trabaja, serialización ultra-anidada frágil. Investigación en línea confirmó: **dos editores SÍ pueden abrir el mismo `project_path`** (foro 3269: dos editores abiertos provocan solo spam "files newer on disk", no lock duro; docs 4.4: `--headless --editor` es oficial). Clon de 300MB descartado por tamaño. Solución: **segundo editor VISIBLE del agente, mismo proyecto, sin clon, con lock por escena y avisos.**

### S — Sesiones con Rol (base, bloquea U'' y T) — 🔨 EN CURSO
- **S1. Registry con rol**: `ConnectedEditors: {(project_path, role) → WS}` donde `role = "user" | "agent:<id>"`. Hoy es `HashMap<project_path, WS>` → colisiona con 2 editores mismo path. `godot_ready` ahora manda `role` (plugin detecta `--heren-agent=<id>` en `OS.get_cmdline_user_args()`).
- **S2. Launcher agente visible**: `launcher.rs:launch_agent_editor(project_path, agent_id)` → `godot --editor --path <proj> -- --heren-agent=<id> --heren-port=<port>` **sin** `--headless` (ventana visible para que el usuario vea el progreso). Puerto dinámico `ws_port()` ya existe (OnceLock + 9099+N).
- **S3. `session/status` + `session/open {mode, visibility}`**: `status` devuelve `state + role + locks + dirty + progress`. `open {mode:"isolated"|"attached", visibility:"visible"|"headless"}` — `isolated` (default agente) va al editor agente; `attached` va al editor usuario con `acquire` advisory.
- **S4. Routing por rol**: server rutea `scene/*`, `node/*` etc al WS del rol que hizo `open`. `session/list` muestra `user:9100 + agent:<id>:9101`.
- **Criterio**: `session/status` lista ambos roles, `session/open` agente no roba foco del usuario, `cargo test` registry con 2 roles verde.

### R — Codec Robusto (independiente, bloquea T)
- **R1. Fin doble encoding**: Rust `GodotVariant` → WS como `Value` nativo (un solo `JSON.stringify`), GDScript recibe `Dictionary` directo (hoy viaja como `String` JSON → `JSON.parse_string` parche BUG3).
- **R2. `VariantCodec.gd`**: walker recursivo `PackedStringArray/Float32Array/Vector2Array/ColorArray`, `TypedArray`, `Resource` (`__type`+`resource_class`+`props`), `Color/Vector2/3/Quaternion/Transform2D/3D/Plane/Rect2/AABB`. Valida `type/hint` antes de `set()` → `type_mismatch` claro.
- **R3. Tests round-trip fuzz**: 3 niveles `Dictionary{ "a": [Color, Vector3, {"__type":"Resource"}] }` → serialize→deserialize→serialize idempotente.
- **Criterio**: `set_prop` con `Array[Color]` 3 niveles sin `resource_incrusted_inline` ni `Color(0,0,0)`.

### U'' — Agente Visible con Lock + Avisos (depende de S)
- **U1. Lock por escena**: `scene_registry` crea `.heren/locks/<Scene>.tscn.lock` `{agent, scene, progress:"12 nodos", pid, since}` al `scene/open` o `node/add` del agente. `session/commit` lo borra.
- **U2. Avisos en editor usuario**: `editor_plugin.gd:_on_scene_changed` checka `.heren/locks` → `EditorToaster.push_toast("⚠️ Agente editando Main.tscn — 12 nodos")` + banner FileSystemDock. `scene/open` usuario sobre escena con lock → `warning: scene_locked_by_agent` (abre solo-lectura si no `force:true`). `node_props/set_prop` sobre archivo con lock → `conflict`.
- **U3. Mensajes automatizados**: cada mutación agente emite `heren/progress` por WS → HerenServer → `notifications/progress` a OpenCode + `push_toast` en ventana usuario (agrupado 500ms): "🤖 Heren: añadió Enemy_3 en (120,40)".
- **U4. Commit atómico**: durante trabajo agente, `scene_registry` solo marca `dirty` en RAM; `ResourceSaver.save()` solo en `session/commit` → **1 escritura a disco = 1 prompt `files newer on disk`** (o 0 con `Auto Reload Scripts on External Change` activado, fix Issue #66644).
- **Criterio**: usuario mueve Node3D en su ventana mientras agente crea 20 nodos en la suya → 0 parpadeo, `status` muestra ambos roles, `commit` recarga en <100ms.

### T — Tools `.tres` Completas (depende de R)
- **T1. `resource/move {from, to}`**: `DirAccess.rename()` + `EditorFileSystem.update_file()` + scan `*.tscn/*.tres/*.gd` que referencian `from` y re-escribe `ExtResource` (hoy deja refs rotas).
- **T2. `resource/duplicate`, `resource/reimport`, `resource/deps {path}`** (quién usa este .tres).
- **T3. `resource/update` robusto** con `VariantCodec` para `Array[StyleBoxFlat]` anidado.
- **Criterio**: `move old.tres → new.tres` actualiza 3 `.tscn` sin huérfano, `cargo test` deps verde.

**Orden**: S → R → U'' → T. Cada fase cierra con `heren-build.bat` (VsDevCmd+debug+test+clippy) + grafo headless `grep SCRIPT ERROR` 0. **Clon descartado**: dos editores mismo `project_path` ya es posible sin lock; clon de 300MB tardaría 2-4s y duplicaría `.godot/import`.

---

## 0.6 Plan Scene Tool con Planning/Orchestration (2026-08-22) — APROBADO

> **Origen**: Feedback del General — el agente no sabe cuándo usar tools low-level, coordenadas rotas, contexto perdido entre calls, conflictos user/agent. Solución: **mismo patrón que `session`** — `scene/open` lockea + da contexto → `scene/plan` diseña → `scene/orchestrate` ejecuta batch → `scene/validate` QA → `scene/commit` guarda + libera lock. Inspirado en **Multi-Agent-CAD (MAC)**: structured state passing (CADBrief → ArchitectPlan → Coder → QA), deterministic translator, typed error routing.

### Flujo Natural (el agente ya lo intuye)

```
1. scene/open {scene_path: "res://complex_test.tscn", mode: "isolated"}
   → devuelve: {lock_id, scene_context: {nodes: [...], resources: [...], scripts: [...], bbox: ..., plan_schema: {...}}}

2. scene/plan {plan: {steps: [...], verification: [...]}}  
   → agente escribe plan CON CONTEXTO (sabe qué nodos existen, qué recursos hay)

3. scene/orchestrate
   → ejecuta batch interno (node/add, node_props/set_props, resource/create, signal/connect)
   → devuelve: {executed_steps, coords_proactivas, warnings}

4. scene/validate
   → QA dual-engine → {error_type: "none"|"dimension"|"topology", details: [...]}

5. Si error_type != "none": agente lee details → scene/plan (edita) → scene/orchestrate → scene/validate

6. scene/commit {save: true}
   → guarda .tscn, libera lock, devuelve {saved: true}
```

### Sub-comandos `scene` (paralelo a `session`)

| Sub-comando | Qué hace | Paralelo en `session` |
|-------------|----------|----------------------|
| `scene/open {scene_path, mode: "isolated"|"attached"}` | Abre escena, lockea, devuelve contexto completo | `session/open` |
| `scene/plan {plan: ScenePlan}` | Escribe/actualiza plan en memoria (no ejecuta) | — (fase de diseño) |
| `scene/orchestrate` | Ejecuta plan → batch interno MCP calls | `orchestrate` (scene-aware) |
| `scene/validate` | QA dual-engine → reporte + `error_type` | `session/health` + `validate/*` |
| `scene/commit` | Guarda + libera lock | `session/close` |
| `scene/status` | Estado actual: lock, plan, dirty, QA report | `session/status` |

### Ventajas Clave

| Problema Actual | Solución con `scene/*` |
|-----------------|------------------------|
| Agente no sabe cuándo usar tools low-level | `scene/open` **instruye**: "Use `scene/plan` to design, `scene/orchestrate` to execute" |
| Contexto perdido entre calls | `scene/open` carga contexto **una vez** → `scene/plan`/`orchestrate`/`validate` lo usan |
| Conflictos user/agent | Lock por escena (`.heren/locks/Scene.tscn.lock`) — `scene/open` falla si locked by other |
| `orchestrate` genérico | `scene/orchestrate` **scene-aware**: resuelve coords, workplanes, instancing, templates |
| Help tool estúpida | `scene/open` devuelve **schema del plan** en `scene_context.plan_schema` |

### Arquitectura MAC Aplicada a Godot

| MAC (CAD) | Heren MCP (Godot) |
|-----------|-------------------|
| `CADBrief` (Spec Planner) | `SceneBrief` — requisitos: nodos, jerarquía, coords, recursos |
| `ArchitectPlan` (Geometric Architect) | `ScenePlan` — pasos: `add_node`, `set_transform`, `add_resource`, `connect_signal`, `instantiate_template` |
| `Python Coder` (deterministic translator) | `SceneCoder` — traduce `ScenePlan` → calls MCP internos (`node/add`, `node_props/set_props`, `resource/create`) |
| `Autonomous Skill Loop` (QA + Aider) | `SceneValidator` — `validate/scene`, `validate/node`, `visual/capture` + auto-repair loop |

### Sistema de Coordenadas — Workplane + Local Coords (Iron Rule #1 MAC)

```json
// ScenePlan usa workplanes — resuelve 3D vs UI automáticamente
{
  "workplane": "XZ",           // 3D world: position/transform
  "workplane_offset": [0, 1, 0],  // Robot base height
  "steps": [
    {"action": "add_node", "node_type": "MeshInstance3D", "name": "Body", "parent": "Robot", "local_pos": [0, 0, 0]},
    {"action": "set_transform", "node_path": "Robot/Body", "scale": [1, 2, 1]},
    {"action": "add_node", "node_type": "ProgressBar", "name": "HealthBar", "parent": "UI/HUD", "workplane": "XY", "local_pos": [20, 20], "anchors_preset": 10}
  ]
}
```

**SceneCoder** resuelve `local_pos` + `workplane` + `workplane_offset` → `position`/`transform` global + `anchors`/`offsets` para UI.

### Selector DSL — Semantic Selection (no hardcoded coords)

```json
// node_query/find con selectores semánticos
{"action": "find", "selector": "children_of:Robot where material.albedo_color.r > 0.5"}
```

### QA Dual-Engine

| Engine A (Deterministic) | Engine B (Heuristic/Visual) |
|--------------------------|----------------------------|
| `validate/scene` + `validate/node` + `node_query` (estructura, scripts, resources) | `visual_image/capture` + `visual_text/summary` (visión real, bbox, node_count) |
| `scene_registry` consistency | Off-screen render comparison |

### Deterministic SceneCoder — Zero-LLM Common Ops

```rust
// scene_coder.rs — traduce ScenePlan → MCP calls SIN LLM
fn plan_to_mcp_calls(plan: &ScenePlan, context: &SceneContext) -> Vec<MCPCall> {
    // add_node, set_transform, add_resource, connect_signal, instantiate_template
    // Batch: agrupa set_props por nodo, resuelve coords, maneja templates
}
```

### Cache Mechanism — Pipeline Cache

`.heren/scene_cache/<scene_name>/` guarda `SceneBrief` + `ScenePlan` → re-run tras repair es instantáneo.

### Aider-First Workflow — Modify Existing

`scene/open {mode: "modify", scene_path: "res://existing.tscn"}` → carga escena existente → `SceneValidator` + repair loop para modificaciones incrementales.

### Implementación Mínima

```
crates/heren-server/src/
├── scene_tool/
│   ├── mod.rs              # SceneAction enum, SceneState, handler registration
│   ├── schemas.rs          # SceneBrief, ScenePlan, SceneStep, VerificationTarget, SceneContext
│   ├── coder.rs            # scene_plan_to_mcp_calls() — deterministic translator
│   ├── validator.rs        # validate_scene() — dual-engine QA
│   └── registry.rs         # SceneRegistry: HashMap<scene_path, SceneState> + locks
addons/heren/
├── scene_handlers.gd       # Extender: handle_open, handle_plan, handle_orchestrate, handle_validate, handle_commit, handle_status
└── scene_registry.gd       # Lock management: .heren/locks/<Scene>.tscn.lock
```

### Registry: `SceneRegistry` (paralelo a `ConnectedEditors`)

```rust
struct SceneRegistry {
    scenes: HashMap<String, SceneState>,  // scene_path -> SceneState
    locks: HashMap<String, LockInfo>,     // scene_path -> {agent_id, pid, since, progress}
}
```

- `scene/open` → registra en `SceneRegistry` + crea `.heren/locks/<scene>.lock`
- `scene/commit` → remueve de registry + borra lock
- `session/status` → incluye `scenes: [{path, lock_id, mode, dirty, qa_status}]`

### Tools Low-Level → Internos (NO expuestos al agente)

En `tools.rs`: registrar **solo 3 tools high-level**:
- `scene_plan_write` → `scene/plan`
- `scene_plan_execute` → `scene/orchestrate`  
- `scene_plan_validate` → `scene/validate`

Tools low-level (`node/add`, `node_props/set_props`, `resource/create`, etc.) → **internos**, solo para `SceneCoder`.

### Extensión Futura: Animaciones y Huesos

Mismo patrón para `animation` y `skeleton`:
- `animation/open {animation_player_path, mode}` → lock + contexto (tracks, keys, blend trees)
- `animation/plan {plan: AnimationPlan}` — steps: `create_track`, `add_key`, `blend_pose`, `retarget`
- `animation/orchestrate` → batch interno
- `animation/validate` → QA: track types, key normalization, blend tree connectivity
- `skeleton/open`, `skeleton/plan`, `skeleton/orchestrate`, `skeleton/validate` — análogo

## 0.7 Plan de extensión del Planning a todo el motor (2026-08-24) — FASES 1-2b COMPLETADAS

> El planning E2E demostró éxito con escenas. Ahora se extiende a animaciones,
> esqueletos, scripts, shaders y tilemaps. Estrategia: **híbrido** — steps
> tipados para escena (80% del uso) + `GenericStep` para el resto (20%).

### Arquitectura híbrida

| Step type | Para qué | Ejemplo |
|-----------|----------|---------|
| `add_node`, `set_transform`, `add_resource`, etc. | Escena (core) | `{"action":"add_node","node_type":"MeshInstance3D",...}` |
| `Generic { action:"generic", tool, tool_action, args }` | Cualquier tool del plugin | `{"action":"generic","tool":"animation","tool_action":"create_player",...}` |

### Fases de implementación

| Fase | Estado | Descripción |
|------|--------|-------------|
| **Fase 1** — GenericStep | ✅ DONE | `SceneStep::Generic` + coder → MCPCall directo. Validator salta. Schema + ejemplo actualizados. |
| **Fase 2** — Steps animación tipados | ✅ DONE | `CreateAnimationPlayer`, `CreateAnimation`, `SetAnimPlayerProps`, `DuplicateAnimation`, `RemoveAnimation` + existentes `AddTrack`, `AddKey`. Coder + validator actualizados. |
| **Fase 2b** — Steps AnimationTree tipados | ✅ DONE | `CreateAnimationTree`, `AddBlendNode`, `ConnectBlendNodes`, `SetTreeRoot`, `SetTreeParam`. Coder + validator actualizados. |
| **Fase 3** — Steps esqueleto tipados | ✅ DONE | `CreateSkeleton`, `SetBonePose`, `CreateIK`, `SetSkin` + existentes `AddBone`, `SetBoneRest`. Coder + validator actualizados. |
| **Fase 4** — Steps script/shader tipados | ✅ DONE (parcial) | `AttachScript`, `CreateShader`, `SetShaderUniform` → mapeo a `resource`/`shader`. |
| **Fase 5** — Validator introspección | Pendiente | Valida GenericStep args contra schema del plugin (FlojoTester). Catch errores antes de ejecutar. |

### Notas de diseño

- **GenericStep** usa `tool_action` (no `action`) para no colisionar con el tag serde `#[serde(tag="action")]`.
- **Validator** hoy salta Generic (Fase 5 añadirá introspección).
- **Passthrough verbatim**: args del Generic viajan sin transformación al plugin.
- **Ejemplo en `scene(action="plan")`**: incluye paso genérico de animación como referencia.

---

## 0.8 Plan Radiográfico — 10 bugs sesión 2026-09-03 — EN CURSO (Fase 0)

> **Origen**: reporte de desarrollador tras sesión real — el agente recibía mentiras sistemáticas (`ok:true` sin verificación), no podía abrir escenas, no veía input_map del proyecto, capture off-screen colgaba 30s en play. Sospecha: bugs arquitectónicos, no puntuales. **Confirmado**: hay 4 problemas de diseño que encubran 10 bugs.

### Diagnóstico por bug (causa raíz + severidad real)

| # | Bug | Causa raíz | Severidad | Fix |
|---|-----|-----------|-----------|-----|
| **#1** | `scene/open` miente (retorna `ok:true` sin verificar pestaña activa) | `handle_open` (scene_handlers.gd L4-16) llama `ei.open_scene_from_path()` que es **deferred en Godot 4** (issue #13816 ya documentado) — `get_edited_scene_root()` corre en el mismo frame, retorna pestaña anterior. **NO valida `scene_file_path` antes de retornar `ok:true`**. | 🔴 Crítico | `await process_frame × 2` + verificar `opened.scene_file_path == scene_path` antes de `ok:true` |
| **#2** | `visual_text coords/ascii` ignora `scene_path` | `handle_scene_coords/summary/ascii` usan `_root_node()` (L61-65) que NO acepta args; `handle_capture` usa `_scene_root(args)` (L4-9) que SÍ acepta. **Inconsistencia copy-paste**. | 🟠 Alto | Sustituir 3 llamadas `_root_node()` por `_scene_root(args)` |
| **#3** | `scene open` con `mode=plan` falla con `-32603 no scene open` | `scene_planning` (server.rs L757-764) acepta `"isolated"/"attached"/"modify"` — `"plan"` cae en `_ => None` y silenciosamente `unwrap_or(Isolated)`. Pero el planning path dispara `load_scene_context` que llama al plugin que lee la pestaña REAL del editor (main_menu), no la escena del plan. **Validación faltante** + bug arquitectónico A2. | 🔴 Crítico | Validar `mode ∈ {isolated, attached, modify, plan}`, devolver error claro si no |
| **#4** | `scene/status` vacío tras open legacy | **Bug arquitectónico A1**: server tiene `SceneRegistry` propio en RAM (`crates/heren-server/src/scene_tool/registry.rs`), plugin tiene `HerenSceneRegistry` propio (`addons/heren/scene_registry.gd`). **NO se sincronizan**. El plugin registra al abrir; el server solo se entera si pasas por el planning path con `mode`/`agent_id`. | 🔴 Crítico | Fase 1: eliminar server-registry, plugin-registry es source-of-truth único |
| **#5** | Editor siempre arranca con main_menu | `application/run/main_scene` apunta a `src/ui/main_menu.tscn`. `open_scene_from_path` deferred — bug #1 raíz. **Doble main_menu.tscn** (raíz y `/src/ui/`) confunde al plugin sobre cuál cargar. | 🟡 Medio | Fix #1 + limpieza manual: borrar `main_menu.tscn` raíz |
| **#6** | `input_map/list` solo retorna 16 builtin spatial_editor | `project_handlers.gd::handle_input_map type="list"` (L168-178) itera `InputMap.get_actions()` — runtime del EDITOR (no del proyecto). Las acciones del proyecto (move_forward, grab_left, etc.) NO aparecen. **El plugin lee del sitio equivocado**. | 🟠 Alto | Iterar `ProjectSettings.get_property_list()` filtrado `name.begins_with("input/")` |
| **#7** | `setting get` reporta `restart_required: true` siempre | `handle_setting` (L40-50) llama `_setting_requires_restart(setting_name)` también en GET. Es cosmético pero miente. | 🟡 Bajo (cosmético) | En GET: `restart_required: false` siempre |
| **#8** | `visual_image capture` timeout >30s durante play | `_render_scene_offscreen` clona root en SubViewport; durante `is_playing_scene()` el renderer compite por GPU → `frame_post_draw` no resuelve. **Comentario en server.rs L869 ya lo sabe**: "capture offscreen → timeout en 3D". | 🟠 Alto | `handle_capture`: si `ei.is_playing_scene()` → rechazar con error claro (`capture_blocked_during_play`) |
| **#9** | `debug/output` retorna log viejo entre runs | `handle_output` (L4-26) lee `_dbg_plugin.last_output` que es buffer global append-only. `handle_run_scene` NO lo limpia antes de play. | 🟡 Medio | En `handle_run_scene`: `_dbg_plugin.last_output.clear()` antes de `play_*` |
| **#10** | `resource/read` para PackedScene retorna `{__type:Resource, resource_class:"Resource"}` sin props | `handle_read` (L4-19) llama `load()` directo sin forzar `efs.update_file()` antes. Si EFS no escaneó el archivo todavía, `load()` retorna `Resource` base en vez de `PackedScene`. | 🟡 Medio | `efs.update_file()` antes de `load()`; fallback explícito `ResourceLoader.load(path, "PackedScene", CACHE_MODE_REUSE)` |

### 🔴 Causas arquitectónicas (raíz del mal)

| # | Problema | Patrón violado |
|---|----------|----------------|
| **A1** | **Dos SceneRegistry sin sincronizar**: server (`crates/heren-server/src/scene_tool/registry.rs`) y plugin (`addons/heren/scene_registry.gd`) mantienen el mismo estado en RAM. El plugin NO reporta hacia arriba; el server solo reconstruye vía `load_scene_context` que hace 3 `forward()` encadenados. | "Single source of truth" — cualquier sistema con ≥2 caches del mismo dato necesita invalidación explícita. Aquí NO la hay. |
| **A2** | **Flujo `open` dual bifurca silenciosamente**: server.rs L628 — `planning_open = action=="open" && (mode.is_some() || agent_id.is_some())`. Si pasan, va a `scene_planning` (server-registry); si no, va a `handle_open` (plugin-registry). El agente no tiene manera de saber cuál path se eligió. | "Explicit routing" — el routing debe ser declarativo, no implícito |
| **A3** | **`ok:true` sin verificación**: `handle_open`, `handle_run_scene`, varios otros retornan éxito sin chequear que la operación realmente ocurrió. Filosofía "fail-fast" violada sistemáticamente. | "Fail-fast" (§10 decisiones, ya documentado) |
| **A4** | **Dispatcher routing frágil**: `dispatcher.gd` L25-35 tiene 3 fallbacks mágicos para resolver método (`handle_<tool_with_slash>` → action del args → strip prefix). Cualquier renombre silencioso rompe el routing. | "Explicit > implicit" |

### 🧹 Auditoría de parámetros zombies (limpieza Fase 0)

**Confirmados como muertos**:

| Tool | Parámetro | Archivo:línea | Razón |
|------|-----------|---------------|-------|
| `session` | `visibility` | server.rs L189, L324 | Solo se reporta en JSON, nunca afecta comportamiento. Nunca implementado `--headless` para agent editor |
| `session` | `agent_id` | server.rs L188, L299 | Solo se usa cuando `mode=isolated` — flujo que el agente típico NO usa. Default = "default" |
| `scene` | `agent_id` | server.rs L601, L639 | Solo se pasa a `scene_planning` → `open_scene` → `LockInfo`. El flujo planning es opcional y agent_id puede ser interno |
| `orchestrate` | `_auto_save` | server.rs L2127 | **Prefijo `_` = marcado como muerto por el autor original**. Nunca usado en el cuerpo |

**Decisión**: **quitarlos del schema público**. Mantener la lógica interna (role = "default", mode planning inferido). El agente ya no tiene que adivinar si agent_id/visibility son relevantes.

### ⚡ Automatizaciones de path (Fase 0)

| Contexto | Antes | Después |
|----------|-------|---------|
| `node/add` sin scene_path | Agente repite path o falla | Usar `apply_scene_context` (ya existe) — recuerda el último scene_path usado |
| `node_query/get_info` sin node_path | Asumir "." (root) automáticamente | Implementado en `handle_get_info` — si no viene, default `"."` |
| `project_path` en cualquier tool | resolve_project tiene 5 fallbacks (explícito → last → role → único → error) | ✅ Ya robusto, mantener |
| `scene_path` en scene_planning | Agente debe repetir | `resolve_planning_scene` toma `first()` del registry si no se pasa |
| `scene/open` | Requiere `mode`/`agent_id` para bifurcarse | Bifurcación sigue pero se valida — `"plan"` ya no falla silenciosamente |

### 📋 Plan de remediación por fases

| Fase | Estado | Descripción | Esfuerzo | Cierre |
|------|--------|-------------|----------|--------|
| **Fase 0 — 止血 (Parches)** | 🔨 EN CURSO | 6 parches quirúrgicos + limpieza parámetros zombies + automatizaciones path | 2-3h | `heren-build.bat` verde + tests Rust/GDScript |
| **Fase 1 — Single registry** | Pendiente | Eliminar `crates/heren-server/src/scene_tool/registry.rs`. Plugin-registry es source-of-truth. `scene/status/list` forward al plugin vía `scene/get_open_scenes` extendido. `load_scene_context` del adapter desaparece | 1 día | scene_planning ya no mantiene estado propio; planning metadata vive en `.heren/scenes/<scene>.json` opcional |
| **Fase 2 — Fail-fast sistemático** | Pendiente | Audit TODO handler que retorna `ok:true`. Helper `assert_effect_applied(action, predicate)`. Lista de sospechosos en §10 ya documentada | ½ día | Test E2E: cada handler con efecto verificable retorna error claro si no aplica |
| **Fase 3 — Dispatcher explícito** | Pendiente | `dispatcher.gd` con tabla declarativa `(tool_name, action) → handler_method`. Tests Rust `tools_parity.rs` verifican cobertura | ½ día | Cada tool/action tiene routing declarado; renames rompen tests |

### 🛠 Fase 0 — Detalle de parches

| # | Cambio | Archivo | Líneas |
|---|--------|---------|--------|
| P0.1 | `handle_open`: `await process_frame ×2` + verificar `scene_file_path == path` antes de `ok:true` | `addons/heren/handlers/scene_handlers.gd` | L4-16 → reescribir como async |
| P0.2 | `handle_scene_coords/summary/ascii`: `_root_node()` → `_scene_root(args)` | `addons/heren/handlers/visual_handlers.gd` | 3 llamadas a sustituir |
| P0.3 | `handle_capture`: rechazar si `ei.is_playing_scene()` | `addons/heren/handlers/visual_handlers.gd` | L4 (nueva guarda) |
| P0.4 | `handle_run_scene`: `_dbg_plugin.last_output.clear()` antes de play | `addons/heren/handlers/debug_handlers.gd` | L29-42 |
| P0.5 | `handle_input_map type="list"`: leer `ProjectSettings.get_property_list()` filtrado | `addons/heren/handlers/project_handlers.gd` | L168-178 |
| P0.6 | `handle_setting op="get"`: `restart_required: false` siempre | `addons/heren/handlers/project_handlers.gd` | L40-50 |
| P0.7 | `resource/read`: `efs.update_file()` antes de `load()`; fallback con tipo explícito | `addons/heren/handlers/resource_handlers.gd` | L4-19 |
| P0.8 | Limpiar `visibility` del schema de `session` | `crates/heren-server/src/server.rs` | L189, L324, JSON response |
| P0.9 | Limpiar `agent_id` del schema de `session` y `scene` (mantener lógica interna default="default") | `crates/heren-server/src/server.rs` | L188, L601, L639, L744, L751 |
| P0.10 | Limpiar `_auto_save` del schema de `orchestrate` | `crates/heren-server/src/server.rs` | L2127 |
| P0.11 | `scene`: validar `mode ∈ {isolated, attached, modify, plan}` — rechazar otros | `crates/heren-server/src/server.rs` | L757-764 |

### ✅ Checklist Fase 0

- [x] AGENTS.md §0.8 redactado
- [x] P0.1 handle_open await + verify
- [x] P0.2 visual_text scene_path
- [x] P0.3 capture play guard
- [x] P0.4 run_scene clear buffer
- [x] P0.5 input_map list from ProjectSettings
- [x] P0.6 setting get restart_required false
- [x] P0.7 resource/read efs.update_file
- [x] P0.8 session.visibility removed
- [x] P0.9 session/scene agent_id removed (default internal)
- [x] P0.10 orchestrate _auto_save removed
- [x] P0.11 scene mode validation
- [x] Limpieza masiva de descripciones: quitar "(v4.X)" y "P0.X" de las 18 tools (regla: descripciones compactas, sin fechas)
- [x] `orchestrate` (tool plana) quitada del schema — duplicaba `scene/plan`+`scene/orchestrate` (Fase 0); §6 actualizado a "Las 18 Tools"
- [x] `heren-build.bat` → 74 tests verdes
- [x] **Plan Round-2 (Fase 0-bis)** — fixes completos del flujo de planning, ver §0.9
- [x] **LSP bridge OpenCode** (`heren-server lsp-bridge`) — sub-comando CLI en Rust puro, stdio↔TCP :6005, auto-launch Godot headless liviano, reconexión automática, modo verbose. 0 deps Node. Ver §0.10 + `docs/lsp-setup.md`.
- [ ] E2E manual con el proyecto del bug report (humanoid.tscn + 8 input actions)
- [ ] Commit + tag

---

## 0.10 LSP Bridge para OpenCode (2026-09-03) — IMPLEMENTADO

> **Origen**: el agente no tenía autocompletado ni chequeo de errores mientras
> escribía código GDScript en OpenCode. El competidor GoPeak tenía 4 tools
> MCP de LSP (`lsp_get_diagnostics`, etc.) — pero eso NO es LSP real, es
> proxy vía tools MCP. Lo que el agente necesita es **LSP server estándar**
> que OpenCode consuma por su stack LSP nativo (`opencode.jsonc` → `lsp.gdscript.command`).

### Decisión del General (2026-09-03)

Bridge **stdio ↔ TCP** en **Rust puro**, dentro del binario `heren-server`,
sub-comando `lsp-bridge`. **0 deps Node** (MasuRii/opencode-godot-lsp descartado
por requerir Node.js, regla "el LSP va a parte del MCP pero hay que hacer que
el auto-lanzado por el LSP consuma apenas recursos").

### Arquitectura

```
OpenCode ──── stdio LSP ────► heren-server lsp-bridge ──── TCP :6005 ────► Godot Editor (LSP nativo)
                                  │
                                  └─ si nadie escucha :6005 y --auto-launch-godot (default ON):
                                     spawn godot --editor --headless --audio-driver Dummy
                                     --lsp-port 6005 --path <project>  (~150-250 MB RAM)
```

### Módulos nuevos (crates/heren-server/src/lsp_bridge/)

- **`frame.rs`** — Parser LSP puro (Content-Length framing + JSON-RPC 2.0). 9 tests unitarios. **Bugs encontrados y resueltos durante implementación**:
  - **OOM 6.4GB**: `parse_one` devolvía `Complete(body)` pero NO drenaba el buffer → `feed()` loop infinito copiando el mismo body. Fix: `parse_one_and_consume()` drena `..body_end` antes de devolver. **Lección: parser incremental = consumir antes de devolver, SIEMPRE**.
  - **Case mismatch**: `has_lsp_enabled` no normalizaba case del key. Fix: `to_ascii_lowercase()` antes de `strip_prefix`.

- **`launcher.rs`** — Auto-launcher de Godot headless liviano. Verifica `project.godot` tiene `[network] language_server/enabled=true`. Espera conexión con backoff 250ms→2s. 6 tests (parser `project.godot` tolerante a espacios/case).

- **`proxy.rs`** — Proxy bidireccional stdin ↔ TcpStream con **reconexión automática** (backoff 1s, ventana `reconnect-max-ms` default 60s). **Mensajes LSP durante desconexión**: se descartan (mejor fail-fast que buffer — LSP requests de OpenCode tienen timeout corto). Modo verbose: preview de 80ch por mensaje a stderr.

- **`mod.rs`** — Clap derive CLI + `BridgeConfig` + orchestrator `run_bridge()`. Entry point `TopLevelCli` con dispatch: sin args = MCP server (compat), `lsp-bridge` = LSP bridge.

### Configuración OpenCode

```jsonc
{
  "lsp": {
    "gdscript": {
      "command": ["D:/path/to/heren-server.exe", "lsp-bridge", "--project-path", "D:/path/to/project"],
      "extensions": [".gd", ".gdshader"],
      "env": { "HEREN_LSP_LOG_FILE": "D:/logs/heren-lsp.log" }
    }
  }
}
```

### Pre-requisito en `project.godot`

```ini
[network]
language_server/enabled=true
language_server/port=6005
```

El bridge **NO modifica** `project.godot` del usuario (decisión conservadora — el setup.md documenta la activación; un flag `--enable-lsp-in-project` puede añadirse si el flujo lo demanda).

### Tests

| Suite | Tests | Tiempo |
|-------|-------|--------|
| `cargo test -p heren-server --lib lsp_bridge` | 23 (frame: 9, launcher: 6, mod: 8) | 0.01s |
| `cargo test -p heren-server --test lsp_bridge` | 2 (proxy con fake LSP server TCP) | 0.07s |
| `cargo test -p heren-server` (total) | **106** (78 + 28 viejos) | ~1.4s |

**Cero regresiones** en el flujo MCP existente (los 55 tests viejos siguen verdes).

### Lint y Release

- `cargo clippy --all -- -D warnings`: **VERDE**
- `cargo build --release`: binario **11.9 MB** (release optimizado)
- Deps nuevas: solo `clap` con feature `["derive", "env"]` (~0.5 MB extra vs dev). **`serde_json`/`tokio`/`tracing` ya estaban en el workspace**.

### Decisiones clave (vs MasuRii/gopeak)

| Decisión | Razón |
|----------|-------|
| Bridge stdio↔TCP (no cliente LSP completo) | OpenCode ya implementa cliente LSP nativo; nosotros solo necesitamos transporte |
| 0 deps Node | Regla explícita del General; Rust puro es viable (~250 LOC del bridge) |
| Auto-launch default ON | El bridge debe funcionar sin config adicional del usuario; Godot headless consume apenas recursos (`--headless --audio-driver Dummy`) |
| Reconnect automático | Godot LSP puede reiniciarse (script reload, project edit); ventana 60s es razonable para entornos de desarrollo |
| Verbose minimalista | Preview 80ch por mensaje: suficiente para debug, no inunda log |
| Sin `lsp-types` crate | El bridge no parsea tipos LSP semánticos (proxy passthrough); ahorra ~3MB binario |

---

## 0.11 Spatial Proactivity — coords unificadas (2026-09-04) — FASE A ✅

> **Origen**: el General detectó que las herramientas de imagen eran "una porquería" (§0 ronda) y propuso reemplazar TODO por coords + espacio puro. Antes de matar `visual_image`, **debíamos asegurar que el sistema de coordenadas fuera robusto** — un agente "ve casi en tiempo real" solo si cada mutación devuelve la posición/bbox/rotación del nodo afectado **sin llamada extra**.
>
> Auditoría reveló **2 problemas gemelos**:
> 1. **Coordenadas dispersas en 4 funciones** (`_node_coords`, `_node_pos`, `_node_bbox`, `coords_of`) con campos solapados y comportamiento inconsistente.
> 2. **9/13 handlers de mutación NO devolvían coords** — tras `set_props` batch / `move` / `duplicate` / `rename` el agente quedaba ciego hasta pedir `get_info` extra.

### Decisión del General (2026-09-04)

**Único punto de verdad** = `HerenCoords.coords_of_node(node, parent_path, tier)` (estática, pura, testeable).
- **Discriminator** `kind` (clase Godot) + `flags` (capacidades) — el cliente sabe qué esperar sin parsear.
- **Tiers** 0/1/2 — el agente pide solo lo que necesita.
- **Pureza 2D ↔ 3D** — un Node2D jamás trae `quat`/`basis`/`cast_shadow`; un Node3D jamás trae `z_index`/`anchors`/`effective_rect`. **El agente deja de desperdiciar tokens en la dimensión equivocada.**

### Fase A — COMPLETADA

| Cambio | Archivo | Detalle |
|--------|---------|---------|
| **Nueva función unificada** | `addons/heren/handlers/coords.gd` | `coords_of_node(node, parent_path, tier)` + helpers privados `_fill_3d` / `_fill_2d_canvas` / `_fill_control` / `_fill_tier2` / `_bbox_of_2d` / `_visibility_mode_str` / `_detect_flags` |
| **Wrapper thin** | `node_handlers.gd::_node_coords` | Antes 118 líneas inlined → ahora 2 líneas que delegan a `coords_of_node(node, _parent_path(node, root), 2)` |
| **Helper `parent_path`** | `node_handlers.gd::_parent_path` | Centraliza el cálculo del path relativo del padre |
| **Eliminar duplicación** | `node_handlers.gd` `_node_coords` (118 líneas) | Borrado; `coords_of_node` es la única implementación |
| **Eliminar duplicación** | `visual_handlers.gd` `_node_pos` + `_node_bbox` | Borradas; `_walk` y `_capture_node` usan `coords_of_node` |
| **Propagar a 13 mutaciones** | `node_handlers.gd` | `add`, `remove`, `set_prop`, `set_props` (batch), `duplicate`, `instantiate`, `rename`, `move`, `set_owner`, `reorder`, `array_append`, `array_remove`, `set_script` → TODAS devuelven `coords` + `scene_node_count` |
| **Migrar scene_handlers** | `scene_handlers.gd` | 3 calls de `coords_of` (legacy) → `coords_of_node(node, "", 2)` |

### Diseño — Discriminator `kind` + `flags`

```jsonc
{
  "kind": "Node2D" | "Node3D" | "Control" | "MeshInstance3D" | "Sprite2D" | ...,
  "flags": {
    "is_2d": bool,         // CanvasItem + descendientes
    "is_3d": bool,         // Node3D + descendientes
    "is_control": bool,    // Control + descendientes
    "has_bbox": bool,      // bbox 2D inferida por tipo
    "has_aabb": bool       // 3D mesh
  },
  "parent_path": str,
  "visible": bool
}
```

### Diseño — Tiers progresivos

| tier | Coste aprox | Contenido |
|------|-------------|-----------|
| **0** | ~30 tok | `kind` + `flags` + `parent_path` + `visible` |
| **1** | ~80-150 tok | + pos + scale + rotation **kind-specific** + bbox/aabb |
| **2** | ~150-250 tok | + modulate + material + collision + render layers + Control: anchors, offsets, size, effective_rect, size_flags |

Tier 3 (animation/light/audio state) queda para Fase C — no implementado aún.

### Diseño — Pureza 2D ↔ 3D (regla crítica)

| Tipo | SÍ incluye | NO incluye (verificado por test) |
|------|------------|---------------------------------|
| **Node2D / Sprite2D / CollisionShape2D** | `pos{x,y}`, `scale{x,y}`, `rotation{deg,rad}`, `z_index`, `bbox`, `size{w,h}` | ❌ `quat`, ❌ `aabb`, ❌ `size_3d`, ❌ `cast_shadow`, ❌ `render_layers` |
| **Node3D / MeshInstance3D** | `pos{x,y,z}`, `scale{x,y,z}`, `rotation{euler_deg, quat}`, `aabb`, `size_3d{x,y,z}`, `cast_shadow`, `gi_mode`, `material_override_path` | ❌ `z_index`, ❌ `bbox`, ❌ `anchors`, ❌ `offsets`, ❌ `effective_rect` |
| **Control** | lo anterior 2D + `anchors`, `offsets`, `size`, `effective_rect`, `size_flags`, `parent_is_container` (tier 2) | ❌ campos exclusivos 3D |
| **Pure Node** | solo `kind`, `flags`, `parent_path`, `visible` | nada más |

### CONTRATO — qué devuelve cada handler (Fase A)

| Handler | Devuelve `coords` | Devuelve `count` | Otra info proactiva |
|---------|:-:|:-:|---------|
| `node/add` | ✅ | ✅ `count` | `inline_resources` warning |
| `node/instantiate` | ✅ | ✅ `count` | `template`, `instance_path` |
| `node/remove` | ✅ | ✅ `scene_node_count` | `had_children`, `parent_path` |
| `node_props/set_prop` | ✅ | ✅ `scene_node_count` | `old_value`, `new_value`, `applied_value` |
| `node_props/set_props` (batch) | ✅ | ✅ `scene_node_count` | `applied`, `requested`, `skipped` |
| `node/duplicate` | ✅ | ✅ `scene_node_count` | `original`, `duplicate` paths |
| `node/rename` | ✅ | ✅ `scene_node_count` | `old_name`, `new_name`, `previous_path` |
| `node/move` | ✅ | ✅ `scene_node_count` | `previous_path`, `old_parent`, `new_parent` |
| `node/set_owner` | ✅ | ✅ `scene_node_count` | `owner_path` |
| `node/reorder` | ✅ | ✅ `scene_node_count` | `new_index`, `old_index` |
| `node/array_append` | ✅ | `array_size` | `value_added` |
| `node/array_remove` | ✅ | `array_size` | `removed_value` |
| `node/set_script` | ✅ | — | `script` |
| `scene/get_edited_scene_root` | ✅ | `child_count` | — |
| `scene/open` | ✅ | `child_count` | `lock_id`, `mode` |
| `scene/save` | ✅ | `child_count` | `saved`, `path` |

### Métricas Fase A

| Métrica | Antes | Ahora |
|---------|-------|-------|
| Funciones de coords duplicadas | 4 (`_node_coords`, `_node_pos`, `_node_bbox`, `coords_of`) | **1** (`coords_of_node`) |
| Handlers que devolvían `coords` | 4/13 | **13/13** |
| Líneas de código de coords en handlers | ~145 | ~15 (wrapper) |
| Datos 3D en respuestas 2D | contaminaba | **0%** (test verifica) |
| Datos 2D en respuestas 3D | contaminaba | **0%** (test verifica) |
| Tests GDScript Fase A | 0 | **9** (null/2D-purity/3D-purity/Control/Sprite/Mesh/tier0/tier2/discriminator) |

### Verificación

| Check | Resultado |
|-------|-----------|
| `cargo test -p heren-server` | **116 tests verdes** (sin regresiones) |
| `cargo clippy -- -D warnings` | verde |
| Grafo headless (`godot --headless --editor --quit-after 60`) | **0 SCRIPT ERROR, 0 Parse Error** |
| Tests GDScript (`run_tests.gd`) | **19/19 verdes** (10 viejos + 9 nuevos) |
| Binario release | OK (~11.9 MB) |

### Bugs colaterales arreglados (gratis)

1. `template_registry._apply_params` — `deserialize_value("HP 50/100")` emitía parse error en Godot 4.5. Fix: `if value is String`, pasa tal cual (string opaco).
2. Coords globales sin parent — gates con `is_inside_tree()` evitan `get_global_transform` warning.
3. Props 4.5+ (`cast_shadow`/`gi_mode`) con `in` defensivo — tolerante a builds donde no existan.

### Pendientes (no parte de Fase A — contrato definido, implementación en próximos sprints)

#### Fase B — `visual_text/spatial` ✅ COMPLETADA (2026-09-04)

5 modes que permiten al agente verificar layout geométrico SIN captura de imagen:

| Mode | Args | Output |
|------|------|--------|
| `overlaps` | `node_path, padding=0` | nodos cuya bbox/aabb intersecta |
| `distance` | `from, to` | vector + magnitud entre dos puntos/nodos |
| `neighbors` | `of, radius` | nodos dentro de un radio |
| `layout` | `node_path` (Control) | effective_rect + Container padding del padre |
| `bounds` | `of="."` | AABB total escena (2D + 3D separadas) |

**Módulo nuevo**: `addons/heren/handlers/visual_tool/spatial_tool.gd` (clase `HerenSpatialTool`, funciones estáticas puras + testeables). Handler: `visual_handlers.handle_scene_spatial(args)` → delega a `HerenSpatialTool.compute(root, args)`.

**Coste típico**: 50-200 tok por llamada. **Reemplaza `visual_image` para validación geométrica.**

**Ejemplo**:
```jsonc
// ¿colisionan mis sprites?
visual_text(action="spatial", mode="overlaps", node_path="Player")
// → { "ok": true, "results": [{"path":"Enemy_1","kind":"Sprite2D"}, ...], "count": 3 }

// ¿dónde está realmente mi HealthBar post-anchors?
visual_text(action="spatial", mode="layout", node_path="HUD/HealthBar")
// → { "effective_rect": {x,y,w,h}, "anchors":..., "offsets":..., "parent_is_container": true, "parent_margin": {l,t,r,b} }

// ¿qué tan grande es la escena?
visual_text(action="spatial", mode="bounds")
// → { "bounds_2d": {x,y,w,h}, "bounds_3d": {min,max,size} }
```

**Bugs colaterales arreglados**:
1. `_fill_3d` ahora devuelve AABB transformada (global si inside_tree, `transform` local si detached) — antes retornaba `get_aabb()` LOCAL sin transformar, lo que hacía que TODAS las BoxMesh tuvieran el mismo AABB y siempre intersectaran (false positive).
2. `_relpath` no usa `get_path()` (que requiere SceneTree) — construido manualmente con parent chain. Funciona con nodos detached en tests headless.

**Tests**: 8 nuevos en `run_tests.gd` (overlaps 2D encuentra/excluye self, overlaps 3D, distance, neighbors radius, layout Control, bounds, unknown mode).

#### Fase C — Tier 3 dynamic state (animation/light/audio/camera/skeleton) ✅ COMPLETADA (2026-09-04)

**Decisión del General (2026-09-04)**: tier 3 = **resumen proactivo** (lo devuelven TODAS las mutaciones); tier 4 = **completo opt-in** vía `tier=4` en `visual/coords`. **AnimationTree entra en sinergia con AnimationPlayer** — siempre van juntos, el tree lleva coords del player del que se nutre (sinergia, sin duplicación).

### Categorías implementadas (7 secciones opt-in por nodo)

| Sección | Aplica a | Coste tier 3 | Coste tier 4 |
|---------|----------|--------------|--------------|
| `animation` | AnimationPlayer | ~50 tok (current/position/playing/speed/autoplay/length) | N/A |
| `animation_tree` | AnimationTree | ~80-120 tok (active, anim_player_path, tree_root_type, current_state si StateMachine, **anim_player_state snapshot**) | + state_machine_state + blend_position |
| `skeleton_3d` | Skeleton3D | ~150-300 tok (count + bone_names + 3 primeras poses) | TODAS las poses (sin truncate) |
| `skeleton_2d` | Skeleton2D | ~150-300 tok (count + lista resumida — son pocos huesos) | + weights / transforms completos |
| `light_3d` | Omni/Spot/DirectionalLight3D | ~30 tok (type, color, energy, indirect_energy, range o spot_range+spot_angle) | N/A |
| `audio` | AudioStreamPlayer/2D/3D | ~40 tok (type, playing, volume_db, pitch_scale, bus, stream, max_distance si 3D) | N/A |
| `camera` | Camera2D/3D | ~25 tok (type, fov o zoom, near/far/current) | N/A |

### Reglas de pureza (verificadas por tests)

- AnimationPlayer **NUNCA** emite animation_tree / skeleton_* / light_3d / audio / camera.
- AnimationTree **NUNCA** emite animation / skeleton_* / light_3d / audio / camera.
- Skeleton3D **NUNCA** emite animation / animation_tree / skeleton_2d / light_3d / audio / camera.
- Skeleton2D **NUNCA** emite animation / animation_tree / skeleton_3d / light_3d / audio / camera.
- Light3D **NUNCA** emite animation / skeleton_* / audio / camera.
- AudioStreamPlayer* **NUNCA** emite animation / skeleton_* / light_3d / camera.
- Camera **NUNCA** emite animation / skeleton_* / light_3d / audio.
- Node3D/Node2D/Control sin estado dinámico → **NO se emite** el bloque `dynamic` (32 tok ahorrados).

### Diseño — API expuesta

**Tool `visual` con param `tier`** (default 1 = comportamiento actual):

```jsonc
visual(action="coords", tier=3)        // resumen por nodo (animation/skeleton_3d count+3 primeros/etc.)
visual(action="coords", tier=4)        // completo (todas las poses skeleton, AnimationTree params completos)
visual(action="coords")                // tier=1 default (mapa visual barato, sin dynamic)
```

**Mutaciones devuelven tier 3 (resumen) proactivo** — `coords_of_node(node, parent, 3)` desde `_node_coords()` (Fase A). Tier 4 SOLO opt-in vía `visual(coords, tier=4)`.

### Sinergia AnimationTree ↔ AnimationPlayer

AnimationTree lleva `anim_player_state` (snapshot del AnimationPlayer asociado):
- `anim_player_path` (NodePath RELATIVO al tree)
- `tree.get_node_or_null(tree.anim_player)` resuelve y captura
- Devuelve `{current, position, playing, speed_scale, autoplay, length}` del player
- **Si el player está en otra rama del árbol, get_node_or_null() con NodePath RELATIVO resuelve correctamente** (FIX: antes usaba scene_root que fallaba en runtime sin editor)

### Snapshot de AnimationTree en detalle

```jsonc
{
  "animation_tree": {
    "active": true,
    "anim_player_path": "../AnimationPlayer",
    "tree_root_type": "AnimationNodeStateMachine" | "AnimationNodeBlendTree" | ...,
    "anim_player_state": { /* snapshot completo del player */ },
    // tier=4:
    "current_state": "idle",                  // si StateMachine
    "blend_position": 0.42                    // si BlendSpace1D/2D
  }
}
```

### Snapshot de Skeleton3D en detalle

```jsonc
{
  "skeleton_3d": {
    "bone_count": 30,
    "motion_scale": 0.01,
    "show_rest_only": false,
    "bone_names": ["root", "spine", ...],    // SIEMPRE completo (strings cortos)
    "poses": [                                // tier 3: 3 primeros; tier 4: TODOS
      {"index": 0, "name": "root", "position": {...}, "rotation": {...}},
      ...
    ],
    "poses_truncated": 27                     // tier 3 con más de 3 huesos
  }
}
```

### Snapshot de AudioStreamPlayer3D

```jsonc
{
  "audio": {
    "type": "AudioStreamPlayer3D",
    "playing": false,
    "volume_db": -6.0,
    "pitch_scale": 1.25,
    "bus": "Master",
    "stream": "res://sfx/click.ogg" | "" | "(inline)",
    "max_distance": 100.0,                    // 3D only
    "attenuation_model": 0                    // 3D only
  }
}
```

### Decisiones técnicas

- **Skeleton2D.get_bone_count()** en Godot 4 requiere `NOTIFICATION_PARENTED` en Bone2D — puede ser async en headless. Por robustez, `_fill_skeleton_2d` itera recursivamente `Bone2D` children en vez de usar la API virtual. Funciona incluso antes del primer frame.
- **Light3D NO tiene `light_enabled` property** (Godot 4.5) — se omite. La luz está activa si el nodo `visible` del CanvasItem padre lo está (y Light3D no hereda de CanvasItem, así que es siempre). Verificado con `get_property_list()`.
- **AudioStreamPlayer3D `bus`** se reporta pero no se puede cambiar en runtime sin AudioServer config — el default es "Master" en todos los casos.
- **AnimationTree.anim_player** es NodePath RELATIVO al tree, no al scene root. `tree.get_node_or_null(tree.anim_player)` resuelve correctamente en runtime (FIX pre-existente: el código viejo usaba `tree.get_tree().get_edited_scene_root()` que retorna null en runtime).
- **`flags.has_dynamic_state`** = `true` si alguna sección se emitió. Permite al agente hacer `if flags.has_dynamic_state: read dynamic.*` sin parsear.

### Cambios por archivo

| Archivo | Cambio |
|---------|--------|
| `coords.gd` | `coords_of_node()` con tier 3/4 + 7 helpers `_fill_animation/animation_tree/skeleton_3d/skeleton_2d/light_3d/audio/camera` + helper `_collect_bones_2d` recursivo |
| `coords.gd::_empty_flags()` | Añadido `has_dynamic_state: false` |
| `node_handlers.gd::_node_coords` | Tier 2 → tier 3 (proactivo con resumen) |
| `visual_handlers.gd::handle_scene_coords` | Acepta `tier` arg (default 1); `_walk` propaga tier y añade bloque `dynamic` al entry si tier>=3 |
| `server.rs::visual` | Parámetro `tier: Option<i64>` con doc inline |

### Métricas Fase C

| Métrica | Antes | Ahora |
|---------|-------|-------|
| Categorías de estado dinámico | 0 | 7 (animation, animation_tree, skeleton_3d, skeleton_2d, light_3d, audio, camera) |
| Handlers que devolvían tier 3 | 0 | 13 (todos los de mutación) |
| Pureza 2D↔3D verificada por test | — | Sí (7 secciones × 9 tests de purity) |
| Tests GDScript | 34 (Fase A+B+D) | **43** (+9 nuevos Fase C) |
| Cobertura AnimationPlayer/Tree/Skeleton/Light/Audio/Camera | — | **9 tests nuevos** |

### Verificación

| Check | Resultado |
|-------|-----------|
| `cargo clippy -- -D warnings` | verde |
| `cargo test -p heren-server` | 84 unit + 28 integration = 112 verdes (race LSP pre-existente aislado) |
| Tests GDScript (`run_tests.gd`) | **43/43 verdes** (34 viejos + 9 nuevos Fase C) |
| Grafo headless | **0 SCRIPT ERROR, 0 Parse Error** |

#### Fase D — `summary` recursivo (cierra §0.1 P6) ✅ COMPLETADA (2026-09-04)

`visual_text/summary` reemplazado por snapshot **recursivo** completo (antes solo 2 niveles):

| Campo | Tipo | Notas |
|-------|------|-------|
| `node_count` | int | recursivo real (todos los descendientes) |
| `by_type` | dict | `{class_name: count}` agregado |
| `tree_depth` | int | profundidad máxima (root=1) |
| `bounds_2d` | dict | AABB escena 2D (si hay CanvasItems) |
| `bounds_3d` | dict | AABB escena 3D (si hay GeometryInstance3D) |
| `warnings` | array | heurísticas: `z_fighting_risk`, `missing_material`, `missing_texture`, `missing_shape` |
| `warning_count` | int | total warnings |

**Cambios**:
- `spatial_tool.summary(root)` — función pura + testeable.
- `visual_handlers.handle_scene_summary` ahora delega al módulo (era inline 2-niveles).
- **`validator.rs::run_engine_b` sin imagen**: ya no llama `capture_scene`. Lee TODO de `visual_summary` JSON: node_count, tree_depth, bounds_2d/3d, warnings. Sustituye el `capture_scene` que fallaba en play (§0.8 #8) y consumía 800 tok.
- `MockClient` actualizado al formato nuevo (`node_count`/`tree_depth`/`bounds_2d`/`bounds_3d`/`warnings`).

**Warnings que detecta** (heurísticas):
- `z_fighting_risk`: 2+ `GeometryInstance3D` misma posición (3D).
- `missing_material`: `MeshInstance3D` con mesh sin material_override ni material en mesh.
- `missing_texture`: `Sprite2D`/`Sprite3D` sin texture.
- `missing_shape`: `CollisionShape2D`/`CollisionShape3D` sin shape.

**Cierre**: §0.1 P6 (summary recursivo) cerrado. §0.8 bug #4 (validator sin imagen) cerrado.

#### Fase E — Eliminar `visual_image` (NO deprecar) ✅ COMPLETADA (2026-09-04)

Decisión del General: las imágenes son "puro código muerto". Eliminación total en lugar de deprecation. **Resultado**: una sola tool `visual` con 4 actions (coords/summary/ascii/spatial).

**Eliminado del server Rust**:
- `async fn visual_image(...)` (tool completo).
- `async fn capture_scene(...)` (método sin callers tras Fase D).
- Parámetro `with_image: Option<bool>` en animation (zombie §0.1).
- `__image_base64` handling en `pure.rs::unwrap_result` (test incluido).
- Comentarios sobre `visual_image` en registry.rs y ws_plugin_server.rs.

**Eliminado del plugin GDScript** (`addons/heren/handlers/visual_handlers.gd`):
- Handlers: `handle_capture`, `handle_capture_node`, `handle_preview_resource`.
- Funciones privadas: `_is_tiny_image`, `_resolve_max_side`, `_encode_image`,
  `_capture_editor_viewport`, `_render_scene_offscreen`, `_fit_camera`,
  `_apply_anim_to_clone`, `_resize_image`, `_find_animation_player`,
  `_resolve_animation_player`, `_strip_scripts`.
- Constantes: `OFFSCREEN_SIZE`, `QUALITY_PRESETS`.
- Variables: `_svp_2d`, `_svp_3d` (pool de SubViewports).
- Bloque `if bool(args.get("with_image", false)):` en
  `animation_handlers.gd::handle_preview`.

**Renombrado**:
- `visual_text` → `visual` (tool unificada, server.rs).
- Routes actualizadas: `visual/coords`, `visual/summary`, `visual/ascii`,
  `visual/spatial`, `visual/scene_summary` (alias interno).
- `visual/capture` y `visual/node` ELIMINADAS de `_routes.gd`.

**Actualizado tests**:
- `tools_parity.rs::dispatch_routes_are_in_plugin_table` — quitado
  `visual/capture` de la lista (Fase 3 §0.8 contrato: cada route usada
  internamente debe existir en `_routes.gd`).
- `validator.rs::MockClient` y `PropMockClient` — sin `capture_scene`.
- `pure.rs::unwrap_result_extracts_image_base64` — eliminado.

**Renombrado del refactor v4.6**: tras la eliminación, la fragmentación
visual_text/visual_image se desvanece — solo queda UNA tool `visual` con
4 acciones (Fase A+B+D). Filosofía "1 tool N acciones" consolidada.

### Notas operativas

- **NO** añadir `_node_coords` de vuelta en otros handlers — usar siempre `HerenCoordsScript.coords_of_node(...)`.
- **NO** hardcodear campos 2D en respuestas 3D ni viceversa — el test `_test_coords_of_node_2d_purity` / `_test_coords_of_node_3d_purity` falla si alguien rompe la pureza.
- **NO** saltar el helper `_parent_path` — calcula bien el caso `node == root` (parent = null → `""`).
- **Tests a tocar** si se cambia el contrato: `_test_coords_of_node_*` en `addons/heren/tests/run_tests.gd`.



---

## 1. Filosofía de Hierro

### 📌 Lección aprendida (descripciones de tools)

**REGLA**: descripciones de tools SOLO son genéricas para que el agente sepa QUÉ hace la tool. NO llevan fechas, NO llevan "v4.X", NO llevan "P0.X (2026-09-03)", NO llevan notas internas de desarrollo, NO llevan cambios de versión. Compactas, lo justo. Cada palabra extra en la description consume contexto del agente y confunde. Lo que el desarrollador hace se registra en AGENTS.md §0, no en el schema.

## 0.9 Plan Round-2 — Planning fixes para skeleton/animation/tree (2026-09-03)

> **Origen**: radiografía del flujo de planning detectó **13 bugs reales** entre coder y plugin. La mayoría silenciosos (commit "exitoso" pero el árbol queda inconsistente). Todos arreglados en esta ronda.

### Cambios por archivo

| Archivo | Fix | Bug |
|---------|-----|-----|
| `animation_handlers.gd` | `handle_tree_set_param` lee `param_name` (alias `name`) | **P-B1**: el coder enviaba `param_name` pero el handler leía `name` → siempre `name required` |
| `animation_handlers.gd` | `handle_tree_get_param` también acepta `param_name` (alias) | Mismo bug espejo en `get_param` |
| `animation_handlers.gd` | `handle_add_track` no concatena `:` si `property` vacío | **P-B4**: path "Node:" con dos puntos colgantes |
| `animation_handlers.gd` | **NUEVO** `handle_tree_add_blend_node` (usa `bt.add_node`) | **P-B2**: el coder emitía `tree_set_param` con dict falso |
| `animation_handlers.gd` | **NUEVO** `handle_tree_connect_blend_nodes` (usa `bt.connect_node 3-args`) | **P-B3**: emitía `set_prop connections=[...]` sobre propiedad inexistente |
| `animation_handlers.gd` | **NUEVO** `handle_tree_set_anim_player` (`tree.anim_player = NodePath`) | **P-B5**: AnimationTree huérfano sin `anim_player` |
| `skeleton_handlers.gd` | `handle_skeleton_ik` dispatch 2D/3D según `dimension` o tipo del nodo | **P-B6**: `_resolve_node(... as Skeleton3D)` fallaba con Skeleton2D |
| `coder.rs` | `AddTrack` omite `property` si está vacío | P-B4 (coder side) |
| `coder.rs` | `CreateAnimationTree` con `player_path` opcional → 2 calls (add + tree_set_anim_player) | P-B5 |
| `coder.rs` | `AddBlendNode` → `action:tree_add_blend_node` (antes `tree_set_param` fake) | P-B2 |
| `coder.rs` | `ConnectBlendNodes` → `action:tree_connect_blend_nodes` (antes `set_prop connections`) | P-B3 |
| `coder.rs` | `CreateIK` pasa `dimension` al handler | P-B6 |
| `coder.rs` | `AddNode { template }` mergea `template_params` + `properties` | **P-B13**: properties del step se ignoraban en template |
| `coder.rs` | Pre-pasada registra poses de AddNode → `SetTransform` posterior omite campos ya cubiertos | **P-M10**: `AddNode` + `SetTransform` mismo nodo duplicaba `position` |
| `coder.rs` | `AddNode` solo emite `scale` si != 1.0 | Coherencia con `position` (que se omite en 0,0,0) |
| `schemas.rs` | `CreateAnimationTree` añade `player_path: Option<String>` | P-B5 |
| `schemas.rs` | `CreateIK` añade `dimension: String` | P-B6 |
| `validator.rs` | `check_property_value` lee la propiedad REAL vía `node_query/get_prop` (no siempre `passed:true`) | **P-M3**: implementación placeholder |
| `validator.rs` | `SceneValidatorClient` trait añade `get_prop` | P-M3 |
| `server.rs` | `ValidatorClientAdapter` implementa `get_prop` (forward a `node_query/get_prop`) | P-M3 |
| `server.rs` | `validate` con `engine="b"` filtra solo Engine B (antes solo `"a"` filtraba) | **P-M7** |
| `server.rs` | `orchestrate` marca `dirty:true` solo si al menos 1 call pasó | **P-B9**: dirty=true incluso con 0 calls exitosas |

### Tests añadidos (11 nuevos)

| Test | Cubre |
|------|-------|
| `test_add_track_omits_empty_property` | P-B4 coder |
| `test_add_node_template_merges_properties` | P-B13 |
| `test_create_animation_tree_with_player` | P-B5 |
| `test_add_blend_node_uses_real_handler` | P-B2 |
| `test_connect_blend_nodes_uses_real_handler` | P-B3 |
| `test_create_ik_dimension_passed_through` | P-B6 |
| `test_add_node_then_set_transform_consolidated` | P-M10 (caso positivo) |
| `test_set_transform_different_position_emitted` | P-M10 (caso negativo: posición distinta SÍ emite) |
| `test_set_transform_no_prior_add` | P-M10 (nodo no presente en AddNode → emite set_props normal) |
| `test_property_value_reads_real_value` | P-M3 |

**Total tests: 84 verdes (49 → 59 unit + 11 + 3 + 4 + 6 + 1)**.

### Notas

- Las actions `animation/tree_add_blend_node`, `animation/tree_connect_blend_nodes`, `animation/tree_set_anim_player` son **NUEVAS** en el plugin (v4.9+). Compatibilidad hacia atrás: si el plugin es viejo, el coder emite y el plugin retorna `"tool method not found"` → el step falla con warning, el agente decide fallback a GenericStep o re-orquestrar.
- El `to_port` del step `ConnectBlendNodes` queda en el schema pero se IGNORA (Godot 4 acepta 3 args en `connect_node`). Se documenta en el step que el campo es no-op.
- `_ik_2d` no implementa IK real (no hay BoneAttachment2D en Godot 4): crea un Node2D target + sugiere usar `skeleton_fabrik` para resolver la cadena. El FABRIK real está en `handle_skeleton_fabrik` desde v4.6.

### 📌 Notas operativas (Round-2)

- **NO** renombrar `HerenSceneRegistry` ni cambiar su API en Fase 0 — Fase 1 lo hará.
- **NO** romper compat: agentes existentes siguen funcionando con los mismos tool names.
- **NO** quitar TODOS los parámetros opcionales del schema — solo los confirmados zombies. `mode`, `dry_run`, `engine`, `save`, `plan_file` SÍ tienen uso real.
- **Tests**: agregar 3 tests GDScript (`run_tests.gd`) — uno por bug arreglado (open_async, visual_scene_path, input_map_from_disk).

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
7. **VALIDACIÓN DE SCRIPTS**: Tras cualquier cambio en `.gd`, SIEMPRE validar todos los scripts del MCP con `godot_validate action=script` en el proyecto de testing (`fixtures/empty_project/`). Un parse error en un handler rompe TODO el plugin.

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

## 6. Las 18 Tools

> **Checklist añadir/quitar tool (2026-08-24)**: AÑADIR = escribir la fn `#[tool]` en server.rs (los tests estructurales de `tests/tools_parity.rs` la cubren solos). QUITAR = borrar la fn; si quieres guarda de regresión, añade el nombre a `FORBIDDEN_TOOLS`. Si la tool no sigue el patrón "1 tool N acciones", añadirla a `TOOLS_WITHOUT_ACTION`. NUNCA mantener listas enumerativas de tools — los invariantes + conteo mínimo (`MIN_TOOLS`) hacen el resto.

| # | Tool | Actions | Dominio |
|---|------|---------|---------|
| 1 | `session` | open, close, list, info, health, **diagnose** | Sesiones |
| 2 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload, **plan, orchestrate, validate, commit, status, list** (planning) | Escenas |
| 3 | `node` | add, instantiate, remove, duplicate, rename, move, set_owner, reorder | Nodos (mutaciones) |
| 3b | `node_query` | get_prop, get_info, get_children, find | Nodos (lecturas) |
| 3c | `node_props` | set_prop, set_props, array_append, array_remove | Nodos (propiedades) |
| 4 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd |
| 5 | `project` | create, setup_plugin, setting (op get/set/list/delete/set_multi + restart_required/applied_runtime), autoload, remove_autoload, input_map (persistencia REAL), shader_global | Configuración |
| 6 | `shader` | create, edit, get, inspect, validate, material, uniform, apply (one-shot) | Shaders |
| 7 | `animation` | create_player, create, add_track, add_key, state_machine, play, stop, seek, speed, get_*, remove_*, update_*, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, tree_*, duplicate, delete, rename, reverse, blend_pose, retarget | Animaciones |
| 8 | `skeleton` | skeleton_create, skeleton_add_bone, skeleton_set_rest, skeleton_skin, skeleton_attachment, skeleton_get_*, skeleton_set_pose, skeleton_ik, skeleton_fabrik, capture_pose | Esqueletos 2D/3D |
| 9 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps |
| 10 | `debug` | summary, status, breakpoint, control, stack, vars, profiler, run_scene, stop_scene, is_playing, get_editor_errors, **output** | Depuración |
| 11 | `validate` | scene, script, node, resource | Validación |
| 12 | `signal` | connect, disconnect, list, set_script | Señales |
| 13 | `visual_text` | coords, summary, ascii | Visión textual |
| 13b | `visual_image` | capture, node | Visión imagen |
| 13c | `ui` | create, layout, canvas_layer, templates, get_info, **theme** | UI 2D: Control desde template o desde cero + presets anchors + CanvasLayer + lista templates + info Control + Theme .tres |
| 14 | `health` | server + editor status | Health |

> **Batch unificado**: ya NO hay tool `orchestrate` separada. El batch se hace con `scene(action="plan", plan_file=...)` + `scene(action="orchestrate")` (continue-on-error, fallos a warnings con step_id). El flujo planning cubre steps tipados (`AddNode`, `SetTransform`, ...) y genéricos (`GenericStep` con `{tool, tool_action, args}`) verbatim.

**Notas:** `scene/create` acepta `instance_scene` (path) o `instance_current:true` (pestaña activa) → la escena nueva contiene otra como instancia ExtResource; guardas: no instanciarse a sí misma, fuente debe existir en disco. `scene/orchestrate` es continue-on-error (fallos van a warnings con su step — abortar dejaba steps aplicados sin constancia); `scene/commit` con `save=false` y dirty falla con error accionable (antes descartaba trabajo silenciosamente). `node/instantiate` = instancia EXTERNA (`instance=ExtResource`, no copia inline) **o template del registry transversal** (`template:"health_bar"`, params via `properties`). `coords proactivas` en toda mutación (§7). `animation`+`skeleton` comparten `animation_handlers.gd`. `session/diagnose` = integridad plugin (ok/stale/missing/orphan) + grafo headless en sandbox + estado editor. **v4.6 split de tools**: `node_query`/`node_props`/`visual_text`/`visual_image` = schemas MINIMALES (el server mapea al mismo handler interno `node/*`/`visual/*`). **v4.7 UI**: tool `ui` (handler `ui_handlers.gd`) + sistema transversal de templates (`template_registry.gd`, patrón `coords.gd`; templates .tscn + params por nombre de nodo canónico). Errores `node_not_found` incluyen `parent_children` (orientación). `rename`/`move` devuelven `previous_path`/`old_parent`. Recursos: pasar PATH string (`res://...`) para ext_resource; dict inline SIN path → warning `resource_incrusted_inline` (se incrustará al guardar).
**Comparativa competidores** (README "Frente a otros MCPs"): datos VERIFICADOS de `.competitors/`. NUNCA marcar ❌ capacidad que el competidor SÍ tiene; usar sus propios análisis (gopeak `ANALYSIS.md`); re-verificar contra repos al actualizar.

---

## 7. Sistema de Coordenadas (ADR-005) + Visión

### Coordenadas unificadas
Auto-detección por keys: `x`+`y`→Vector2; `x`+`y`+`z`→Vector3; `r`+`g`+`b`→Color; `origin`+`x_axis`+`y_axis`→Transform2D; `origin`+`basis`→Transform3D; `normal`+`d`→Plane; `position`+`size`→Rect2/AABB. Expansión v4: Vector2i/3i, Quaternion, StringName. `deserialize_resource` instancia por ClassDB.

### Fuente única de verdad (Fase A — §0.11)
**`HerenCoords.coords_of_node(node, parent_path, tier)`** en `addons/heren/handlers/coords.gd`. Estática, pura, testeable.
- **Discriminator** `kind` + `flags` (is_2d/is_3d/is_control/has_bbox/has_aabb)
- **Tiers** 0/1/2 (3 reservado para Fase C): mínimo → estándar → enriquecido
- **Pureza 2D ↔ 3D**: Node2D jamás trae `quat`/`basis`/`cast_shadow`; Node3D jamás trae `z_index`/`anchors`/`effective_rect`
- **Proactividad en mutaciones**: 13/13 handlers de node devuelven `coords` del nodo post-op + `scene_node_count`. Ver contrato completo en §0.11.

**Prohibido**: reimplementar `_node_coords` / `_node_pos` / `_node_bbox` / `coords_of` legacy en otros archivos. Toda lectura/escritura de coordenadas pasa por `coords_of_node`.



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
| **Multi-instancia** | ❌ `kill_previous_servers()` ELIMINADO — mataba servers de sesiones OpenCode hermanas (`MCP connection closed` + agentes sin tools). `ws_port()` cachea con OnceLock + busca `9099+N` libre → 1 puerto por instancia. **Discovery (fix 2026-09-03)**: cada server escribe `.heren/server_port.json` {port, pid}; el editor lee cada 5s y reconecta si el puerto cambia. Cleanup: `ctrlc` handler + `flojo_run_stdio` return borran el archivo. `is_process_alive` usa `tasklist /FI PID eq N` (Windows) o `kill -0` (Unix). |
| **plugin.cfg** | Formato Godot 4: `enabled=PackedStringArray("res://addons/heren/plugin.cfg")` (path completo, verificado contra `editor_node.cpp`). `"heren"` desnudo se acepta al leer pero se re-escribe completo; `PackedStringArray()` vacío = lost-update (editor vivo pisa el enable). |
| **enable idempotente** | Reemplaza CUALQUIER `enabled=` por la canónica; solo escribe si difiere + verifica. Contrato `Result<bool,String>`: Ok(true)=escribió, **Ok(false)=ya canónico = ÉXITO** (antes false → "failed" → nunca lanzaba = misterio "heren"), Err=fallo real. |
| **Sync plugin** | Incremental por contenido: solo diffs, borra huérfanos (.uid), reporta COPY FAILURES (nunca `is_ok()` silencioso). **🚨 BUG RAÍZ**: `collect_files` perdía el prefijo `handlers/` → copy contra ruta inexistente → NotFound tragado → "plugin up-to-date" MENTIRA → core nuevo + handlers viejos → SCRIPT ERROR `set_debugger_plugin` → crash. Fix: `walk(root, dir)` con root original. |
| **launch_editor** | Mata zombie PRIMERO → sleep → escribe plugin+enable → relanza (nadie pisa project.godot). No relanza si no hace falta: `reuse up-to-date` / `plugin_changed=true` → agente decide `session/reopen`. Plugin se habilita UNA vez. Godot NO tiene hot-reload de plugins (#11612). |
| **Detección editor** | `godot_processes_for`: acepta `--editor`, `--path` **o `project.godot`** en cmdline (doble clic); normaliza backslashes→`/` (`d:\...` vs `d:/...` — cmdlines reales de Windows). wmic `/format:csv`: `parts[1]=CommandLine, parts[2]=PID` (estaban invertidos → siempre vacío → editor duplicado). |
| **Versiones** | Plugin manda `plugin_version` en godot_ready (la que CORRE, no disco). `session/info` → source/installed/editor + `plugin_stale` + remedy; `session/health` → `stale_editors[]`. Reopen recarga código nuevo. |
| **Contexto escena (S3)** | `apply_scene_context` (server, por proyecto) + `_scene_root(args)`: el agente fija scene_path UNA vez. Prioridad resuelve: **pestaña real → registry → disco** (RAM=caché, disco=fuente; antes el fantasma en RAM ganaba). `normalize_scene_path` SIEMPRE (`res://`, forward, sin trailing; 8 tools + plugin defensivo). |
| **SceneRegistry (S6)** | `scene_path → root` en RAM = fuente del flujo MCP. `scene/save` = pack directo + `ensure_owner_recursive` + ResourceSaver (NUNCA `save_scene()` de pestaña). `create` abre pestaña; si falla, árbol vivo en registry (fantasma = diseño). `ensure_owner_recursive` NO baja en `scene_file_path != ""` (instancia externa). `handle_save` acepta `output_path` alias. **🚨 REDISEÑO 2026-08-15 (disco = fuente de verdad)**: el disco manda, la memoria es solo overlay del agente. Antes de CADA op sobre escena en disco, `resolve_root` hace `sync_from_disk`: si mtime del disco > registrado → recarga (reload_scene_from_path — API real Godot 4, NO `reload_scene_from_disk` que es Godot 3) + re-aplica `_pending_ops` (replay de set_prop del agente). El agente NUNCA ve el conflicto. `handle_save` sincroniza ANTES de guardar; solo reporta `replay_skipped` si hubo sync real (no falso positivo en save normal). `set_prop` verifica que el valor se aplicó (`applied_value` + `_values_match`) y registra la op en `_pending_ops`. Verificado: NodePath exports (loot_marker/steering) se conservan tras save; hand-edit del usuario (collision_mask) se conserva tras set_prop+save. **🚨 FIX 2026-08-15 (save re-embebía scripts — CAUSA RAÍZ)**: `ResourceSaver.FLAG_BUNDLE_RESOURCES` está documentado como **"Bundles external resources"** — INCORPORA los recursos externos (scripts .gd con resource_path) dentro del .tscn como `sub_resource` con `script/source`. Fix: quitarla de `handle_save` Y `_create_scene_file`. Los recursos inline sin resource_path se guardan vía `ensure_resource_local_recursive()` → `resource_local_to_scene=true` (Godot los serializa inline naturalmente). Verificado: script .gd → `ext_resource` ✅; ShaderMaterial+Shader inline → `sub_resource` con `local_to_scene` ✅. **🚨 FIX freed instance**: `get_root` hacía `root is Node` ANTES de `is_instance_valid` → CRASH "Left operand of 'is' is a previously freed instance" si la pestaña se cerró. Fix: `is_instance_valid(root)` PRIMERO (seguro con freed), luego `is Node`. **🚨 FIX prioridad save**: handle_save daba prioridad al registry (`get_root`) sobre la pestaña real → si `set_prop` cambiaba el script de la pestaña a ext_resource, save guardaba la copia STALE del registry con script embebido. Fix: handle_save usa MISMA prioridad que resolve_root (pestaña real → registry → disco). |
| **🚨 FIX 2026-08-15 (shape pierde radius — Godot #44008)** | `resource_local_to_scene=true` NO funciona con PackedScene (issue Godot #44008): el recurso se serializa como sub_resource PERO pierde sus props modificadas (CircleShape2D sin radius). Fix: quitar `ensure_resource_local_recursive` de `handle_set_prop` y de `deserialize_resource` (coords.gd). Los sub-recursos sin resource_path se serializan inline naturalmente al guardar (verificado: Shader+ShaderMaterial completos). **Nota**: "radius perdido" con radius=10 era comportamiento CORRECTO de Godot (default de `CircleShape2D.radius` = 10.0 — las props default no se serializan). radius≠default se serializa correctamente. **Gotcha**: en runtime, un script con `class_name` embebido como built-in da parse error `"class_name" isn't allowed in built-in scripts` → SIEMPRE ext_resource por path. |
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
  | **debug summary (2026-08-15)** | `debug/summary` = snapshot completo en UNA llamada: editor (scene_open, scene_name, selected_nodes) + plugin (connected) + game (is_playing, is_paused, is_breaked, breakpoint_hit, fps) + errors (runtime con stack completo + output_errors del panel) + breakpoints + profiler + console (last_lines). El agente diagnostica con 1 llamada en vez de 5. **🚨 Lección: verificar SIEMPRE que las propiedades del plugin existen antes de usarlas** — `get_session(i)` (no existe; usar `first_session()`), `has_frame_vars` (no existe; usar `vars_pending` + `last_vars`), `breaked_session_id` (no existe) causaban "Unknown error" silencioso en runtime sin error de parseo. |
  | **🚨 Scene planning v4.8 (2026-08-24)** | E2E tester encontró el flujo planning MUERTO de raíz: (1) adapters/coder reenviaban al editor con nombres MCP `godot_*` — el dispatcher del plugin rutea por prefijo BARE antes del `/` (`scene`, `node_query`, `validate`...) → "no handler for prefix: godot_scene". **Regla: forward() SIEMPRE usa nombres internos `prefijo/metodo`**; los `godot_*` solo existen del lado OpenCode. (2) `node_props` NO tiene handler en el plugin — set_props va por `node`+action `set_props`. (3) Planning integrado como sub-comandos server-side de la tool `scene` (`plan|orchestrate|validate|commit|status|list`) — NUNCA tool separada ni forward al plugin para estos. (4) `health` sin project_path devolvía `project_connected:false` fijo → ahora usa resolve_project fallback. **Lección meta: verificar con grep que las ediciones grandes REALMENTE aplicaron** — dos edits reportaron "OK" y no aplicaron (mojibake en oldString); el binario viejo siguió expuesto y un agente tester perdió su sesión completa. |
  | **🚨 Planning E2E v4 → fixes P0 (2026-08-24)** | Cuarta iteración E2E: flujo open→plan→orchestrate→commit OK pero escenas VACÍAS. (1) **P0a**: `SceneStep::AddNode` no tenía campo `properties` → serde descartaba mesh/shape/material silenciosamente. Fix: campo `properties: HashMap` passthrough VERBATIM al plugin (su deserialize_value ya convierte colores/vectores/arrays/res://); precedencia: props explícitas SOBREESCRIBEN derivados de local_pos/resource_path. (2) **P0b**: validate chequeaba contra snapshot del open (árbol vacío) → QA ciego. Fix: refresh de contexto vía load_scene_context + `registry.update_context()` ANTES de validar. (3) Workplane enum partido: serde `x_z` vs schemars `XZ` → rename explícito + alias. (4) Swap y/z silencioso en resolve_local_to_global → identidad+offset (el agente escribe coords de mundo). (5) Coder emitía position/rotation como args sueltos que node/add IGNORA → todo va dentro de properties; resource_path mapea a mesh/shape según tipo. (6) plan viaja como ARCHIVO (`plan_file`, patrón orchestrate) — inline `plan` eliminado (anyOf del schema rechazaba planes válidos); `action="plan"` sin plan_file devuelve ejemplo canónico auto-documentado. (7) orchestrate continue-on-error con step_id en warnings; dry_run preview; commit(save=false) con dirty falla accionable; validación de padres simula steps del propio plan (adiós 23 falsos positivos). **Lección: reproducir DIRECTO contra el server (health/session/scene calls) en vez de armar harnesses stdio — OpenCode ya es el harness.** |

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
- **LSP bridge: parser incremental = consumir ANTES de devolver** (lección §0.10). Si `parse_one` devuelve `Complete(body)` pero no drena `..body_end` del buffer, el loop externo `feed()` ve el mismo separator otra vez y entra en loop infinito copiando el body → OOM 6.4GB en tests. SIEMPRE drenar el frame del buffer antes de devolver.
- **LSP nativo de Godot requiere `[network] language_server/enabled=true` en `project.godot`** (no es solo pasar `--lsp-port=6005`). El bridge NO modifica el `project.godot` del usuario; el setup.md documenta la activación. Si el LSP no está habilitado, `--auto-launch-godot` falla con `LspNotEnabled` → instrucción clara al usuario.
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
- [ ] D1-D4: D1 ✅ CIM detección, D2 ✅ open espera conexión, D3 ✅ handle_vars timeout + handle_get_editor_errors EditorLog + ensure_hooked retries 10, D3-s ✅ debug/summary (snapshot completo) + fixes props inexistentes (get_session→first_session, has_frame_vars→vars_pending, breaked_session_id eliminado), pendiente tests+docs D4
- [ ] P4 track_type: documented in handler code (value/position_3d/rotation_3d/scale_3d/method/bezier/audio)
- [ ] P5 resource/create: verbose flag pending (return only changed props default)
- [ ] P6 visual/summary: M2 fixed + counting recursivo implementado
- [ ] P7 resource_incrusted_inline: soporte added en resource handlers (warning en lugar de fallo silencioso)
- [ ] P8 tool ui: implementado v4.7 (6 acciones + templates + theme)
- [ ] P9 parent_path normalization: fixed - now returns root name instead of "."
- [x] BUG GRAVE save re-embebe scripts + freed instance crash (2026-08-15): handle_save prioridad pestaña real primero (no registry stale); scene_registry is_instance_valid antes de is Node
- [x] BUG shape pierde radius (2026-08-15): resource_local_to_scene roto (Godot #44008) → quitar de handle_set_prop + deserialize_resource; radius=10 era default correcto
- [ ] P10 animation/get_animation: pending implementar acción get_animation específica
- [x] **§0.11 Spatial Proactivity — Fase A (2026-09-04)**: `coords_of_node` fuente única en `coords.gd` + 13/13 handlers devuelven `coords` + `scene_node_count` proactivos + purity 2D↔3D verificada por 9 tests GDScript.
- [x] **§0.11 Spatial Proactivity — Fase B (2026-09-04)**: `visual_text/spatial` con 5 modes (overlaps/distance/neighbors/layout/bounds) en `visual_tool/spatial_tool.gd` (funciones puras). 8 tests GDScript nuevos + AABB global en `_fill_3d` (bug colateral false-positive arreglado).
- [x] **§0.11 Spatial Proactivity — Fase C (2026-09-04)**: tier 3 dynamic state (animation, animation_tree en sinergia con AnimationPlayer, skeleton_3d con resumen 3 primeros huesos, skeleton_2d iterando Bone2D children, light_3d, audio, camera) proactivo en mutaciones + tier 4 opt-in vía `visual/coords tier=4`. 9 tests GDScript nuevos.
- [x] **§0.11 Spatial Proactivity — Fase D (2026-09-04)**: `visual_text/summary` recursivo (node_count + by_type + tree_depth + bounds_2d/3d + warnings z_fighting/material/texture/shape) + validator Engine B sin imagen (lee visual_summary JSON en vez de capture_scene). 7 tests GDScript nuevos.
- [x] **§0.11 Spatial Proactivity — Fase E (2026-09-04)**: ELIMINACIÓN total de `visual_image` (no deprecation) + rename `visual_text` → `visual` → UNA tool unificada con 4 actions (coords/summary/ascii/spatial). `with_image` zombie de §0.1 también eliminado. Ver §0.11.

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
