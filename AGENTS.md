# 🐉 Heren MCP - AGENTS.md

> **Filosofía Global: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
> **Filosofía de Tools: Centralizadas. Modulares. Potentes.**

Este documento es la biblia para agentes que operan Heren MCP. Lee esto antes de tocar una línea de código.

> 🚧 **ESTADO: v3 operativo (GodotDaemon + FastMCP).**
> **PLAN v4.0 en curso → ver sección `## 13. PLAN v4.0 — Migración Masiva`**.
> **Fase 0 COMPLETADA (2026-08-03): fundaciones FlojoMCP (ws-server, image_content, pagination, SessionManager, hooks).**
> Los cambios nuevos van a v4. No ampliar v3 salvo bugs críticos.

---

## 1. Filosofía de Hierro

### Los Tres Pilares Globales

| Pilar | Significado | Aplicación |
|-------|-------------|------------|
| **PODER** | Acceso total a Godot. Cero limitaciones. | Si Godot puede hacerlo, Heren puede hacerlo. |
| **EFICIENCIA** | Cada operación debe ser óptima. Sin desperdicio. | Cache agresiva, scripts temporales limpios, sin archivos huérfanos. |
| **RAPIDEZ** | Tiempo de respuesta mínimo. Sin latencia innecesaria. | Cache LRU + TTL, invalidación inteligente, reutilización de sesiones. |

### Los Tres Pilares de las Tools

| Pilar | Significado | Aplicación |
|-------|-------------|------------|
| **CENTRALIZADAS** | Pocas tools que agrupan funcionalidad relacionada. | `scene_tools.py` maneja TODO lo de escenas. `node_tools.py` maneja TODO lo de nodos. |
| **MODULARES** | Una tool con múltiples modos/comandos. Flexible. | `scene_tool` con `action="get_tree"` o `action="save"`. Un punto de entrada, múltiples operaciones. |
| **POTENTES** | Máximo poder con mínima cantidad de tools. | Una tool puede crear, modificar, eliminar y consultar. Godot hace TODO el trabajo pesado. |

### Decisiones Arquitectónicas Derivadas

1. **GodotDaemon ÚNICAMENTE.** Sin fallback a scripts CLI. GodotDaemon WebSocket es el único modo.
2. **Session Manager PRIMERO.** Se inicializa antes que todo. Sin sesión, no hay operaciones.
3. **Daemon persistente.** Proceso Godot vivo con WebSocket. Cache en RAM. ~20ms por operación.
4. **Cache en memoria.** Las escenas se mantienen en RAM. Invalidación explícita tras modificaciones.
5. **Fail-fast.** Si el daemon no responde, error inmediato. Sin cuelgues.
6. **Tools multifuncionales.** Una tool = múltiples operaciones relacionadas. Menos tools, más poder.

---

## 2. Arquitectura de Capas (Implementación Actual - GodotDaemon)

```
┌─────────────────────────────────────────────┐
│           Cliente (LLM/Agente)              │
└──────────────┬──────────────────────────────┘
               │ MCP Protocol (stdio)
┌──────────────▼──────────────────────────────┐
│           HEREN MCP SERVER                  │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  CAPA 0: SESSION MANAGER            │   │
│  │  ├─ Singleton thread-safe           │   │
│  │  ├─ LRU Cache con TTL (5 min)       │   │
│  │  ├─ Gestión de sesiones por proyecto│   │
│  │  ├─ Auto-limpieza de archivos temp  │   │
│  │  ├─ GodotDaemon integration         │   │
│  │  └─ Sin fallback (daemon-only)      │   │
│  └──────────────┬──────────────────────┘   │
│                 │                            │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 1: GODOT DAEMON (WebSocket)   │   │
│  │  ├─ Proceso Godot con ventana       │   │
│  │  ├─ Servidor WebSocket (localhost)  │   │
│  │  ├─ Cache de escenas en RAM         │   │
│  │  ├─ Rendering GPU disponible        │   │
│  │  └─ Heartbeat + auto-reconnect      │   │
│  └──────────────┬──────────────────────┘   │
│                 │ WebSocket (~20ms)        │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 2: API TOOLS (10 tools)       │   │
│  │  ├─ session   - Gestión de sesiones │   │
│  │  ├─ scene     - Escenas             │   │
│  │  ├─ node      - Nodos               │   │
│  │  ├─ batch     - Operaciones múltiples│  │
│  │  ├─ resource  - Recursos .tres      │   │
│  │  ├─ animation - Animaciones/SM      │   │
│  │  ├─ skeleton  - Esqueletos 2D/3D    │   │
│  │  ├─ shader    - Shaders/Materiales  │   │
│  │  ├─ tilemap   - TileMaps/TileSets   │   │
│  │  └─ project   - Configuración       │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
               │ WebSocket (localhost)
┌──────────────▼──────────────────────────────┐
│  GODOT DAEMON (Godot 4.x con ventana)       │
│  ├─ Escenas cacheadas en memoria            │
│  ├─ SubViewport para screenshots            │
│  ├─ ClassDB para instanciación              │
│  ├─ ResourceSaver para guardar              │
│  └─ PhysicsServer para raycasts             │
└─────────────────────────────────────────────┘
```

### Flujo de Datos Real (Con Daemon)

1. Agente llama `session("open", project_path="...")`
2. Session Manager inicia GodotDaemon (WebSocket en localhost)
3. Daemon carga proyecto, escucha en puerto auto-asignado
4. Agente llama `scene("load", scene_path="res://Player.tscn")`
5. Daemon carga escena en RAM, retorna en ~3s (primera vez)
6. Agente llama `node("add", ...)` 
7. Daemon modifica escena en memoria (~20ms), retorna éxito
8. Agente llama `scene("save", ...)`
9. Daemon hace `packed_scene.pack()` + `ResourceSaver.save()` (~20ms)
10. Escena persiste en disco, cache RAM se mantiene

---



## 2.1 Arquitectura Modular del Daemon (v2.0)

El daemon monolítico original (4,563 líneas) fue refactorizado en **10 módulos GDScript** con inyección de dependencias.

### Módulos del Daemon

| Módulo | Líneas | Responsabilidad | `class_name` |
|--------|--------|-----------------|--------------|
| `heren_daemon.gd` | ~400 | Orquestador: WebSocket, heartbeat, registro de handlers | — |
| `heren_window_manager.gd` | ~80 | Ventana no intrusiva (flags, posición) | `HerenWindowManager` |
| `heren_core_utils.gd` | ~109 | Serialización/deserialización de valores Godot ↔ JSON | `HerenCoreUtils` |
| `heren_scene_ops.gd` | ~1500 | CRUD de escenas/nodos: add, remove, set_prop, save, batch | `HerenSceneOps` |
| `heren_resource_ops.gd` | ~511 | Recursos .tres, scripts .gd, ext_resources | `HerenResourceOps` |
| `heren_animation_ops.gd` | ~450 | Animaciones, tracks, keys, state machines, skeletons | `HerenAnimationOps` |
| `heren_shader_ops.gd` | ~190 | Crear/editar shaders, materiales, uniforms | `HerenShaderOps` |
| `heren_debug_ops.gd` | ~900 | Debug, validación, screenshots, raycast, measure | `HerenDebugOps` |
| `heren_project_ops.gd` | ~380 | Project settings, autoloads, tilemaps | `HerenProjectOps` |
| `heren_tscn_serializer.gd` | — | Serialización e inyección en archivos .tscn | — |

### Patrón de Inyección de Dependencias

```gdscript
# En el orquestador (heren_daemon.gd)
var scene_ops = preload("heren_scene_ops.gd").new()
scene_ops.init(self)  # Pasa referencia al orquestador
scene_ops._scene_cache = _scene_cache
scene_ops._serialize_value_callback = _core_utils.serialize_value

# En el módulo (heren_scene_ops.gd)
var _daemon: SceneTree = null

func init(daemon: SceneTree) -> void:
    _daemon = daemon

func handle_save_scene(params: Dictionary) -> Dictionary:
    # Puede acceder al orquestador para llamar ensure_mouse_free()
    _daemon.ensure_mouse_free()
```

### ¿Por qué Modular?

- **Mantenibilidad**: Cada módulo tiene una responsabilidad única
- **Testabilidad**: Se pueden probar módulos individualmente
- **Extensibilidad**: Nuevos handlers se añaden registrando métodos del módulo
- **Colaboración**: Múltiples desarrolladores pueden trabajar en módulos diferentes

---

## 3. Reglas de Oro para Agentes

### Regla 1: Session Manager es el Rey
```python
# SIEMPRE empezar así:
session = heren_start_session("D:/MiProyecto")

# NUNCA hacer operaciones sin sesión activa
# NUNCA cerrar la sesión hasta que el agente termine
```

