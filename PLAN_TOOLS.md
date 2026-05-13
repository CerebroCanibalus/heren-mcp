# Plan de Migración de Tools - Heren MCP (Híbrido Moderado)

## Inventario Original: 93 Tools

El MCP original tenía **93 tools** dispersas en 15 archivos:

| Archivo | Tools | Cantidad |
|---------|-------|----------|
| `session_tools.py` | start_session, end_session, get_active_session, list_sessions, get_session_info, commit_session, discard_changes | 7 |
| `scene_tools.py` | create_scene, get_scene_tree, save_scene, list_scenes, instantiate_scene, modify_scene, set_editable_paths, remove_ext_resource, remove_sub_resource | 9 |
| `node_tools.py` | add_ext_resource, add_node, remove_node, update_node, get_node_properties, rename_node, move_node, duplicate_node, find_nodes, add_node_groups, remove_node_groups | 11 |
| `project_tools.py` | get_project_info, list_projects, get_project_structure, find_scripts, find_resources | 5 |
| `property_tools.py` | set_node_properties (con schema masivo) | 1 |
| `signal_and_script_tools.py` | connect_signal, disconnect_signal, list_signals, set_script, add_sub_resource | 5 |
| `array_tools.py` | scene_array_operation, preview_array_operation | 2 |
| `validation_tools.py` | validate_tscn, validate_gdscript, validate_scene_references, validate_project | 4 |
| `resource_tools.py` | create_resource, read_resource, update_resource, get_uid, update_project_uids, list_resources | 6 |
| `resource_builder_tools.py` | build_resource, build_nested_resource, create_state_machine, create_blend_space_1d, create_blend_space_2d, create_blend_tree, create_sprite_frames, create_tile_set, batch_create_animations, add_animation_track | 10 |
| `global_tools.py` | add_autoload, remove_autoload, list_autoloads, set_autoload_enabled, set_shader_global, get_shader_globals, remove_shader_global, add_global_group, remove_global_group, list_global_groups, set_project_setting, get_project_setting, get_project_settings, remove_project_setting | 13 |
| `shader_tools.py` | manage_shader, manage_shader_material, create_render_pipeline, analyze_shader | 4 |
| `debug_tools.py` | run_debug_scene, check_script_syntax | 2 |
| `tilemap_tools.py` | inspect_tileset, inspect_tilemap, set_tilemap_cells, set_tilemap_layer_properties, apply_tilemap_terrain, create_tilemap_pattern, set_tilemap_pattern, render_tileset_atlas | 8 |
| `skeleton_tools.py` | create_skeleton2d, add_bone2d, setup_polygon2d_skinning, create_skeleton3d, add_bone_attachment3d, setup_mesh_skinning | 6 |

**Total: 93 tools** → Problema: Saturación de contexto, difícil de recordar, repetición de lógica.

---

## Arquitectura Heren Híbrida Moderada: ~18 Tools

**Filosofía**: Centralizar lo simple, especializar lo complejo.

### Grupo A: Altamente Centralizadas (3-5 actions cada una)
Operaciones simples, comparten lógica, usadas constantemente.

| # | Tool | Actions | Cobertura Original |
|---|------|---------|-------------------|
| 1 | `session_tool` | start, end, info, list, commit, discard | 7 session tools |
| 2 | `scene_tool` | get_tree, save, create, list, instantiate, modify, info | 9 scene tools |
| 3 | `node_tool` | add, remove, update, get_props, rename, move, duplicate, find, groups | 11 node tools |

### Grupo B: Moderadamente Centralizadas (2-4 actions)
Dominios relacionados con lógica compartida.

| # | Tool | Actions | Cobertura Original |
|---|------|---------|-------------------|
| 4 | `signal_tool` | connect, disconnect, list, set_script | 4 signal/script tools |
| 5 | `validation_tool` | tscn, gdscript, references, project | 4 validation tools |
| 6 | `debug_tool` | run_scene, check_syntax, profile | 2 debug tools |

