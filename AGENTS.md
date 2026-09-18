# 🐉 Heren MCP — AGENTS.md

> Biblia del agente. Léelo antes de tocar código.
>
> **ESTADO: v4.9** — EditorPlugin (GDScript→EditorInterface) + heren-server.exe Rust/FlojoMCP.
> 18 tools centralizadas, WS plugin server (patrón gopeak), auto-launch, NDJSON por stdio.
> Workspace Rust local (`crates/heren-server`); FlojoMCP = framework SOLO (crates.io, por version).
> Bridge Python y daemon v3 **archivados en rama `archive/v3`**. **Cambios nuevos → v4/Rust.**
> **Historial de fases completadas y bugs arreglados → CHANGELOG.md** (este archivo solo guarda conocimiento VIVO).
> **Dirección actual: Plan Worker-First (§0.12)** — `scene_script` (worker GDScript del agente) reemplazará la mayoría de las tools enumeradas.

---

## 0. Pendientes

### Bugs abiertos
- **M1** `node/array_remove`: borra el primer elemento, no el `value` (int vs float en `find`). Fix: tipar/normalizar.
- **M2** `visual/summary`: `node_count:0` inconsistente (by_type OK). Handler cuenta mal.
- **M3** `validate/node`: `script_cannot_instantiate` — scripts MCP no se compilan. Falta re-import/scan.
- **P3+P11** `add_key` rotation_3d: Quaternion directo normalizado funciona; Vector3→Quaternion NO soportado (Godot rechaza conversión); handler devuelve error claro (no silencioso).
- **P5** `resource/create` devuelve ~100 props — flag `verbose:false` default pendiente.
- **P10** `animation/get_animation` listada en schema pero NO implementada.
- **Gaps tool**: `node_query` no expone `by` (find por tipo) ni `owner_path`/`script` en get_info; `resource` exige requireds irrelevantes en create_script/edit_script.
- **BUG 5** (no reproducido): reporte de Shader/Theme serializados vacíos — 3 casos de prueba pasaron; si reaparece, pedir entorno del reportante.

### §0.13 Validador maduró (W4-c, 2026-09-10)

**Antes**: `validate/script` retornaba `reload_err=43` + "ver debug/output" → fix-loop de **3 calls**.
**Ahora**: inline diagnostics con `parse_hints[{rule,line,col,message,confidence}]` → fix-loop de **2 calls**.

- `static_analyze_gdscript(source)` en `heren_handler.gd` — 13 reglas (10 high, 2 medium; `await_at_top_level` pendiente, heurística ambigua):
  - **high**: `tabs_and_spaces_mixed`, `unbalanced_parens/brackets/braces`, `unterminated_string`, `unterminated_triple_string`, `export_on_const`, `await_stuck_to_identifier`, `shadow_builtin_var`, `class_name_duplicate_in_file`
  - **medium**: `missing_colon_after_func_def`, `missing_colon_after_keyword`
- `script_diagnostics(path)` — load + analyze + reload, shape unificado. Reemplaza al antiguo `_script_diagnostics` de `resource_handlers.gd` (DRY).
- `validate/script` y `validate/scripts` propagan `parse_hints` en cada entry. Tests: `run_tests.gd` (17 nuevos: 14 reglas + 2 unified + 1 sanity).

**Bugs colaterales resueltos**:
- ✅ `node_handlers.gd:372` `NodePath == String` crashea en GDScript 4.5+ → `_values_match` coerce antes de `==`.
- ✅ `shader_handlers.gd` llamaba 7 helpers (`_shader_structural_issues`, `_parse_shader_type`, `_shader_uniforms_to_json`, `_find_shader_material`, `_mode_to_str`, `_uniform_type_str`, `_hint_str`) que **NO existían en ningún archivo** desde W4 cleanup 2026-09-09 → `shader/validate`, `shader/inspect`, `shader/get` rotos. Restaurados desde commit `0728708`.

### §0.14 Installer + validador automático (2026-09-10)
- `install_plugin.py --force` — sync content-aware (diff real de bytes; sin `--force` solo chequea existencia). `--dry-run` muestra el diff.
- `scripts/validate_plugin.bat` — los 4 pasos de §3.7 en 1 comando.

### §0.8 Fases 1-3 (arquitectónicas) — ABIERTAS
- **Fase 1 — Single registry**: eliminar `crates/heren-server/src/scene_tool/registry.rs`. Plugin-registry (`scene_registry.gd`) = source-of-truth único. `scene/status/list` forward al plugin. `load_scene_context` del adapter desaparece.
- **Fase 2 — Fail-fast sistemático**: auditar TODO handler que retorna `ok:true`. Helper `assert_effect_applied(action, predicate)`.
- **Fase 3 — Dispatcher explícito**: `dispatcher.gd` con tabla declarativa `(tool_name, action) → handler_method`. Tests `tools_parity.rs` verifican cobertura.
- **Causas raíz A1-A4** (ver CHANGELOG para detalle): A1 dos registries sin sincronizar · A2 flujo `open` dual bifurca silenciosamente · A3 `ok:true` sin verificación · A4 dispatcher con 3 fallbacks mágicos.
- **W4/W5 deben diseñarse sobre la Fase 1** para no consolidar la deuda.