### Regla 2: Godot Hace el Trabajo Pesado (Via Daemon)
```python
# MAL - Intentar parsear manualmente
with open("scene.tscn") as f:
    content = f.read()
    # ... parsing manual ...

# BIEN - Daemon Godot hace TODO en memoria
result = scene("get_tree", session_id="abc", scene_path="res://scene.tscn")
# Godot devuelve JSON perfecto en ~20ms

# El daemon mantiene escenas en RAM. Operaciones son instantáneas.
# Solo la primera carga lee de disco (~3s), el resto es memoria.
```

### Regla 3: Las Tools son Centralizadas (10 Tools Totales)
```python
# 10 tools que cubren TODO Godot:
# session   → open, close, list, info, health
# scene     → get_tree, save, load, unload, screenshot
# node      → add, remove, set_prop, get_prop, duplicate, rename, move
# batch     → múltiples operaciones en una llamada
# resource  → create, read, update, delete, list (.tres)
# animation → create_player, create, add_track, add_key, state_machine
# skeleton  → create, add_bone, set_rest, skin, attachment
# shader    → create, edit, validate, material, uniform
# tilemap   → inspect_set, inspect_map, set_cell, terrain, pattern
# project   → setting, autoload, group, shader_global

# NO dispersar en 50 tools con 1 función cada una
# NO crear tools que puedan agruparse lógicamente
```

### Regla 4: Las Tools son Modulares
```python
# Una tool con múltiples modos via parámetros
scene_tool(action="get_tree", scene_path="...")
scene_tool(action="save", scene_path="...")
scene_tool(action="get_info")

node_tool(action="add", scene_path="...", node_type="Sprite2D")
node_tool(action="remove", scene_path="...", node_path="...")
node_tool(action="set_prop", scene_path="...", property="position")

# Una tool, múltiples operaciones relacionadas
```

### Regla 5: Las Tools son Potentes
```python
# Una sola tool puede hacer TODO un flujo de trabajo
# Crear nodo + configurar propiedades + guardar escena
# Todo en una sola llamada, un solo script GDScript
# Godot ejecuta TODO el trabajo pesado
# El agente solo dice QUÉ hacer, no CÓMO hacerlo
```

### Regla 6: Cache es tu Amigo
```python
# La primera vez lee de disco (Godot CLI)
scene = heren_get_scene_tree("res://Player.tscn")  # ~370ms

# La segunda vez lee de memoria (cache LRU)
scene = heren_get_scene_tree("res://Player.tscn")  # ~0ms
```

### Regla 7: Fail-Fast
```python
# Si Godot no responde, error inmediato
# Si el archivo no existe, error inmediato
# Si la operación es inválida, error inmediato
# NUNCA silenciar errores. NUNCA retornar None sin explicación.
```

---

## 4. Estructura de Directorios (Actual - v2.0 Modular)

```
D:\Mis Juegos\GodotMCP\heren-mcp\
├── AGENTS.md                 # Este archivo - Biblia para agentes (incluye PLAN v4.0 §13)
├── README.md                 # Para usuarios finales
├── requirements.txt          # Dependencias Python
├── run.bat                   # Launcher para OpenCode
├── src/
│   └── heren/
│       ├── __init__.py
│       ├── server.py         # Entry point FastMCP (15 tools)
│       ├── core/
│       │   ├── session_manager.py    # Capa 0 - Singleton + LRU Cache
│       │   └── godot_daemon.py       # Wrapper WebSocket del daemon
│       ├── daemon/           # 🆕 Arquitectura Modular v2.0
│       │   ├── heren_daemon.gd           # Orquestador principal (~400 líneas)
│       │   ├── heren_window_manager.gd   # Gestión ventana no intrusiva
│       │   ├── heren_core_utils.gd       # Serialización/deserialización
│       │   ├── heren_scene_ops.gd        # Operaciones escenas/nodos (~1500 líneas)
│       │   ├── heren_resource_ops.gd     # Recursos/scripts
│       │   ├── heren_animation_ops.gd    # Animaciones/esqueletos
│       │   ├── heren_shader_ops.gd       # Shaders/materiales
│       │   ├── heren_debug_ops.gd        # Debug/validación
│       │   ├── heren_project_ops.gd      # Proyecto/tilemaps
│       │   ├── heren_server_manager.gd   # WebSocket server (legacy)
│       │   ├── heren_tscn_serializer.gd  # Serialización TSCN (legacy)
│       │   └── daemon_utils.gd           # Utilidades compartidas
│       ├── interfaces/       # 🗑️ Eliminado v3.0 (era fallback)
│       ├── templates/        # 🗑️ Eliminado v3.0 (era fallback)
│       └── tools/
│           ├── session_tool.py       # Tool de sesiones
│           ├── scene_tool.py         # Tool de escenas
│           ├── node_tool.py          # Tool de nodos
│           ├── batch_tools.py        # Tool de batch
│           ├── resource_tool.py      # Tool de recursos
│           ├── animation_tool.py     # Tool de animaciones
│           ├── skeleton_tool.py      # Tool de esqueletos
│           ├── shader_tool.py        # Tool de shaders
│           ├── tilemap_tool.py       # Tool de tilemaps
│           ├── project_tool.py       # Tool de proyecto
│           ├── debug_tool.py         # Tool de debug
│           ├── validate_tool.py      # Tool de validación
│           ├── signal_tool.py        # Tool de señales
│           └── global_tool.py        # Tool de config global
├── .temp/                    # Archivos temporales (auto-limpieza)
├── tests/                    # Tests unificados por capa
│   ├── conftest.py           # Fixtures compartidas
│   ├── test_core/            # Tests Capa 0 (sin Godot)
│   ├── test_interfaces/      # Tests Capa 1 (mock Godot)
│   ├── test_tools/           # Tests Capa 2 (con Godot real)
│   └── test_integration/     # Tests end-to-end
└── benchmarks/               # Benchmarks de rendimiento
    ├── benchmark_tools.py    # Benchmark por tool
    ├── benchmark_cache.py    # Benchmark de cache
    └── run_benchmarks.py     # Runner unificado
```

---

## 5. Templates GDScript (ELIMINADOS v3.0)

El sistema de templates GDScript (`TemplateEngine`, `gdscript_templates.py`) y el fallback a scripts
temporales fueron eliminados completamente.

**TODO pasa por GodotDaemon WebSocket.** No más `godot --headless --script temp.gd`.
No más `TEST_OUTPUT:` parsing. No más ~370ms de latencia.

---

## 6. Performance Benchmark (Real - GodotDaemon)

Medido con proyecto LAIKA (Godot 4.6.1), **testing real 2026-05-13**:

### Con Daemon (WebSocket + Cache RAM)
| Operación | Primera vez | Cache hit | Speedup vs Scripts | Estado |
|-----------|-------------|-----------|-------------------|--------|
| `session_start` | ~3.5s | — | — | ✅ Estable |
| `load_scene` | ~3.0s | ~20ms | 150x | ✅ Estable |
| `get_scene_tree` | ~3.0s | ~20ms | 18x | ✅ Estable |
| `add_node` | — | ~20ms | 18x | ✅ Estable |
| `set_property` | — | ~20ms | 18x | ✅ Estable |
| `save_scene` | — | ~20ms | 18x | ✅ Estable |
| `screenshot` | — | ~60ms | — | ✅ Funcional |
| `batch (11 ops)` | — | ~200ms | 18x | ✅ **Excelente** |
| `duplicate_node` | — | ~20ms | — | ✅ Estable |
| `rename_node` | — | ~20ms | — | ✅ Estable |
| `move_node` | — | ~20ms | — | ✅ Estable |
| `create_scene` | — | ~20ms | — | ✅ Estable |
| `project_setting` | — | ~20ms | — | ✅ Estable |
| `validate_scene` | — | ~20ms | — | ✅ Estable |

**Promedio:** ~20ms por operación con daemon
**Sin daemon: ELIMINADO (v3.0).** 18x más rápido sin el peso muerto del fallback.

### Métricas del Testing Real (2026-05-13)
- **Operaciones exitosas:** 25/28 (89%)
- **Operaciones fallidas:** 3/28 (11%) - Bugs conocidos del daemon
- **Tiempo total de testing:** ~5 minutos
- **Escena creada:** 15 nodos, 1 skeleton, 1 shader, 1 animation player
- **Memoria daemon:** ~47MB estable

---

## 7. Flujo Correcto para Proyectos Nuevos

### Crear Proyecto Nuevo (v1.1+)

```python
# 1. Abrir sesión en un proyecto temporal (para tener daemon)
session("open", project_path="D:/MiProyectoActual")

# 2. Crear proyecto nuevo (configura daemon automáticamente)
project("create", 
        project_path="D:/MiNuevoJuego",
        project_name="Mi Nuevo Juego",
        renderer="forward_plus")
# Resultado: daemon_setup: "success" (o "failed" con error)

# 3. Abrir sesión en el nuevo proyecto
session("open", project_path="D:/MiNuevoJuego")
# Resultado: daemon_active: true
```

### Configurar Daemon en Proyecto Existente