### Grupo C: Especializadas (1 action principal)
Lógica demasiado compleja para centralizar sin parameter bloat.

| # | Tool | Acción Principal | Cobertura Original |
|---|------|------------------|-------------------|
| 7 | `resource_tool` | create, read, update, list | 6 resource tools |
| 8 | `animation_tool` | batch_create, add_track, create_library | batch_create_animations, add_animation_track |
| 9 | `state_machine_tool` | create_state_machine, create_blend_space, create_blend_tree | create_state_machine, blend_space_1d/2d, blend_tree |
| 10 | `sprite_tile_tool` | create_sprite_frames, create_tile_set | create_sprite_frames, create_tile_set |
| 11 | `shader_management_tool` | create, edit, read, validate, delete, list_templates | manage_shader (modos) |
| 12 | `shader_material_tool` | create, set_params, read_params, clear_params | manage_shader_material |
| 13 | `render_pipeline_tool` | create_pipeline | create_render_pipeline |
| 14 | `shader_analyze_tool` | inspect, optimize, compare, profile | analyze_shader |
| 15 | `tilemap_inspect_tool` | inspect_tileset, inspect_tilemap | inspect_tileset, inspect_tilemap |
| 16 | `tilemap_edit_tool` | set_cells, terrain, pattern | set_tilemap_cells, apply_terrain, create/set_pattern |
| 17 | `tilemap_render_tool` | render_atlas | render_tileset_atlas |

### Grupo D: Atómicas (1 action con sub-modes)
Operaciones simples que no justifican más granularidad.

| # | Tool | Actions | Cobertura Original |
|---|------|---------|-------------------|
| 18 | `project_tool` | info, structure, find_scripts, find_resources, list_projects | 5 project tools |
| 19 | `global_tool` | autoload, shader_global, group, project_setting | 13 global tools |
| 20 | `skeleton_tool` | create, add_bone, skinning | 6 skeleton tools |

**Total: ~20 tools** → 78% de reducción (93 → 20). Balance óptimo entre simplicidad y evitar parameter bloat.

---

## Especificación de Tools

### Grupo A: Altamente Centralizadas

#### 1. session_tool (YA IMPLEMENTADO ✅)

```python
@heren.tool()
def session_tool(
    session_id: str = "",
    action: str = "info",  # "start", "end", "info", "list", "commit", "discard"
    project_path: str = "",
    save: bool = True,
) -> dict:
    """Gestiona sesiones de proyecto. action="start" requiere project_path."""
```

**Status**: ✅ Funcional en `src/heren/tools/scene_tools.py`

---

#### 2. scene_tool (YA IMPLEMENTADO ✅)

```python
@heren.tool()
def scene_tool(
    session_id: str,
    action: str = "get_tree",  # "get_tree", "save", "create", "list", "instantiate", "modify", "info"
    scene_path: str = "",
    project_path: str = "",
    root_type: str = "Node2D",
    root_name: str = "Root",
    inherits: str = "",
    parent_scene_path: str = "",
    node_name: str = "",
    parent_node_path: str = ".",
    editable_children: bool = False,
    new_root_type: str = "",
    new_root_name: str = "",
) -> dict:
    """Operaciones CRUD de escenas. Godot CLI nativo, sin parser propio."""
```

**Status**: ✅ Funcional con templates: `get_scene_tree`, `save_scene`

**Faltan implementar via Godot CLI**:
- `create` - Crear nueva escena desde cero
- `list` - Listar escenas del proyecto  
- `instantiate` - Instanciar una escena en otra
- `modify` - Modificar propiedades de escena
- `info` - Obtener metadata de escena

---

#### 3. node_tool (YA IMPLEMENTADO ✅)

