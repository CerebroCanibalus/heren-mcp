<div align="center">

![Heren Godot MCP Banner](assets/HerenGodotBanner.png)

<p>
  <a href="README.md">???? Español</a> •
  <a href="README.en.md">???? English</a>
</p>

</div>

---

> *"La técnica es una actividad compositora o destructora, violenta, y esto es lo que Aristóteles llamaba la poiesis, la poesía, precisamente."* — **Gustavo Bueno**

---

# ?? Heren Godot MCP v1.1

?? **Heren Godot MCP** — *Plus Ultra*: ir más allá. ??

Servidor MCP de alto rendimiento para **Godot Engine 4.x** que permite a IAs y asistentes controlar proyectos directamente: crear escenas, manipular nodos, gestionar recursos, conectar señales y validar código, **todo mediante un daemon persistente que opera en milisegundos**.

**?? v1.1**: Debug funcional, Array operations, Editable paths, Project creation, **persistencia completa de sub-resources**, auto-shutdown, retry automatico

---

## ?? Características

| Caracteristica | Descripcion |
|---|---|
| ?? **Daemon WebSocket persistente** | Godot headless mantiene conexion viva via WebSocket — operaciones en ~20ms |
| ??? **15 herramientas centralizadas** | Escenas, nodos, recursos, scripts, senales, animaciones, shaders, validacion y debug |
| ?? **Persistencia completa** | Sub-resources (shapes, materials, environments), senales y propiedades se guardan en .tscn |
| ? **Batch operations** | Ejecuta multiples operaciones en una sola llamada WebSocket |
| ?? **Fallback automatico** | Si el daemon no esta disponible, usa scripts temporales (Godot CLI) |
| ??? **Validacion integrada** | Valida escenas, scripts, nodos y recursos antes de aplicar cambios |
| ?? **Debug completo** | Breakpoints, stack traces, watch variables y captura de consola |
| ?? **Screenshots** | Captura frames de escenas con rendering GPU |
| ?? **I18n nativo** | Sistema de localizacion espanol/ingles integrado |
| ?? **Auto-shutdown** | Daemon se apaga tras 3 minutos de inactividad (evita procesos colgados) |
| ?? **Retry automatico** | Reintenta iniciar daemon hasta 3 veces si falla |
| ?? **Ventana discreta** | Daemon renderiza a 320x200 en esquina inferior derecha |

---

## ??? Frente a otros MCPs de Godot

### ?? La diferencia que importa: persistencia vs. intermediación

**Coding-Solo** y **GoPeak** son buenos proyectos, pero tienen una limitación fundamental: cada operación requiere lanzar Godot desde cero. Esto es como tener que encender el coche cada vez que quieres cambiar de marcha.

**Heren Godot MCP** mantiene Godot vivo en segundo plano como un daemon persistente. Una sola conexión WebSocket, operaciones en milisegundos para siempre.

| Capacidad | Coding-Solo<br>(3.6k?) | GoPeak<br>(179?) | **Heren** |
|---|---|---|---|
| **Crear escenas y nodos** | ? Lento | ? Rapido* | **? Instantaneo** |
| **Editar propiedades** | ? Lento | ? Rapido* | **? Instantaneo** |
| **Persistir sub-resources** | ? | ? | **? Completo** |
| **Conectar senales** | ? | ? Requiere plugin | **? Sin plugin** |
| **Batch operations** | ? | ? | **? 10x mas rapido** |
| **Debug breakpoints** | ? | ? Requiere DAP | **? Integrado** |
| **Screenshots GPU** | ? | ? Requiere addon | **? Nativo** |
| **Validacion de escenas** | ? | ? | **? Automatico** |
| **Gestion de recursos** | ? Basico | ? Avanzado | **? Completo** |
| **Shaders y materiales** | ? | ? | **? Nativo** |
| **TileMap/Terrain** | ? | ? Requiere plugin | **? Sin plugin** |
| **Skeleton/Rigging 2D-3D** | ? | ? | **? Unico** |
| **State machines de animacion** | ? | ? | **? Unico** |
| **Fallback si daemon cae** | ? | ? | **? Automatico** |
| **Retry automatico** | ? | ? | **? 3 intentos** |
| **Auto-shutdown** | ? | ? | **? 3 minutos** |
| **Requiere plugin Godot** | ? | ? Si | **? No** |
| **Requiere Node.js** | ? npm | ? npm | **? Solo Python** |
| **Setup inicial** | npm install | 60s+ plugin + npm | **?? pip install** |
| **Docs en espanol** | ? | ? | **? Nativo** |

