# 🐉 Heren MCP — AGENTS.md

> Biblia del agente. Léelo antes de tocar código.
>
> **ESTADO: v4.4.2 OPERATIVO** — EditorPlugin (GDScript→EditorInterface) + heren-server.exe Rust/FlojoMCP.
> 15 tools centralizadas, WS plugin server (patrón gopeak), auto-launch, NDJSON por stdio.
> Workspace Rust local (`crates/heren-server`); FlojoMCP = framework SOLO (flojo-mcp/macros/session @ crates.io, consumido por version, no path).
> Bridge Python (`python -m heren.v4.bridge`) = fallback/referencia, NO activo. **Cambios nuevos → v4/Rust.**
> Plugin SIEMPRE ENCENDIDO + sync incremental por contenido + `session/diagnose` (debugger unificado).

---

## 0. 🚨 Pendientes

- **M1** `node/array_remove`: borra el primer elemento, no el `value` (int vs float en `find`). Fix: tipar/normalizar.
- **M2** `visual/summary`: `node_count:0` inconsistente (by_type OK). Handler cuenta mal.
- **M3** `validate/node`: `script_cannot_instantiate` — scripts MCP no se compilan. Falta re-import/scan.
- **Visual**: `budget`/`cache` → handler `handle_vision_budget/cache` NO existe en el plugin. `coords` incompleto (3 nodos, paths "..").
- **Gaps tool**: `node` no expone query/by/recursive/owner_path/script (usar `orchestrate` con args crudos); `resource` no crea dirs padre (crearlos antes); `resource` exige requireds irrelevantes en create_script/edit_script (hacerlos opcionales).

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
scripts: heren-build.bat (VsDevCmd+debug+test+release+clippy) · run.bat · install_mcp.py · deploy-fix.bat (rename exe en uso→copia nuevo)
src/heren/              # bridge Python (fallback, NO activo)
.temp/ · tests/ · benchmarks/
```

---

## 5. Performance

~20ms/op con editor vivo (v4). Sin daemon (v3 ELIMINADO). 1ª vez disco ~3s, cache hit RAM ~20ms.

---

## 6. Las 15 Tools

| # | Tool | Actions | Dominio |
|---|------|---------|---------|
| 1 | `session` | open, close, list, info, health, **diagnose** | Sesiones |
| 2 | `scene` | get_open_scenes, get_edited_scene_root, open, save, create, unload | Escenas |
| 3 | `node` | add, instantiate, remove, set_prop, get_prop, get_info, get_children, find, duplicate, rename, move, set_owner, reorder, array_append, array_remove | Nodos |
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
| 14 | `visual` | coords, summary, ascii, capture, node, budget, cache | Visión §7 |
| 15 | `health` | server + editor status | Health |

**Notas:** `node/instantiate` = instancia EXTERNA (`instance=ExtResource`, no copia inline). `coords proactivas` en toda mutación (§7). `animation`+`skeleton` comparten `animation_handlers.gd`. `session/diagnose` = integridad plugin (ok/stale/missing/orphan) + grafo headless en sandbox + estado editor.
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
> PENDIENTE: validación E2E en vivo.

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
| **project** | `create` sin editor (escribe project.godot directo — evita circular dependency). `setting` con `op` + `restart_required` (prefijos read-at-startup) / `applied_runtime` (viewport, max_fps). `input_map` persistencia REAL: `ProjectSettings.set_setting("input/<action>", {deadzone, events})` — InputMap/ProjectSettings.save() solo RAM. |
| **Skeleton** | 🚨 Skeleton2D NO tiene find_bone/set_bone_rest (API falsa): huesos = Bone2D hijos `.rest=Transform2D`. `BoneAttachment2D` NO existe (Node2D hijo — Parse Error rompía el plugin). `set_bone_weights(find_bone(), PackedFloat32Array)` (índice, no nombre). IK 2D = FABRIK propio (Godot no tiene nativo). |
| **Handlers** | `signal/list` defensivo (conn as Dictionary, `.get()`, key `"signal"`). `material.resource_name` (Resource NO tiene `.name`). `_ensure_parent_dir()` antes de escribir. `undo_redo add_do_method` con `callv` (expande Array). Escribir .gd/.tscn/.godot sin BOM (`UTF8Encoding($false)`). |
| **diagnose (v4.4.2)** | `session/diagnose`: integrity (ok/stale/missing/orphan por archivo, tamaños) + graph (copia addons/heren a sandbox `%TEMP%/heren_graph_check_<pid>`, `godot --headless --editor --quit-after 3`, captura SCRIPT ERROR/Parse Error, limpia SIEMPRE) + editor (procesos con cmdline, WS, puerto). Detecta lo que `--check-only` individual NO ve. Verificado: diagnosticó el crash real sin tocar el proyecto. |
| **debug output (v4.5)** | 🚨 `EditorDebuggerPlugin._capture` SOLO recibe mensajes con `:` (sed.cpp `plugins_capture`: `colon_index < 1` = invalid) — los mensajes `error`/`output`/`stack_dump` NUNCA llegan al plugin. El camino real: signal `debug_data` del `ScriptEditorDebugger` (emite TODOS los mensajes ANTES del handler integrado, sed.cpp `_parse_message`). Hook one-shot por árbol fallaba silencioso si el dock no estaba montado → 0 errores. Fix: reintentos 30×1s + conecta a TODOS los ScriptEditorDebugger del TabContainer (multi-sesión). El texto `E hh:mm:ss:mmm ...` del panel Output = mensaje `output` con `MESSAGE_TYPE_ERROR=2` (sed.cpp:590) → expuesto como `debug/get_editor_errors → output_errors` y `debug/output` (filter=error\|all). Formato `error` estructurado = OutputError marshall [hr,min,sec,msec,file,func,line,error,descr,warning,stack*3] verificado en debugger_marshalls.cpp 4.7. |

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
| `orchestrate` "Unknown error" | tool:"node/add" normalizado; errores por op en results (no abortan batch) |
| Deadlock stderr sin drenar | tracing SOLO a `HEREN_LOG_FILE`, nunca stderr |
| Build MSVC | `heren-build.bat` carga VsDevCmd del BuildTools 2022 |
| Macro FlojoMCP visibilidad | `#[flojo_mcp]` usaba `item.vis` (no hardcode) |
| deserialize_value no recorría Array | Rama `elif value is Array` recursiva |
| project.godot corrupto (BOM) | `WriteAllText(..., UTF8Encoding($false))` |
| Undo/redo node/add devolvía path vacío | `callv(&"add_do_method", [obj, method] + args)` |