```python
@heren.tool()
def node_tool(
    session_id: str,
    action: str = "add",  # "add", "remove", "update", "get_props", "rename", "move", "duplicate", "find", "groups"
    scene_path: str = "",
    node_path: str = "",
    parent_path: str = ".",
    node_type: str = "",
    node_name: str = "",
    properties: dict = None,
    unique_name_in_owner: bool = False,
    new_properties: dict = None,
    new_name: str = "",
    new_parent_path: str = "",
    duplicate_name: str = "",
    name_pattern: str = "",
    type_filter: str = "",
    groups: list = None,
    groups_action: str = "add",  # "add", "remove"
) -> dict:
    """Operaciones CRUD de nodos. Godot CLI nativo."""
```

**Status**: ✅ Funcional con templates: `add_node`, `remove_node`, `set_property`, `get_node_properties`

**Faltan implementar**:
- `rename`, `move`, `duplicate`, `find`, `groups`

---

### Grupo B: Moderadamente Centralizadas

#### 4. signal_tool (NUEVO - Por implementar)

```python
@heren.tool()
def signal_tool(
    session_id: str,
    action: str = "connect",  # "connect", "disconnect", "list", "set_script"
    scene_path: str = "",
    # Para connect/disconnect/list
    from_node: str = "",
    signal_name: str = "",
    to_node: str = "",
    method: str = "",
    flags: int = 0,
    binds: list = None,
    # Para set_script
    node_path: str = "",
    script_path: str = "",
) -> dict:
    """Gestión de señales y scripts en escenas."""
```

**Mapeo desde original**:
- `action="connect"` → `connect_signal()`
- `action="disconnect"` → `disconnect_signal()`
- `action="list"` → `list_signals()`
- `action="set_script"` → `set_script()`

**Implementación**: Godot CLI templates que modifiquen connections y scripts en PackedScene.

**Prioridad**: Alta. Conectar señales es workflow fundamental.

---

#### 5. validation_tool (NUEVO - Por implementar)

```python
@heren.tool()
def validation_tool(
    session_id: str,
    action: str = "tscn",  # "tscn", "gdscript", "references", "project"
    project_path: str = "",
    # Para tscn
    scene_path: str = "",
    strict: bool = False,
    # Para gdscript
    script_path: str = "",
    script_content: str = "",
    use_godot_syntax: bool = True,
    # Para references
    ref_scene_path: str = "",
    # Para project
    validate_strict: bool = False,
) -> dict:
    """Validación de escenas, scripts y referencias."""
```

**Mapeo desde original**:
- `action="tscn"` → `validate_tscn()`
- `action="gdscript"` → `validate_gdscript()` (3 capas: Godot real, API, patrones)
- `action="references"` → `validate_scene_references()`
- `action="project"` → `validate_project()`

**Prioridad**: Alta. Validación pre-guardado es crítica.

---

#### 6. debug_tool (NUEVO - Por implementar)

```python
@heren.tool()
def debug_tool(
    session_id: str,
    action: str = "run_scene",  # "run_scene", "check_syntax", "profile"
    project_path: str = "",
    # Para run_scene
    scene_path: str = "",
    godot_path: str = "",
    timeout: int = 30,
    debug_collisions: bool = False,
    debug_paths: bool = False,
    debug_navigation: bool = False,
    # Para check_syntax
    script_path: str = "",
    # Para profile
    profile_scene: str = "",
    profile_duration: int = 5,
) -> dict:
    """Ejecutar Godot headless para debug, validación y profiling."""
```

**Prioridad**: Media. Útil para validación pero no bloqueante.

---

### Grupo C: Especializadas

#### 7. resource_tool (NUEVO - Por implementar)

```python
@heren.tool()
def resource_tool(
    session_id: str,
    action: str = "create",  # "create", "read", "update", "list"
    resource_path: str = "",
    project_path: str = "",
    resource_type: str = "",
    properties: dict = None,
) -> dict:
    """Gestión básica de recursos .tres."""
```

**Mapeo desde original**: `create_resource`, `read_resource`, `update_resource`, `list_resources`