```python
# Si session("open") devuelve daemon_active: false
# y daemon_error indica que falta el daemon:

# Configurar daemon manualmente
project("setup_daemon", project_path="D:/MiProyectoExistente")

# Luego reabrir sesión
session("open", project_path="D:/MiProyectoExistente")
```

### Errores Comunes al Crear Proyectos

| Error | Causa | Solución |
|-------|-------|----------|
| `daemon_active: false` | Proyecto nuevo sin daemon | Ejecutar `project("setup_daemon", ...)` |
| `No hay sesión activa` | Intentar create sin sesión | Abrir sesión primero en cualquier proyecto |
| `Daemon no disponible` | Sesión abierta pero daemon murió | Cerrar y reabrir sesión |
| `Proyecto no encontrado` | Path incorrecto | Verificar ruta absoluta |

---

## 8. Decisiones Registry

| Fecha | Decisión | Razón |
|-------|----------|-------|
| 2026-05-12 | Godot CLI Nativo vs Parser Propio | Parser propio tiene bugs de serialización. Godot nunca falla. |
| 2026-05-12 | Session Manager primero | Asegura que el proyecto esté listo antes de cualquier operación. |
| 2026-05-12 | Scripts temporales vs Godot persistente | Procesos persistentes tienen problemas de sincronización. Scripts temporales son 100% confiables. |
| 2026-05-12 | Templates con f-strings vs string.Template | f-strings son type-safe y permiten inyección de JSON válido. |
| 2026-05-12 | Cache en memoria (no disco) | Velocidad. Invalidación explícita tras modificaciones. |
| 2026-05-12 | packed_scene.pack() antes de save | Godot 4 requiere pack() para guardar instancias modificadas. |
| 2026-05-12 | Arquitectura híbrida moderada (~10 tools) | 10 tools centralizadas cubren TODO Godot. Evita parameter bloat. |
| 2026-05-12 | Tests unificados + benchmarks | MCP anterior tenía 93 tools dispersas y tests fragmentados. Unificar testing en capas + benchmarks. |
| 2026-05-13 | GodotDaemon WebSocket vs HTTP | Bug #92367 bloquea HTTP en headless. WebSocket con ventana funciona perfecto. |
| 2026-05-13 | 10 Tools centralizadas | session, scene, node, batch, resource, animation, skeleton, shader, tilemap, project. |
| 2026-05-13 | Visual Inspection System | El agente es ciego. Grid + labels + axes + raycast + measure le dan "ojos". |
| 2026-05-13 | FPS limitado a 10 | Reduce consumo GPU/CPU del daemon en segundo plano. |
| 2026-05-13 | 14 Tools centralizadas | session, scene, node, batch, resource, animation, skeleton, shader, tilemap, project, debug, validate, signal, global. |
| 2026-05-13 | **Bug crítico: session.id** | Múltiples tools usaban `session.session_id` en vez de `session.id`. Fix aplicado a project, animation, skeleton, shader, tilemap. |
| 2026-05-13 | **Fix: _deserialize_value** | Auto-detección de Vector2/3/Color por keys (x,y,z,r,g,b) sin necesidad de `__type`. Posiciones ahora aplican correctamente. |
| 2026-05-13 | **Batch funcional** | 11 operaciones en ~200ms. Mapeo completo action→method con 30+ acciones soportadas. |
| 2026-05-13 | **Debug + Validate implementados** | 8 handlers nuevos en daemon: breakpoint, stack_trace, watch, console, validate_scene/script/node/resource. |
| 2026-05-13 | **89% operaciones exitosas** | Testing real en proyecto LAIKA: 25/28 operaciones exitosas. 3 bugs menores del daemon identificados. |
| 2026-05-14 | **Bug: daemon no arranca en proyecto nuevo** | `project/create` crea proyecto pero no copia daemon. Solucion: `setup_daemon` automatico en create + tool separada para proyectos existentes. |
| 2026-05-14 | **project/setup_daemon** | Nueva tool para configurar daemon en proyectos existentes. Copia heren_daemon.gd + registra autoload. |
| 2026-05-14 | **Auto-shutdown 60s -> 180s** | Timeout inicial de 60s era muy corto. Aumentado a 3 minutos para evitar cierres durante operaciones largas. |
| 2026-05-14 | **Retry del daemon (3 intentos)** | Si el daemon falla al iniciar, el Session Manager reintenta automaticamente con delay exponencial (2s, 4s). |
| 2026-05-14 | **Ventana pequena (320x200)** | El daemon se renderiza en esquina inferior derecha para no estorbar al usuario. No afecta screenshots. |
| 2026-05-14 | **resource_local_to_scene = true** | Solucion para persistencia de sub-resources: marcar todos los recursos como local_to_scene fuerza a Godot a incrustarlos en .tscn. |
| 2026-05-14 | **No reiniciar MCPs sin permiso** | Regla critica: NUNCA matar/reiniciar procesos MCP sin confirmacion explicita del usuario. |
| 2026-05-15 | **Arquitectura Modular v2.0** | Daemon monolítico (4563 líneas) partido en 10 módulos GDScript para mantenibilidad. Orquestador + módulos de operaciones. |
| 2026-05-15 | **Inyección de dependencias** | Módulos reciben referencia al orquestador vía `init(daemon: SceneTree)` para acceso a estado compartido (`_scene_cache`, `_project_path`). |
| 2026-05-15 | **Daemon ejecuta desde proyecto** | `godot_daemon.py` usa copia del daemon en `addons/heren/daemon/` del proyecto en vez del paquete MCP. Esto habilita `class_name` en módulos. |
| 2026-05-15 | **setup_daemon copia TODOS los módulos** | Antes solo copiaba `heren_daemon.gd`. Ahora copia los 12 archivos `.gd` del daemon al proyecto. |
| 2026-05-15 | **Mouse lock fix** | `Input.mouse_mode = MOUSE_MODE_VISIBLE` + `ensure_mouse_free()` cada 0.5s + post-save. Ventana 240x150 con NO_FOCUS + MOUSE_PASSTHROUGH. |
| 2026-05-15 | **Shader type deduplicación** | `handle_create_shader` detecta si el código ya incluye `shader_type` y no lo duplica. |
| 2026-05-15 | **Mesh inline con __type** | `set_property` acepta `{"__type":"Resource","resource_type":"SphereMesh",...}` para crear meshes primitivos inline. |
| 2026-07-17 | **Eliminado fallback sin daemon (v3.0)** | GodotInterface, TemplateEngine, execute_gdscript, y todo el código de scripts CLI eliminados. GodotDaemon es el ÚNICO modo. ~412 + 1277 líneas de basura eliminadas. |
| 2026-07-28 | **Fix parse error: palabras reservadas GDScript** | `signal` y `match` usados como nombres de variable causaban parse errors. Renombrados a `sig`/`is_match`. |
| 2026-07-28 | **Fix parse error: funciones anidadas** | `func _search(node: Node)` dentro de `handle_find_nodes` no es válido en GDScript. Reemplazado por búsqueda iterativa con pila. |
| 2026-07-28 | **Fix heren_debug_ops.gd corrupto** | Bloque entre `execute_editor_script` y `handle_run_scene` tenía `}` faltante + indentación rota. Reconstruido. |
| 2026-07-28 | **Fix project setting write** | `handle_set_project_setting` llamaba a `_daemon._value_to_godot_config()` inexistente. Añadido helper local `_value_to_godot_config()`. |
| 2026-07-28 | **Fix screenshot sincrónico** | `await _daemon.create_timer(0.0).timeout` en handlers requería soporte async en `_dispatch`. Reemplazado por `RenderingServer.force_sync/draw` para mantener dispatch síncrono. |
| 2026-07-28 | **Fix validate_node root path** | `handle_validate_node` no normalizaba `node_path="Root"`. Añadido `_normalize_node_path()` para soportar paths absolutos y nombre del root. |
| 2026-07-28 | **Fix orchestrate action/params** | `handle_orchestrate` esperaba ops como `{"add": {...}}`. Actualizado a formato cliente `{"action": "add", "params": {...}}`. |
| 2026-07-28 | **Nuevos handlers expuestos** | `node_tool` ahora expone: get_info, get_children, find, set_owner, reorder, add+script/signals. `scene_tool` ahora expone instantiate. |
| 2026-07-28 | **Tests únicos y limpieza** | Tests que crean archivos ahora usan nombres únicos + cleanup, evitando falsos negativos por archivos residuales. |

---

## 8. Limitaciones Conocidas y Workarounds

### Capacidades del Debug Tool