\* Velocidad con plugin instalado y Godot corriendo

### ??? Por qué somos 18x más rápidos

| Operación | Coding-Solo | GoPeak | **Heren** |
|---|---|---|---|
| **Leer escena** | ~367ms (lanza Godot) | ~80ms* (WebSocket) | **~20ms** (daemon persistente) |
| **Añadir nodo** | ~367ms | ~60ms* | **~20ms** |
| **Batch 10 operaciones** | ~3.7s (10× Godot) | ~600ms* | **~200ms** |
| **Screenshot** | ? | ~500ms* | **~50ms** |

> **Nota**: Los tiempos de GoPeak requieren tener el plugin `godot_mcp_editor` instalado y Godot abierto. Sin eso, funciona como Coding-Solo.

### ?? La magia técnica

**Coding-Solo** funciona así:
1. Tu IA pide "añade un nodo"
2. El MCP lanza `godot --headless --script temp.gd`
3. Godot arranca (300ms), ejecuta (50ms), cierra (17ms)
4. Total: **~367ms por cada operación**

**GoPeak** funciona así:
1. Tu IA pide "añade un nodo"  
2. Si tienes el plugin instalado y Godot abierto ? WebSocket rápido
3. Si no ? lanza Godot como Coding-Solo
4. Necesitas instalar un addon en cada proyecto

**Heren** funciona así:

**1. Abres una sesión**
```python
session("open", project_path="D:/MiJuego")
```
? Heren arranca Godot en modo headless (sin ventana) con un script especial. Esto toma ~3 segundos **una sola vez**.

**2. El daemon se mantiene vivo**
? Godot queda escuchando en un puerto WebSocket. No se cierra. No consume interfaz gráfica. Solo ~75MB de RAM.

**3. Ejecutas tools**
```python
node("add", session_id="abc", scene_path="res://Player.tscn", ...)
```
? Mensaje WebSocket directo al daemon. Godot ya está arrancado, no hay overhead. **~20ms**.

**4. Cierras cuando quieras**
```python
session("close", session_id="abc")
```
? El daemon se cierra limpiamente. O puedes dejarlo abierto todo el día.

**El secreto**: Godot nunca se cierra entre operaciones. Es como tener el editor abierto permanentemente, pero sin interfaz gráfica y consumiendo solo ~75MB de RAM.

### ?? Ventajas del sistema de sesiones

| Ventaja | ¿Qué significa? |
|---------|----------------|
| **Persistencia** | Godot arranca una vez, no 100 veces |
| **Aislamiento** | Cada proyecto tiene su propio daemon. No hay conflictos |
| **Múltiples sesiones** | Puedes trabajar en 3 proyectos simultáneamente |
| **Recuperación** | Si algo falla, fallback automático a scripts sin perder datos |
| **Limpieza** | `session("close")` cierra todo limpiamente |
| **Health check** | `session("health")` te dice si todo está funcionando |

### ?? Comparativa de arquitecturas

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **Arquitectura** | Scripts temporales | Plugin + WebSocket | **Daemon nativo WebSocket** |
| **Persistencia** | Ninguna | Solo con plugin | **Siempre activo** |
| **Overhead por operación** | ~367ms | ~60-80ms* | **~20ms** |
| **Setup** | `npm install` | Plugin + npm + Node.js | **`pip install`** |
| **Dependencias** | Node.js + Godot | Node.js + Godot + Plugin | **Solo Python + Godot** |
| **Proyecto limpio** | ? | ? (necesita addon) | **?** |
| **Fallback** | ? | ? | **? Automático** |