### §0.5 Sin sesiones (Fennara-style) — decisión arquitectural 2026-09-09
**Implementado completo — detalles en §8.** Sin tool `session`; el editor conectado ES la sesión (ADR-004). `health` la reemplaza. Auto-launch transparente. `HEREN_AUTO_LAUNCH=0` para deshabilitar. Lifecycle del editor = del usuario (server NUNCA mata al editor). Actions eliminadas: `session/open|close|info|status|list|diagnose|reopen`.

### §0.6/0.7 Planning (DEPRECADO por W4)
Flujo `scene/plan {plan_file}` → `scene/orchestrate` → `scene/validate` → `scene/commit`. Steps tipados + `GenericStep` passthrough. Cache `.heren/scene_cache/<scene>/`. **W4 lo reemplaza con `scene_script`** (workers GDScript) — mantener planning como OPCIONAL, no núcleo.

### §0.10 LSP Bridge (IMPLEMENTADO 2026-09-03)
- `heren-server lsp-bridge` — sub-comando CLI Rust puro, stdio↔TCP :6005, auto-launch Godot headless liviano, reconexión automática (backoff 1s, ventana 60s), verbose preview 80ch. 0 deps Node.
- Módulos: `lsp_bridge/{frame,launcher,proxy,mod}.rs`. 25 tests. Binario release 11.9 MB.
- Config OpenCode: `lsp.gdscript.command = [heren-server.exe, lsp-bridge, --project-path, <proj>]`, extensions `.gd/.gdshader`.
- **Pre-requisito**: `[network] language_server/enabled=true` en `project.godot` (el bridge NO lo modifica; `docs/lsp-setup.md` documenta).
- **Lección clave**: parser incremental = **consumir ANTES de devolver** (si `parse_one` no drena el frame del buffer, loop infinito → OOM 6.4GB en tests).

### §0.12 Plan Worker-First (2026-09-09) — DECISIÓN DEL GENERAL: APROBADO

> **Origen**: análisis del competidor `fennara-godot-ai` (284★, Asset Store, usado por estudios). Veredicto: no ganan en features, ganan en **filosofía de diseño**. ~10 tools primitivas vs nuestras 18 tools × N acciones. **Decisión**: refactor worker-first — *"si `run_scene_edit_script` nos ahorra CASI TODAS las tools, que así sea"*.

### La lección central: `run_scene_edit_script`

El agente escribe un **worker GDScript** completo; Fennara lo ejecuta en el editor contra la escena real con red de seguridad transaccional:

```
worker.gd → path temporal en proyecto → PARSE-CHECK previo → ejecución
  (inspect: detached read-only | edit: muta + save SOLO si ctx marcado modificado)
→ POST-validación → si falla CUALQUIER punto: escena original intacta
→ respuesta incluye path del worker → iterar con script_path sin reescribir
```

Garantías por capas (NO sandbox real — convención documentada + transaccionalidad): parse-check previo · save transaccional · **ownership helpers** (owner incorrecto de internals PackedScene = RECHAZADO; aplanado de raíz heredada = restore + fallo) · límites de dominio (`.glb`/import → tool aparte; graph detached ≠ Run Scene, documentado) · worker reutilizable por path.

**Por qué mata nuestro DSL**: los bugs P-B1..P-B13 (CHANGELOG §0.9) fueron TODOS del traductor coder→handler. Con workers no hay traductor — el agente habla directo con el API de Godot. Cobertura total sin enumerar: cero código nuevo por capability nueva, para siempre.

### Qué hacen mejor (lecciones adoptables — top 6)

| # | Lección | Nuestro gap (resuelto o pendiente) |
|---|---------|-------------|
| 1 | Tools primitivas + game-agnostic | 18 × N acciones; agente adivina args por action |
| 2 | Worker GDScript del agente | **Resuelto W4**: scene_script |
| 3 | Diagnósticos AUTOMÁTICOS en la edición | **Resuelto W4-c**: parse_hints inline; W1 inline en create_script |
| 4 | Transaccionalidad: failed no muta | **Parcial W4**: scene_script transaccional; orchestrate continue-on-error sigue dejando pasos aplicados |
| 5 | `class_info` ClassDB real + docs XML | **Resuelto W2**: node_query class_info |
| 6 | Protección de paths + snapshots pre-mutación | **Resuelto W0**: protected_reason + snapshot_file statics |

Resto (8-14): guía en proyecto (W3 ✅), runtime_session/probes (W5), import (W4b), capturas (W6), docs de tools con "Working behavior", distribución, scripts reutilizables por proyecto — sin equivalente aún.

### Qué hacemos MEJOR (NO romper imitándolos)

- **Coords proactivas + tiers + pureza 2D/3D (§0.11)** — ellos no tienen equivalente.
- **Undo/redo granular por op** — su worker es todo-o-nada por script.
- **Templates transversales** (health_bar, crosshair...) — sin equivalente.
- **Instalación liviana**: 1 binario + plugin GDScript vs su CLI+daemon+GDExtension+CEF.
- **Sin telemetría**.