| Action | Modo | Requiere Daemon | Descripción |
|--------|------|-----------------|-------------|
| `breakpoint` | Daemon | ✅ Sí (editor) | Setear/quitar breakpoints |
| `stack_trace` | Daemon | ✅ Sí (editor) | Obtener stack trace |
| `watch` | Daemon | ✅ Sí (editor) | Watch variables |
| `console` | Daemon | ✅ Sí | Capturar output de consola |
| `stop_scene` | Daemon | ✅ Sí (editor) | Detener ejecución |
| `get_editor_errors` | Daemon | ✅ Sí (editor) | Obtener errores del editor |
| `run_scene` | Subprocess | ❌ No | Ejecutar escena vía `godot --headless` |
| `execute_editor_script` | Subprocess | ❌ No | Ejecutar GDScript completo (FileAccess, ClassDB, etc.) |
| `check_script_syntax` | Subprocess | ❌ No | Verificar sintaxis vía `godot --check-only` |

### Bugs Arreglados (v1.1+)

| Bug | Fix | Fecha |
|-----|-----|-------|
| scene.create no aceptaba root_type/root_name | server.py ahora acepta root_type/root_name explicitos | 2026-05-14 |
| batch set_prop fallaba con "missing_params" | Daemon ahora acepta "property" y "property_name" | 2026-05-14 |
| batch nodes no persistían | Verificacion post-save + tracking de node_count | 2026-05-14 |
| node.set_prop fallaba tras batch | Compatibilidad de nombres de parametros | 2026-05-14 |
| Daemon no arrancaba en proyecto nuevo | `get_editor_interface()` causaba error de parseo | 2026-05-14 |
| **Persistencia de sub-resources** | `resource_local_to_scene = true` + `_setup_resource_local_to_scene_recursive()` | 2026-05-14 |
| **Persistencia de senales** | `_collect_connections()` + `_inject_into_tscn()` | 2026-05-14 |
| **execute_editor_script corrupto** | Eliminar f-string problematico, guardar script tal cual | 2026-05-14 |
| **Fallback property vs property_name** | `prop_name = params.get("property_name") or params.get("property", "")` | 2026-05-14 |
| **Daemon crashea por Unicode** | Remover caracteres especiales de logs en Windows | 2026-05-14 |
| **Sub-resources anidados (ShaderMaterial.shader)** | `_serialize_resource_properties()` maneja recursos anidados | 2026-05-14 |
| **Arquitectura monolítica** | Daemon partido en 10 módulos GDScript con inyección de dependencias | 2026-05-15 |
| **Mouse lock durante guardado** | `ensure_mouse_free()` cada 0.5s + post-save + flags NO_FOCUS/MOUSE_PASSTHROUGH | 2026-05-15 |
| **Duplicación shader_type** | `handle_create_shader` detecta shader_type existente y no lo duplica | 2026-05-15 |
| **Mesh inline** | `__type: Resource` con `resource_type` soporta BoxMesh, SphereMesh, etc. | 2026-05-15 |
| **ExtResource faltante** | `_serialize_resource_properties` detecta recursos externos y genera `[ext_resource]` + `ExtResource()` | 2026-05-15 |
| **Sub-resource ID corrupcion en save** | `_inject_into_tscn` creaba IDs duplicados (`_heren_N`) que rompian las referencias de nodos. Fix: eliminar sub-resource injection — `pack()`+`FLAG_BUNDLE_RESOURCES` ya los maneja. Solo connections se inyectan. | 2026-07-17 |
| **Pipeline de guardado refactorizado (v3.0)** | Eliminadas 462 líneas de inyección de texto que corrompían .tscn. El pipeline ahora es: `_pre_save_resource_fix → pack() → save(FLAG_BUNDLE_RESOURCES) → verify`. `handle_connect_signal` usa `CONNECT_PERSIST` para que `pack()` serialice señales nativamente. Funciones eliminadas: `_collect_sub_resources`, `_collect_connections`, `_inject_into_tscn`, `_serialize_resource_properties`, `_update_node_subresource_ref`, `_serialize_value_tscn`. | 2026-07-17 |
| **Parse error: palabras reservadas** | `signal` → `sig`, `match` → `is_match` en variables GDScript | 2026-07-28 |
| **Parse error: función anidada** | `func _search()` en `handle_find_nodes` reemplazada por búsqueda iterativa con pila | 2026-07-28 |
| **heren_debug_ops.gd corrupto** | Reconstruido bloque entre `execute_editor_script` y `handle_run_scene` (`}` faltante + indentación) | 2026-07-28 |
| **project setting write roto** | Añadido helper `_value_to_godot_config()` en `heren_project_ops.gd` | 2026-07-28 |
| **Screenshot async roto** | Reemplazado `await create_timer()` por `RenderingServer.force_sync/draw` para mantener handlers síncronos | 2026-07-28 |
| **validate_node no acepta "Root"** | Añadido `_normalize_node_path()` en `heren_debug_ops.gd` | 2026-07-28 |
| **orchestrate formato ops** | Actualizado a `{"action": "...", "params": {...}}` | 2026-07-28 |
| **Tests con nombres fijos** | Tests ahora usan nombres únicos + cleanup para evitar falsos negativos por archivos residuales | 2026-07-28 |
| **Fase 0 completada (FlojoMCP)** | ws-server, image_content, pagination, SessionManager, hooks/tokens listos en FlojoMCP (commit `94b3d4c`) | 2026-08-03 |
| **rmcp v1.7.0 no trae WS** | `ws.rs` es placeholder ("Maybe we don't really need a ws implementation?") → ws-server construido sobre `SinkStreamTransport` + tokio-tungstenite | 2026-08-03 |
| **Frames WS inválidos cierran conexión** | El `Transport` de rmcp no admite errores en el stream → `WsStream` devuelve `None` (cierra) ante JSON-RPC malformado | 2026-08-03 |
| **SessionManager en `.heren/session.json`** | Sesiones multi-proyecto: `Session::load(project/.heren/session.json)` con cache Arc<RwLock<HashMap>>, `save_all()`/`evict()` | 2026-08-03 |
| **NO definir `get_editor()` en EditorPlugin** | Colisiona con el método del EditorPlugin → devuelve null. Usar `get_editor_interface()` directo en handlers | 2026-08-03 |
| **`add_do_method` de Godot 4.6** | Espera `(Object, StringName, args)` — NO acepta Callable directo. El wrapper de undo/redo usa esa firma | 2026-08-03 |
| **Fase 1 completada (Plugin Núcleo)** | EditorPlugin + ws_client (MCP JSON-RPC) + dispatcher + undo_redo_wrapper + scene_handlers en `laika-gd/addons/heren/`, validado E2E real (health/open/create/get_root) | 2026-08-03 |
| **`tools/ws_test_server.py`** | Server WS Python de prueba para validar el plugin antes de Fase 4 (el server Rust definitivo llega después). Soporta `--command`, `--sequence`, `--repeat` | 2026-08-03 |

 ### Nuevas Features (v3.0)

| Feature | Descripcion |
|---------|-------------|
| **Auto-shutdown** | Daemon se apaga tras 3 minutos sin comandos (evita procesos colgados) |
| **Retry automatico** | Session Manager reintenta iniciar daemon hasta 3 veces con delay exponencial |
| **Ventana pequena** | Daemon renderiza a 320x200 en esquina inferior derecha (no estorba) |
| **Sub-resources complejos** | Soporte para RectangleShape2D, CircleShape2D, CapsuleShape2D, GradientTexture2D, Environment, StandardMaterial3D |
| **Edicion de recursos** | Modificar propiedades de sub-resources existentes y re-guardar |
| **Escenas 3D completas** | Crear cuartos, luces, camaras, materiales con transparencia/metallic |
| **Eliminado index tool** | Tool redundante (MCP protocol ya lista tools automáticamente). Eliminados ~205 líneas de tools_index.py + ~60 de server.py |
| **Docstrings compactados 84%** | Descripciones de tools reducidas de ~4,255 → ~670 tokens. Ahora 1-2 líneas compactas en vez de secciones Actions/Args/Returns/Examples |
| **Dirty tracking + auto-save** | `_dirty_scenes` rastrea modificaciones. `handle_save_all_dirty()` guarda todo lo sucio. Auto-save cada 10s via timer en `_process()`. Shutdown save: al cerrar daemon se guardan escenas sucias primero. `_mark_dirty()` en 11 handlers mutantes, `_clear_dirty()` tras save/unload/delete. |
### Nuevas Features (v2.0 Modular)

| Feature | Descripcion |
|---------|-------------|
| **Arquitectura modular** | 10 módulos GDScript separados por responsabilidad (escenas, recursos, shaders, debug, etc.) |
| **Inyección de dependencias** | Módulos reciben referencia al orquestador vía `init(daemon: SceneTree)` |
| **class_name funcional** | Todos los módulos usan `class_name` registrado globalmente por Godot |
| **Mouse lock fix** | `Input.mouse_mode = MOUSE_MODE_VISIBLE` + `ensure_mouse_free()` cada 0.5s + post-save |
| **Ventana 240x150** | Más pequeña y con flags NO_FOCUS + MOUSE_PASSTHROUGH + TRANSPARENT |
| **Mesh inline** | `properties.mesh = {"__type":"Resource", "resource_type":"SphereMesh", ...}` |
| **Shader deduplicación** | El daemon detecta `shader_type` existente y no lo duplica |
| **setup_daemon completo** | Copia los 12 archivos `.gd` del daemon al proyecto automáticamente |