---

## ?? Instalación

### Desde fuente

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp
pip install -e .
```

### Instalador automático

```bash
python install.py
```

### Requisitos

- ?? **Python** >= 3.10
- ?? **Godot** >= 4.2 (recomendado 4.6+)
- ?? **Sistema operativo**: Windows, Linux, macOS

---

## ?? Configuración MCP

Añade esto a tu configuración de MCP (Cursor, Claude Desktop, OpenCode, etc.):

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

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `GODOT_EXE` | Ruta al ejecutable de Godot | `D:/Godot/Godot_v4.6.1.exe` |
| `HEREN_PORT` | Puerto del daemon WebSocket | `4567` |
| `HEREN_LOG_LEVEL` | Nivel de logging | `INFO`, `DEBUG` |

---

## ?? Uso Rápido

```python
# Iniciar sesión
session_tool(action="open", project_path="D:/MiJuego")
# ? {"success": true, "session_id": "abc123", "daemon_active": true}

# Crear escena
scene_tool(action="create", session_id="abc123", scene_path="res://Player.tscn")

# Añadir nodo
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

### ?? Batch Operations

```python
# Múltiples operaciones en una sola llamada
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

## ??? Herramientas Disponibles (15 Tools, 60+ Acciones)

### ?? Gestión

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **session** | open, close, list, info, health | Controla el daemon de Godot. Abre, cierra, monitoriza |
| **index** | list, info, example | Descubre tools y acciones. Pregunta "¿qué puedo hacer?" |

### ?? Escenas y Nodos

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **scene** | get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, **add_ext_resource**, **set_editable_paths** | Carga escenas, guarda, captura imágenes, lista activas, recursos externos, paths editables |
| **node** | add, remove, set_prop, get_prop, duplicate, rename, move, **array_append**, **array_remove** | Crea nodos, edita propiedades, duplica, mueve, arrays |
| **batch** | - | Ejecuta múltiples operaciones en una sola llamada |

### ?? Animación y Rigging

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **animation** | create_player, create, add_track, add_key, state_machine | Crea animaciones, keyframes, state machines completas |
| **skeleton** | create, add_bone, set_rest, skin, attachment | Rigging 2D/3D, pesos de huesos, attachments |

### ?? Gráficos

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **shader** | create, edit, validate, material, uniform | Crea shaders GDScript, materiales, edita uniforms |
| **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | Edita TileMaps, terrain painting, patterns |

### ?? Configuración

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **resource** | create, read, update, delete, list, **create_script**, **read_script**, **edit_script** | Gestiona recursos .tres (materiales, física, etc.) y scripts .gd |
| **project** | **create**, setting, autoload, remove_autoload, shader_global | **Crea proyectos nuevos**, cambia settings de project.godot, autoloads |
| **signal** | connect, disconnect, list, set_script | Conecta señales entre nodos, asigna scripts |
| **global** | autoload, project_setting, shader_global | Configuración global del proyecto |

### ?? Debug y Validación

| Tool | Acciones | ¿Qué hace? |
|------|----------|-----------|
| **debug** | breakpoint, stack_trace, watch, console, **run_scene**, **stop_scene**, **get_editor_errors**, **execute_editor_script** | Breakpoints, stack traces, variables, consola, **ejecutar/detener escenas**, **errores del editor**, **ejecutar GDScript** |
| **validate** | scene, script, node, resource | Valida escenas, scripts, nodos y recursos |

### ?? Ejemplo: crear un personaje completo

```python
# 1. Abrir sesión
session("open", project_path="D:/MiJuego")

# 2. Crear escena
scene("load", session_id="abc", scene_path="res://Player.tscn")

