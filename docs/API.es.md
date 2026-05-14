# Referencia API - Heren MCP

Referencia completa de todas las tools de Heren MCP y sus acciones.

## Resumen de Tools

Heren MCP proporciona **15 tools centralizadas** que cubren todas las operaciones de Godot:

| Tool | Descripción | Acciones |
|------|-------------|----------|
| `session` | Gestión de sesiones | `open`, `close`, `list`, `info`, `health` |
| `scene` | Operaciones de escenas | `get_tree`, `save`, `load`, `unload`, `list_loaded`, `screenshot`, `create`, `delete`, `rename` |
| `node` | Operaciones de nodos | `add`, `remove`, `set_prop`, `get_prop`, `duplicate`, `rename`, `move` |
| `batch` | Ejecución batch | `execute` |
| `resource` | Gestión de recursos | `create`, `read`, `update`, `delete`, `list` |
| `animation` | Animaciones | `create_player`, `create`, `add_track`, `add_key`, `state_machine` |
| `skeleton` | Esqueletos 2D/3D | `create`, `add_bone`, `set_rest`, `skin`, `attachment` |
| `shader` | Shaders y materiales | `create`, `edit`, `validate`, `material`, `uniform` |
| `tilemap` | TileMaps y TileSets | `inspect_set`, `inspect_map`, `set_cell`, `terrain`, `pattern` |
| `project` | Configuración del proyecto | `setting`, `autoload`, `remove_autoload`, `shader_global` |
| `debug` | Depuración | `breakpoint`, `stack_trace`, `watch`, `console` |
| `validate` | Validación | `scene`, `script`, `node`, `resource` |
| `signal` | Señales entre nodos | `connect`, `disconnect`, `list`, `set_script` |
| `global` | Configuración global | `autoload`, `project_setting`, `shader_global` |
| `index` | Descubrimiento de tools | `list`, `info`, `example` |

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

## Tool Index

Descubre las tools disponibles.

```python
# Listar todas las tools
index(action="list")

# Obtener info de una tool
index(action="info", tool_name="scene")

# Obtener ejemplo de uso
index(action="example", tool_name="node", action_name="add")
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