### Workarounds Recomendados

```python
# Para ejecutar escenas (requiere editor):
# No usar: debug("run_scene", ...)
# Usar: Lanzar Godot Editor manualmente

# Para scripts complejos:
# No usar: debug("execute_editor_script", script_code="FileAccess...")
# Usar: Crear archivo .gd y ejecutar con godot --script

# Para batch con set_prop:
# Usar "property_name" o "property" (ambos funcionan ahora)

# Para recursos anidados complejos (ShaderMaterial con shader code):
# El fix de resource_local_to_scene funciona para la mayoria de casos
# Si falla, crear .gdshader separado y referenciar como ExtResource

# Para crear nodos con meshes inline:
# Usar: properties={"mesh": {"__type":"Resource", "resource_type":"SphereMesh", "radius": 0.5}}
# Soporta: BoxMesh, SphereMesh, CapsuleMesh, CylinderMesh, PrismMesh, QuadMesh
```

---

## 9. Checklist para Agentes

Antes de entregar código:
- [ ] ¿El Session Manager se inicializa primero?
- [ ] ¿Todas las operaciones usan el daemon si está disponible?
- [ ] ¿Todas las operaciones requieren GodotDaemon activo? (no hay fallback)
- [ ] ¿Se usan templates con f-strings (no string.Template)?
- [ ] ¿Hay manejo de errores en cada operación?
- [ ] ¿Se actualiza la caché después de modificaciones?
- [ ] ¿Se limpian archivos temporales después de usar?
- [ ] ¿Se cierra la sesión correctamente al final?
- [ ] ¿Nuevos handlers se registran en `_register_handlers()`?
- [ ] ¿Nuevas tools se registran en `server.py`?
- [ ] ¿Hay tests unitarios para la nueva funcionalidad?
- [ ] ¿Los tests de integración pasan?
- [ ] ¿El benchmark no muestra regresión de rendimiento?
- [ ] ¿Se actualizó AGENTS.md con la nueva tool?
- [ ] ¿Se usa `session.id` y NUNCA `session.session_id`?
- [ ] ¿Se reinició el MCP después de cambios en Python (session_manager, tools)?
- [ ] ¿Se probaron las tools con daemon activo?
- [ ] ¿Se documentaron bugs conocidos en la sección correspondiente?

---

## 9. Testing y Benchmarking

### Filosofía de Testing

**Unificado pero no monolítico.** Tests organizados por capa arquitectónica:

| Directorio | Qué testea | Requiere Godot | Velocidad |
|------------|-----------|----------------|-----------|
| `test_core/` | Session Manager, Cache, Helpers | ❌ No | ⚡ Instantáneo |
| `test_tools/` | Tools MCP (scene, node, session) | ✅ Sí (daemon) | 🐢 ~20ms/test |
| `test_integration/` | Workflows completos | ✅ Sí (daemon) | 🐢 ~2-5s/test |

> **Nota:** `test_interfaces/` eliminado en v3.0. Ya no hay fallback que testear.

**Reglas de Testing:**
1. **Fixtures compartidas** en `conftest.py`: `temp_project`, `daemon_session`
2. **Proyecto temporal Godot** por test: auto-crea `project.godot` + estructura mínima
3. **Reset de estado** entre tests: `reset_session_manager` como fixture `autouse`
4. **Tests independientes**: cada test debe poder ejecutarse solo
5. **No mockear Godot** en tests de tools: si Godot falla, el test debe fallar

### Filosofía de Benchmarking

**Rendimiento es una feature.** Todo cambio que afecte performance debe ser medible:

```python
# Benchmark mínimo para cada tool
@pytest.mark.benchmark
class TestSceneToolBenchmark:
    def test_get_scene_tree_cold(self, session_id, temp_project):
        # 1 warm-up + 10 mediciones
        times = measure_tool(scene_tool, action="get_tree", n=10)
        assert avg(times) < 0.5  # 500ms máximo
    
    def test_get_scene_tree_cache(self, session_id, temp_project):
        # Primera llamada calienta cache
        scene_tool(action="get_tree", ...)
        # Segunda llamada debe ser <1ms
        times = measure_tool(scene_tool, action="get_tree", n=10)
        assert avg(times) < 0.001  # 1ms máximo
```

**Métricas críticas:**
| Métrica | Target | Alerta |
|---------|--------|--------|
| Tool cold | <500ms | >1000ms |
| Tool cache hit | <1ms | >5ms |
| Cache hit rate | >80% | <50% |
| Memoria por sesión | <50MB | >100MB |
| Archivos temporales | 0 después de test | >0 |

**Runner de benchmarks:**
```bash
# Ejecutar benchmarks
python -m benchmarks.run_benchmarks

# Generar reporte JSON
python -m benchmarks.run_benchmarks --output report.json

# Comparar con baseline
python -m benchmarks.run_benchmarks --compare baseline.json
```

---

## 9.1 Testing Real - Resultados Documentados (2026-05-13)

### Sesión de Testing

**Proyecto:** LAIKA (Godot 4.6.1) | **Sesión:** 59fa57d4 | **Daemon:** Activo puerto 49631

#### Flujo Ejecutado (Ejemplo Real)

```python
# 1. Crear nivel completo vía batch (11 ops en ~200ms)
batch([
  {"action": "add", "params": {"node_type": "CharacterBody2D", "node_name": "Player", "properties": {"position": {"x": 100, "y": 300}}}},
  {"action": "add", "params": {"node_type": "StaticBody2D", "node_name": "Ground", "properties": {"position": {"x": 400, "y": 500}}}},
  {"action": "add", "params": {"node_type": "CharacterBody2D", "node_name": "Enemy1", "properties": {"position": {"x": 600, "y": 300}}}},
  {"action": "add", "params": {"node_type": "Area2D", "node_name": "Coin1", "properties": {"position": {"x": 300, "y": 250}}}},
  {"action": "save", "params": {"scene_path": "res://test_level.tscn"}}
])

# 2. Validar
validate("scene", scene_path="res://test_level.tscn")  # → VÁLIDO

# 3. Configurar proyecto
project("setting", setting_name="display/window/size/viewport_width", value=1920)
```

#### Resultados por Tool (v2.0 Modular - 2026-05-15)

| Tool | Tests | Exitosos | Fallidos | Estado |
|------|-------|----------|----------|--------|
| session | 3 | 3 | 0 | ✅ 100% |
| scene | 6 | 6 | 0 | ✅ 100% |
| node | 6 | 6 | 0 | ✅ 100% |
| batch | 1 | 1 | 0 | ✅ 100% |
| project | 2 | 2 | 0 | ✅ 100% |
| debug | 3 | 3 | 0 | ✅ 100% |
| validate | 2 | 2 | 0 | ✅ 100% |
| resource | 2 | 2 | 0 | ✅ 100% |
| skeleton | 2 | 2 | 0 | ✅ 100% |
| animation | 3 | 3 | 0 | ✅ 100% |
| shader | 3 | 3 | 0 | ✅ 100% |
| signal | 2 | 2 | 0 | ✅ 100% |
| global | 2 | 2 | 0 | ✅ 100% |
| tilemap | 1 | 1 | 0 | ✅ 100% |

**Total: 39/39 operaciones exitosas (100%)**

*Nota: Testing realizado en proyecto Vindictide con daemon modular v2.0*

---

## 10. Las 15 Tools de Heren MCP v2.0

### Lista Completa y Estado

| # | Tool | Actions | Dominio | Estado | Notas |
|---|------|---------|---------|--------|-------|
| 1 | `session` | open, close, list, info, health | Gestión de sesiones | ✅ **100%** | Estable |
| 2 | `scene` | get_tree, save, load, unload, list_loaded, screenshot, create, delete, rename, add_ext_resource, set_editable_paths | Escenas | ✅ **100%** | v2.0: Modular |
| 3 | `node` | add, remove, set_prop, get_prop, duplicate, rename, move, array_append, array_remove | Nodos | ✅ **100%** | v2.0: Mesh inline soportado |
| 4 | `batch` | (múltiples operaciones) | Batch operations | ✅ **100%** | 11 ops en ~200ms |
| 5 | `resource` | create, read, update, delete, list, create_script, read_script, edit_script | Recursos .tres + .gd | ✅ **100%** | v2.0: script CRUD |
| 6 | `animation` | create_player, create, add_track, add_key, state_machine | Animaciones | ✅ **100%** | v2.0: AnimationLibrary |
| 7 | `skeleton` | create, add_bone, set_rest, skin, attachment | Esqueletos 2D/3D | ✅ **100%** | v2.0: Modular |
| 8 | `shader` | create, edit, validate, material, uniform | Shaders | ✅ **100%** | v2.0: Sin duplicación de shader_type |
| 9 | `tilemap` | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps | ✅ **100%** | v2.0: Requiere tilesets |
| 10 | `project` | create, setup_daemon, setting, autoload, remove_autoload, shader_global | Configuración | ✅ **100%** | v2.0: setup_daemon copia todos los módulos |
| 11 | `debug` | breakpoint, stack_trace, watch, console, run_scene, stop_scene, get_editor_errors, execute_editor_script | Depuración | ✅ **100%** | v2.0: Debug completo |
| 12 | `validate` | scene, script, node, resource | Validación | ✅ **100%** | v2.0: scene/node verificados |
| 13 | `signal` | connect, disconnect, list, set_script | Señales | ✅ **100%** | v1.0: Signal management |
| 14 | `global` | autoload, project_setting, shader_global | Configuración global | ✅ **100%** | v1.0: Global settings |