# 3. Añadir nodo raíz con batch (más rápido)
batch(session_id="abc", operations=[
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": ".",
        "node_type": "CharacterBody2D",
        "node_name": "Player",
        "properties": {"position": {"x": 100, "y": 200}}
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Player",
        "node_type": "Sprite2D",
        "node_name": "Sprite"
    }},
    {"action": "add", "params": {
        "scene_path": "res://Player.tscn",
        "parent_path": "Player",
        "node_type": "CollisionShape2D",
        "node_name": "Hitbox"
    }},
    {"action": "save", "params": {
        "scene_path": "res://Player.tscn"
    }}
])

# 4. Conectar señal
signal("connect", session_id="abc", scene_path="res://Player.tscn",
       from_node="Player/Hitbox", signal_name="body_entered",
       to_node="Player", method="_on_hitbox_body_entered")

# 5. Validar
validate("scene", session_id="abc", scene_path="res://Player.tscn")
```

---

## ?? Arquitectura: La Magia del Daemon Persistente

### ¿Cómo funciona esta locura?

Heren MCP no es un simple "lanzador de scripts". Es un **ecosistema vivo** que mantiene a Godot despierto y escuchando:

```
+-------------+      +------------------+      +---------------------+
¦  Agente IA  ¦------?¦  Heren MCP       ¦-----?¦  Godot Daemon       ¦
¦  (Cursor,   ¦      ¦  Server          ¦      ¦  (WebSocket)        ¦
¦  Claude,    ¦      ¦                  ¦      ¦                     ¦
¦  OpenCode)  ¦?-----¦  • 15 tools      ¦?-----¦  • Proyecto cargado ¦
+-------------+      ¦  • Session Mgr   ¦      ¦  • Escenas en RAM   ¦
                     ¦  • Cache LRU     ¦      ¦  • Nodos vivos      ¦
                     ¦  • Fallback      ¦      ¦  • FPS limitado     ¦
                     +------------------+      +---------------------+
```

### ?? El ciclo de vida

1. **`session("open")`** ? El servidor arranca Godot en modo headless con un script especial (`heren_daemon.gd`)
2. **El daemon** abre un servidor WebSocket en el puerto 4567 y carga tu proyecto
3. **Tu IA** envía comandos vía las 15 tools ? cada tool traduce a JSON ? WebSocket
4. **Godot** recibe el JSON, ejecuta la operación usando la API nativa de Godot, y responde
5. **Todo en ~20ms** porque Godot nunca se cierra

### ??? El fallback: cuando la magia falla

Si el daemon cae (crashea, cierras Godot manualmente, etc.), Heren **no se rinde**:

```
Operación fallida en daemon --? Intenta reconnexión (3 reintentos)
                                      ¦
                    Falló --? Fallback a scripts temporales
                                      ¦
                         Godot CLI nativo ejecuta la operación
                                      ¦
                         Resultado: ~370ms pero funciona igual
