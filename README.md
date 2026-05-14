<div align="center">

![Heren Godot MCP Banner](assets/banner.png)

</div>

---

> *"La tecnica es una actividad compositora o destructora, violenta, y esto es lo que Aristoteles llamaba la poiesis, la poesia, precisamente."* — **Gustavo Bueno**

---

# Heren Godot MCP

**Heren Godot MCP** — *Plus Ultra*: ir mas alla.

Servidor MCP de alto rendimiento para **Godot Engine 4.x** que permite a IAs y asistentes controlar proyectos directamente: crear escenas, manipular nodos, gestionar recursos, conectar senales y validar codigo, **todo mediante un daemon persistente que opera en milisegundos**.

---

## Caracteristicas

| Caracteristica | Descripcion |
|---|---|
| **Daemon WebSocket persistente** | Godot headless mantiene conexion viva via WebSocket — operaciones en ~20ms |
| **15 herramientas centralizadas** | Escenas, nodos, recursos, scripts, senales, animaciones, shaders, validacion y debug |
| **Batch operations** | Ejecuta multiples operaciones en una sola llamada WebSocket |
| **Fallback automatico** | Si el daemon no esta disponible, usa scripts temporales (Godot CLI) |
| **Validacion integrada** | Valida escenas, scripts, nodos y recursos antes de aplicar cambios |
| **Debug completo** | Breakpoints, stack traces, watch variables y captura de consola |
| **Screenshots** | Captura frames de escenas con rendering GPU |
| **I18n nativo** | Sistema de localizacion espanol/ingles integrado |

---

## Frente a otros MCPs de Godot

### Velocidad: persistencia vs. intermediacion

La diferencia principal: otros MCPs lanzan `godot --headless --script` por cada operacion (~370ms de overhead). Heren MCP mantiene un daemon Godot persistente via WebSocket — operaciones en milisegundos.