### Filosofía: Centralizadas

```python
# 14 tools cubren TODO Godot Engine
# NO dispersar en 50 archivos
# NO crear una tool por cada operación atómica
```

### Filosofía: Modulares

```python
# Una tool con múltiples modos via parámetro 'action'
def resource_tool(action, **kwargs):
    if action == "create":
        return create_resource(**kwargs)
    elif action == "read":
        return read_resource(**kwargs)
    elif action == "update":
        return update_resource(**kwargs)

# El agente usa UNA tool para múltiples operaciones
resource_tool(action="create", resource_path="res://mat.tres", resource_type="ShaderMaterial")
resource_tool(action="read", resource_path="res://mat.tres")
```

### Bugs Arreglados en v1.1 ✅

| # | Bug | Tool Afectada | Estado | Fix |
|---|-----|---------------|--------|-----|
| 1 | **Animación no persiste** | `animation` (create, add_track) | ✅ ARREGLADO | Usar AnimationLibrary en vez de add_animation() |
| 2 | **Shader uniform no aplica** | `shader` (uniform) | ✅ ARREGLADO | Cubrir 4 tipos de materiales (CanvasItem, GeometryInstance3D override/overlay, MeshInstance3D surface) |

### Bugs Conocidos del Daemon (v2.0 Modular)

| # | Bug | Tool Afectada | Severidad | Workaround |
|---|-----|---------------|-----------|------------|
| 1 | **Screenshot pequeño/vacío** | `scene` (screenshot) | 🟢 Baja | Normal sin texturas/cámaras configuradas |
| 2 | **ExtResource faltante** | `node` (add con material externo) | 🟡 Media | Cuando se crea un nodo con `ShaderMaterial` que referencia un `.gdshader` externo, el daemon no genera la declaración `[ext_resource]` en el `.tscn`. La escena queda corrupta para Godot. |

**Fix planificado:** Detectar referencias a recursos externos durante la serialización de sub-resources e inyectar las declaraciones `[ext_resource]` correspondientes al principio del archivo. |

### Regla Crítica: `session.id` vs `session.session_id`

**NUNCA uses `session.session_id`**. El objeto Session tiene `session.id`:

```python
# ❌ MAL - AttributeError
session_manager.get_godot_daemon(session.session_id)

# ✅ BIEN
session_manager.get_godot_daemon(session.id)
```

**Tools afectadas si se usa mal:** project, animation, skeleton, shader, tilemap.

---

## 11. Sistema Visual - "Ojos para el Agente"

El agente no puede ver la escena. El Sistema Visual le da "ojos":

### `scene` action `"inspect_visual"`
- **Grid superpuesto** - Cada 100px, coordenadas visibles
- **Labels de nodos** - Nombre de cada nodo en su posición
- **Axes indicator** - X (rojo), Y (verde), Z (azul) en esquina
- **Bounding boxes** - Cajas alrededor de nodos seleccionables

### `scene` action `"raycast"`
- El agente dispara un rayo desde cualquier punto
- El daemon responde: ¿qué colisionó? ¿dónde? ¿normal?
- Perfecto para posicionamiento automático

### `scene` action `"measure"`
- Distancia entre dos nodos
- Ángulo entre vectores
- Bounding box de un grupo
- El agente puede "medir" antes de "mover"

### Ejemplo de uso
```python
# 1. Tomar screenshot con grid
scene("inspect_visual", session_id="abc", scene_path="res://Level.tscn",
      output_path="C:/Temp/level_grid.png", show_grid=True, show_labels=True)

# 2. Medir distancia entre enemigo y jugador
measure(session_id="abc", scene_path="res://Level.tscn", 
        node_a="Enemy", node_b="Player")
# → {"distance": 150.5, "direction": {"x": -1, "y": 0}}

# 3. Raycast para ver qué hay delante del jugador
raycast(session_id="abc", scene_path="res://Level.tscn",
        from={"x": 100, "y": 200}, direction={"x": 1, "y": 0})
# → {"hit": true, "position": {"x": 250, "y": 200}, "collider": "Wall"}
```

---

---

## 13. PLAN v4.0 — Migración Masiva

> 🚧 **ESTADO: EN CURSO (Fase 2 planificada).** v3 sigue operativo.
> **Fase 0 COMPLETADA (2026-08-03)** — fundaciones FlojoMCP listas (commit `94b3d4c` en FlojoMCP).
> **Fase 1 COMPLETADA (2026-08-03)** — Plugin Núcleo en `laika-gd/addons/heren/` (EditorPlugin + WS client + dispatcher + undo/redo + scene_handlers, validado E2E real).
> Objetivo: reemplazar **GodotDaemon + FastMCP (Python)** por **EditorPlugin + FlojoMCP (Rust)**.
> Los cambios nuevos van a v4. No ampliar v3 salvo bugs críticos.

### 13.1 Resumen

| | v3 (actual) | v4 (objetivo) |
|---|---|---|
| **Acceso a editor** | ❌ Daemon standalone (EditorInterface inaccesible) | ✅ EditorPlugin real (`extends EditorPlugin`) |
| **Undo/Redo** | ❌ Irreversible | ✅ `EditorUndoRedoManager` |
| **MCP server** | Python FastMCP (~60MB, schemas rotos con decoradores) | Rust FlojoMCP (7MB, schemas en compile-time) |
| **Transporte** | WebSocket (daemon=server, frágil) | WebSocket (plugin=cliente, auto-reconnect, patrón gopeak) |
| **Visibilidad** | SubViewport sin cámara | Viewports 2D/3D reales + sistema de visión con presupuesto de tokens |
| **Sesiones** | SessionManager Python (LRU, temp files) | `flojo-session` persistente por proyecto |
| **Coordenadas** | `serialize_value`/`deserialize_value` (éxito) | Heredado + expansión (Transform2D/3D, snaps, relativas) |

### 13.2 Decisiones Arquitectónicas (ADR)

**ADR-001: FlojoMCP sobre FastMCP.** FastMCP genera schemas por introspection runtime → los decoradores (`@require_session`) rompen la firma → schemas vacíos. FlojoMCP genera schemas en compile-time (macro `syn` + `schemars`) → imposible de romper. Prueba real: PulseWire ya lo usa en producción. Regla: todo lo que construyamos en FlojoMCP debe ser **feature genérica** reutilizable, no específico de Godot.

**ADR-002: EditorPlugin sobre GodotDaemon.** El daemon corre `Engine.is_editor_hint() = false` → `_get_editor_interface_or_fail()` siempre falla. Nunca podrá tocar el editor real. Con EditorPlugin ganamos: `EditorUndoRedoManager`, viewports 2D/3D reales, `EditorFileSystem` (import pipeline), play con breakpoints, selection sync, popup selectors, toaster.

**ADR-003: WebSocket con plugin=cliente (patrón gopeak).** Transporte WebSocket local, pero **el plugin es el CLIENTE** y el server MCP es el **SERVER**. gopeak (competencia real) valida el patrón: el MCP server abre server HTTP+WS unificado; el EditorPlugin se conecta con auto-reconnect y backoff exponencial. El editor NO depende de que el server exista. Permite push de eventos (`scene_changed`, `selection_changed`). Invertimos el rol de v3 (daemon=server) que causaba puerto ocupado y daemon muerto sin aviso. Descartadas: HTTP JSON-RPC (sin push), plugin hace MCP completo en GDScript (pierde FlojoMCP).

**ADR-004: Sesiones guardadas por proyecto.** `flojo-session` persistente en `.heren/session.json` dentro del proyecto Godot. Mantiene la arquitectura de sesiones exitosa sin SessionManager Python.

**ADR-005: Coordenadas unificadas heredadas + expansión.** Conservar `serialize_value`/`deserialize_value` con auto-detección por keys y expandir tipos. Fue un gran éxito (posiciones aplican correctamente). Expansión backward-compatible.

### 13.3 Arquitectura Objetivo

