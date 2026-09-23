# Changelog — Heren MCP

> **Política de versiones**: `[X.Y.Z]` se publica al cortar un release público
> (binarios en `bin/` + tag `vX.Y.Z` en git). Las iteraciones intermedias
> `[4.9]`–`[4.14]` y los `[Unreleased]` debajo son commits en `main` sin release;
> se consolidan en el siguiente `[X.Y.Z]` que cortemos. **Actual**: `[5.0.0]`
> consolida todo el trabajo de Worker-First (W4) + inspect (W4b) + fix del path
> del archivo + unificación de versiones.

---

## [5.0.0] - 2026-09-22 - 🐉 Worker-First · inspect proactivo · fix archive

**Breaking changes** (no es patch — es release mayor):

- 📦 **Toolset: 19 → 15 tools**. Las tools que el agente rara vez invocaba directamente
  (`animation/tree_*`, `animation/capture_pose|blend_pose|retarget`, `skeleton/*`,
  `tilemap/*`, `ui/layout`, `ui/theme`, `shader/material|uniform|apply`,
  `node/reorder|move|set_owner`, `signal/set_script`) **fueron archivadas** a
  `archived_handlers/gd_source/` (código muerto histórico, no se compila). El worker
  las reemplaza con ~10 líneas de GDScript en vez de un handler + schema + dispatcher.
- 🚫 **`session/*` tool ELIMINADA** (ADR-004). El editor conectado **es** la sesión.
  Sin `session/open|close|info|status|list|diagnose|reopen`. El primer tool call con
  `project_path` paga el auto-launch si hace falta; los siguientes son ~20ms.
- ✨ **Nueva tool centralizada** `scene_script` con **3 actions**: `run`, `list`, **`inspect`**.
  Es el reemplazo de las tools archivadas: el agente escribe workers GDScript contra
  la API real de Godot con red transaccional (parse-check previo + snapshot +
  save solo si `ctx.mark_modified()` + restore en fallo).
- 🔢 Versión canónica unificada a `5.0.0` en `plugin.cfg`, `Cargo.toml` workspace,
  `crates/heren-server/Cargo.toml`, `README.md`, `README.en.md`, `AGENTS.md`.

### ✨ Worker-First (W4) — el corazón de v5.0

- El agente escribe un worker GDScript completo (`@tool` · `extends RefCounted` ·
  `func run(ctx) -> void`) y nosotros lo ejecutamos contra la escena viva con red de
  seguridad transaccional.
- **API `ctx`**: `own/instance_scene/template/get_node_or_null/find_nodes_by_name/
  ensure_unique_child_name/remove_node/clear_children/coords/log/error/
  mark_modified/output/snapshot_subtree`. Rechaza mutaciones en modo `inspect`.
- **Garantías por capas (no sandbox real — convención documentada + transaccionalidad)**:
  parse-check previo · save transaccional (`ctx.mark_modified()` requerido) ·
  ownership helpers (owner incorrecto de internals PackedScene = RECHAZADO) ·
  límites de dominio (`.glb`/import → tool aparte) · graph detached ≠ Run Scene.
- **Worker reutilizable por path**: la primera vez va `code=...`, los reintentos
  van `script_path=...` (parcheo el mismo archivo con `resource/edit_script`).
- **Contrato de errores**: `ran:false` significa que el worker falló (ver `error`)
  pero la tool tuvo éxito. La escena original está intacta. Iteras parcheando el
  `script_path` devuelto. `ok:false` queda reservado para fallos de infraestructura
  (sin editor, etc.).

### ✨ W4b · `scene_script/inspect` — vista READ-ONLY sin ejecutar worker

- **Problema**: con W4 el agente escribe workers ciegos — 1 round-trip por insight
  (escribe worker → ejecuta → recibe `changes`+`coords` → itera).
- **Solución**: nueva action `inspect` que carga la escena detached (read-only) y
  devuelve árbol + agregados (skeleton bones, animations, materials, lights, audio,
  cameras, tilemaps) en 1 call sin ejecutar código.
- **Args**: `scene_path` (default = edited root), `tier` (default 1), `depth`
  (default -1 ilimitado), `expand_scene` (default `[]`).
- **Decisiones del General**: tier 1 por defecto (no 2); PackedScene instanciadas
  son opacas por defecto con opt-in `expand_scene=[...]`.
- **Output**: `root` (coord + `children` recursivo) · `opaque_packed_scenes`
  (relpaths opacos) · `aggregates` (9 secciones cruzadas) · `scene_node_count`.
- **Lección meta**: el root de una PackedScene tiene `scene_file_path = path de la
  propia escena` — el walk inicial lo marcaba como opaco y nunca entraba a sus hijos.
  Fix: parámetro `is_root` en `_inspect_walk` que exenta la raíz del check de
  opacidad.

### ✨ Receipt post-worker proactivo (W4b)

- **Problema**: el receipt de `handle_run` solo traía `touched` (tier 1) + `root`
  coords. El agente tenía que re-inspeccionar la escena tras cada worker.
- **Solución**:
  - `coords.aggregates` (skeleton bones, animations, animation_trees, materials,
    lights, audios, cameras, tilemaps) reusando `_inspect_aggregates` — un motor,
    dos consumidores.
  - **Tier dinámico**: si el worker tocó un nodo con estado dinámico (`Skeleton3D`,
    `Skeleton2D`, `AnimationPlayer`, `AnimationTree`, `Light3D`, audio, camera),
    el tier efectivo del receipt sube automáticamente a 3 → el agente ve el árbol
    dinámico resultante SIN re-inspect. `_touched_dynamic(ctx)` decide.
  - `ctx.snapshot_subtree(path, tier)` — el worker puede adjuntar al receipt un
    subárbol específico. Coste acotado al subárbol. Rechaza en read-only.
- **Convención unificada de paths**: `_relpath` ahora usa `./X/Y/Z` consistente
  con `_inspect_walk` (antes había DOS formatos incompatibles → el agente veía
  paths distintos en `changes.added[]` vs `inspect.tree`). Root → `"."`. Huérfanos
  → nombre plano.
- **Files**: `addons/heren/handlers/scene_script.gd`, `addons/heren/tests/run_tests.gd`.

### 🐛 Bug crítico: `archive/` rompía la compilación del plugin al arrancar

- **Síntoma**: 7 parse errors en `addons/heren/archive/handlers/*.gd` al abrir
  cualquier proyecto con Heren MCP: `_undo_redo is not a function`,
  `_assign_material not found`, `_container_layout_warning not found`,
  `coords.gd preload does not exist`, etc.
- **Causa raíz**: los 7 handlers archivados de v3 vivían en `addons/heren/archive/handlers/`
  — **DENTRO del directorio que escanea Godot**. Cada vez que el editor arrancaba,
  intentaba compilarlos (parse errors garantizados por diseño). **Un parse error
  en CUALQUIER archivo del addon rompe TODO el grafo** (§3.7, §11).
- **Fix**: `git mv addons/heren/archive/ → archived_handlers/gd_source/` (raíz del
  repo, FUERA de `addons/`). Godot ya no los escanea. Fixture también borrado
  (era código derivado, no fuente).
- **Compatibilidad**: los handlers siguen siendo `.gd` (preservan highlighting)
  pero son código muerto histórico.

### 🧪 Tests v5.0

- **GDScript**: 77 passed, 0 failed (era 72 antes de W4b).
- **Rust**: 85 passed, 0 failed. Cargo tools_parity: 7/7 pass.
- **Compile headless**: 0 parse errors.
- **Plugin cargado limpio**: el bug del archivo se erradicó.

### 🔧 Sistema de versiones

- `plugin.cfg`: `4.4.2` → **`5.0.0`** (lo que el editor Godot muestra al usuario).
- `Cargo.toml` workspace: `0.1.0` → **`5.0.0`**.
- `crates/heren-server/Cargo.toml` description: `v4` → **`v5.0`**.
- `README.md` / `README.en.md`: `v4.9` → **`v5.0`** (8 refs cada uno).
- `AGENTS.md`: `ESTADO: v4.9` → **`v5.0`**; `Cambios nuevos → v4/Rust` → **`v5/Rust`**;
  `18 tools` → **`15 tools (19 → 15 en v5.0 W4 cleanup)`**.
- Comentarios internos en `addons/heren/*` y `fixtures/...`: 8 menciones `v4.9` → `v5.0`.
- `CONTRIBUTING.md` plantilla de bug-report: `Versión Heren MCP: 4.6.0` → **`5.0.0`**.

---

## [Unreleased] - 2026-09-22 - W4b inspect + fix archive/ rompe plugin