| Operacion | [Coding-Solo](https://github.com/Coding-Solo/godot-mcp) (3.6k) | [GoPeak](https://github.com/HaD0Yun/Gopeak-godot-mcp) (179) | **Heren Godot MCP** |
|---|---|---|---|
| Leer escena | ~367ms (Godot headless) | ~80ms* (WebSocket) | **~20ms** (daemon persistente) |
| Anadir nodo | ~367ms | ~60ms* | **~20ms** |
| Batch 10 ops | ~3.7s | ~600ms* | **~200ms** |

*Estimado con plugin ya instalado y corriendo

### Comparativa completa

| Dimension | [Coding-Solo](https://github.com/Coding-Solo/godot-mcp) | [GoPeak](https://github.com/HaD0Yun/Gopeak-godot-mcp) | [tugcantopaloglu](https://github.com/tugcantopaloglu/godot-mcp) | **Heren Godot MCP** |
|---|---|---|---|---|
| **Herramientas** | ~15 | 95+ | 149 | **15** |
| **Persistencia** | No (lanza Godot cada vez) | Si (WebSocket) | No | **Si (WebSocket daemon)** |
| **Velocidad** | Lento (~367ms/op) | Medio (~80ms/op) | Lento (~2-5s/op) | **Rapido (~20ms/op)** |
| **Sin plugin Godot** | Si | No (requiere addon) | No | **Si** |
| **Sin Node.js** | No (requiere npm) | No (requiere npm) | No | **Si (solo Python)** |
| **Batch operations** | No | Si | No | **Si** |
| **Fallback automatico** | No | No | No | **Si** |
| **Debug (breakpoints)** | No | Si (DAP) | No | **Si** |
| **Screenshots** | No | Si | No | **Si** |
| **Validacion** | No | No | No | **Si** |
| **I18n** | No | No | No | **Si** |
| **Setup time** | npm install | 60s+ plugin | npm install | **0s** |
| **Memoria persistente** | 0MB | ~450MB | 0MB | **~75MB** |

### Comparativa de funcionalidades

| Funcionalidad | Coding-Solo | GoPeak | tugcantopaloglu | **Heren** |
|---|---|---|---|---|
| **Daemon persistente** | No | Si | No | **Si** |
| **Sin plugin instalado** | Si | No | No | **Si** |
| **Batch operations** | No | Si | No | **Si** |
| **Fallback automatico** | No | No | No | **Si** |
| **Conexion de senales** | No | Si | Si | **Si** |
| **Gestion de autoloads** | No | Si | Si | **Si** |
| **Debug breakpoints** | No | Si | No | **Si** |
| **Screenshots GPU** | No | Si | No | **Si** |
| **Validacion escenas** | No | No | No | **Si** |
| **Shaders y materiales** | No | Si | Si | **Si** |
| **TileMap/Terrain** | No | Si | Si | **Si** |
| **Skeleton/Rigging** | No | No | No | **Si** |
| **LSP (autocompletado)** | No | Si | No | No |
| **DAP (debugger avanzado)** | No | Si | No | No |
| **Runtime inspection** | No | Si | No | No |
| **Input injection** | No | Si | No | No |
| **Asset library** | No | Si | No | No |
| **Docs en espanol** | No | No | No | **Si** |
| **Instalacion** | `npx` (npm) | `npx` (npm) | npm | **`pip` (Python)** |

**Lo que tenemos y ellos no:** Daemon persistente con 0s setup, batch operations, fallback automatico, validacion integrada, debug breakpoints, screenshots GPU, docs en espanol, sin necesidad de plugin ni Node.js.

**Lo que ellos tienen y nosotros no:** LSP (autocompletado GDScript), DAP (debugger con breakpoints avanzado), runtime inspection, input injection, asset library.

---

## Hecho para la comunidad hispanohablante y lusofona

La comunidad de Godot en espanol y portugues es enorme, pero las herramientas de IA para desarrollo de juegos estan disenadas exclusivamente en ingles. Heren Godot MCP nace de esa realidad:

- **Documentacion en espanol**: guias, errores y referencia tecnica en tu idioma
- **Creado por y para** desarrolladores de Espana, Mexico, Argentina, Colombia, Brasil, Portugal y toda Iberoamérica
- **Sin barrera idiomatica**: porque hacer juegos no deberia requerir hablar ingles

---

## Instalacion

### Desde fuente

```bash
git clone https://github.com/tu-usuario/heren-mcp.git
cd heren-mcp
pip install -e .
```

### Instalador automatico

```bash
python install.py
```

### Requisitos

- **Python** >= 3.10
- **Godot** >= 4.2 (recomendado 4.6+)
- **Sistema operativo**: Windows, Linux, macOS

---

## Configuracion MCP

Anade esto a tu configuracion de MCP (Cursor, Claude Desktop, OpenCode, etc.):

```json
{
  "mcpServers": {
    "heren": {
      "command": "python",
      "args": ["-m", "heren.server"],
      "env": {
        "GODOT_EXE": "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe"
      }
    }
  }
}
```

### Variables de entorno

| Variable | Descripcion | Ejemplo |
|----------|-------------|---------|
| `GODOT_EXE` | Ruta al ejecutable de Godot | `D:/Godot/Godot_v4.6.1.exe` |
| `HEREN_PORT` | Puerto del daemon WebSocket | `4567` |
| `HEREN_LOG_LEVEL` | Nivel de logging | `INFO`, `DEBUG` |

---

## Uso Rapido

```python
# Iniciar sesion
session_tool(action="open", project_path="D:/MiJuego")
# -> {"success": true, "session_id": "abc123", "daemon_active": true}

# Crear escena
scene_tool(action="create", session_id="abc123", scene_path="res://Player.tscn")

# Anadir nodo
node_tool(
    action="add",
    session_id="abc123",
    scene_path="res://Player.tscn",
    parent_path=".",
    node_type="CharacterBody2D",
    node_name="Player"
)

# Guardar escena
scene_tool(action="save", session_id="abc123", scene_path="res://Player.tscn")
```

### Batch Operations

```python
# Multiples operaciones en una sola llamada
batch_tool(session_id="abc123", operations=[
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": ".",
        "node_type": "Sprite2D",
        "node_name": "Body"
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Body",
        "node_type": "CollisionShape2D",
        "node_name": "Hitbox"
    }},
    {"action": "save", "params": {
        "scene_path": "res://Player.tscn"
    }}
])
```

---

## Herramientas Disponibles

| Tool | Acciones | Descripcion |
|------|----------|-------------|
| **session** | open, close, list, info, health | Gestion de sesiones con Godot |
| **scene** | load, save, get_tree, screenshot | Operaciones de escenas |
| **node** | add, remove, set_prop, get_prop, duplicate, rename, move | Manipulacion de nodos |
| **signal** | connect, disconnect, list, set_script | Conexion de senales y scripts |
| **animation** | create_player, create, add_track, add_key, state_machine | Sistema de animaciones |
| **shader** | create, edit, validate, material, uniform | Shaders y materiales |
| **skeleton** | create, add_bone, set_rest, skin, attachment | Rigging 2D/3D |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps y TileSets |
| **resource** | create, read, update, delete, list | Gestion de recursos .tres |
| **project** | setting, autoload, remove_autoload, shader_global | Configuracion del proyecto |
| **batch** | - | Operaciones batch de alto rendimiento |
| **debug** | breakpoint, stack_trace, watch, console | Herramientas de debugging |
| **validate** | scene, script, node, resource | Validacion de archivos |
| **index** | list, info, example | Descubrimiento de tools |

---

## Arquitectura

```
Agente IA -> Heren MCP Server -> WebSocket -> Godot Daemon (headless)
                  |
                  v
          Session Manager + Cache
```

### Flujo de operacion

1. **Agente** envia peticion al servidor MCP
2. **Heren MCP** verifica si hay sesion activa
3. Si hay **daemon activo** -> WebSocket (~20ms)
4. Si no hay daemon -> **Fallback** a scripts (~370ms)
5. **Godot** ejecuta la operacion y responde
6. **Cache** almacena resultados frecuentes

---

## Documentacion

- [AGENTS.md](AGENTS.md) — Guia completa para agentes de IA
- [docs/INSTALL.md](docs/INSTALL.md) — Instalacion detallada
- [docs/API.md](docs/API.md) — Referencia completa de la API
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Arquitectura tecnica
- [CONTRIBUTING.md](CONTRIBUTING.md) — Como contribuir
- [CHANGELOG.md](CHANGELOG.md) — Historial de cambios

---

## Benchmarks

Ver [benchmarks/BENCHMARKS.md](benchmarks/BENCHMARKS.md) para comparativas reales con metodologia y resultados detallados.

### Resumen de rendimiento

| Operacion | Con Daemon | Sin Daemon |
|-----------|-----------|------------|
| Anadir nodo | ~20ms | ~370ms |
| Guardar escena | ~15ms | ~340ms |
| Leer arbol | ~25ms | ~400ms |
| Screenshot | ~50ms | ~800ms |

---

## Contribuir

Las contribuciones son bienvenidas. Lee [CONTRIBUTING.md](CONTRIBUTING.md) para:

- Como clonar e instalar
- Como correr tests
- Como reportar bugs
- Estilo de codigo
- Como proponer features

---

## Licencia

[MIT](LICENSE) 2026 Heren MCP Contributors

---

<div align="center">

**Hecho con amor para la comunidad iberoamericana de Godot**

[Star en GitHub](https://github.com/tu-usuario/heren-mcp) · [Reportar bug](https://github.com/tu-usuario/heren-mcp/issues) · [Proponer feature](https://github.com/tu-usuario/heren-mcp/issues)

**Plus Ultra: ir mas alla.**

</div>