```
OpenCode (cliente MCP)
    │  STDIO (MCP protocol)
    ▼
HerenServer.exe  (FlojoMCP — Rust, 7MB, sin runtime)
    │  WebSocket server local (127.0.0.1:PUERTO)  ← patrón gopeak
    ▼
HerenEditorPlugin  (EditorPlugin GDScript → EditorInterface)
    ├── editor_plugin.gd         # extends EditorPlugin, lifecycle
    ├── ws_client.gd             # cliente WS con auto-reconnect
    ├── dispatcher.gd            # recibe tool_invoke → ejecuta handler
    ├── undo_redo_wrapper.gd     # envuelve ops en EditorUndoRedoManager
    ├── handlers/
    │   ├── scene_handlers.gd    # EditorInterface scene ops
    │   ├── node_handlers.gd     # nodos, transforms, coordenadas
    │   ├── resource_handlers.gd # EditorFileSystem, imports
    │   ├── animation_handlers.gd# AnimationPlayer, AnimationTree, state machines
    │   ├── skeleton_handlers.gd # Skeleton2D/3D
    │   ├── shader_handlers.gd   # shaders, materiales
    │   ├── tilemap_handlers.gd  # TileMap, TileSet, terrain, patterns
    │   ├── project_handlers.gd  # ProjectSettings, autoloads, input map
    │   ├── debug_handlers.gd    # run/stop, breakpoints (editor real)
    │   ├── visual_handlers.gd   # viewports, previews, screenshots
    │   └── validation_handlers.gd
    └── events/
        └── event_pusher.gd      # scene_changed, selection_changed → WS
```

**Módulos ELIMINADOS de v3**: `godot_daemon.py`, `session_manager.py` (Python), `heren_daemon.gd` orquestador, `heren_window_manager.gd`, `heren_server_manager.gd`, `heren_tscn_serializer.gd` (la serialización de .tscn la hace Godot nativamente al guardar).

### 13.4 Features Genéricas a Aportar a FlojoMCP

> Regla de hierro: **nada específico de Godot**. Todo es infraestructura MCP reutilizable. El plugin Godot es el primer consumidor, no el dueño.

| Feature | Crate/Feature | Descripción | Beneficiarios |
|---------|---------------|-------------|---------------|
| **`ws-server`** | `flojo-transport` o feature en `flojo-mcp` | Exponer server WebSocket local al que se conectan plugins/agentes externos | Godot, Unity, Blender, browsers, daemons |
| **`image_content` / `image_resource`** | `flojo-mcp` | Contenido imagen base64 en tool results y resources (`Content::image` del spec MCP) | Cualquier server con screenshots/thumbnails/gráficos |
| **Truncación/paginación** | `flojo-mcp` (helpers) | `truncate_json()`, `PageableResult`, `summarize_tree()` | Resultados grandes: escenas, logs, DB |
| **Session multi-proyecto** | `flojo-session` | Sesión path-based: `Session::load(path)` por workspace/proyecto | Editores, IDEs, repos |
| **Hooks/middleware de tool call** | `flojo-mcp` | pre/post hooks: logging, métricas, presupuesto de tokens | Observabilidad universal |
| **`ctx.tokens_estimate`** | `flojo-mcp` | Estimación de tokens del payload de respuesta | Control de costo universal |

### 13.5 Sistema de Coordenadas (Heredado + Expansión)

**Heredado (v3 — funcionando):**
```gdscript
{"x": 100, "y": 200, "__type": "Vector2"}     # auto-detección por keys
{"x": 1, "y": 0, "z": 0, "__type": "Vector3"}
{"r": 1, "g": 0, "b": 0, "a": 1, "__type": "Color"}
{"x": 0, "y": 0, "w": 64, "h": 64, "__type": "Rect2"}
{"path": "Player/Sprite", "__type": "NodePath"}
```
Auto-detección: `x`+`y` → Vector2; `x`+`y`+`z` → Vector3; `r`+`g`+`b` → Color. `deserialize_resource`: `{"type": "RectangleShape2D", "size": {...}}` → instancia por `ClassDB`.

**Expansión v4:**
| Tipo | Formato JSON | Notas |
|------|--------------|-------|
| `Vector2i/3i` | `{x, y, __type}` | Para tilemaps, celdas, enteros |
| `Transform2D` | `{origin: {x,y}, x_axis: {x,y}, y_axis: {x,y}}` | Posición + rotación + scale completo |
| `Transform3D` | `{origin: {x,y,z}, basis: {x: {...}, y: {...}, z: {...}}}` | Basado en basis 3x3 |
| `Quaternion` | `{x, y, z, w, __type}` | Rotación 3D |
| `Plane` / `AABB` | `{normal, d}` / `{position, size}` | Para raycasts, bounding boxes |
| `StringName` | `{name, __type: "StringName"}` | Nombres de nodos/signals |

**Sistema de Grid/Snap (nuevo):**
- `visual_snap_grid`: consultar/configurar snapping del editor (`EditorInterface.get_node_3d_*_snap()`, `is_node_3d_snap_enabled()`).
- `coord_to_tile` / `tile_to_coord`: convertir píxeles ↔ celdas de tilemap (`TileMap.local_to_map()` / `map_to_local()`).
- `coord_relative`: mover nodo relativo a otro: `{parent: "Player", offset: {x, y}}` → calcula posición absoluta.

**Dónde vive**: la serialización de coordenadas vive en FlojoMCP como feature genérica (crate `flojo-godot-types` o dentro del contract de `ws-server`) — NO en el plugin. Unity/Blender la reutilizan. El plugin implementa la conversión exacta Godot ↔ JSON.

### 13.6 Sistema de Visibilidad — "Ojos con Control"

> **Problema que resuelve**: el modelo era ciego. La solución no es darle TODO, es darle **lo que pida, cuando lo pida, al costo que elija**.

**Principios:** (1) Pull, no push — el agente pide ver, nada se inyecta solo. (2) Jerarquía de costo — texto → ASCII → low-res → full-res. (3) Presupuesto de tokens por sesión — el server trackea, el agente consulta. (4) Cache de visión — si la escena no cambió, reusa. (5) Regiones/foco — ver solo un nodo/área.

**Tools de visión:**
| Tool | Costo est. | Qué devuelve |
|------|-----------|--------------|
| `visual_scene_summary` | ~50 tok | Contador por tipo de nodo, bbox total, dirty flags |
| `visual_ascii_scene` | ~150 tok | Árbol ASCII colapsado/expandido (no imagen) |
| `visual_inspect_scene` | alto | Captura viewport 2D/3D **real del editor** (cámaras + gizmos) + metadatos |
| `visual_inspect_node` | alto | Captura enfocada en un nodo (framing) |
| `visual_preview_resource` | bajo | Thumbnail vía `EditorResourcePreview` / `make_mesh_previews` |
| `visual_diff` | bajo | Diff textual antes/después (ver cambio sin 2 imágenes) |
| `vision_budget` | ~30 tok | Consultar/establecer presupuesto de la sesión |
| `vision_cache` | ~30 tok | Ver/limpiar cache de visión |

Cada tool de visión devuelve metadatos: `tokens_estimate`, `bytes`, `resolution`, `cached: bool`. El agente decide conscientemente.

**Eventos visuales (push controlado):** `selection_changed` → notifica al agente (opcional, con rate-limit): "el usuario seleccionó Player/Sprite". NO se envía imagen, solo el path del nodo (barato).

### 13.7 TileMaps, AnimationPlayers y Recursos Complejos

**TileMap/TileSet (expansión):**
| Capacidad | Detalle |
|-----------|---------|
| **Inspección completa** | `inspect_set` / `inspect_map`: atlas sources, terrains, patterns, layers |
| **Coordenadas tiles vs píxeles** | `local_to_map` / `map_to_local` / `coord_to_tile` / `tile_to_coord` |
| **Pintado por región** | `set_cells` en región rect (batch), con preview opcional |
| **Terrain autoconnect** | `set_cell` + `apply_terrain` con reglas de peering |
| **Patrones reutilizables** | Crear `TileMapPattern` desde selección de celdas |
| **Custom data layers** | `set_custom_data` en celdas |
| **Y-sort / physics layers** | Configuración de capas físicas y ordenamiento |

**Patrón de uso (workflow):** `coord_to_tile` para saber dónde pintar → `visual_preview_resource` para ver el tileset → `set_cells` en lote → `visual_inspect_scene` para verificar.

**AnimationPlayer / AnimationTree / State Machines:**
| Capacidad | Detalle |
|-----------|---------|
| **Libraries** | Crear/listar `AnimationLibrary` por player |
| **Tracks** | value / position / rotation / scale / method / audio / animation |
| **Keys con easing** | Insertar keys con `Tween` curves (Linear, Cubic, Elastic...) |
| **Blend spaces** | Crear `AnimationNodeBlendSpace2D/3D` |
| **State machines** | `AnimationNodeStateMachine` con nodos, transitions, auto-advance |
| **Edición visual** | `visual_inspect_node` sobre el `AnimationTree` para ver resultado |
| **One-shot batch** | Crear animación completa en una llamada: tracks + keys + loop |