### Plan W (Worker-First) — fases

| Fase | Qué | Estado |
|------|-----|--------|
| **W0** ✅ | Safety basics: paths protegidos + snapshot-before-save statics | Cerrado |
| **W1** ✅ | Diagnósticos inline en create/edit_script | Cerrado (ahora W4-c madura a `validate/script`) |
| **W2** ✅ | `class_info` (ClassDB real) + `props_diff` | Cerrado |
| **W3** ✅ | Guía en proyecto: `addons/heren/ai/guidelines.md` | Cerrado |
| **W4** ✅ | **`scene_script`**: worker GDScript con ctx, transaccional, parse-check previo, validate post | Cerrado (E2E 27/27 + Omega) |
| **W4b** | `filesystem/scan` + import status | **Siguiente** — necesidad demostrada en E2E (EFS en frío no ve assets copiados) |
| **W5** | Runtime session + `runtime_script` (probes input/frames, lease, slot) — reemplaza `debug/run_scene` frágil | Pendiente |
| **W6** | (Opcional) `visual/capture` opt-in vía worker `ctx.capture()` | Pendiente |
| **W7** | Export/build headless (`godot --export-release` + validar presets) — **NADIE lo tiene; diferenciador** | Pendiente |
| **W8** | Test runner GUT/gdUnit headless — **NADIE lo tiene** | Pendiente |

**Pendiente W4**: limpieza de tools/steps que scene_script reemplaza (animation tree_*/skeleton/tilemap/ui theme+layout/signal/node duplicate+reorder+move+set_owner/shader material+uniform+apply + steps tipados Fases 2/2b/3/4) — propuesta al General pendiente de OK.

### Gaps (consolidado)

**Fundamentales (ellos Y nosotros)**: export/build headless · test runner GUT/gdUnit · deps inversos ("¿quién referencia este .tres?") · scene diff semántico · profiler/memoria · multiplayer/audio/perf verification · progreso streaming · snapshot/rollback de proyecto · modo headless/CI (NOSOTROS ya corremos plugin headless en tests = diferenciador).

**Solo nuestros (Fennara los tiene)**: gestión de imports (W4b) · startup pass headless por escena (vs nuestro validate/scene solo estructural) · seguridad de transporte (token+HMAC+approval; nosotros localhost abierto = aceptable para tool personal, bloqueante para distribuir) · multiplataforma (ellos Win/Linux/mac; nosotros Windows-first).

### Deuda estructural (2026-09-09)

- `server.rs` **101KB monolito** + `launcher.rs` **53KB** — split pendiente.
- `resource/delete` SIN protección de paths, cero gestión de imports, cero snapshot/backup — resueltos en W0.
- A1/A2/A3/A4 (dos registries, open dual, ok:true sin verificar, dispatcher fallbacks mágicos) — **W4/W5 sobre Fase 1**.

---

## 1. Filosofía de Hierro

- **Global**: PODER (Godot hace todo, cero límites) · EFICIENCIA (cada op óptima, sin huérfanos) · RAPIDEZ (~20ms/op).
- **Tools**: CENTRALIZADAS (pocas, por dominio) · MODULARES (1 tool, N acciones vía `action`) · POTENTES (1 llamada = flujo completo).
- **Derivado**: EditorPlugin REAL (v4), sesión = editor vivo, fail-fast, cache RAM, mutaciones con undo/redo.

### 📌 Lección aprendida (descripciones de tools)

**REGLA**: descripciones de tools SOLO genéricas — el agente debe saber QUÉ hace la tool. NO fechas, NO "v4.X", NO "P0.X", NO notas internas. Compactas, lo justo. Cada palabra extra consume contexto del agente. Lo que el desarrollador hace se registra en AGENTS.md §0, no en el schema.

---

## 2. Arquitectura (EditorPlugin + Rust)

```
OpenCode —STDIO NDJSON→ HerenServer.exe (Rust/FlojoMCP, WS server local 127.0.0.1:PUERTO) —WS→ HerenEditorPlugin
```

- `editor_plugin.gd` (lifecycle) · `ws_client.gd` (auto-reconnect) · `dispatcher.gd` (rutea tools→handlers, soporta coroutine) · `undo_redo_wrapper.gd` · `scene_registry.gd` · `heren_debugger_plugin.gd` · `handlers/` (scene, node, resource, animation+skeleton, shader, tilemap, project, debug, visual, signal, validate, coords).
- **Flujo**: cualquier tool call con `project_path` → `ensure_editor_connected` (auto-launch si falta) → WS al editor → plugin ejecuta → receipt. Sin tool de "abrir sesión".
- **Discovery (fix 2026-09-03, refinado 2026-09-18)**: cada server escribe `.heren/server_port.json` {port, pid} **en el project_path real** (no en CWD) cuando hay primer tool call con proyecto; el editor lee cada 5s y reconecta si el puerto cambia (editor reconecta solo tras reinicio de OpenCode). `ws_port()` = OnceLock + busca `9099+N` libre. ❌ `kill_previous_servers()` ELIMINADO (mataba servers de sesiones hermanas). **Ya NO se crea `.heren` en directorios no-Godot al arrancar el server**.

