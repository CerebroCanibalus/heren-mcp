# Changelog — Heren MCP

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