**Implementación**: Python puro + parser .tres (ya existe en MCP original).

**Prioridad**: Media.

---

#### 8. animation_tool (NUEVO - Por implementar)

**¿Por qué separada de resource_tool?** Las animaciones requieren lógica compleja de tracks, keyframes, y flattening de propiedades. No merece estar en la tool simple de recursos.

```python
@heren.tool()
def animation_tool(
    session_id: str,
    action: str = "batch_create",  # "batch_create", "add_track", "create_library"
    scene_path: str = "",
    # Para batch_create
    animations: list = None,
    # Para add_track
    animation_name: str = "",
    track: dict = None,
    # Para create_library
    library_name: str = "",
    animation_references: list = None,
) -> dict:
    """Creación y gestión de Animation resources con tracks y keyframes."""
```

**Mapeo desde original**: `batch_create_animations`, `add_animation_track`

**Prioridad**: Alta. Animaciones son críticas para cualquier juego.

---

#### 9. state_machine_tool (NUEVO - Por implementar)

**¿Por qué separada?** State machines requieren jerarquías complejas de SubResources con referencias cruzadas. Especializar evita parameter bloat.

```python
@heren.tool()
def state_machine_tool(
    session_id: str,
    action: str = "state_machine",  # "state_machine", "blend_space", "blend_tree"
    scene_path: str = "",
    # Para state_machine
    name: str = "",
    states: list = None,
    transitions: list = None,
    # Para blend_space
    blend_space_type: str = "1d",  # "1d", "2d"
    animations: list = None,
    min_space: dict = None,
    max_space: dict = None,
    # Para blend_tree
    nodes: list = None,
    connections: list = None,
) -> dict:
    """Creación de AnimationNodeStateMachine, BlendSpace y BlendTree."""
```

**Mapeo desde original**: `create_state_machine`, `create_blend_space_1d/2d`, `create_blend_tree`

**Prioridad**: Alta.

---

#### 10. sprite_tile_tool (NUEVO - Por implementar)

**¿Por qué separada?** SpriteFrames y TileSet tienen APIs completamente diferentes. Pero son simples enough para estar juntas.

```python
@heren.tool()
def sprite_tile_tool(
    session_id: str,
    action: str = "sprite_frames",  # "sprite_frames", "tile_set"
    scene_path: str = "",
    # Para sprite_frames
    sprite_name: str = "",
    sprite_animations: list = None,
    # Para tile_set
    tileset_name: str = "",
    tile_size: dict = None,
    sources: list = None,
    physics_layer_0: dict = None,
) -> dict:
    """Creación de SpriteFrames y TileSet resources."""
```

**Mapeo desde original**: `create_sprite_frames`, `create_tile_set`

**Prioridad**: Media.

---

#### 11. shader_management_tool (NUEVO - Por implementar)

**¿Por qué separada de shader_material_tool?** Manage shader opera sobre archivos .gdshader puros. Material opera sobre nodos en escenas. Dominios diferentes.

```python
@heren.tool()
def shader_management_tool(
    session_id: str,
    action: str = "create",  # "create", "edit", "read", "validate", "delete", "list_templates"
    project_path: str = "",
    shader_path: str = "",
    template: str = "",
    code: str = "",
    uniforms: dict = None,
    render_modes: list = None,
    replace_section: str = "",
) -> dict:
    """Gestión de archivos .gdshader: crear, editar, validar, eliminar."""
```

**Mapeo desde original**: `manage_shader()` (modos create, edit, read, validate, delete, list_templates)

**Implementación**: Python puro (shaders son archivos de texto).

**Prioridad**: Media.

---

#### 12. shader_material_tool (NUEVO - Por implementar)

```python
@heren.tool()
def shader_material_tool(
    session_id: str,
    action: str = "create",  # "create", "set_params", "read_params", "clear_params"
    project_path: str = "",
    scene_path: str = "",
    target_node: str = "",
    shader_path: str = "",
    params: dict = None,
    material_name: str = "",
    use_override: bool = True,
) -> dict:
    """Asignar ShaderMaterial a nodos y gestionar parámetros de shader."""
```

