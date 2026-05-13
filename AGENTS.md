# 🐉 Heren MCP - AGENTS.md

> **Filosofía Global: Poder. Eficiencia. Rapidez.**
> **Filosofía de Tools: Centralizadas. Modulares. Potentes.**

Este documento es la biblia para agentes que operan Heren MCP. Lee esto antes de tocar una línea de código.

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
| **CENTRALIZADAS** | Un punto de entrada único para cada operación. | `scene_tools.py` para escenas, `node_tools.py` para nodos. Sin dispersión. |
| **MODULARES** | Cada tool hace UNA cosa bien. Componible. | `add_node` solo añade. `set_property` solo modifica. Combinables en batch. |
| **POTENTES** | Máximo poder con mínima complejidad. | Una tool = un script GDScript completo. Godot hace TODO el trabajo pesado. |

### Decisiones Arquitectónicas Derivadas

1. **Godot CLI Nativo ÚNICAMENTE.** Cero parsers propios. Cero serialización manual.
2. **Session Manager PRIMERO.** Se inicializa antes que todo. Sin sesión, no hay operaciones.
3. **Scripts Temporales por Operación.** Godot headless ejecuta un script GDScript autónomo por cada operación. Más confiable que procesos persistentes.
4. **Cache en memoria.** Las escenas se mantienen en RAM. Invalidación explícita tras modificaciones.
5. **Fail-fast.** Si Godot no responde en 30 segundos, error claro. Sin cuelgues.
6. **Templates GDScript con f-strings.** Generación de código type-safe. Sin inyección de variables inválidas.

---

## 2. Arquitectura de Capas (Implementación Actual)

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
│  │  ├─ Singleton thread-safe           │   │
│  │  ├─ LRU Cache con TTL (5 min)       │   │
│  │  ├─ Gestión de sesiones por proyecto│   │
│  │  ├─ Auto-limpieza de archivos temp  │   │
│  │  └─ Cleanup thread (sesiones exp)   │   │
│  └──────────────┬──────────────────────┘   │
│                 │                            │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 1: GODOT CLI INTERFACE        │   │
│  │  ├─ Genera scripts GDScript via     │   │
│  │  │   TemplateEngine (f-strings)     │   │
│  │  ├─ Ejecuta Godot --headless        │   │
│  │  ├─ Parsea TEST_OUTPUT JSON         │   │
│  │  ├─ Manejo de errores detallado     │   │
│  │  └─ Invalidación de cache           │   │
│  └──────────────┬──────────────────────┘   │
│                 │                            │
│  ┌──────────────▼──────────────────────┐   │
│  │  CAPA 2: API TOOLS                  │   │
│  │  ├─ scene_tools.py                  │   │
│  │  │   ├─ start_session               │   │
│  │  │   ├─ end_session                 │   │
│  │  │   ├─ get_scene_tree              │   │
│  │  │   ├─ save_scene                  │   │
│  │  │   └─ get_project_info            │   │
│  │  └─ node_tools.py                   │   │
│  │      ├─ add_node                    │   │
│  │      ├─ remove_node                 │   │
│  │      ├─ set_property                │   │
│  │      └─ get_node_properties         │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
               │ subprocess (Godot CLI)
┌──────────────▼──────────────────────────────┐
│  GODOT ENGINE (headless --script temp.gd)   │
│  ├─ Carga escena                          │
│  ├─ Modifica nodos                        │
│  ├─ packed_scene.pack() + save()          │
│  └─ Imprime TEST_OUTPUT JSON              │
└─────────────────────────────────────────────┘
```

### Flujo de Datos Real

1. Agente llama `heren_start_session(project_path)`
2. Session Manager verifica Godot y crea sesión
3. Agente llama `heren_add_node(...)`
4. API Tool → GodotInterface → TemplateEngine renderiza template con f-strings
5. Session Manager crea archivo GDScript temporal
6. Ejecuta `godot --headless --script temp.gd`
7. Godot carga escena, modifica, hace `packed_scene.pack()` + `ResourceSaver.save()`
8. Godot imprime `TEST_OUTPUT: {"success": true, ...}`
9. Python parsea stdout, extrae JSON, elimina archivo temporal
10. Session Manager invalida cache de la escena modificada

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

### Regla 3: Las Tools son Centralizadas
```python
# TODAS las operaciones de escena van a scene_tools.py
# TODAS las operaciones de nodo van a node_tools.py
# NO crear tools dispersas en múltiples archivos
```

### Regla 4: Las Tools son Modulares
```python
# Cada tool hace UNA cosa bien
heren_add_node(...)      # Solo añade
heren_set_property(...)  # Solo modifica
heren_save_scene(...)    # Solo guarda

# Combinar en secuencia para operaciones complejas
```

### Regla 5: Las Tools son Potentes
```python
# Una sola tool puede generar un script GDScript de 50 líneas
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

