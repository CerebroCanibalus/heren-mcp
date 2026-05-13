# 🐉 Heren MCP - AGENTS.md

> **Filosofía: Poder. Eficiencia. Rapidez.**

Este documento es la biblia para agentes que operan Heren MCP. Lee esto antes de tocar una línea de código.

---

## 1. Filosofía de Hierro

### Los Tres Pilares

| Pilar | Significado | Aplicación |
|-------|-------------|------------|
| **PODER** | Acceso total a Godot. Cero limitaciones. | Si Godot puede hacerlo, Heren puede hacerlo. |
| **EFICIENCIA** | Cada operación debe ser óptima. Sin desperdicio. | Batch operations, caché agresiva, sin procesos muertos. |
| **RAPIDEZ** | Tiempo de respuesta mínimo. Sin latencia innecesaria. | Godot persistente, sin lanzar procesos, comunicación directa. |

### Decisiones Arquitectónicas Derivas

1. **Godot CLI Nativo ÚNICAMENTE.** Cero parsers propios. Cero serialización manual.
2. **Session Manager PRIMERO.** Se inicializa antes que todo. Sin sesión, no hay operaciones.
3. **Cache en memoria.** Las escenas se mantienen en RAM. Invalidación por timestamp.
4. **Batch por defecto.** Si el agente hace 5 operaciones, se envían en 1 script GDScript.
5. **Fail-fast.** Si Godot no responde en 5 segundos, error claro. Sin cuelgues.

---

## 2. Arquitectura de Capas

```
┌─────────────────────────────────────────────┐
│           Cliente (LLM/Agente)              │
└──────────────┬──────────────────────────────┘
               │ MCP Protocol
┌──────────────▼──────────────────────────────┐
│           HEREN MCP SERVER                  │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  CAPA 0: SESSION MANAGER            │   │
│  │  ├─ Se inicializa AL INICIO         │   │
│  │  ├─ Mantiene Godot headless vivo    │   │
│  │  ├─ Cache de escenas en memoria     │   │
│  │  ├─ Estado del proyecto             │   │
│  │  └─ Undo/Redo stack                 │   │
│  └──────────────┬──────────────────────┘   │
│                 │                            │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 1: GODOT CLI INTERFACE        │   │
│  │  ├─ Comunicación persistente        │   │
│  │  ├─ Genera scripts GDScript         │   │
│  │  └─ Parsea JSON de respuestas       │   │
│  └──────────────┬──────────────────────┘   │
│                 │                            │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 2: API TOOLS                  │   │
│  │  ├─ scene_tools                     │   │
│  │  ├─ node_tools                      │   │
│  │  ├─ resource_tools                  │   │
│  │  ├─ animation_tools                 │   │
│  │  ├─ shader_tools                    │   │
│  │  └─ tilemap_tools                   │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
               │ stdin/stdout JSON-RPC
┌──────────────▼──────────────────────────────┐
│  GODOT ENGINE (headless + bridge.gd)        │
└─────────────────────────────────────────────┘
```

### Flujo de Datos

1. Agente llama `heren_start_session(project_path)`
2. Session Manager arranca Godot headless con `bridge.gd`
3. Agente llama `heren_add_node(...)`
4. API Tool genera script GDScript
5. Godot CLI Interface envía script a Godot
6. Godot ejecuta y devuelve JSON
7. Session Manager actualiza caché

---

## 3. Reglas de Oro para Agentes

### Regla 1: Session Manager es el Rey
```python
# SIEMPRE empezar así:
session = heren_start_session("D:/MiProyecto")

# NUNCA hacer operaciones sin sesión activa
# NUNCA cerrar la sesión hasta que el agente termine
```

### Regla 2: Godot Hace el Trabajo Pesado
```python
# MAL - Intentar parsear manualmente
with open("scene.tscn") as f:
    content = f.read()
    # ... parsing manual ...

# BIEN - Dejar que Godot lo haga
result = heren_get_scene_tree("res://scene.tscn")
# Godot devuelve JSON perfecto
```

### Regla 3: Batch es Mejor que Individual
```python
# MAL - 5 llamadas individuales
for i in range(5):
    heren_add_node(...)

# BIEN - 1 llamada con batch
heren_batch_operation([
    {"action": "add_node", ...},
    {"action": "add_node", ...},
    {"action": "add_node", ...},
])
```

### Regla 4: Cache es tu Amigo
```python
# La primera vez lee de disco
scene = heren_get_scene_tree("res://Player.tscn")  # ~100ms

# La segunda vez lee de memoria
scene = heren_get_scene_tree("res://Player.tscn")  # ~1ms
```

### Regla 5: Fail-Fast
```python
# Si Godot no responde, error inmediato
# Si el archivo no existe, error inmediato
# Si la operación es inválida, error inmediato
# NUNCA silenciar errores. NUNCA retornar None sin explicación.
```

---

## 4. Estructura de Directorios

```
D:\Mis Juegos\GodotMCP\heren-mcp\
├── AGENTS.md                 # Este archivo
├── README.md                 # Para usuarios finales
├── requirements.txt          # Dependencias Python
├── src/
│   └── heren/
│       ├── __init__.py
│       ├── server.py         # Entry point MCP
│       ├── core/
│       │   ├── session_manager.py    # Capa 0
│       │   ├── cache.py              # LRU + TTL
│       │   └── state.py              # Estado del proyecto
│       ├── interfaces/
│       │   ├── godot_cli.py          # Capa 1 - Comunicación
│       │   └── protocol.py           # JSON-RPC
│       ├── tools/
│       │   ├── scene_tools.py
│       │   ├── node_tools.py
│       │   ├── resource_tools.py
│       │   ├── animation_tools.py
│       │   ├── shader_tools.py
│       │   └── tilemap_tools.py
│       └── bridges/
│           └── heren_bridge.gd       # Script Godot
├── tests/
│   ├── test_session.py
│   ├── test_godot_cli.py
│   └── test_integration.py
└── docs/
    ├── ARCHITECTURE.md
    └── API.md
```

---

## 5. Protocolo de Comunicación

### Formato de Comandos (MCP → Godot)
```json
{
  "id": "cmd_001",
  "action": "get_scene_tree",
  "params": {
    "scene_path": "res://Player.tscn"
  }
}
```

### Formato de Respuestas (Godot → MCP)
```json
{
  "id": "cmd_001",
  "success": true,
  "data": {
    "nodes": [...],
    "resources": [...]
  }
}
```

### Errores
```json
{
  "id": "cmd_001",
  "success": false,
  "error": "Scene file not found: res://Missing.tscn"
}
```

---

## 6. Decisions Registry

| Fecha | Decisión | Razón |
|-------|----------|-------|
| 2026-05-12 | Godot CLI Nativo vs Parser Propio | Parser propio tiene bugs de serialización. Godot nunca falla. |
| 2026-05-12 | Session Manager primero | Asegura que Godot esté listo antes de cualquier operación. |
| 2026-05-12 | JSON-RPC sobre stdin/stdout | Simple, portable, sin dependencias de red. |
| 2026-05-12 | Cache en memoria (no disco) | Velocidad. Invalidación por mtime del archivo. |

---

## 7. Checklist para Agentes

Antes de entregar código:
- [ ] ¿El Session Manager se inicializa primero?
- [ ] ¿Todas las operaciones pasan por Godot?
- [ ] ¿Hay manejo de errores en cada operación?
- [ ] ¿Se actualiza la caché después de modificaciones?
- [ ] ¿Se cierra la sesión correctamente al final?

---

**Recuerda: Poder. Eficiencia. Rapidez.**

*Herensuge vigila tu código.*