---

## 12. Gotchas y Lecciones

- **Tools MCP se cargan al INICIO de la sesión** → tras recompilar el server, SESIÓN NUEVA (toolset no refresca en conversación en curso).
- **Un parse error en un handler rompe TODO el plugin** → editor no conecta sin error visible. Validar: `--check-only --script` + **grafo completo** `godot --headless --editor --path <proj> --quit-after 3` grep `SCRIPT ERROR|Parse Error` (—check-only NO detecta `:=` "Cannot infer"; preferir tipos explícitos).
- **Handlers source NO se sincronizan solos con E2E** (`.temp/e2e_minigame/...`) → copiar manual tras cada cambio.
- Config MCP OpenCode: clave `environment` (NO `env`); existe `"timeout"` (ms, default 5000).
- Godot headless compite por .godot lock → editor cerrado o copia.
- NO definir `func get_editor()` en EditorPlugin (colisiona) → `get_editor_interface()`.
- `add_do_method` Godot 4.6: `(Object, StringName, args)` — NO Callable directo.
- resource_handlers sin undo/redo (archivos externos, `EditorFileSystem.update_file()`). `delete` usa DirAccess (ResourceLoader no borra).
- Consola Windows cp1252 → nada de emojis en output Python (`UnicodeEncodeError`); forzar UTF-8.

---

## 13. Checklist

- [ ] ¿undo/redo en mutaciones de escena? ¿coords unificadas + `tokens_estimate` en visual?
- [ ] ¿Tests (Rust) + GUT? ¿documentado en AGENTS.md?
- [ ] ¿Validado `--check-only` + grafo completo headless tras editar handlers?
- [ ] ¿Cambios al plugin SOLO en `addons/heren/` (nunca LAIKA)? ¿bridge v4 operativo?
- [ ] ¿Sesión nueva tras recompilar el server?

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