---

## 3. Reglas de Oro

1. **Pasar `project_path` SIEMPRE primero** (o tener un editor conectado — el server auto-detecta). Nunca operar sin proyecto resoluble; el primer tool call paga el auto-launch si hace falta.
2. Godot hace el trabajo pesado — NUNCA parsear .tscn a mano.
3. Tools centralizadas/modulares/potentes: el agente dice QUÉ, no CÓMO.
4. Cache amigo: 1ª vez disco (~3s), luego RAM (~0ms).
5. Fail-fast: NUNCA silenciar errores ni retornar None sin explicación.
6. LAIKA SOLO pruebas: source vive en `addons/heren/`; cambios → commit SOLO en heren-mcp.
7. **VALIDACIÓN DE SCRIPTS (OBLIGATORIA al terminar)**: Tras CUALQUIER cambio en `.gd`:
   - **Grafo completo**: `godot --headless --editor --path fixtures/empty_project --quit-after 5` + grep `SCRIPT ERROR|Parse Error` → 0. Un parse error en un handler rompe TODO el plugin.
   - **Suite**: `godot --headless --path fixtures/empty_project --script res://addons/heren/tests/run_tests.gd` → `N passed, 0 failed`.
   - **Script individual**: `validate(action="script")` usa `GDScript.reload()` → `reload_err=43` si roto.
   - Preferir tipos explícitos SIEMPRE: `var x := variant_member.size()` = "Cannot infer" (Variant no infiere).

---

## 4. Estructura

```
crates/heren-server/    # server Rust (src/: editor, launcher, registry, server, ws_plugin_server, lsp_bridge/, scene_tool/; tests/)
addons/heren/           # FUENTE del plugin (copiable a cualquier proyecto)
scripts/                # heren-build.bat (VsDevCmd+debug+test+release+clippy) · run.bat · install_mcp.py · install_plugin.py · validate_plugin.bat (compile+tests+sync 1-click) · deploy-fix.bat
fixtures/               # proyectos Godot mínimos para tests (empty_project/)
.temp/ · tests/ · benchmarks/  # tests activos en Rust/GUT; Python v3 archivado en rama archive/v3
```

---

## 5. Performance

~20ms/op con editor vivo (v4). Sin daemon. 1ª vez disco ~3s, cache hit RAM ~20ms.

---

## 6. Las 18 Tools

> **Checklist añadir/quitar tool**: AÑADIR = fn `#[tool]` en server.rs (tests `tools_parity.rs` cubren solos). QUITAR = borrar fn; guarda de regresión → `FORBIDDEN_TOOLS`. Tool sin patrón "1 tool N acciones" → `TOOLS_WITHOUT_ACTION`. NUNCA listas enumerativas — invariantes + conteo mínimo (`MIN_TOOLS`).

| # | Tool | Actions | Dominio |
|---|------|---------|---------|
| 1 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload, plan, orchestrate, validate, commit, status, list | Escenas |
| 2 | `node` | add, instantiate, remove, duplicate, rename, move, set_owner, reorder | Nodos (mutaciones) |
| 2b | `node_query` | get_prop, get_info, get_children, find, **class_info**, **props_diff** | Nodos (lecturas) |
| 2c | `node_props` | set_prop, set_props, array_append, array_remove | Nodos (props) |
| 3 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd |
| 4 | `project` | create, setup_plugin, setting, autoload, remove_autoload, input_map, shader_global | Configuración |
| 5 | `shader` | create, edit, get, inspect, validate, material, uniform, apply | Shaders |
| 6 | `animation` | create_player, create, add_track, add_key, state_machine, play/stop/seek/speed, get_*/remove_*/update_*, one_shot, tween, record, from_path, loop_pose, preview, curve, capture_pose, tree_*, duplicate/delete/rename/reverse, blend_pose, retarget | Animaciones |
| 7 | `skeleton` | skeleton_create, add_bone, set_rest, skin, attachment, get_*, set_pose, ik, fabrik, capture_pose | Esqueletos 2D/3D |
| 8 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps |
| 9 | `debug` | summary, status, breakpoint, control, stack, vars, profiler, run_scene, stop_scene, is_playing, get_editor_errors, output | Depuración |
| 10 | `validate` | scene, script, node, resource | Validación |
| 11 | `signal` | connect, disconnect, list, set_script | Señales |
| 12 | `visual` | coords, summary, ascii, spatial | Visión textual (Fase E: visual_image ELIMINADA) |
| 13 | `ui` | create, layout, canvas_layer, templates, get_info, theme | UI 2D |
| 14 | `health` | estado server + editores; `diagnose=true` ejecuta debugger unificado | Diagnóstico |
| 15 | `scene_script` | run, list | **W4 Worker-First**: worker GDScript del agente (§0.12) |