**Mapeo desde original**: `manage_shader_material()`

**Implementación**: Godot CLI (requiere instanciar escena y modificar nodos).

**Prioridad**: Media.

---

#### 13. render_pipeline_tool (NUEVO - Por implementar)

**¿Por qué separada?** Es una tool muy específica que crea escenas completas de post-procesado. No encaja bien con las otras.

```python
@heren.tool()
def render_pipeline_tool(
    session_id: str,
    project_path: str = "",
    pipeline_name: str = "",
    effects: list = None,
    resolution: dict = None,
    output_to_screen: bool = True,
) -> dict:
    """Crear cadenas de post-procesado con ColorRects encadenados."""
```

**Mapeo desde original**: `create_render_pipeline()`

**Prioridad**: Baja. Especializado.

---

#### 14. shader_analyze_tool (NUEVO - Por implementar)

**¿Por qué separada?** Es análisis estático, no modifica nada. Es puro Python.

```python
@heren.tool()
def shader_analyze_tool(
    session_id: str,
    project_path: str = "",
    shader_path: str = "",
    mode: str = "inspect",  # "inspect", "optimize", "compare", "profile"
    target_platform: str = "desktop",
    comparison_shader: str = "",
) -> dict:
    """Análisis estático de shaders: complejidad, optimizaciones, comparación."""
```

**Mapeo desde original**: `analyze_shader()`

**Prioridad**: Baja. Diagnóstico, no operativo.

---

#### 15. tilemap_inspect_tool (NUEVO - Por implementar)

```python
@heren.tool()
def tilemap_inspect_tool(
    session_id: str,
    action: str = "inspect_tileset",  # "inspect_tileset", "inspect_tilemap"
    project_path: str = "",
    tileset_path: str = "",
    scene_path: str = "",
    tilemap_node_path: str = "",
    godot_path: str = "",
    timeout: int = 30,
) -> dict:
    """Inspeccionar TileSet y TileMap sin modificarlos."""
```

**Mapeo desde original**: `inspect_tileset`, `inspect_tilemap`

**Implementación**: Godot CLI OBLIGATORIO (tile_data comprimido).

**Prioridad**: Media-Alta.

---

#### 16. tilemap_edit_tool (NUEVO - Por implementar)

```python
@heren.tool()
def tilemap_edit_tool(
    session_id: str,
    action: str = "set_cells",  # "set_cells", "terrain", "pattern"
    project_path: str = "",
    scene_path: str = "",
    tilemap_node_path: str = "",
    layer: int = 0,
    # Para set_cells
    cells: list = None,
    # Para terrain
    terrain_cells: list = None,
    terrain_set: int = 0,
    terrain: int = 0,
    ignore_empty: bool = True,
    # Para pattern
    pattern_rect: dict = None,
    pattern_name: str = "",
    pattern_position: dict = None,
    pattern_index: int = -1,
    pattern_path: str = "",
    godot_path: str = "",
    timeout: int = 30,
) -> dict:
    """Modificar celdas, terrain y patterns en TileMap."""
```

**Mapeo desde original**: `set_tilemap_cells`, `apply_tilemap_terrain`, `create_tilemap_pattern`, `set_tilemap_pattern`

**Prioridad**: Media-Alta.

---

#### 17. tilemap_render_tool (NUEVO - Por implementar)

**¿Por qué separada?** Requiere GPU/display server (no puede correr headless). Especializarla evita complicar las otras.

```python
@heren.tool()
def tilemap_render_tool(
    session_id: str,
    project_path: str = "",
    tileset_path: str = "",
    output_path: str = "",
    format: str = "jpeg",
    quality: float = 0.85,
    return_preview: bool = False,
    godot_path: str = "",
    timeout: int = 60,
) -> dict:
    """Renderizar atlas de TileSet con grid numerado. Requiere GPU."""
```