### ✨ W4b: `scene_script/inspect` — vista READ-ONLY sin ejecutar worker
- **Problema**: con W4 el agente escribe workers GDScript ciegos — 1 round-trip por insight (escribe worker → ejecuta → recibe `changes`+`coords` → itera).
- **Solución**: nueva action `inspect` que carga la escena detached (read-only) y devuelve árbol + agregados (skeleton bones, animations, materials, lights, audio, cameras, tilemaps) en 1 call sin ejecutar código.
- **Args**: `scene_path` (default = edited root), `tier` (default 1), `depth` (default -1 ilimitado), `expand_scene` (default `[]`).
- **Decisiones del General**: tier 1 por defecto (no 2); PackedScene instanciadas son opacas por defecto con opt-in `expand_scene=[...]`.
- **Output**:
  - `root` — coord + `children` recursivo.
  - `opaque_packed_scenes` — relpaths de sub-escenas no expandidas.
  - `aggregates` — `skeletons_3d`, `skeletons_2d`, `animations`, `animation_trees`, `materials`, `lights`, `audios`, `cameras`, `tilemaps`.
  - `scene_node_count` — total recursivo.
- **Files**: `addons/heren/handlers/scene_script.gd`, `addons/heren/_routes.gd`, `crates/heren-server/src/server.rs`, `crates/heren-server/tests/tools_parity.rs`, `addons/heren/tests/run_tests.gd` (+3 tests).
- **Tests**: 75 passed, 0 failed (era 72). Cargo tools_parity: 7/7 pass.

### 🐛 Bug crítico: `archive/` rompía la compilación del plugin al arrancar
- **Síntoma**: al abrir cualquier proyecto con Heren MCP, el log del editor mostraba 7 parse errors en `addons/heren/archive/handlers/*.gd`:
  - `Parse Error: Member "_undo_redo" is not a function` (node_movement_handlers.gd)
  - `Parse Error: Function "_assign_material()" not found in base self` (shader_ops_handlers.gd)
  - `Preload file "res://addons/heren/archive/handlers/coords.gd" does not exist` (tilemap_handlers.gd)
  - `Parse Error: Function "_container_layout_warning()" not found in base self` (ui_layout_theme_handlers.gd)
  - etc.
- **Causa raíz**: los 7 handlers archivados de v3 vivían en `addons/heren/archive/handlers/` — DENTRO del directorio que escanea Godot. Cada vez que el editor arrancaba, intentaba compilarlos (dependen de APIs v3 que ya no existen → parse errors garantizados por diseño). **Un parse error en CUALQUIER archivo del addon rompe TODO el grafo** (§3.7, §11) → el plugin no cargaba.
- **Fix**: `git mv addons/heren/archive/ → archived_handlers/gd_source/` (raíz del repo, FUERA de `addons/`). Godot ya no los escanea. Fixture `fixtures/empty_project/addons/heren/archive/` también borrado (era código derivado, no fuente).
- **Compatibilidad**: los handlers siguen siendo `.gd` (preservan highlighting) pero son código muerto histórico — si alguien los compila, fallará. Documentado en `archived_handlers/gd_source/handlers/README.md`.
- **Lección meta**: el §3.7 + §11 advertían sobre "un parse error rompe todo el plugin", pero el validador (`validate_plugin.bat`) NO detectaba este caso porque estaba enfocado en handlers ACTIVOS. Reforzar el `validate_plugin.bat` para que también intente compilar el directorio archivado (debe fallar A PROPÓSITO) — pendiente.

### ✨ Receipt post-worker proactivo (W4b)
- **Problema**: el receipt de `handle_run` solo traía `touched` (tier 1) + `root` coords. El agente tenía que re-inspeccionar la escena tras cada worker para saber QUÉ quedó.
- **Solución**:
  - `coords.aggregates` (skeleton bones, animations, animation_trees, materials, lights, audios, cameras, tilemaps) reusando `_inspect_aggregates` — un motor, dos consumidores.
  - **Tier dinámico**: si el worker tocó un nodo con estado dinámico (Skeleton3D, Skeleton2D, AnimationPlayer, AnimationTree, Light3D, audio, camera), el tier efectivo del receipt sube automáticamente a 3 → el agente ve el árbol dinámico resultante SIN re-inspect. `_touched_dynamic(ctx)` decide.
  - `ctx.snapshot_subtree(path, tier)` — el worker puede adjuntar al receipt un subárbol específico (ej. "así quedó el personaje"). El receipt lo devuelve en `coords.subtrees[]`. Coste acotado al subárbol. Rechaza en read-only.
- **Convención unificada de paths**: antes había DOS formatos incompatibles (`_inspect_walk` → `./X/Y/Z`, `ctx._relpath` → `/X/Y/Z`). El agente veía paths distintos en `changes.added[]` vs `inspect.tree`. **Fix**: `_relpath` ahora usa `./X/Y/Z` consistente con `_inspect_walk`. Root → `"."`. Huérfanos → nombre plano.
- **Files**: `addons/heren/handlers/scene_script.gd` (`_receipt_coords` reescrito, `_touched_dynamic` nuevo, `WorkerCtx.snapshot_subtree`), `addons/heren/tests/run_tests.gd` (+2 tests, 1 modificado).
- **Tests**: 77 passed, 0 failed (era 75). Cargo build OK.

## [Unreleased] - 2026-09-18 - Fix: discovery file solo en project_path real

### 🐛 Bug: `.heren` se creaba en CWD aunque no fuera proyecto Godot
- **Síntoma**: al arrancar `heren-server.exe` desde cualquier directorio, se creaba `.heren/server_port.json` en el CWD — incluso si no había proyecto Godot allí.
- **Causa**: `run()` escribía discovery en `std::env::current_dir()` antes de saber qué proyecto se usaría.
- **Fix**: mover escritura de discovery a `ensure_editor_connected` (que recibe `project_path` real). El server ya no crea `.heren` en directorios no-Godot al arrancar.
- **Files**: `crates/heren-server/src/server.rs`, `crates/heren-server/src/discovery.rs`.

---

## [Unreleased] - 2026-09-10 - W4-c validador maduró + 2 bugs pre-existentes críticos

### ✨ W4-c: static analyzer inline en `validate/script` (fix-loop 3→2 calls)
- `heren_handler.gd`: nuevos statics `static_analyze_gdscript(source)` y
  `script_diagnostics(path)` (DRY — reemplaza al local `_script_diagnostics` de
  resource_handlers.gd).
- **13 reglas** heurísticas con `confidence:high|medium`:
  - **high**: `tabs_and_spaces_mixed`, `unbalanced_parens/brackets/braces`,
    `unterminated_string`, `unterminated_triple_string`, `export_on_const`,
    `await_stuck_to_identifier`, `shadow_builtin_var`, `class_name_duplicate_in_file`
  - **medium**: `missing_colon_after_func_def`, `missing_colon_after_keyword`,
    `await_at_top_level` (placeholder — desactivado en v1)
- Schema unificado:
  - Roto: `{valid:false, reload_err:43, parse_hints:[{rule,line,col,message,confidence}], hint}`
  - Válido: `{valid:true, reload_err:0, can_instance:bool, warnings:[...]}`
- `validate/script` y `validate/scripts` ahora devuelven `parse_hints` inline.
  El fix-loop baja de **3 calls (validate → debug/output → fix) a 2** (validate
  con hints → fix).
- 17 tests nuevos: 1 regresión NodePath, 14 reglas W4-c, 2 unified shape.

### 🐛 Bug pre-existente crítico: 5 helpers perdidos en `shader_handlers.gd`
- **Causa**: el W4 cleanup archivó `shader_ops_handlers.gd` pero dejó los CALLERS
  `_shader_structural_issues`, `_parse_shader_type`, `_shader_uniforms_to_json`,
  `_find_shader_material`, `_mode_to_str` (más `_uniform_type_str`, `_hint_str`).
- **Efecto**: `shader/validate`, `shader/inspect`, `shader/get` crasheaban al
  compilar el plugin. SCRIPT ERROR desde 2026-09-09 — **detectado por el
  headless compile check del validador nuevo** (W4-c fue lo que lo expuso).
- **Fix**: restaurados desde commit `0728708` (8 funciones, ~80 líneas).
- **Lección meta**: el `validate/scripts` que ya teníamos ESTE handler como
  roto y NO lo sabíamos. W4-c + el script `validate_plugin.bat` son la red
  de seguridad que faltaba.

### 🐛 Bug runtime: `NodePath == String` crashea en GDScript 4.5+
- **Síntoma**: `node/set_props` con `skeleton_path: "Physical..."` (o cualquier
  NodePath string) → "Invalid operands 'NodePath' and 'String' in operator '=='"
  en `node_handlers.gd:372` → handler crashea → respuesta malformada → el
  MCP cliente intenta parsear y falla con "Parse JSON failed: got 'Physical'".