**Notas**: `scene/create` acepta `instance_scene`/`instance_current` → escena nueva contiene otra como ExtResource; guardas: no instanciarse a sí misma, fuente en disco. `node/instantiate` = instancia EXTERNA (`instance=ExtResource`) **o template del registry transversal** (`template:"health_bar"`, params via `properties`). `coords proactivas` en toda mutación (§7). `animation`+`skeleton` comparten `animation_handlers.gd`. Errores `node_not_found` incluyen `parent_children`. `rename`/`move` devuelven `previous_path`/`old_parent`. Recursos SIEMPRE por PATH (`res://...`); dict inline sin path → warning `resource_incrusted_inline`. **Sin tool `session`** (eliminado §0.5) — el primer tool call con `project_path` auto-lanza el editor.
**Templates (registry transversal)**: `addons/heren/templates/*.tscn` + `template_registry.gd` (nombre → escena). `node/instantiate {template, properties}` instancia + aplica params. Añadir template: .tscn en `templates/` + entrada en registry + test en `run_tests.gd`.
**Comparativa competidores** (README): datos VERIFICADOS de `.competitors/`. NUNCA marcar ❌ capacidad que el competidor SÍ tiene; re-verificar contra repos al actualizar.

---

## 7. Sistema de Coordenadas (ADR-005) + Visión

### Fuente única de verdad
**`HerenCoords.coords_of_node(node, parent_path, tier)`** en `addons/heren/handlers/coords.gd`. Estática, pura, testeable.

- **Discriminator** `kind` (clase Godot) + `flags` (is_2d/is_3d/is_control/has_bbox/has_aabb/has_dynamic_state).
- **Tiers**: 0 (~30 tok: kind+flags+parent+visible) · 1 (~80-150: pos/scale/rotation kind-specific + bbox/aabb) · 2 (~150-250: + modulate/material/collision/Control anchors-offsets-size) · 3 (resumen proactivo en TODA mutación: animation/animation_tree/skeleton resumen/light/audio/camera) · 4 (opt-in vía `visual/coords tier=4`: poses completas, params completos).
- **Pureza 2D ↔ 3D** (verificada por tests): Node2D jamás trae `quat`/`aabb`/`cast_shadow`; Node3D jamás trae `z_index`/`anchors`/`effective_rect`.
- **Proactividad**: 13/13 handlers de mutación devuelven `coords` + `scene_node_count`. Contrato completo en CHANGELOG (§0.11 Fase A).

**Prohibido**: reimplementar `_node_coords`/`_node_pos`/`_node_bbox`/`coords_of` legacy. Toda lectura/escritura de coords pasa por `coords_of_node`. Tests a tocar si cambia el contrato: `_test_coords_of_node_*` en `run_tests.gd`.

### Auto-detección de tipos (deserialize)
Keys: `x`+`y`→Vector2; `x`+`y`+`z`→Vector3; `r`+`g`+`b`→Color; `origin`+`x_axis`+`y_axis`→Transform2D; `origin`+`basis`→Transform3D; `normal`+`d`→Plane; `position`+`size`→Rect2/AABB. Vector2i/3i, Quaternion, StringName. `deserialize_resource` instancia por ClassDB. Strings `res://`/`user://` → string plano (nunca deserializar: UID sintético corrompía project.godot).

### Visión — jerarquía de costo
```
NIVEL 0: Coords textuales (siempre, proactivo)    ~20-100 tok
NIVEL 1: summary + ascii (sin imagen)             ~50-150 tok
NIVEL 2: capture (si existiera)                   ~200-400 tok
```
**Regla de oro:** NIVEL 0 primero; imagen solo cuando el texto no basta.

`visual/spatial` (Fase B): `overlaps` (bbox intersecta, padding), `distance` (from/to), `neighbors` (radius), `layout` (Control: effective_rect + container padding), `bounds` (AABB total 2D+3D). Módulo puro: `visual_tool/spatial_tool.gd`.

`visual/summary` (Fase D): recursivo — node_count, by_type, tree_depth, bounds_2d/3d, warnings (`z_fighting_risk`, `missing_material`, `missing_texture`, `missing_shape`), warning_count. Validator Engine B lee este JSON (sin imagen).

### Tier 3 dynamic state (7 secciones, pureza verificada)
`animation` (AnimationPlayer) · `animation_tree` (en sinergia: lleva `anim_player_state` snapshot del player asociado; NodePath RELATIVO al tree) · `skeleton_3d` (count + bone_names completos + 3 primeras poses; tier 4 = todas) · `skeleton_2d` (itera Bone2D children recursivo — `get_bone_count()` puede ser async en headless) · `light_3d` · `audio` · `camera`. Nodo sin estado dinámico → NO emite bloque `dynamic` (32 tok ahorrados). `flags.has_dynamic_state` = true si emitió.

---

## 8. Sin sesiones — auto-launch + `health`

**El editor conectado ES la sesión.** No hay tool de "abrir/cerrar sesión".

```
ConnectedEditors: {project_path → WS} (sin rol — un editor por proyecto).
Tool call con project_path → ensure_editor_connected():
  ├─ editor vivo conectado → OK (no-op, ~0ms)
  ├─ sin editor + auto_launch=true (default) → launch + wait connect (3-10s)
  └─ sin editor + auto_launch=false → error claro: abre Godot o habilita auto_launch
```