**Mapeo desde original**: `render_tileset_atlas()`

**Prioridad**: Baja. Visual, no operativo.

---

### Grupo D: Atómicas

#### 18. project_tool (NUEVO - Por implementar)

```python
@heren.tool()
def project_tool(
    session_id: str,
    action: str = "info",  # "info", "structure", "find_scripts", "find_resources", "list_projects"
    project_path: str = "",
    directory: str = "",
    recursive: bool = True,
    type_filter: str = "",
) -> dict:
    """Información y descubrimiento de proyectos Godot."""
```

**Mapeo desde original**: `get_project_info`, `get_project_structure`, `find_scripts`, `find_resources`, `list_projects`

**Implementación**: Python puro (no requiere Godot CLI).

**Prioridad**: Media.

---

#### 19. global_tool (NUEVO - Por implementar)

```python
@heren.tool()
def global_tool(
    session_id: str,
    action: str = "autoload",  # "autoload", "shader_global", "group", "project_setting"
    project_path: str = "",
    # Para autoload
    autoload_mode: str = "add",  # "add", "remove", "list", "enable", "disable"
    autoload_name: str = "",
    script_path: str = "",
    singleton: bool = True,
    # Para shader_global
    shader_global_mode: str = "set",  # "set", "get", "remove"
    global_name: str = "",
    global_type: str = "",
    global_value: str = "",
    # Para group
    group_mode: str = "add",  # "add", "remove", "list"
    group_name: str = "",
    # Para project_setting
    setting_mode: str = "set",  # "set", "get", "list", "remove"
    section: str = "",
    key: str = "",
    value: Any = None,
) -> dict:
    """Gestión de configuración global en project.godot."""
```

**Mapeo desde original**: 13 global tools → 1 tool con 4 sub-modes

**Implementación**: Python puro. Editar project.godot quirúrgicamente.

**Prioridad**: Media.

---

#### 20. skeleton_tool (NUEVO - Por implementar)

```python
@heren.tool()
def skeleton_tool(
    session_id: str,
    action: str = "create",  # "create", "add_bone", "skinning", "calculate_rest", "calculate_weights"
    scene_path: str = "",
    project_path: str = "",
    skeleton_type: str = "2d",  # "2d", "3d"
    parent_path: str = ".",
    skeleton_name: str = "Skeleton2D",
    bone_name: str = "",
    parent_bone: str = "",
    bone_length: float = 32.0,
    mesh_path: str = "",
    polygon_path: str = "",
    godot_path: str = "",
) -> dict:
    """Creación y configuración de esqueletos 2D/3D."""
```

**Mapeo desde original**: 6 skeleton tools → 1 tool con 5 actions

**Prioridad**: Baja. Especializado.

---

## Roadmap de Implementación

### Fase 1: Fundamentos (COMPLETADO ✅)
- ✅ `session_tool` - Sesiones
- ✅ `scene_tool` - Escenas básicas (get_tree, save)
- ✅ `node_tool` - Nodos básicos (add, remove, set_prop, get_props)

### Fase 2: Core GameDev (EN PROGRESO)
- [ ] `signal_tool` - Señales y scripts (conectar, asignar scripts)
- [ ] `animation_tool` - Animaciones con tracks
- [ ] `state_machine_tool` - State machines y blend spaces
- [ ] `validation_tool` - Validación pre-guardado

### Fase 3: Productividad (PENDIENTE)
- [ ] `resource_tool` - Recursos básicos .tres
- [ ] `sprite_tile_tool` - SpriteFrames y TileSet
- [ ] `project_tool` - Descubrimiento de proyectos
- [ ] `global_tool` - Configuración global (autoloads, settings)