```

**Esto significa**: nunca te quedas atascado. Si el daemon no puede, Godot CLI sí puede.

### ?? ¿Por qué es tan rápido?

| Factor | Impacto |
|---|---|
| **Godot persistente** | No paga el costo de arranque (~300ms) por operación |
| **WebSocket directo** | Comunicación binaria, sin overhead de HTTP ni procesos |
| **Operaciones en batch** | 10 operaciones en un solo mensaje WebSocket |
| **Cache LRU** | Escenas frecuentes se mantienen en memoria |
| **FPS limitado** | Daemon corre a 10 FPS, consume poca CPU |

### ?? Consumo de recursos

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **RAM persistente** | 0 MB | ~450 MB | **~75 MB** |
| **CPU (idle)** | 0% | ~5% | **~1%** |
| **Tiempo de arranque** | 0s | 60s+ (instalación) | **3s** |
| **Overhead por operación** | 367ms | 60-80ms | **20ms** |

---

## ?? Documentación

- ?? [AGENTS.md](AGENTS.md) — Guía completa para agentes de IA
- ?? [docs/INSTALL.md](docs/INSTALL.md) — Instalación detallada
- ?? [docs/API.md](docs/API.md) — Referencia completa de la API
- ??? [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Arquitectura técnica
- ?? [CONTRIBUTING.md](CONTRIBUTING.md) — Cómo contribuir
- ?? [CHANGELOG.md](CHANGELOG.md) — Historial de cambios

---

## ?? Benchmarks: Datos Reales

Medimos operaciones reales en proyectos Godot reales. No estimaciones.

### ??? Heren vs. Competidores

| Operación | Coding-Solo<br>(3.6k?) | GoPeak<br>(179?) | **Heren** | Speedup vs Coding-Solo | Speedup vs GoPeak |
|---|---|---|---|---|---|
| **Leer escena** | 367ms | 80ms* | **20ms** | **18x** | **4x** |
| **Añadir nodo** | 367ms | 60ms* | **20ms** | **18x** | **3x** |
| **Cambiar propiedad** | 367ms | 55ms* | **15ms** | **24x** | **3.7x** |
| **Batch 10 nodos** | 3,670ms | 600ms* | **180ms** | **20x** | **3.3x** |
| **Screenshot** | ? | 500ms* | **50ms** | 8 | **10x** |
| **Validar escena** | ? | ? | **25ms** | 8 | 8 |

*Mediciones GoPeak con plugin instalado y Godot abierto

### ?? Metodología

**Hardware**: Windows 11, Ryzen 5 3600, 16GB RAM, SSD NVMe

**Proyecto**: Godot 4.6, proyecto 2D con 50 nodos

**Coding-Solo**: `npx @coding-solo/godot-mcp`, operación `add_node` medida 10 veces, promedio.

**GoPeak**: `npx gopeak`, perfil `compact`, plugin `godot_mcp_editor` instalado, Godot abierto. Operación `add_node` medida 10 veces.

**Heren**: `session("open")` ? 10 operaciones `node("add")` ? promedio.

**Nota importante**: Los benchmarks de GoPeak miden **solo la operación WebSocket**, excluyendo el tiempo de instalación del plugin y apertura de Godot. En un flujo real, GoPeak requiere ~60s de setup inicial.

### ?? Gráfico de latencia

```
Latencia por operación (ms, menor es mejor)

Coding-Solo:  ¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦ 367ms
GoPeak:       ¦¦¦¦¦¦¦¦¦¦ 80ms
Heren:        ¦¦ 20ms
              +--------------------------------------------+
              0   50  100  150  200  250  300  350  400
```

### ?? Consumo de memoria

| | Coding-Solo | GoPeak | Heren |
|---|---|---|---|
| **Sin operaciones** | 0 MB | 450 MB | **75 MB** |
| **Durante operación** | 200 MB* | 450 MB | **75 MB** |
| **Después de 1h** | 0 MB | 450 MB | **75 MB** |

\* Coding-Solo lanza Godot por cada operación, por lo que el consumo es esporádico pero el tiempo es mayor.

### ?? Conclusión

**Heren es 18x más rápido que Coding-Solo** porque no lanza Godot cada vez.

**Heren es 4x más rápido que GoPeak** con WebSocket, y no requiere plugin.

**Heren consume 6x menos RAM que GoPeak** porque no carga el editor completo.

**Heren es el único con fallback automático**: si el daemon cae, sigue funcionando via scripts.

---

## ?? Contribuir

¡Las contribuciones son bienvenidas! Lee [CONTRIBUTING.md](CONTRIBUTING.md) para:

- ?? Cómo clonar e instalar
- ?? Cómo correr tests
- ?? Cómo reportar bugs
- ?? Estilo de código
- ?? Cómo proponer features

---

## ?? Licencia

[MIT](LICENSE) © 2026 Heren MCP Contributors

---

<div align="center">

? [Star en GitHub](https://github.com/CerebroCanibalus/heren-mcp) · ?? [Reportar bug](https://github.com/CerebroCanibalus/heren-mcp/issues) · ?? [Proponer feature](https://github.com/CerebroCanibalus/heren-mcp/issues)

---

**Por los trabajadores y los iberófonos del mundo** ??

????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

*Porque la creación no debería estar limitada al inglés.*

?? **Plus Ultra: ir más allá.** ??

</div>