**Recursos complejos (ShaderMaterial, SpriteFrames, Gradient...):**
| Tipo | Estrategia |
|------|-----------|
| **ShaderMaterial** | Crear `.gdshader` + material con uniforms tipados |
| **SpriteFrames** | Añadir frames desde texturas, set anims |
| **Gradient/GradientTexture2D** | `{points: [{offset, color}], fill: "linear"}` |
| **Curves** | `Curve` con `{points: [{pos, left_tangent, right_tangent}]}` |
| **PhysicsMaterial** | friction, bounce, roughness |
| **Environment (3D)** | ambient, fog, tonemap |
| **NavigationMesh** | geometría, agent radius |

**Regla**: cualquier recurso complejo debe tener (1) inspección → (2) edición → (3) preview → (4) persistencia verificada.

### 13.8 Sesiones Guardadas (arquitectura)

```
.heren/session.json  (dentro del proyecto Godot)
├── project_path              # proyecto activo (reportado por plugin)
├── vision: { budget_tokens, spent_tokens, default_resolution, cache }
├── preferences: { show_grid, ascii_depth, snap_enabled }
├── last_edited_scene: "res://src/scenes/level1.tscn"
└── workspace_state: { open_scenes, selected_nodes }
```
- Usa `flojo-session` (KV persistente) + patrón *path-based por proyecto* (feature a aportar).
- El `Context` de FlojoMCP la inyecta a todos los tools automáticamente.
- El plugin reporta el proyecto activo → FlojoMCP carga la sesión correcta.

### 13.9 Plan por Fases

**Fase 0 — Fundaciones FlojoMCP (1-2 sem).** Objetivo: FlojoMCP tiene las features genéricas.
- [x] `ws-server` feature (WebSocket server local + handshake + reconnect) — commit `94b3d4c` (flojo-mcp)
- [x] `image_content` / `image_resource` (base64) — `image_content`/`text_content`/`content_result` en `tool.rs`
- [x] Helpers de truncación/paginación — `pagination.rs`: `truncate_json`, `PageableResult`/`PageInfo`, `summarize_tree`
- [x] Session path-based multi-proyecto — `session_manager.rs`: `SessionManager` + `.heren/session.json`
- [x] Hooks/middleware + `tokens_estimate` — `hooks.rs`: `ToolHooks` pre/post + `estimate_tokens`
- [x] Tests + benchmarks + CI — 46 unit + 2 E2E ws + 3 session, fmt/clippy limpios, CI existente cubre all-features
- **Criterio**: ✅ ejemplo `echo_ws` + `image_content` funcionales, tests verdes (validado con cliente WebSocket real)
- **Nota**: rmcp v1.7.0 NO trae WS (`ws.rs` es placeholder) → construido sobre `SinkStreamTransport` (acepta `(Sink, Stream)` de `JsonRpcMessage`). Frames JSON-RPC inválidos cierran la conexión.

**Fase 1 — Plugin Núcleo (2-3 sem).** Objetivo: editor_plugin.gd + WS client + dispatcher + scene básicas con undo/redo.
- [x] `addons/heren/editor_plugin.gd` (`extends EditorPlugin`) — instalado en `laika-gd/addons/heren/`
- [x] `ws_client.gd` (conecta a server MCP, auto-reconnect, backoff) — habla MCP JSON-RPC, recibe `tools/call`, responde resultados
- [x] `dispatcher.gd` (tool_invoke → handler) — rutea por prefijo (`scene/*` → scene_handlers)
- [x] `undo_redo_wrapper.gd` (agrupa ops en `EditorUndoRedoManager.create_action`) — wrapper con `add_do_method(Object, StringName, args)` (Godot 4.6 no acepta Callable directo)
- [x] Handlers: health, project_info, get_edited_scene_root, get_open_scenes, create/save/open scene — `handlers/scene_handlers.gd`
- [x] Validación E2E real (2026-08-03): `tools/call scene/health` → healthy; `scene/open play_area.tscn` → opened; `scene/create Node2D TestNode` → creado como hijo de PlayArea; `scene/get_edited_scene_root` → has_scene:true. Herramienta: `tools/ws_test_server.py` (server WS Python de prueba)
- **Criterio**: ✅ desde OpenCode → crear escena en editor abierto → Ctrl+Z lo deshace (validado: nodo creado vía EditorUndoRedoManager, deshacible)
- **Hallazgo**: NO definir `func get_editor()` en EditorPlugin (colisiona); usar `get_editor_interface()` directo en handlers.
- **Nota**: el plugin se valida contra un server WS Python de prueba (`tools/ws_test_server.py`). El server Rust definitivo (HerenServer.exe con FlojoMCP) llega en Fase 4; el plugin ya habla el protocolo MCP JSON-RPC estándar que ese server usará.

**Fase 2 — Migrar Módulos (3-4 sem).** Objetivo: escena, nodo, recurso, shader, animación, skeleton, tilemap, proyecto, debug, validación.
- [ ] `scene_handlers.gd` (EditorInterface scene ops reales)
- [ ] `node_handlers.gd` (CRUD nodos + coordenadas expandidas)
- [ ] `resource_handlers.gd` (EditorFileSystem, imports)
- [ ] `animation_handlers.gd`, `skeleton_handlers.gd`, `shader_handlers.gd`
- [ ] `tilemap_handlers.gd` (sistema completo §13.7)
- [ ] `project_handlers.gd`, `debug_handlers.gd`, `validation_handlers.gd`
- **Criterio**: cada módulo con tests GUT en editor.

**Fase 3 — Sistema de Visión (2-3 sem).** Objetivo: §13.6 completo.
- [ ] Captura viewports 2D/3D reales
- [ ] 8 tools de visión + presupuesto + cache
- [ ] Previews de recursos
- [ ] Eventos push (selection_changed, scene_changed) con rate-limit
- **Criterio**: `visual_*` funcionales, presupuesto respetado, cache funciona.

**Fase 4 — Tools FlojoMCP + Sesiones (3-4 sem).** Objetivo: portar 14 tools Python → Rust, sesiones persistentes.
- [ ] Definir tools Rust con macros `#[tool]` + schemas
- [ ] FlojoTester para cada tool
- [ ] Sesiones path-based por proyecto
- [ ] `visual_*` tools en Rust
- **Criterio**: todos los tests en FlojoTester, sesiones sobreviven reinicio.

**Fase 5 — Hardening + Release (2 sem).**
- [ ] CI: `cargo test`, `flojo check`, GUT, benchmarks
- [ ] Packaging: addon `.zip` + `HerenServer.exe`
- [ ] Docs (README, TROUBLESHOOTING)
- [ ] Comparativa vs gopeak/coding-solo en `benchmark_vs_competitors.py`
- **Criterio**: Release v4.0.0, benchmark documentado.

**Total: ~14-16 semanas.**

### 13.10 Comparación Competencia (referencia)

| | gopeak | coding-solo | Heren v3 | Heren v4 |
|---|--------|-------------|----------|----------|
| Transporte | WS (plugin=cliente) | STDIO + subprocess | WS (daemon=server) | **WS (plugin=cliente)** |
| Editor real | ✅ | ❌ | ❌ | ✅ |
| Undo/Redo | ❌ | ❌ | ❌ | ✅ |
| Sesiones | ❌ | ❌ | ✅ (Python) | ✅ (flojo-session) |
| Visibilidad | ❌ | ❌ | SubViewport | **Viewports reales + presupuesto** |
| Coordenadas | manual por tool | manual | unificado (éxito) | **unificado + expansión** |
| Validación | ❌ | ❌ | ❌ | ✅ JSON schema automático |
| Tests | ❌ | ❌ | pytest frágil | **FlojoTester** |

### 13.11 Riesgos y Mitigaciones

| Riesgo | Prob. | Impacto | Mitigación |
|--------|-------|---------|------------|
| FlojoMCP v0.1.0 inmaduro | Media | Alto | PulseWire ya lo usa; piloto en Fase 1 |
| Migración de 80 handlers es larga | Alta | Medio | Por fases, cada una con criterio |
| Coordenadas nuevas rompen compat | Baja | Alto | Backward-compatible + tests de regresión |
| Eventos push saturan tokens | Media | Medio | Rate-limit + presupuesto + pull-first |
| Plugin depende de editor abierto | Alta | Bajo | Documentar; modo headless para CI futuro |

### 13.12 Checklist v4 (para agentes)

- [ ] ¿El handler usa `EditorUndoRedoManager` para mutaciones?
- [ ] ¿La serialización de coordenadas usa el sistema unificado?
- [ ] ¿La tool devuelve `tokens_estimate` si es visual?
- [ ] ¿Respeta el presupuesto de visión de la sesión?
- [ ] ¿Hay tests en FlojoTester (Rust) y GUT (GDScript)?
- [ ] ¿El evento push tiene rate-limit?
- [ ] ¿Se documentó en AGENTS.md v4?

---

**Recuerda: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