**`HEREN_AUTO_LAUNCH=0`** deshabilita el auto-launch (usuario abre Godot manualmente).
**`HEREN_DEFAULT_PROJECT=<path>`** fija el proyecto por defecto (si no, cae a `last_project`).

**Lifecycle del editor = del usuario**: el server **NUNCA** mata el editor al desconectar. El editor vive; el WS se reconecta vía discovery `.heren/server_port.json`.

**`health`** (reemplaza `session/health|info|status|list|diagnose`):
- Sin project_path: estado global (versiones, conexiones, env vars, auto_launch, last_project).
- Con project_path: detalle de ese proyecto (conexión, versiones, dirty, unexpected_close).
- Con `diagnose=true`: ejecuta el debugger unificado (integridad plugin + grafo headless sandbox).

`.heren/session.json` → SOLO `last_project` (persiste entre tool calls como fallback de `project_path`). NO se persiste: estado de planning, locks, roles (todo efímero RAM o por-proyecto en el plugin).

---

## 9. Animación — Gotchas API (v4.5+)

- `AnimationNodeBlendSpace3D` NO existe (solo 1D/2D). `connect_node(input, input_index, output)` = 3 args.
- `track_type` real: `value`/`position_3d`/`rotation_3d`/`scale_3d`/`method`/`bezier`/`audio` (NO `rotation`/`transform`).
- `rotation_3d` exige Quaternion `{x,y,z,w}` NORMALIZADO (norma=1) — handler normaliza; Vector3 falla (Godot rechaza conversión).
- `SkeletonIK3D.target_node` = NodePath, `magnet` = Vector3. `Skeleton2D` NO tiene find_bone/set_bone_rest (huesos = Bone2D hijos `.rest`). `BoneAttachment2D` NO existe. `set_bone_weights(find_bone(), PackedFloat32Array)` (índice, no nombre). IK 2D = FABRIK propio.
- `Light3D` NO tiene `light_enabled` property (4.5) — validar APIs con `has_method()`.

---

## 10. Decisiones (las que importan — historial completo en CHANGELOG)

**Arquitectura / multi-instancia**
- **EditorPlugin > GodotDaemon** (daemon corre `is_editor_hint=false` → nunca toca el editor real). WS plugin=cliente (patrón gopeak). Sesión = editor vivo RAM + `last_project` disco. FlojoMCP > FastMCP (schemas compile-time).
- **NDJSON, NO Content-Length** (OpenCore 1.18). Schemas booleanos `true` → `{}`. `args()` omite keys None (`str(null)`="<null>" rompía guards). id JSON-RPC tolera `1`/`"1"`/`"1.0"`.
- **`kill_previous_servers()` ELIMINADO.** `ws_port()` OnceLock + `9099+N`. Discovery (refinado 2026-09-18): `.heren/server_port.json` {port, pid} se escribe **en el project_path real** (no en CWD) al primer tool call con proyecto; editor lee cada 5s y reconecta si cambia. **Ya NO se crea `.heren` en directorios no-Godot al arrancar el server**.