- **Fix**: `_values_match` coerce `NodePath↔String` antes de `==`.
- Regresión: `_test_nodepath_string_coerce`.

### 🐛 Bug UX: `no handler for prefix` sin diagnóstico
- **Síntoma**: agente llama `godot_scene_script` (registrada en server.rs) →
  plugin devuelve `{"ok":false,"error":"no handler for prefix: scene_script"}`.
  El usuario no sabe si es bug MCP, bug de routing, o plugin desactualizado.
- **Causa típica**: el plugin del proyecto del usuario fue instalado con
  `install_plugin.py` SIN `--force` → el source del plugin quedó viejo (sin
  `scene_script_handlers`). El server Rust SÍ conoce `scene_script` (rebuilt),
  el plugin NO. Mismatch de versiones.
- **Fix**: el dispatcher ahora devuelve `error` con la lista de prefixes
  registrados + `hint` accionable: "install_plugin.py --force + reinicia Godot
  (no hay hot-reload de plugins — Godot issue #11612)".
- Regresión: `_test_dispatcher_unknown_prefix`.

### ✨ Auto-reload del plugin (W5 §0.13, fix 2026-09-10)
- **Problema**: `ensure_editor_connected` tenía fast-path SI el editor ya estaba
  conectado → plugin stale en RAM, agent trabaja con código viejo. El sync a
  disco (`ensure_plugin_installed`) solo corría en `launch_editor` (cuando NO
  había editor). Resultado: editabas `addons/heren/*` → recompilabas server →
  `cargo build` no tocaba nada en el editor abierto → `godot_scene_script`
  fallaba con "no handler for prefix".
- **Síntoma reportado**: agente llamó `godot_scene_script` → MCP devolvió
  `-32603: no handler for prefix: scene_script`. La herramienta estaba en el
  schema del server pero NO en el plugin del proyecto del usuario.
- **Fix**: `ensure_editor_connected` ahora SIEMPRE corre `ensure_plugin_installed`
  PRIMERO (content-aware sync, barato si no hay cambios). Si el editor YA está
  conectado pero el plugin cambió en disco → mata editor + espera kill +
  re-lanza con código nuevo. El agente solo tiene que RETRY la tool call.
- **Mecánica**: `close_editor` (taskkill) + poll `is_editor_running` hasta
  `EDITOR_KILL_WAIT_MS * 2` (3s) + call `launch_editor` (que re-escribe
  `project.godot` con `enable_plugin_in_project` antes de spawn).
- **Mensaje legacy borrado**: `launch_editor` ya no dice "ejecuta
  session/reopen" (tool eliminada en §0.5). Ahora: "Auto-reload will restart
  the editor on the next tool call".
- **Limitación documentada**: si la escena tiene cambios sin guardar (dirty),
  el agente los PIERDE al matar el editor. Para uso personal aceptable.
- Tests Rust: `ensure_plugin_installed_is_idempotent` (idempotencia del sync).
- Validación: `cargo test -p heren-server` → 113/113 passed.
- Validación GDScript: `run_tests.gd` → 72/72 passed.

### 📦 `install_plugin.py` ahora es content-aware
- Por defecto solo chequea EXISTENCIA → "ya instalado" aunque los archivos
  hayan cambiado.
- Con `--force` (alias del futuro `--content-aware`): diff real de bytes,
  copia solo lo que cambió, elimina archivos extra en dst (ej. `.uid`
  regenerados por Godot).
- `--dry-run` muestra el diff sin tocar disco.

### 🆕 Script `scripts/validate_plugin.bat` (el "actualizador" honesto)
- Ejecuta los 4 pasos OBLIGATORIOS de AGENTS.md §3.7 en 1 comando:
  1. Sync fixtures (addons/heren → fixtures/empty_project/addons/heren)
  2. Headless compile check (`godot --headless --editor --quit-after 5`)
     → grep SCRIPT ERROR / Parse Error / Compile Error = 0
  3. Test suite (`godot --headless --script res://addons/heren/tests/run_tests.gd`)
  4. (opcional) `cargo build -p heren-server`
- Sale con código 1 si CUALQUIER paso falla. Antes esto era flujo manual de
  3-4 comandos.

### 📊 Resultado de validación
- **0 parse errors** en el grafo del plugin.
- **71/71 tests passed** (67 originales + 4 nuevos: Bug NodePath + 3 W4-c
  que se añadieron en la segunda iteración).
- 17 tests W4-c cubren las 13 reglas heurísticas + 2 unified shape + 1
  regresión + 1 sanity (no false positives en código válido).

### 📌 Lecciones
- **El validador ES la red de seguridad**: sin el headless compile check,
  el bug de `shader_handlers.gd` pudo vivir semanas. Era exactamente el
  tipo de regresión que la §0.13 (W4-c) iba a prevenir.
- **`install_plugin.py` sin `--force` es engañoso**: dice "ya instalado"
  pero los archivos pueden estar desactualizados. El comportamiento por
  defecto se preserva por compatibilidad, pero `--force` es lo correcto
  para iterar.
- **`run_tests.gd` no detecta parse errors del plugin graph** — solo
  ejecuta helpers puros. El compile check headless es la única red de
  seguridad real para "el plugin CARGA?". W4-c más `validate_plugin.bat`
  cierran ese gap.

## [Unreleased] - 2026-09-05 - debug runtime_errors + validate/scripts (compilador del editor)

### 🐛 Fix: plugin no cargaba (`Nonexistent function 'new' in base 'GDScript'` en editor_plugin.gd:92)
- Causa raíz: `debug_handlers.gd` L342 `var count := _dbg_plugin.last_output_errors.size()` —
  `last_output_errors` es Variant (sin tipo en el debugger plugin) → `.size()` retorna Variant →
  **"Cannot infer the type"** = parse error → `preload()` devuelve GDScript en estado de error → `.new()` falla.
- Fix: `var count: int = ...` (tipo explícito). Verificado con grafo headless: 0 SCRIPT ERROR.

### 🐛 Fix: `validate/script` mentía `valid:true` para scripts rotos
- `load()` de un .gd con errores **NO retorna null** en Godot 4.5: devuelve el GDScript en estado
  de error (verificado empíricamente: `load_null=false, can_instance=false, reload_err=43`).
- Fix: `handle_script` ahora hace `gdscript.reload()` → `ERR_PARSE_ERROR (43)` si el análisis
  falla → retorna `ok:false, valid:false, reload_err` en vez de `ok:true` hardcodeado.

### ✨ Nuevo: `validate/scripts` — validación BULK con el compilador del editor
- Recorre todos los `.gd` bajo `dir` (default `res://`), `load()` + `reload()` cada uno.
- `reload()` ES el analyzer del editor → mismo veredicto que el editor.
- Devuelve `{ok, checked, broken_count, broken:[{path, reload_err}]}`; los mensajes humanos
  ("Cannot infer...") caen al EditorLog → `debug/output filter=error`.
- Salta `res://addons/heren/` (auto-reload del plugin vivo es riesgoso; los handlers del plugin
  se validan con grafo headless + run_tests.gd).
- Schema: `validate(action, dir)` — nuevo param `dir`.

### 📌 Lección
- `--check-only --script` en Godot 4.5 **SÍ detecta** "Cannot infer" (nota vieja de §12 era incorrecta).
- Regla reforzada en AGENTS.md §3: tras CUALQUIER cambio .gd → grafo headless + run_tests.gd.

## [Unreleased] - 2026-09-04 - Fase C (tier 3 dynamic state: animation/skeleton/light/audio/camera)

### 🆕 Tier 3 dynamic state (Fase C, §0.11)

**Decisión del General**: tier 3 = resumen proactivo (lo devuelven TODAS
las mutaciones); tier 4 = completo opt-in vía `tier=4` en `visual/coords`.
**AnimationTree entra en sinergia con AnimationPlayer** — siempre van
juntos, el tree lleva coords del player del que se nutre (snapshot).

**7 secciones opt-in por nodo** (cada una SOLO si aplica al nodo):
1. `animation` (AnimationPlayer) — current/position/playing/speed/autoplay/length
2. `animation_tree` (AnimationTree) — active, anim_player_path, tree_root_type,
   current_state (si StateMachine), **anim_player_state snapshot del player**
3. `skeleton_3d` (Skeleton3D) — bone_count + bone_names + 3 primeras poses (tier 3)
   o TODAS (tier 4) + motion_scale + show_rest_only
4. `skeleton_2d` (Skeleton2D) — bone_count + lista resumida (iterando
   recursivamente Bone2D children — robusto en headless)
5. `light_3d` (Omni/Spot/DirectionalLight3D) — type + color + energy +
   indirect_energy + range (omni) o spot_range+spot_angle
6. `audio` (AudioStreamPlayer/2D/3D) — type + playing + volume_db +
   pitch_scale + bus + stream + max_distance (3D)
7. `camera` (Camera2D/3D) — type + fov/zoom + near/far + current (3D only)

**API expuesta**:
- Tool `visual` con `tier`: `visual(coords, tier=3)` (resumen) / `tier=4`
  (completo) / `tier=1` (default = mapa visual barato, comportamiento actual).
- **Mutaciones proactivas** devuelven tier 3 desde `_node_coords()`.
- Tier 4 SOLO opt-in vía `visual(coords, tier=4)`.

**Pureza verificada** (9 tests GDScript nuevos): AnimationPlayer NUNCA
emite animation_tree/skeleton_*/light_3d/audio/camera. Cada categoría es
opt-in por nodo.

**Bugs colaterales arreglados**:
- `AnimationTree.anim_player_state`: antes usaba `get_edited_scene_root()`
  (null en runtime). Ahora `tree.get_node_or_null(tree.anim_player)` con
  NodePath RELATIVO — resuelve correctamente.
- `Skeleton2D.get_bone_count()` async en headless. Reemplazado por
  iteración recursiva `Bone2D` children — funciona antes del primer frame.
- `Light3D` NO tiene `light_enabled` property (verificado con
  `get_property_list()`). Se omitió del summary.

**Verificación**:
- 43/43 GDScript verdes (34 viejos + 9 nuevos Fase C).
- 84 Rust unit tests + 28 integration = 112 verdes (race LSP pre-existente).
- `cargo clippy -- -D warnings` verde.
- Grafo headless sin SCRIPT/Parse Error.

**Decisiones técnicas**:
- `flags.has_dynamic_state` global = true si alguna sección se emitió.
- Cada sección NO se emite si no aplica (no null, no {}).
- Si TODAS las secciones están vacías, NO se emite el bloque `dynamic`
  (ahorra ~30 tok por nodo no-dinámico).
- Sinergia AnimationTree↔AnimationPlayer: el tree resuelve el NodePath del
  player y lo snapshottea — el agente ve TODO lo que se está animando desde
  un solo call.

**Resultado neto**: +260 LOC en `coords.gd` (7 helpers + dynamic block) +
+25 LOC en `server.rs` (param tier) + 9 tests = sistema de coordenadas
proactivo completo (tiers 1/2/3 + tier 4 opt-in).

## [Unreleased] - 2026-09-04 - Limpieza Fase E (visual_image ELIMINADO, visual_text → visual)

### 🧹 Eliminación total de `visual_image` + unificación `visual`

**Decisión del General**: las imágenes son "puro código muerto" — no se
deprecan, se ELIMINAN. La fragmentación v4.6 (visual_text + visual_image)
se desvanece: queda UNA sola tool `visual` con 4 actions.

**Eliminado del server Rust**:
- `async fn visual_image(...)` (tool completo).
- `async fn capture_scene(...)` (sin callers desde Fase D).
- Parámetro `with_image` en animation tool (zombie §0.1).
- `__image_base64` handling en `pure.rs::unwrap_result` + test.

**Eliminado del plugin GDScript**:
- Handlers: `handle_capture`, `handle_capture_node`, `handle_preview_resource`.
- Funciones privadas: `_is_tiny_image`, `_resolve_max_side`, `_encode_image`,
  `_capture_editor_viewport`, `_render_scene_offscreen`, `_fit_camera`,
  `_apply_anim_to_clone`, `_resize_image`, `_find_animation_player`,
  `_resolve_animation_player`, `_strip_scripts`.
- Constantes: `OFFSCREEN_SIZE`, `QUALITY_PRESETS`.
- Variables: `_svp_2d`, `_svp_3d` (SubViewport pool).
- Bloque `with_image` en `animation_handlers.handle_preview`.
- Routes `visual/capture`, `visual/node` eliminadas.

**Renombrado**:
- `visual_text` → `visual` (tool unificada en server.rs).
- Mantiene 4 actions: `coords|summary|ascii|spatial` (todas JSON puro).
- Routes internas: `visual/coords`, `visual/summary`, `visual/ascii`,
  `visual/spatial`, `visual/scene_summary` (alias usado por validator).

**Tests**:
- `tools_parity.rs::dispatch_routes` actualizado (sin `visual/capture`).
- `validator.rs::MockClient` y `PropMockClient` sin `capture_scene`.
- `pure.rs` test `unwrap_result_extracts_image_base64` eliminado.

**Verificación**:
- 34/34 GDScript verdes (sin cambios).
- 112 Rust tests verdes (sin regresiones).
- `cargo clippy -- -D warnings` verde.
- Grafo headless sin SCRIPT/Parse Error.

**Resultado neto**: -440 líneas de código muerto eliminado. La tool `visual`
consolida coords/summary/ascii/spatial en una sola API limpia.

## [Unreleased] - 2026-09-04 - Spatial Proactivity Fase D (summary recursivo + validator sin imagen)

### 🧭 summary — snapshot recursivo + validator Engine B sin imagen

**Problema**: `visual_text/summary` solo contaba 2 niveles (root + 1) — info
incompleta. `validator.rs::run_engine_b` dependía de `capture_scene` (imagen
base64) que falla durante play (§0.8 #8) y consume 800 tok.

**Solución** (Fase D de §0.11):
- `spatial_tool.summary(root)` — función pura + testeable que devuelve:
  - `node_count` (recursivo), `by_type` (agregado por class_name),
    `tree_depth`, `bounds_2d`, `bounds_3d`, `warnings`.
- Warnings heurísticas: `z_fighting_risk`, `missing_material`,
  `missing_texture`, `missing_shape`.
- `visual_handlers.handle_scene_summary` delega al módulo (reemplaza inline).
- **`validator.rs::run_engine_b` sin imagen**: lee TODO de `visual_summary`
  JSON (node_count vs context, tree_depth, bounds, warnings). Sustituye
  `capture_scene`. El validator ya no requiere render GPU off-screen.
- `MockClient` (tests) actualizado al formato nuevo.

**Cierra**:
- §0.1 P6 (`visual/summary` recursivo).
- §0.8 bug #4 (validator sin imagen).

**Tests**: 7 nuevos en `run_tests.gd` (recursive count, tree_depth, by_type,
bounds 2D/3D, z_fighting warning, missing_material, missing_texture).
34/34 GDScript verdes, 113 Rust verdes, clippy verde, grafo headless sin
parse errors.

## [Unreleased] - 2026-09-04 - Spatial Proactivity Fase B (visual_text/spatial)

### 🧭 spatial_tool — 5 modes para validación geométrica sin imagen

**Problema**: el agente quería verificar overlaps/distancia/layout de UI pero
`visual_image/capture` falla durante play (§0.8 #8), consume 200-800 tok y el
modelo no razona bien sobre PNGs renderizados.

**Solución** (Fase B de §0.11):
- Nuevo `addons/heren/handlers/visual_tool/spatial_tool.gd` (clase
  `HerenSpatialTool`, funciones estáticas puras + testeables).
- Nueva action `spatial` en `visual_text` con 5 modes:
  - `overlaps(node_path, padding)` → nodos cuya bbox/aabb intersecta
  - `distance(from, to)` → vector + magnitud entre dos puntos/nodos
  - `neighbors(of, radius)` → nodos dentro de un radio
  - `layout(node_path)` → Control effective_rect + Container padding
  - `bounds(of=".")` → AABB total escena (2D + 3D separadas)

**Bugs colaterales arreglados**:
- `_fill_3d` ahora devuelve AABB transformada (`transform` local o
  `global_transform` según `is_inside_tree()`) — antes retornaba `get_aabb()`
  LOCAL sin transformar, false-positive en overlaps 3D.
- `_relpath` no usa `get_path()` (requiere SceneTree) — construido manualmente
  con parent chain. Funciona con nodos detached.

**Tests**: 8 nuevos en `run_tests.gd` (overlaps 2D encuentra/excluye self,
overlaps 3D, distance, neighbors, layout Control, bounds, unknown mode).
27/27 GDScript verdes, 113 Rust verdes, clippy verde, grafo headless sin
parse errors. `cargo build --release` falla por binario bloqueado (no
relacionado con Fase B).

**Coste típico**: 50-200 tok por llamada. Reemplaza la necesidad de
captura de imagen para validación geométrica.

## [Unreleased] - 2026-09-04 - Spatial Proactivity Fase A

### 🧭 coords_of_node — fuente única de verdad

**Problema**: el sistema de coordenadas estaba disperso en 4 funciones
(`_node_coords`, `_node_pos`, `_node_bbox`, `coords_of`) con campos solapados
y comportamiento inconsistente. 9/13 handlers de mutación NO devolvían coords
— el agente quedaba ciego tras `set_props` batch / `move` / `duplicate` /
`rename` / `set_owner` / `reorder` / `array_*` / `set_script`.

**Solución** (Fase A de §0.11):
- Nueva `HerenCoords.coords_of_node(node, parent_path, tier)` en
  `addons/heren/handlers/coords.gd` — estática, pura, testeable, **única fuente**.
- **Discriminator** `kind` (clase Godot) + `flags` (capacidades).
- **Tiers** 0/1/2/3 — el agente pide solo lo que necesita (30/150/250 tok).
- **Pureza 2D ↔ 3D**: Node2D jamás trae `quat`/`basis`/`cast_shadow`; Node3D
  jamás trae `z_index`/`anchors`/`effective_rect`.
- 13/13 mutaciones ahora devuelven `coords` + `scene_node_count` proactivos.
- Eliminadas las 4 funciones duplicadas (`_node_coords` 118 líneas inlined,
  `_node_pos`, `_node_bbox`, `coords_of` legacy).

**Bugs colaterales arreglados**:
- `template_registry._apply_params` ya no llama `deserialize_value` con strings
  opacos (parse error en Godot 4.5).
- Coords globales con `is_inside_tree()` guard — sin warnings al usar nodos
  sin parent.
- Accesos defensivos `"prop" in node` para tolerar builds donde `cast_shadow`/
  `gi_mode`/`visibility_mode` no existan.

**Tests**: 9 nuevos en `addons/heren/tests/run_tests.gd` (null safety / 2D
purity / 3D purity / Control / Sprite / Mesh / tier 0 / tier 2 / discriminator).
19/19 GDScript verdes + 116 Rust verdes + clippy verde + grafo headless sin
parse errors.

**Contrato documentado**: AGENTS.md §0.11 — tabla de qué devuelve cada handler
(13 mutaciones + 3 calls de scene_handlers). Fases B (visual_text/spatial),
C (tier 3), D (summary recursivo) y E (deprecar visual_image) definidas pero
NO implementadas — siguen el orden del plan.

## [Unreleased] - 2026-09-03 - LSP bridge OpenCode (Rust puro, 0 deps Node)

### 🚀 LSP bridge para OpenCode

Sub-comando CLI `heren-server lsp-bridge` que conecta OpenCode (stdio LSP) con
el LSP nativo de Godot (TCP :6005). Permite autocompletado, chequeo de errores,
goto-definition y hover mientras el agente escribe GDScript en OpenCode.

**Arquitectura**: bridge stdio↔TCP en Rust puro, 0 deps Node. Reusa el editor
abierto (no auto-lanza) o auto-lanza Godot headless liviano (`--editor
--headless --audio-driver Dummy`, ~150-250 MB RAM). Reconexión automática
(ventana 60s), modo verbose minimalista (preview 80ch por mensaje).

**Módulos nuevos**: `crates/heren-server/src/lsp_bridge/{frame,launcher,proxy,mod}.rs`
+ `crates/heren-server/tests/lsp_bridge.rs` (test integración con fake LSP server TCP).

**Tests**: 23 unit + 2 integration (106 total en el crate, 0 regresiones MCP).
**Lint**: `cargo clippy --all -- -D warnings` verde.
**Binario release**: 11.9 MB (vs 11.4 MB sin clap — +0.5 MB).

**Configuración OpenCode** (`~/.config/opencode/opencode.jsonc`):
```jsonc
"lsp": {
  "gdscript": {
    "command": ["D:/path/to/heren-server.exe", "lsp-bridge"],
    "extensions": [".gd", ".gdshader"]
  }
}
```

**Pre-requisito** (en `project.godot`): `[network] language_server/enabled=true`
+ `language_server/port=6005`. El bridge NO modifica `project.godot` del usuario.

**Docs**: `docs/lsp-setup.md` (guía completa) + `opencode.lsp.example.jsonc` (snippet copy-paste).

### 🐛 Bugs encontrados y resueltos durante implementación

1. **OOM 6.4GB en tests del frame parser**: `parse_one` devolvía `Complete(body)` pero NO drenaba el buffer → `feed()` loop infinito. Fix: `parse_one_and_consume()` drena `..body_end` antes de devolver. Lección en AGENTS.md §12.

2. **Case mismatch en `has_lsp_enabled`**: el parser de `project.godot` no normalizaba case del key `language_server/enabled`. Fix: `to_ascii_lowercase()` antes de `strip_prefix`.

3. **`clap::Arg::env()` no encontrado**: faltaba feature `env` en clap. Fix: `clap = { version = "4", features = ["derive", "env"] }`.

## [Unreleased] - 2026-08-15 - E2E escena compleja (11 problemas)

### 🧪 E2E real contra editor vivo

Escena 3D compleja (20 nodos: meshes, materiales, animaciones, shader, script, UI) construida SOLO con tools MCP en `.temp/e2e_complex/`. Reporte: `.temp/E2E_REPORT.md`.

**🔴 Críticos**:
- **P1** `orchestrate` falla SIEMPRE con "Unknown error" (ambas formas de tool) — el batch es inútil.
- **P2** `create_player` ignora `player_path` — crea el player en el ROOT.
- **P3** `add_key` fallo SILENCIOSO con `rotation_3d` + Vector3 (`key_idx:-1`, `ok:true`).
- **P11** `add_key` inserta Quaternion NO normalizado → warning Godot.

**🟠 Altos**: P4 `track_type` no documentado · P5 `resource/create` devuelve ~100 props · P6 `summary` node_count:0 + no recursivo.
**🟡 Medios**: P7 meshes inline sin alternativa · P8 tool `ui` no en server viejo · P9 `parent_path` → "." · P10 `get_animation` no implementada.

**AGENTS.md**: §0.1 eliminado (todo [x], historial en CHANGELOG); nuevo **§0.3 Plan de Mejoría E2E** (severo); §9/§11/§12/§13 actualizados con lecciones (Quaternion normalizado, track_type real, create_player en root).

**Nota log**: `failed to load plugin path=list` = config global OpenCode (`"plugin": ["list"]` inexistente), NO del MCP de Godot.

## [Unreleased] - 2026-08-14 - Fase UI: templates + tool `ui`

### 🧩 Sistema transversal de templates (UI-1)

**Problema**: crear un HUD requería 6-10 llamadas (crear Control, fijar 9 anchors/offsets a pelo, añadir hijos, estilizar). El agente adivinaba valores de layout → HUDs rotos; `get_info` no exponía anchors/offsets → ceguera de UI.

**Solución** — sistema transversal (patrón `coords.gd`, lo usa cualquier tool):
- `addons/heren/templates/` — 6 templates .tscn 2D: `health_bar`, `crosshair`, `dialogue_box`, `score_label`, `boss_bar`, `inventory_slot`
- `metadata.json` — índice con params `{target|targets, property, resource}` por nombre de nodo canónico
- `template_registry.gd` — `list_templates()` / `instantiate(name, params)` / `template_exists()` con cache RAM; deserializa params con el sistema de coordenadas
- `node/instantiate` acepta `template` (params via `properties`); schema Rust de `node` gana `template` y `script` (gap preexistente)
- **1 llamada = barra de vida completa** (`node/instantiate {template:"health_bar", properties:{color, label}}`)

### 🎨 Tool `ui` (UI-2) — 6 acciones

- `ui/create` — Control desde template o desde cero (`node_type` obligatorio si no template) + `layout` preset
- `ui/layout` — 9 presets de anchors (`full_rect`, `bottom_center`, `top_left`, `top_right`, `center`, `bottom_left`, `bottom_right`, `center_left`, `center_right`); avisa si el padre es Container
- `ui/canvas_layer` — CanvasLayer (layer, follow_viewport) para HUD overlay
- `ui/templates` — lista templates con params
- `ui/get_info` — anchors/offsets/size_flags/min_size/parent_is_container de un Control
- `ui/theme` — crea/modifica Theme .tres (`colors`, `styleboxes`, `font_sizes`, `constants` con claves `ThemeType/item`) + aplica a Control vía `node_path`

**Lecturas enriquecidas**: `node_query/get_info` devuelve `ui` (anchors/offsets/size_flags/min_size/parent_is_container) para Control; `_node_coords` añade `anchors`/`offsets`.

**Bugs corregidos**: `{} != null` → `is_empty()` en `template_exists`; clippy `map_unwrap_or` preexistente; línea en blanco en `lib.rs`.

**Lecciones** (ver AGENTS.md §10): `String.split()` devuelve `PackedStringArray` (sin `pop_back`) → tipar `var segments: Array`; `NodePath` no tiene `begins_with`/`trim_prefix` → `str(path)` primero; `Copy-Item -Recurse` anida si el destino existe → `Remove-Item` antes.

Verificado: 51 tests Rust + 10 GDScript verdes, clippy pedante 0 warnings, fmt limpio, grafo headless sin SCRIPT ERROR, CI grep actualizado a 10 passed.

## [Unreleased] - 2026-08-14 - Fase F: tipos semánticos

### 🎯 Schemas JSON descriptivos

**Problema**: 42 propiedades `Option<serde_json::Value>` generaban schemas vacíos `{}` sin descripción. Los clientes MCP (OpenCode, APIs de modelos) no podían validar ni guiar al usuario sobre qué tipo de datos espera el parámetro.

**Solución**: Migración a tipos semánticos de FlojoMCP:
- `GodotVariant`: cualquier valor (dict, array, string, number, bool, Vector2/3, Color, Transform, etc.)
- `GodotDict`: Dictionary `{key: value}` donde key es string
- `Vector2`, `Vector3`, `Color`, `Transform2D`, `Transform3D`, etc.

**Resultado**:
- Antes: 42 propiedades con schema vacío `{}` sin descripción
- Después: 0 propiedades vacías; todas con `$ref` a definiciones descriptivas
- Los schemas ahora incluyen `definitions` con `description` y `type` apropiados

**Cambios técnicos**:
- 26 propiedades → `Option<GodotDict>` (properties, values, uniforms, parameters, nodes, connections, points, tracks, to, from, transform, bones, chain, target_position, magnet, weights, target_pose, rest_transform, bone_weights, compare, coords, atlas_coords, cells, region, plan, animation)
- 5 propiedades → `Option<GodotVariant>` (value, events, event, states, transitions)
- 41 conversiones `.map(Into::into)` añadidas para interoperar con `args()` que espera `Value`

**Dependencias**: FlojoMCP actualizado con `types.rs` (16 tipos semánticos) y `From<GodotDict/GodotArray> for Value`.

Verificado: 51 tests Rust + 5 GDScript verdes, fmt/clippy limpios.

## [Unreleased] - 2026-08-11 - Fase E: UX/contribución

### 🆕 Tool help/introspect

- Nueva tool `help` (E3): sin tool → lista todas las tools expuestas; con `tool='X'` → devuelve `description` + `parameters` (schema reducido). Sin mapeo manual (usa `list_tools` del toolset). Añadida a `EXPECTED_TOOLS` y a excepciones de `action` en tests.

### 📚 Documentación/UX

- **E1**: `CONTRIBUTING.md` reescrito para stack Rust+GDScript (el viejo describía Python v3 archivado). Incluye guía paso a paso "cómo añadir una tool" (Rust schema → GDScript handler → registro → tests).
- **E2**: README apunta a `scripts/install_mcp.py` (movido en Fase A).
- **E5**: política UIDs — **NO se versionan `.uid`** (`.gitignore: *.uid`; autogenerados por Godot, versionarlos corrompe referencias cross-project).
- **E4**: comparativa de competidores confirmada (nota honesta ya en README).

Verificado: 51 tests Rust + 5 GDScript verdes, fmt/clippy limpios.

# Changelog - Heren MCP

## [Unreleased] - 2026-08-11 - Fase D: tests y calidad

### 🧪 Tests

- **D2**: `addons/heren/tests/run_tests.gd` — runner GDScript headless (sin GUT) para helpers puros (coords serialize/deserialize, constants.default_ws_url, heren_error). 5 tests.
- **D4**: `tools_parity.rs` reforzado — verifica `description` no vacía + `action` en schema (excepto orchestrate/health).

### 🔧 Calidad

- **D3**: clippy pedantic activo (`#![warn(clippy::pedantic)]` con allows de estilo doc/must_use); lints de código corregidos (`cargo clippy --fix`).
- **D5**: `benches/pure_helpers.rs` — benchmarks Criterion (normalize_scene_path, args builder, unwrap_result).
- **D6**: CI ejecuta grafo headless con grep `SCRIPT ERROR\|Parse Error` + runner GDScript.

Verificado: 50 tests Rust + 5 GDScript verdes, fmt/clippy limpios, grafo headless Godot 4.6.1 exit 0.

# Changelog - Heren MCP

## [Unreleased] - 2026-08-11 - Fase C: reorganización estructural

### 🏗️ Rust

- **C1**: nuevos `crates/heren-server/src/pure.rs` — helpers puros (`normalize_scene_path`, `args`, `unwrap_result`) extraídos de `server.rs` + tests unitarios. `server.rs` de ~1700 → ~1634 líneas.

### 🎮 Plugin GDScript

- **C2**: `animation_handlers.gd` (2531 líneas) dividido — `skeleton_handlers.gd` extraído (17 funciones skeleton, hereda de animation_handlers). Dispatcher registra "skeleton" → skeleton_handlers.
- **C4**: nuevo `handlers/heren_handler.gd` — contrato base (`set_editor_plugin`, `_editor_interface`, `_args_dict`). 11 handlers migrados de `extends Node` a `extends heren_handler.gd` (eliminada `var _editor_plugin` duplicada).
- **C5**: `constants.gd` (WS_PORT_DEFAULT, RES_PREFIX, `default_ws_url()`) y `constants.rs` (WS_PORT_BASE, TOOL_TIMEOUT_MS, EDITOR_KILL_WAIT_MS). `ws_client.gd` usa la constante centralizada.
- **C6**: `handlers/heren_error.gd` — shape estándar de error (`err`/`ok`/`err_with`) + helper `_err()` en la base.

### 🔧 No aplicables (documentado)

- C3 (dividir `project_handlers.gd`): dispatcher rutea por prefix; 524 líneas ya manejable.
- C7 (tests Python): archivados en Fase B.

Verificado: `cargo test --all` 49 verdes, fmt/clippy limpios, grafo headless Godot 4.6.1 exit 0.

# Changelog - Heren MCP

## [Unreleased] - 2026-08-10 - Fases A y B de limpieza

### 📋 Auditoría

- Nuevo `AUDIT-2026-08-10.md`: crítica de diseño, mantenibilidad, workflow y confort; bloqueantes críticos; propuesta de reorganización.
- Registrados en `AGENTS.md` pendientes derivados del audit.

### 🧹 Fases A y B: limpieza de sangrado y poda de código muerto

- **Fase A:**
  - Limpieza de `.pyc`, `__pycache__`, `.temp/` y actualización de `.gitignore`.
  - Scripts de build reubicados de raíz a `scripts/` (`heren-build.bat`, `run.bat`, `install_mcp.py`, `deploy-fix.bat`, `setup_plugin.bat`, `install_plugin.py`, `ws_test_server.py`).
  - Nuevo fixture `fixtures/empty_project/project.godot` para tests autónomos.
  - CI mínima en `.github/workflows/ci.yml` (Rust fmt/clippy/test, Godot headless, Python lint).
  - Verificado: `cargo test --all` pasa (47 tests). Dependencia `flojo-mcp` por path resuelve correctamente.

- **Fix linker LNK1104 (`msvcrt.lib` no encontrado):**
  - Causa: VS 18 Insiders (Community 2026 Preview) tiene `link.exe` (MSVC 14.51) pero está INCOMPLETO — falta `lib/x64/msvcrt.lib`. rustc/cc lo detecta como el toolset más nuevo y falla al linkear.
  - Fix: nuevo `.cargo/config.toml` fija el toolset del VS 2022 BuildTools (MSVC 14.44.35207 + Windows SDK 10.0.26100.0) como linker y `LIB` explícito. Cargo ya no depende de VsDevCmd ni de la detección automática.
  - Si el VS 18 se completa algún día (componente `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`), borrar `.cargo/config.toml`.

- **Fase B:**
  - Creada rama local `archive/v3` con todo el código Python/daemon v3.
  - Eliminado de `main`: `src/heren/daemon/`, `src/heren/tools/`, `src/heren/core/session_manager.py`, `src/heren/v4/`, `src/heren/server.py`, `src/heren/i18n/`, `src/heren/bridges/`, `src/heren/__init__.py`.
  - Eliminados tests y benchmarks Python obsoletos (`tests/test_*/`, `benchmarks/*.py`).
  - Creados `tests/README.md` y `benchmarks/README.md` explicando dónde están los tests activos.

### 🧪 Tests nuevos

- `crates/heren-server/tests/tool_latency.rs`: benchmarks de latencia para `list_tools`, validación de schemas y serialización de args (no requieren editor vivo).
- `crates/heren-server/tests/registry_mutability.rs`: tests de mutabilidad de `EditorRegistry` — dirty tracking, aislamiento por proyecto, unexpected_close y concurrencia.
- `addons/heren/tests/test_node_mutability.gd`: esqueleto de test GDScript para mutaciones de nodos con undo/redo (requiere editor/GUT).

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

---

## [4.9] - 2026-09-09 - Archivo de AGENTS.md (compresión 123KB → 36KB)

Historia completada movida desde AGENTS.md. Referencias vivas en AGENTS.md §0.12 (Plan Worker-First).

### §0.1 E2E Round-1 (COMPLETADO)
- P1/P2: `session/open` con project_path explícito; `scene/open` con `apply_scene_context` + `_scene_root(args)`.
- 5/5 tools críticas E2E OK (session, scene, node, node_query, node_props).

### §0.3 Debug D1-D4 (D1-D3 COMPLETADOS, D4 PENDIENTE)
- D1: `debug/output` vía signal `debug_data` de ScriptEditorDebugger (EditorDebuggerPlugin._capture solo recibe mensajes con `:`).
- D2: `debug/summary` snapshot completo 1 llamada (verificar props del plugin antes de usar: `first_session()`, `vars_pending`).
- D3: `debug/run_scene` funcional pero frágil (hooks one-shot, reintentos 10x1s). D4 (probes de gameplay) → Plan W5.

### §0.4 Bug report usuario (4/5 FIXED)
- BUG1-4 fixed (coords globales, deserialize, set_prop verificación, save prioridad). BUG5 (Shader/Theme serializados vacíos) NO reproducido — 3 casos de prueba pasaron.

### §0.8 Fase 0 (COMPLETADO)
- Checklist Fase 0: `session/open` primero, `apply_scene_context`, `normalize_scene_path` en 8 tools, dirty set, flush-before-destroy, `session/reopen` flush+graceful_close.

### §0.9 E2E Round-2 (COMPLETADO — lecciones en AGENTS.md §10)
- P-B1..P-B13: todos bugs del traductor coder→handler (param_name vs name, set_prop connections inexistente, path con `:` colgante, forward con nombres MCP `godot_*` vs internos bare, etc.). Motivación directa del Plan Worker-First (§0.12): con workers no hay traductor.

### §0.11 Fases A-E (COMPLETADO — contrato vivo en AGENTS.md §7)
- Fase A: coords proactivas 13/13 handlers de mutación.
- Fase B: `visual/spatial` (overlaps/distance/neighbors/layout/bounds) — módulo puro `visual_tool/spatial_tool.gd`.
- Fase C: pureza 2D/3D verificada por tests (`_test_coords_of_node_2d_purity` / `_3d_purity`).
- Fase D: `visual/summary` recursivo con warnings (z_fighting_risk, missing_material/texture/shape) — Validator Engine B lee este JSON.
- Fase E: `visual_image` ELIMINADO (implementación rota: placeholder 2x2, timeout en play). Concepto re-vivable como W6 opt-in.
- Fase F: tipos semánticos FlojoMCP (`GodotVariant`, `GodotDict`...) — 42 props de schema vacías → 0.

### §11 Bugs arreglados (historial)
- BUG 1: coords globales sin `is_inside_tree()` → warning `get_global_transform`.
- BUG 2: deserialize de strings `res://` creaba UID sintético → corrompía project.godot.
- BUG 3: Color/dicts anidados serializados como strings JSON por WS → `deserialize_value` parsea strings JSON.
- BUG 4: `scene/save` usaba registry stale → handle_save misma prioridad que resolve_root.
- P0.5: `input_map` persistencia real via ProjectSettings.set_setting + save.
- P0.7: `resource/*` con `EditorFileSystem.update_file()` post-write.
- P1/P2: session/open + scene/open con contexto explícito.

---

## [4.10] - 2026-09-09 - W0 Safety + W4 scene_script (Worker-First)

### W0 — Protección de paths + snapshot-before-save
- `heren_handler.gd`: statics `protected_reason()` / `snapshot_file()` / `restore_snapshot()` + `PROTECTED_PREFIXES`
  (`addons/heren/`, `project.godot`, `.git/`, `.godot/`, `export_presets.cfg`).
- `resource_handlers.gd`: delete/update/create_script/edit_script bloquean paths protegidos y
  dejan snapshot en `.heren/backup/<file>.<ts>.bak` antes de tocar disco (recuperable en receipt).
- Motivación: `resource/delete` verificada SIN protección (grep `protect` → 0) — el agente podía
  borrarse a sí mismo (`addons/heren/plugin.cfg`) o destruir `project.godot`.

### W4 — `scene_script` (worker GDScript del agente)
- Nueva tool `scene_script` (run|list) + handler `handlers/scene_script.gd` + rutas en `_routes.gd`.
- Contrato del worker: `@tool` + `extends RefCounted` + `func run(ctx) -> void` (fail-fast si no).
- ctx API: `get_scene_root/get_scene_path/is_read_only/set_scene_root/own/instance_scene/template/
  coords/get_node_or_null/find_nodes_by_name/ensure_unique_child_name/remove_node/clear_children/
  log/error/mark_modified/output`.
- Flujo transaccional: parse-check previo (reload err 43) → root (pestaña→registry→disco) →
  snapshot W0 → `worker.run(ctx)` → save SOLO si `mark_modified()` → post-validate (validate/scene)
  → si falla: restore snapshot. Modo `inspect`: PackedScene detached read-only, liberado al final.
- **Contrato de errores**: fallo del worker = `ok:true + ran:false` + diagnósticos + `script_path`
  (el payload sobrevive el transporte; `ok:false` viaja como JSON-RPC error SIN payload).
- Innovaciones vs Fennara: `ctx.template()` (templates transversales dentro del worker),
  `ctx.coords()` (sistema ADR-005 consultable en el worker), receipt con coords proactivas
  (root tier-N + nodos tocados tier-1) + `changes` (semantic diff de ops mediadas por ctx).
- server.rs: tool `scene_script` (forward_mutating en edit, forward en inspect/list).

### Bugs encontrados en E2E (arreglados)
- Cache GDScript: `load()` de .gd ya cargado devuelve source VIEJO → refrescar `source_code`
  desde disco antes de `reload()` (workflow de retry por script_path).
- `add_child()` con nombre en conflicto + `force_readable_name=false` → `@Class@ID` (no "Tower2").
  Workers deben usar `ctx.ensure_unique_child_name()` antes de add_child.
- EFS scan en frío: assets recién copiados invisibles hasta scan (metadata.json → template null).
  Confirma necesidad de W4b (filesystem/scan + readiness).

### Validación
- Suite GDScript: 49 passed, 0 failed (6 tests nuevos W0/W4).
- Rust: cargo test OK (104 tests), clippy -D warnings limpio.
- E2E stdio NDJSON contra editor vivo (`.temp/e2e_scene_script.py`): **27 passed, 0 failed**
  (worker edit+save, transaccionalidad sin mark_modified, inspect detached, parse-check fail-fast,
  retry por script_path, contrato base/run, ctx.error, ctx.template, W0 protección, list).

---

## [4.11] - 2026-09-09 - E2E intrincado "Estación Omega" (vía MCP directo, GenericStep)

### Qué se probó
Escena compleja construida 100% por workers a través del flujo planning REAL
(scene/plan + orchestrate con GenericStep passthrough → scene_script/run):
- Jerarquía anidada (Station/Section1-6/Hull+Body+Col), 12 pilares procedurales
  con CylinderMesh, materiales StandardMaterial3D, luces (Directional+Omni),
  Camera3D con look_at_from_position (gotcha detached), AnimationPlayer +
  AnimationLibrary + track "Station:rotation:y", AnimationTree con
  AnimationNodeStateMachine (2 nodos + 2 transiciones), AudioStreamPlayer,
  HUD (CanvasLayer + template health_bar + Button con anchors), Skeleton3D
  con 4 huesos y poses, instancia de subescena (crosshair) vía instance_scene.

### Resultados (ground truth: .tscn parseado + coords MCP)
- 68 nodos, 0 nombres @-auto, todos los recursos serializados.
- Cam transform con el look_at aplicado (pitch -45° persistido).
- anim_player = ../Anim (binding tree→player sobrevivió save+reload).
- Pilares en espiral persistidos (Pillar01 → 20,0,0).
- health_bar y Cross como instancias ExtResource (no aplanadas).
- Skeleton: 4 huesos vivos y en disco (bones/0/name = "Spine"...).
- QA dual-engine: depth 5, bounds 3D ~55×13.5×54, 12 missing_material
  warnings = detección CORRECTA (los pilares no tienen material).

### Bugs/hallazgos nuevos
- `Skeleton3D.add_bones()` NO existe en 4.7 → worker abortó silenciosamente
  en esa línea (el save lo hizo un step posterior). Fix del worker: patrón
  has_method() con fallback a add_bone(). **W2 class_info es la prevención
  estructural — demostrado empíricamente.**
- orchestrate no devuelve receipts por step (solo applied_state) — los
  logs/outputs del worker se pierden en el flujo planning.
- orchestrate exige que la escena del plan exista ("no scene open in editor")
  — el flujo new-scene de scene_script funciona por llamada directa pero no
  vía orchestrate. Workaround: scene/create primero.
- visual/coords con node_path cae a contexto stale (misma respuesta para
  "Rig" y "AnimTree") — bug preexistente del handler visual, investigar.

### §0.5 re-scoped por Worker-First
- S (roles + editor visible del agente): MÁS valioso (1 op grande e invisible
  en vez de 50 pequeñas).
- R (codec): CRÍTICO — strings GDScript enormes + receipts; prerrequisito W5.
- U'': simplificado — 1 lock por worker; el commit atómico ya lo hizo W4;
  _pending_ops replay casi obsoleto.
- T: se encoge — resource/update muere (worker); sobreviven move/deps/reimport.

---

## [4.12] - 2026-09-09 - W1 + W2 + W3 (percepción y prevención)

### W2 — `node_query class_info` + `props_diff` (ClassDB real)
- `node_query class_info {class_name, filter?, include_inherited?}`: métodos (name+args+return,
  const/vararg), propiedades (STORAGE only), señales, enums — de ClassDB de la versión conectada.
  `filter=substring` acota (ej: `class_info Skeleton3D filter=bone` responde "¿existe add_bones?" de un vistazo).
- `node_query props_diff {node_path}`: solo las props que DIFIEREN del default de la clase
  (patrón Fennara "get_node_properties" — tokens mínimos). Cap 64 + truncated flag.
- Motivación empírica: `Skeleton3D.add_bones()` NO existe en 4.7 y el worker del E2E Omega
  abortó silenciosamente. class_info lo habría prevenido.
- Ironía registrada: la primera implementación usó `ClassDB.is_virtual()` (no existe en 4.7)
  y un `@warning_ignore` inválido — detectado por el grafo headless en el primer pase.

### W1 — Diagnósticos inline en create/edit_script
- `resource/create_script` y `edit_script` ejecutan `_script_diagnostics()` (load + refresh
  source desde disco + reload) y devuelven `diagnostics: {valid, reload_err?, error?}` en la
  MISMA respuesta. Fix-loop de 3 llamadas → 1.
- El refresh de source_code evita el cache de recursos (source viejo en re-ediciones).

### W3 — Guía inyectada en el proyecto del usuario
- `addons/heren/ai/guidelines.md` viaja DENTRO del plugin (la sync la copia a cada proyecto).
- Contenido: contrato scene_script, reglas del worker (has_method, ensure_unique_child_name,
  own/PackedScene, detached ≠ runtime, tipado explícito, ctx.coords), jerarquía de percepción,
  validación, límites (paths protegidos, EFS en frío), planning opcional.
- `project/setup_plugin` reporta la ruta de la guía en su respuesta.

### Validación
- Suite GDScript: 51 passed, 0 failed (2 tests nuevos W1/W2).
- heren-build.bat completo: debug + tests + release + clippy -D warnings — TODO VERDE
  (el release pudo escribirse tras matar los servers con permiso del General).
- Binario target/release actualizado con W0+W4+W1+W2+W3.

---

## [4.13] - 2026-09-09 - R0: Auditoría de codec + fix R1 (rediseño sesiones, fase 1)

### R0 — Auditoría de codec (23/23 PASS)
Round-trip de tipos complejos por el pipeline completo MCP→WS→plugin→receipt
(`.temp/e2e_codec.py`, binario nuevo):
- set_props con dicts estructurados (Vector3 position, euler rotation, scale) ✅
- Strings JSON-anidados en props String: round-trip INTACTO (tras fix R1) ✅
- Strings de 10KB+unicode ✅ · unicode/emoji en valores, logs, node names y
  lookups por nombre unicode ✅ · worker receipts con outputs anidados ✅
- `node_query class_info` (W2) verificado en el mismo pase ✅

### Fix R1 — deserialización type-aware (bug real encontrado por la auditoría)
- `coords.gd deserialize_typed`: si target_type == TYPE_STRING y el valor es
  String, devolverlo TAL CUAL. Antes: valores no-Array iban directo a
  `deserialize_value`, que parsea strings "JSON-looking" → un valor string
  legítimo con JSON dentro se convertía en Dictionary (1→1.0, escapes
  alterados) y el set_prop fallaba la verificación de valor aplicado.
- El parseo JSON de strings sigue disponible para props NO-String (fix BUG 3 intacto).

### Lecciones del audit (bugs del TEST, no del codec — documentados)
- `rotation` en Node3D es euler Vector3, NO Quaternion (dict {x,y,z,w} falla).
- set_prop de `name` RENOMBRA el nodo — los lookups posteriores por el nombre
  viejo fallan (usar una prop no-identidad para tests de strings, ej: Label.text).
- GDScript NO tiene repetición de strings ("y" * 5000 = compile error con tipos
  literales) — usar `.repeat()`. GDScript cuenta codepoints: "ñ🦀" = 2 chars.
- inspect lee del DISCO — scene/save antes de inspeccionar nodos solo en memoria.

### Estado del rediseño de sesiones (§0.5 re-scoped)
- ~~R0~~ ✅ (esta fase) · R3 (fuzz permanente) pendiente · S-cierre: S1/S2/S4 ya
  existen (registry con rol, launch_agent_editor --heren-agent,
  call_tool_with_role) — auditoría de gaps pendiente · U''-reducido (lock por
  worker + EditorToaster) pendiente · W4b pendiente.

### Validación
- Suite GDScript: 51 passed, 0 failed · heren-build.bat completo VERDE.

---

## [4.14] - 2026-09-09 - Sin sesiones (Fennara-style): la herramienta `session` se elimina

### Cambio arquitectural (decisión General 2026-09-09)
**La tool `session` se elimina.** El server no tiene concepto de lifecycle de sesión:
el editor conectado ES la sesión (ADR-004). Sin `agent_id`, sin roles, sin lock por
escena (también eliminados en esta fase — el save transaccional + sync_from_disk
cubren la seguridad de disco).

### Qué cambia
- **`session/open|close|info|status|list|diagnose|reopen`**: ELIMINADOS.
  Reemplazo: cualquier tool con `project_path` funciona sin preámbulo.
- **Auto-launch transparente**: el primer tool call con `project_path` paga el coste
  de launch (3-10s) si no hay editor conectado. Implementado en
  `ensure_editor_connected` (server.rs). Los siguientes son ~20ms.
- **`HEREN_AUTO_LAUNCH=0`** deshabilita el auto-launch (el usuario abre Godot
  manualmente con el plugin).
- **`HEREN_DEFAULT_PROJECT=<path>`** fija el proyecto por defecto (si no, cae
  a `last_project` server-side).
- **`health`** absorbe las antiguas acciones de session: estado global + detalle
  por proyecto + `diagnose=true` ejecuta el debugger unificado
  (integridad plugin + grafo headless sandbox).
- **Lifecycle del editor = del usuario**: el server **nunca** mata el editor al
  desconectar. El editor vive; el WS se reconecta vía discovery
  `.heren/server_port.json`.
- Sin `agent_id`, sin roles: el registry rutea por `project_path` al único
  editor del proyecto.

### Archivos
- `crates/heren-server/src/server.rs`: `ensure_editor_connected` (nuevo helper),
  `forward`/`forward_mutating` lo invocan, nueva `health` tool, `session`
  eliminada (20058 → 5023 bytes), role infrastructure eliminada
  (`active_role_store`/`set_active_role`/`get_active_role`/`clear_active_role`).
- `registry.rs`: `call_tool_with_role` queda (no usado por server; queda por
  compat con el plugin si lo invoca directamente). No se elimina.
- AGENTS.md §0.5 reescrito, §3 regla 1, §6 tool table, §8 "Sin sesiones", §11 EFS note, §12 checklist.
- guidelines.md (en el plugin): sin menciones a `session/open`.
- README.md / README.en.md: ciclo de vida y robustez actualizados.

### Validación
- tools_parity 7/7 PASS (MIN_TOOLS=15 satisfecho: 17 tools restantes).
- cargo test 84/84 PASS.
- clippy -D warnings: clean.
- heren-build.bat completo: debug + tests + release + clippy — VERDE.
- Binario target/release actualizado (11.8MB).