## 4. Estructura de Directorios (Actual)

```
D:\Mis Juegos\GodotMCP\heren-mcp\
├── AGENTS.md                 # Este archivo
├── README.md                 # Para usuarios finales
├── requirements.txt          # Dependencias Python
├── run.bat                   # Launcher para OpenCode
├── src/
│   └── heren/
│       ├── __init__.py
│       ├── server.py         # Entry point FastMCP
│       ├── core/
│       │   └── session_manager.py    # Capa 0 - Singleton + LRU Cache
│       ├── interfaces/
│       │   └── godot_cli.py          # Capa 1 - GodotInterface
│       ├── templates/
│       │   └── gdscript_templates.py # Templates f-string para GDScript
│       ├── tools/
│       │   ├── scene_tools.py        # Tools de escenas
│       │   └── node_tools.py         # Tools de nodos
│       └── bridges/
│           └── heren_bridge.gd       # Bridge GDScript (backup)
├── .temp/                    # Archivos temporales (auto-limpieza)
└── tests/                    # Tests (por implementar)
```

---

## 5. Templates Disponibles

| Template | Operación | Descripción |
|----------|-----------|-------------|
| `get_scene_tree` | Lectura | Obtiene árbol completo de nodos con propiedades |
| `save_scene` | Escritura | Guarda escena con cambios |
| `add_node` | Escritura | Añade nodo con propiedades configurables |
| `remove_node` | Escritura | Elimina nodo y guarda |
| `set_property` | Escritura | Modifica propiedad de un nodo |
| `get_node_properties` | Lectura | Obtiene todas las propiedades editables |
| `get_project_info` | Lectura | Lee project.godot (nombre, main_scene, versión) |

### Formato de TEST_OUTPUT

```gdscript
# Godot imprime esto al final de cada script
print('TEST_OUTPUT: ' + JSON.stringify({
    "success": true,
    "data": {...}
}))
```

Python parsea stdout buscando la línea que comienza con `TEST_OUTPUT:`.

---

## 6. Performance Benchmark (Real)

Medido con proyecto LAIKA (Godot 4.6.1):

| Operación | Tiempo Cold | Tiempo Cache | Speedup |
|-----------|-------------|--------------|---------|
| `start_session` | 0.043s | — | — |
| `get_scene_tree` | 0.370s | 0.000s | ∞x |
| `get_node_properties` | 0.363s | — | — |
| `add_node` | 0.377s | — | — |
| `set_property` | 0.368s | — | — |
| `save_scene` | 0.368s | — | — |

**Promedio escritura:** ~0.37s por operación

---

## 7. Decisiones Registry

| Fecha | Decisión | Razón |
|-------|----------|-------|
| 2026-05-12 | Godot CLI Nativo vs Parser Propio | Parser propio tiene bugs de serialización. Godot nunca falla. |
| 2026-05-12 | Session Manager primero | Asegura que el proyecto esté listo antes de cualquier operación. |
| 2026-05-12 | Scripts temporales vs Godot persistente | Procesos persistentes tienen problemas de sincronización. Scripts temporales son 100% confiables. |
| 2026-05-12 | Templates con f-strings vs string.Template | f-strings son type-safe y permiten inyección de JSON válido. |
| 2026-05-12 | Cache en memoria (no disco) | Velocidad. Invalidación explícita tras modificaciones. |
| 2026-05-12 | packed_scene.pack() antes de save | Godot 4 requiere pack() para guardar instancias modificadas. |

---

## 8. Checklist para Agentes

Antes de entregar código:
- [ ] ¿El Session Manager se inicializa primero?
- [ ] ¿Todas las operaciones pasan por Godot CLI?
- [ ] ¿Se usan templates con f-strings (no string.Template)?
- [ ] ¿Hay manejo de errores en cada operación?
- [ ] ¿Se actualiza la caché después de modificaciones?
- [ ] ¿Se limpian archivos temporales después de usar?
- [ ] ¿Se cierra la sesión correctamente al final?

---

## 9. Filosofía de Tools en Detalle

### Centralizadas

```
scene_tools.py  →  TODO lo relacionado con escenas
node_tools.py   →  TODO lo relacionado con nodos

NO dispersar funcionalidad.
NO crear archivos por cada tool.
```

### Modulares

```python
# Cada función es independiente y compostable
def heren_add_node(...):      # Solo añade
    pass

def heren_set_property(...):  # Solo modifica
    pass

# El agente las combina según necesidad
heren_add_node(...)
heren_set_property(...)
heren_save_scene(...)
```

### Potentes

```python
# Una tool genera un script GDScript completo de 40+ líneas
# Godot hace TODO: carga, modifica, pack, guarda, responde JSON
# El agente solo declara la INTENCIÓN, no la IMPLEMENTACIÓN
```

---

**Recuerda: Poder. Eficiencia. Rapidez.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