**Plugin / launch**
- `enabled=PackedStringArray("res://addons/heren/plugin.cfg")` (path completo Godot 4). `"heren"` desnudo se acepta al leer pero se re-escribe completo; `PackedStringArray()` vacío = lost-update.
- **enable idempotente**: reemplaza CUALQUIER `enabled=` por la canónica; solo escribe si difiere. `Ok(false)` = ya canónico = ÉXITO.
- **Sync plugin incremental por contenido** (W0 + §0.14: `install_plugin.py --force`). 🚨 BUG RAÍZ histórico: `collect_files` perdía prefijo `handlers/` → "plugin up-to-date" MENTIRA. Fix: `walk(root, dir)` con root original.
- `launch_editor`: zombie kill → sleep → escribe plugin+enable → relanza. No relanza si no hace falta. Godot NO tiene hot-reload de plugins (#11612).
- **Detección editor**: CIM → tasklist → wmic (wmic ELIMINADO en Win11 24H2+). PowerShell escapa comillas como `""` → parser CSV robusto + `decode_win_output` (UTF-16LE con BOM).

**Contexto escena / save**
- **Prioridad**: pestaña real → registry → disco. `normalize_scene_path` SIEMPRE (8 tools + plugin defensivo).
- **`scene/save` = pack directo** + `ensure_owner_recursive` + ResourceSaver (NUNCA `save_scene()` de pestaña). Disco = fuente de verdad: `resolve_root` hace `sync_from_disk` (mtime) + re-aplica `_pending_ops`.
- **`set_prop` verifica valor aplicado** (`applied_value` + `_values_match`). `is_instance_valid(root)` ANTES de `is Node` (freed instance crash).
- 🚨 **Save NO re-embebe scripts**: `FLAG_BUNDLE_RESOURCES` INCORPORA .gd dentro del .tscn (QUITADA de handle_save y _create_scene_file). 🚨 Godot #44008: con PackedScene pierde props modificadas → `ensure_resource_local_recursive` QUITADA. Sub-recursos sin path se serializan inline naturalmente. `class_name` embebido built-in = parse error → SIEMPRE ext_resource por path.

**Recursos / serialización**
- **Sub-recursos inline viajan COMPLETOS** (`{"__type":"Resource", resource_class, props}` filtro STORAGE). Strings `res://` → string plano (nunca deserializar: UID sintético corrompía project.godot).
- **`resource_handlers` sin undo/redo** (archivos externos, `EditorFileSystem.update_file()`). `delete` usa DirAccess. `_ensure_parent_dir()` antes de escribir. `.gd/.tscn/.godot` sin BOM.
- **`project/input_map`** persistencia REAL: `ProjectSettings.set_setting("input/<action>", ...)` + save. GET siempre `restart_required:false`. `input_map/list` lee `ProjectSettings.get_property_list()` filtrado `input/`.
- 🚨 **Color (BUG 3)**: `GodotVariant` serializa dicts anidados como strings JSON por WS → plugin recibe `String`. `deserialize_value` parsea JSON antes de procesar. (R1 §0.5 lo elimina de raíz.)

**Shader / debug**
- 🚨 `Shader.get_errors()` NO EXISTE en 4.7 → `var x := sh.get_errors()` = Parse Error → plugin muerto. Helpers restaurados desde commit `0728708` (§0.13): `_shader_structural_issues` + heurística. `sh.get_mode()` no `.mode`. **Lección: validar APIs con `has_method()`.**
- 🚨 `EditorDebuggerPlugin._capture` SOLO recibe mensajes con `:` — `error`/`output`/`stack_dump` NUNCA llegan. Camino real: signal `debug_data` del `ScriptEditorDebugger`. Hook one-shot falla si dock no montado → reintentos 10×1s + conecta a TODOS. `handle_vars` espera señal real con timeout 2s.

**Planning / schemas**
- 🚨 adapters/coder reenviaban con nombres MCP `godot_*` — dispatcher rutea por prefijo BARE → **Regla: `forward()` SIEMPRE usa nombres internos `prefijo/metodo`**. Planning = sub-comandos server-side de tool `scene` — NUNCA tool separada.
- 🚨 **`SceneStep::AddNode.properties` passthrough VERBATIM** (serde descartaba silenciosamente). Workplane enum: rename explícito + alias (serde `x_z` vs schemars `XZ`). `plan_file` viaja como ARCHIVO. orchestrate continue-on-error.
- 🚨 **Lección meta**: verificar con grep que las ediciones grandes REALMENTE aplicaron — dos edits reportaron "OK" y no aplicaron (mojibake en oldString); binario viejo quedó expuesto.
- **Fase F tipos semánticos**: `Option<serde_json::Value>` genera schema `{}` → FlojoMCP `types.rs` con wrappers (`GodotVariant`, `GodotDict`...) + `#[schemars(description)]`. 42 props vacías → 0.
- **v4.6 split tools**: schema plano 15 params = laberinto. Fix: (a) args `Option<>` con defaults; (b) split node/node_query/node_props; (c) orientación continua (`parent_children`); (d) anti-incrustado: recursos inline → warning `resource_incrusted_inline`. Regla: recursos SIEMPRE por PATH.

**Otros**
- 🚨 **Capture durante play**: `_render_scene_offscreen` durante `is_playing_scene()` compite por GPU → timeout 30s. Guard: rechazar con `capture_blocked_during_play`.
- **Coords globales**: gates con `is_inside_tree()` evitan `get_global_transform` warning. Props 4.5+ con `in` defensivo. `_relpath` sin `get_path()` (requiere SceneTree) — construido manual con parent chain.

---

## 11. Gotchas y Lecciones

**🚨 Críticos (causan crashes/silencios)**
- **Tools MCP se cargan al INICIO de la sesión** → tras recompilar el server, SESIÓN NUEVA (toolset no refresca en conversación en curso).
- **Un parse error en un handler rompe TODO el plugin** → editor no conecta sin error visible. Validar: grafo completo headless + grep. (2026-09-05: `--check-only` en 4.5 SÍ detecta "Cannot infer"; de todas formas preferir tipos explícitos).
- **🚨 Cache de recursos GDScript (W4)**: `load()` de un .gd ya cargado devuelve el resource CACHED con el source VIEJO → `reload()` recompila el código roto de siempre. Fix (scene_script.gd): refrescar `gd.source_code = FileAccess.get_file_as_string(path)` ANTES de `reload()`.
- **🚨 `add_child()` con nombre en conflicto** (W4 E2E): con `force_readable_name=false` (default), un nombre duplicado se reemplaza por `@Class@ID` (NO "Tower2"). Workers deben usar `ctx.ensure_unique_child_name(parent, nombre)` ANTES de add_child.
- **🚨 Contrato de errores scene_script (W4)**: fallo del WORKER = `ok:true + ran:false` + diagnósticos + `script_path` (el payload sobrevive el transporte). `ok:false` viaja como JSON-RPC error **SIN payload** (ws_client descarta el dict) — solo el mensaje. Workflow de retry: parchar el script_path devuelto + re-run.
- **🚨 Runtime errors en workers abortan SILENTAMENTE (E2E Omega)**: `skel.add_bones()` NO existe en 4.7 → el worker abortó en esa línea sin error visible; el save lo hizo un step posterior. Los receipts (`ran:false`) lo delatan, pero orchestrate NO los devuelve. Lección doble: (1) validar APIs con `has_method()` en workers (patrón del fix), (2) **W2 class_info es la prevención estructural**.

**Triviales (anotan para no repetir)**
- **Handlers source NO se sincronizan solos con E2E** (`.temp/e2e_complex/...`) → copiar manual tras cada cambio (ahora via `validate_plugin.bat`).
- `String.split()` devuelve `PackedStringArray`** (sin `pop_back`) → tipar `var segments: Array`. `NodePath` no tiene `begins_with`/`trim_prefix` → `str(path)` primero.
- `Copy-Item -Recurse` anida contenido si el destino existe → `Remove-Item` antes de copiar el plugin al fixture.
- Config MCP OpenCode: clave `environment` (NO `env`); existe `"timeout"` (ms, default 5000).
- Godot headless compite por .godot lock → editor cerrado o copia.
- NO definir `func get_editor()` en EditorPlugin (colisiona) → `get_editor_interface()`.
- `add_do_method` Godot 4.6: `(Object, StringName, args)` — NO Callable directo. `callv` con `callv(&"add_do_method", [obj, method] + args)` (expande Array).
- Consola Windows cp1252 → nada de emojis en output Python (`UnicodeEncodeError`); forzar UTF-8.
- **Nota log de sesión (no es del MCP)**: `failed to load plugin path=list error="Plugin export is not a function"` → config global OpenCode tiene `"plugin": ["list"]` pero el paquete NO existe. Fix: quitar de config o instalar el paquete.

**Pendientes (bugs/features abiertos descubiertos en E2E Omega)**
- EFS scan en frío: assets recién copiados son invisibles hasta que el EFS escanea. Solución = W4b.
- orchestrate: no devuelve receipts por step + exige escena existente (workaround: scene/create primero).
- visual/coords con node_path cae a contexto stale (misma respuesta para "Rig" y "AnimTree") — investigar (M2).

---

## 12. Checklist

- [ ] **Plan W (§0.12)**: ~~W0~~ ✅ → ~~W1~~ ✅ → ~~W2~~ ✅ → ~~W3~~ ✅ → ~~W4~~ ✅ (E2E 27/27 + Omega) → W4b imports → W5 runtime. **Pendiente W4: limpieza de tools reemplazadas** (propuesta al General). W7/W8 (export/build, test runner) = diferenciadores.
- [ ] **§0.5 Sin sesiones** (✅ arquitectura, ✅ R0 codec): implementado (Opción B — reemplazar tool session por auto-launch + health). Pendientes: R3 fuzz permanente, W4b (imports/readiness).
- [ ] §0.8 Fases 1-3 (single registry, fail-fast, dispatcher explícito) — W4/W5 sobre Fase 1.
- [ ] M1 array_remove · M2 summary node_count · M3 validate/node scripts · P5 verbose · P10 get_animation.
- [ ] **BUG NUEVO (E2E Omega)**: visual/coords con node_path cae a contexto stale (misma respuesta para "Rig" y "AnimTree") — investigar.
- [ ] orchestrate: devolver receipts por step + soportar escenas nuevas del plan.
- [ ] Split server.rs (101KB) + launcher.rs (53KB).
- [ ] E2E manual con proyecto del bug report (humanoid.tscn + 8 input actions).
- [x] **§0.13 W4-c validador maduró** (2026-09-10): 13 reglas heurísticas en `static_analyze_gdscript`, `parse_hints` inline en `validate/script` y `validate/scripts`, 17 tests nuevos, 2 bugs colaterales resueltos (NodePath==String en node_handlers.gd:372 + shader_handlers.gd sin helpers).
- [x] **§0.14 install_plugin.py --force + validate_plugin.bat** (2026-09-10): sync content-aware + validador 1-click (sync fixtures → compile → tests → cargo build).

### Validación obligatoria (§3.7) — flujo compacto

**Tras CUALQUIER cambio en `.gd`** — corre UNO de estos:

```bash
# 1-click (Windows; corre desde cmd directo, no PowerShell):
scripts\validate_plugin.bat

# Manual (4 pasos; equivalente exacto):
powershell -File .temp\sync_fixtures.ps1   # o el cp manual que está en el bat
godot --headless --editor --path fixtures\empty_project --quit-after 5   # grep SCRIPT ERROR → 0
godot --headless --path fixtures\empty_project --script res://addons/heren/tests/run_tests.gd   # "N passed, 0 failed"
cargo build -p heren-server                # solo si tocaste Rust
```

**Sync de plugin a fixtures** (sin `validate_plugin.bat`):
```bash
# Diff real (sincroniza solo lo que cambió):
python scripts\install_plugin.py --project fixtures\empty_project --force --dry-run   # muestra diff
python scripts\install_plugin.py --project fixtures\empty_project --force               # aplica
```

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