### Fase 4: Especializados (PENDIENTE)
- [ ] `shader_management_tool` - Shaders
- [ ] `shader_material_tool` - Materiales
- [ ] `render_pipeline_tool` - Pipelines de post-procesado
- [ ] `shader_analyze_tool` - Análisis de shaders
- [ ] `tilemap_inspect_tool` - Inspección de TileMaps
- [ ] `tilemap_edit_tool` - Edición de TileMaps
- [ ] `tilemap_render_tool` - Renderizado de atlas
- [ ] `debug_tool` - Debug y profiling
- [ ] `skeleton_tool` - Esqueletos

---

## Comparativa de Arquitecturas

| Aspecto | MCP Original | Heren Centralizado | Heren Híbrido Moderado |
|---------|-------------|-------------------|----------------------|
| **Cantidad de tools** | 93 | 12 | 20 |
| **Tokens System** | ~30k | ~4k | ~7k |
| **Parameter Bloat** | Moderado | Severo | Mínimo |
| **Descubrimiento LLM** | Muy difícil | Difícil | Fácil |
| **Mantenimiento** | Pesadilla | Fácil | Fácil |
| **Batch Operations** | Limitado | Trivial | Trivial |
| **Debugging** | Fácil | Difícil | Fácil |
| **Granularidad** | Muy fina | Muy gruesa | Balanceada |

---

## Decisiones de Diseño Clave

### 1. ¿Por qué separar `animation_tool` de `resource_tool`?
Las animaciones requieren lógica compleja de flattening de tracks, keyframes con times/transitions/values, y cálculo automático de length. Juntar esto con `resource_tool` (que solo crea recursos simples) haría que `resource_tool` tuviera 10+ parámetros irrelevantes para la mayoría de los casos.

### 2. ¿Por qué separar `shader_management_tool` de `shader_material_tool`?
`shader_management` opera sobre archivos de texto puros (.gdshader). `shader_material` opera sobre escenas instanciadas (asignar ShaderMaterial a nodos). Requieren implementaciones completamente diferentes (Python puro vs Godot CLI).

### 3. ¿Por qué separar `tilemap_inspect`, `tilemap_edit`, `tilemap_render`?
- `inspect`: Solo lectura, Godot CLI
- `edit`: Modificación, Godot CLI + save
- `render`: Requiere GPU/display server (no headless)

Juntarlas haría que la tool tuviera parámetros para celdas, terrain, patterns, resolución, formato, quality... un desastre.

### 4. ¿Por qué eliminar `property_tools.py`?
El schema masivo de propiedades por tipo de nodo (1422 líneas) es imposible de mantener. En su lugar:
- `node_tool(action="update", properties={...})` para propiedades simples
- El LLM conoce las propiedades de nodos Godot (está en su training data)
- Godot CLI valida que las propiedades existen en tiempo de ejecución

---

## Notas de Implementación

### Godot CLI Templates

Cada tool que requiere Godot CLI usa el patrón:

```python
# 1. Renderizar template GDScript con f-strings
template = f"""
extends SceneTree
func _init():
    var scene = load("{scene_path}").instantiate()
    # ... operaciones ...
    var packed = PackedScene.new()
    packed.pack(scene)
    ResourceSaver.save(packed, "{scene_path}")
    print("SUCCESS")
    quit()
"""

# 2. Ejecutar via GodotInterface
godot = GodotInterface(project_path)
result = godot.run_script(template)

# 3. Parsear resultado
if "SUCCESS" in result.stdout:
    return {"success": True}
```

### Batch Operations (Futuro)

Una vez todas las tools estén implementadas, agregar:

```python
@heren.tool()
def batch_tool(
    session_id: str,
    operations: list[dict],  # Lista de operaciones a ejecutar en un solo script
) -> dict:
    """Ejecuta múltiples operaciones en un solo script GDScript."""
```

Esto reduciría 10 operaciones de 10×0.37s = 3.7s a 1×0.5s = 0.5s.

---

*Documento vivo - Actualizar conforme se implementan tools*
