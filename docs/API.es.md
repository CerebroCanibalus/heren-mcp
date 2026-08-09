# Referencia API - Heren MCP

Referencia completa de todas las tools de Heren MCP y sus acciones.

## Resumen de Tools

Heren MCP proporciona **18 tools centralizadas** (v4.6) que cubren todas las operaciones de Godot.
**Solo `action` es required** en cada tool — el resto de args son opcionales con defaults por action en el plugin (fin de los `-32602 required` absurdos).

| Tool | Descripción | Acciones |
|------|-------------|----------|
| `session` | Sesiones + debugger unificado | `open`, `reopen`, `close`, `list`, `info`, `health`, `diagnose` |
| `scene` | Escenas contra el editor real | `get_open_scenes`, `get_edited_scene_root`, `open`, `save`, `create`, `unload` |
| `node` | Nodos — MUTACIONES | `add`, `instantiate`, `remove`, `duplicate`, `rename`, `move`, `set_owner`, `reorder` |
| `node_query` | Nodos — LECTURAS (no dirty) | `get_info`, `get_children`, `get_prop`, `find` |
| `node_props` | Nodos — PROPIEDADES | `set_prop`, `set_props`, `array_append`, `array_remove` |
| `resource` | Recursos y scripts | `create`, `read`, `update`, `delete`, `list`, `create_script`, `read_script`, `edit_script` |
| `project` | Configuración del proyecto | `create`, `setup_plugin`, `setting` (op get/set/list/delete/set_multi), `autoload`, `remove_autoload`, `input_map`, `shader_global` |
| `shader` | Shaders y materiales | `create`, `edit`, `get`, `inspect`, `validate`, `material`, `uniform`, `apply` |
| `animation` | Animaciones | `create_player`, `create`, `add_track`, `add_key`, `state_machine`, `play`, `stop`, `seek`, `speed`, `get_*`, `remove_*`, `update_*`, `one_shot`, `tween`, `record`, `from_path`, `loop_pose`, `preview`, `curve`, `capture_pose`, `tree_*`, `duplicate`, `delete`, `rename`, `reverse`, `blend_pose`, `retarget` |
| `skeleton` | Esqueletos 2D/3D | `skeleton_create`, `skeleton_add_bone`, `skeleton_set_rest`, `skeleton_skin`, `skeleton_attachment`, `skeleton_get_*`, `skeleton_set_pose`, `skeleton_ik`, `skeleton_fabrik`, `capture_pose` |
| `tilemap` | TileMaps y TileSets | `inspect_set`, `inspect_map`, `set_cell`, `terrain`, `pattern` |
| `signal` | Señales entre nodos | `connect`, `disconnect`, `list`, `set_script` |
| `validate` | Validación | `scene`, `script`, `node`, `resource` |
| `debug` | Depuración con editor real | `status`, `breakpoint`, `control`, `stack`, `vars`, `profiler`, `run_scene`, `stop_scene`, `is_playing`, `get_editor_errors`, `output` |
| `orchestrate` | Operaciones batch | (múltiples ops; `plan` inline o `plan_file`) |
| `visual_text` | Visión textual (NIVEL 0-1) | `coords`, `summary`, `ascii` |
| `visual_image` | Visión imagen (NIVEL 2-3) | `capture`, `node` |
| `health` | Health check | estado server + editor |


---

## Tool de Sesión

Gestiona las conexiones a proyectos Godot.

### `session(action="open")`

Abre una nueva sesión con un proyecto Godot.

```python
session(
    action="open",
    project_path="D:/TuJuego",
    godot_path=None,      # Opcional: auto-detectado
    use_daemon=True       # Usar daemon WebSocket (recomendado)
)
```

**Retorna:**
```json
{
  "success": true,
  "session_id": "abc123",
  "project_path": "D:/TuJuego",
  "daemon_active": true
}
```

### `session(action="close")`

Cierra una sesión.

```python
session(action="close", session_id="abc123")
```

### `session(action="list")`

Lista todas las sesiones activas.

```python
session(action="list")
```

### `session(action="health")`

Verifica la salud del daemon.

```python
session(action="health", session_id="abc123")
```

---

## Tool de Escena

Opera sobre archivos de escena de Godot (.tscn).

### `scene(action="get_tree")`

Obtiene el árbol de nodos de una escena.

```python
scene(
    action="get_tree",
    session_id="abc123",
    scene_path="res://Player.tscn"
)
```

### `scene(action="create")`

Crea una nueva escena.

