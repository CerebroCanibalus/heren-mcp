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
| **CENTRALIZADAS** | Pocas tools que agrupan funcionalidad relacionada. | `scene_tools.py` maneja TODO lo de escenas. `node_tools.py` maneja TODO lo de nodos. |
| **MODULARES** | Una tool con múltiples modos/comandos. Flexible. | `scene_tool` con `action="get_tree"` o `action="save"`. Un punto de entrada, múltiples operaciones. |
| **POTENTES** | Máximo poder con mínima cantidad de tools. | Una tool puede crear, modificar, eliminar y consultar. Godot hace TODO el trabajo pesado. |

### Decisiones Arquitectónicas Derivadas

1. **Godot CLI Nativo ÚNICAMENTE.** Cero parsers propios. Cero serialización manual.
2. **Session Manager PRIMERO.** Se inicializa antes que todo. Sin sesión, no hay operaciones.
3. **Scripts Temporales por Operación.** Godot headless ejecuta un script GDScript autónomo por cada operación. Más confiable que procesos persistentes.
4. **Cache en memoria.** Las escenas se mantienen en RAM. Invalidación explícita tras modificaciones.
5. **Fail-fast.** Si Godot no responde en 30 segundos, error claro. Sin cuelgues.
6. **Templates GDScript con f-strings.** Generación de código type-safe. Sin inyección de variables inválidas.
7. **Tools multifuncionales.** Una tool = múltiples operaciones relacionadas. Menos tools, más poder.

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
│  │  CAPA 2: API TOOLS (3 tools)        │   │
│  │  ├─ scene_tools.py                  │   │
│  │  │   └─ scene_tool(action="...")     │   │
│  │  ├─ node_tools.py                   │   │
│  │  │   └─ node_tool(action="...")      │   │
│  │  └─ session_tools.py                │   │
│  │      └─ session_tool(action="...")   │   │
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
# POCAS tools que agrupan mucha funcionalidad
# scene_tools.py → TODO lo de escenas (tree, save, info)
# node_tools.py → TODO lo de nodos (add, remove, set, get)
# NO dispersar en 20 archivos con 1 función cada uno
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
| 2026-05-12 | Arquitectura híbrida moderada (~20 tools) | Centralizar lo simple (session/scene/node), especializar lo complejo (animation/shader/tilemap). Evita parameter bloat. Ver PLAN_TOOLS.md. |
| 2026-05-12 | Tests unificados + benchmarks | MCP anterior tenía 93 tools dispersas y tests fragmentados. Unificar testing en capas + benchmarks de rendimiento para detectar regresiones. |

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
- [ ] ¿Hay tests unitarios para la nueva funcionalidad?
- [ ] ¿Los tests de integración pasan?
- [ ] ¿El benchmark no muestra regresión de rendimiento?

---

## 9. Testing y Benchmarking

### Filosofía de Testing

**Unificado pero no monolítico.** Tests organizados por capa arquitectónica:

| Directorio | Qué testea | Requiere Godot | Velocidad |
|------------|-----------|----------------|-----------|
| `test_core/` | Session Manager, Cache, Helpers | ❌ No | ⚡ Instantáneo |
| `test_interfaces/` | GodotInterface, TemplateEngine | ❌ Mock | ⚡ Rápido |
| `test_tools/` | Tools MCP (scene, node, session) | ✅ Sí | 🐢 ~0.4s/test |
| `test_integration/` | Workflows completos | ✅ Sí | 🐢 ~2-5s/test |

**Reglas de Testing:**
1. **Fixtures compartidas** en `conftest.py`: `temp_project`, `session_id`, `sample_scene`
2. **Proyecto temporal Godot** por test: auto-crea `project.godot` + estructura mínima
3. **Reset de estado** entre tests: `reset_session_manager` como fixture `autouse`
4. **Tests independientes**: cada test debe poder ejecutarse solo
5. **No mockar Godot** en tests de tools: si Godot falla, el test debe fallar

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

## 10. Filosofía de Tools en Detalle

### Centralizadas

```
scene_tools.py  →  TODO lo relacionado con escenas
node_tools.py   →  TODO lo relacionado con nodos

NO dispersar funcionalidad en 20 archivos.
NO crear una tool por cada operación atómica.
```

### Modulares

```python
# Una tool con múltiples modos via parámetro 'action'
def scene_tool(action, **kwargs):
    if action == "get_tree":
        return get_scene_tree(**kwargs)
    elif action == "save":
        return save_scene(**kwargs)
    elif action == "get_info":
        return get_project_info(**kwargs)

# El agente usa UNA tool para múltiples operaciones
scene_tool(action="get_tree", scene_path="...")
scene_tool(action="save", scene_path="...")
```

### Potentes

```python
# Una tool puede hacer flujos completos
# Crear nodo + configurar propiedades + guardar escena
# Todo en una sola llamada, un solo script GDScript de 50+ líneas
# Godot hace TODO: carga, modifica, pack, guarda, responde JSON
# El agente solo declara la INTENCIÓN, no la IMPLEMENTACIÓN
```

---

**Recuerda: Poder. Eficiencia. Rapidez.**
**Recuerda: Centralizadas. Modulares. Potentes.**

*Herensuge vigila tu código.*