```python
scene(
    action="create",
    session_id="abc123",
    scene_path="res://NuevaEscena.tscn",
    root_type="Node2D",
    root_name="Root"
)
```

### `scene(action="screenshot")`

Captura una screenshot (requiere daemon).

```python
scene(
    action="screenshot",
    session_id="abc123",
    scene_path="res://Player.tscn",
    output_path="C:/temp/screenshot.png",
    resolution=(1920, 1080)
)
```

---

## Tool de Nodo

Manipula nodos dentro de escenas.

### `node(action="add")`

Añade un nodo a una escena.

```python
node(
    action="add",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path=".",           # Ruta del padre
    node_type="Sprite2D",
    node_name="Body",
    properties={
        "position": {"x": 100, "y": 200}
    }
)
```

### `node(action="set_prop")`

Cambia una propiedad de un nodo.

```python
node(
    action="set_prop",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path="Player",
    property_name="position",
    value={"x": 100, "y": 200}
)
```

---

## Tool de Señales

Gestiona señales entre nodos.

### `signal(action="connect")`

Conecta una señal de un nodo a otro.

```python
signal(
    action="connect",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D",
    signal_name="body_entered",
    to_node="Player",
    method="_on_area_body_entered"
)
```

### `signal(action="disconnect")`

Desconecta una señal.

```python
signal(
    action="disconnect",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D",
    signal_name="body_entered",
    to_node="Player",
    method="_on_area_body_entered"
)
```

### `signal(action="list")`

Lista todas las señales de un nodo.

```python
signal(
    action="list",
    session_id="abc123",
    scene_path="res://Player.tscn",
    from_node="Player/Area2D"
)
```

### `signal(action="set_script")`

Asigna un script a un nodo.

```python
signal(
    action="set_script",
    session_id="abc123",
    scene_path="res://Player.tscn",
    node_path="Player",
    script_path="res://scripts/player.gd"
)
```

---

## Tool Global

Gestiona la configuración global del proyecto.

### `global_tool(action="autoload")` - Añadir

Añade un autoload.

```python
global_tool(
    action="autoload",
    session_id="abc123",
    autoload_name="GameManager",
    script_path="res://autoloads/game_manager.gd"
)
```

### `global_tool(action="autoload")` - Quitar

Quita un autoload.

```python
global_tool(
    action="autoload",
    session_id="abc123",
    autoload_name="GameManager"
)
```

### `global_tool(action="autoload")` - Listar

Lista todos los autoloads.

```python
global_tool(
    action="autoload",
    session_id="abc123"
)
```

### `global_tool(action="project_setting")`

Lee o escribe settings de project.godot.

```python
# Leer
global_tool(
    action="project_setting",
    session_id="abc123",
    setting_name="display/window/size/viewport_width"
)

# Escribir
global_tool(
    action="project_setting",
    session_id="abc123",
    setting_name="display/window/size/viewport_width",
    value=1920
)
```

---

## Tool Batch

Ejecuta múltiples operaciones atómicamente.

```python
batch(
    session_id="abc123",
    operations=[
        {
            "action": "add",
            "params": {
                "scene_path": "res://Player.tscn",
                "parent_path": ".",
                "node_type": "Sprite2D",
                "node_name": "Body"
            }
        },
        {
            "action": "set_prop",
            "params": {
                "scene_path": "res://Player.tscn",
                "node_path": "Body",
                "property_name": "position",
                "value": {"x": 100, "y": 200}
            }
        }
    ],
    stop_on_error=True
)
```

---

## Parámetros Comunes

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `session_id` | `str` | Identificador de sesión activa |
| `scene_path` | `str` | Ruta al archivo de escena (res:// o absoluta) |
| `node_path` | `str` | Ruta del nodo dentro de la escena (ej: "Player/Sprite2D") |
| `action` | `str` | Operación a realizar |

## Formato de Retorno

Todas las tools retornan un diccionario:

```json
{
  "success": true,
  "data": { ... }
}
```

En caso de error:

```json
{
  "success": false,
  "error": "Descripción del error"
}
```

## Notas de Rendimiento

- **Con Daemon**: Operaciones en ~20ms
- **Sin Daemon**: Fallback a scripts temporales (~370ms)
- **Caché**: Árboles de escena se cachean por 5 minutos

## Internacionalización

Heren MCP soporta inglés y español. El sistema detecta automáticamente el idioma del SO.

Para forzar un idioma:

```python
from heren.i18n import set_language
set_language("es")  # o "en"
```

Ver también: [Referencia API (Inglés)](API.md)
