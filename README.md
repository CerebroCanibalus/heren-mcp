<div align="center">

![Heren Godot MCP Banner](assets/HerenGodotBanner.png)

<p>
  <a href="README.md">🇪🇸 Español</a> •
  <a href="README.en.md">🇬🇧 English</a>
</p>

</div>

---

> *"La técnica es una actividad compositora o destructora, violenta, y esto es lo que Aristóteles llamaba la poiesis, la poesía, precisamente."* — **Gustavo Bueno**

---

# ⚔️ Heren Godot MCP

🏰 **Heren Godot MCP** — *Plus Ultra*: ir más allá. 🐉

Servidor MCP de alto rendimiento para **Godot Engine 4.x** que permite a IAs y asistentes controlar proyectos directamente: crear escenas, manipular nodos, gestionar recursos, conectar señales y validar código, **todo mediante un daemon persistente que opera en milisegundos**.

---

## ⚔️ Características

| Característica | Descripción |
|---|---|
| 🔌 **Daemon WebSocket persistente** | Godot headless mantiene conexión viva vía WebSocket — operaciones en ~20ms |
| 🛠️ **15 herramientas centralizadas** | Escenas, nodos, recursos, scripts, señales, animaciones, shaders, validación y debug |
| ⚡ **Batch operations** | Ejecuta múltiples operaciones en una sola llamada WebSocket |
| 🔄 **Fallback automático** | Si el daemon no está disponible, usa scripts temporales (Godot CLI) |
| 🛡️ **Validación integrada** | Valida escenas, scripts, nodos y recursos antes de aplicar cambios |
| 🐛 **Debug completo** | Breakpoints, stack traces, watch variables y captura de consola |
| 📸 **Screenshots** | Captura frames de escenas con rendering GPU |
| 🌍 **I18n nativo** | Sistema de localización español/inglés integrado |

---

## 🛡️ Frente a otros MCPs de Godot

### Velocidad: persistencia vs. intermediación

La diferencia principal: otros MCPs lanzan `godot --headless --script` por cada operación (~370ms de overhead). Heren MCP mantiene un daemon Godot persistente vía WebSocket — operaciones en milisegundos.

| Operación | [Coding-Solo](https://github.com/Coding-Solo/godot-mcp) (3.6k⭐) | [GoPeak](https://github.com/HaD0Yun/Gopeak-godot-mcp) (179⭐) | **Heren Godot MCP** |
|---|---|---|---|
| Leer escena | ~367ms (Godot headless) | ~80ms* (WebSocket) | **~20ms** (daemon persistente) |
| Añadir nodo | ~367ms | ~60ms* | **~20ms** |
| Batch 10 ops | ~3.7s | ~600ms* | **~200ms** |

*Estimado con plugin ya instalado y corriendo

### Comparativa completa

| Dimensión | [Coding-Solo](https://github.com/Coding-Solo/godot-mcp) | [GoPeak](https://github.com/HaD0Yun/Gopeak-godot-mcp) | [tugcantopaloglu](https://github.com/tugcantopaloglu/godot-mcp) | **Heren Godot MCP** |
|---|---|---|---|---|
| **Herramientas** | ~15 | 95+ | 149 | **15** |
| **Persistencia** | ❌ (lanza Godot cada vez) | ✅ (WebSocket) | ❌ | **✅ (WebSocket daemon)** |
| **Velocidad** | Lento (~367ms/op) | Medio (~80ms/op) | Lento (~2-5s/op) | **⚡ Rápido (~20ms/op)** |
| **Sin plugin Godot** | ✅ | ❌ (requiere addon) | ❌ | **✅** |
| **Sin Node.js** | ❌ (requiere npm) | ❌ (requiere npm) | ❌ | **✅ (solo Python)** |
| **Batch operations** | ❌ | ✅ | ❌ | **✅** |
| **Fallback automático** | ❌ | ❌ | ❌ | **✅** |
| **Debug (breakpoints)** | ❌ | ✅ (DAP) | ❌ | **✅** |
| **Screenshots** | ❌ | ✅ | ❌ | **✅** |
| **Validación** | ❌ | ❌ | ❌ | **✅** |
| **I18n** | ❌ | ❌ | ❌ | **✅** |
| **Setup time** | npm install | 60s+ plugin | npm install | **🚀 0s** |
| **Memoria persistente** | 0MB | ~450MB | 0MB | **💾 ~75MB** |

### Comparativa de funcionalidades

| Funcionalidad | Coding-Solo | GoPeak | tugcantopaloglu | **Heren** |
|---|---|---|---|---|
| **Parser nativo TSCN** | ❌ | ❌ | ❌ | ❌ (usa Godot CLI nativo) |
| **Daemon persistente** | ❌ | ✅ | ❌ | **✅** |
| **Sin plugin instalado** | ✅ | ❌ | ❌ | **✅** |
| **Batch operations** | ❌ | ✅ | ❌ | **✅** |
| **Fallback automático** | ❌ | ❌ | ❌ | **✅** |
| **Conexión de señales** | ❌ | ✅ | ✅ | **✅** |
| **Gestión de autoloads** | ❌ | ✅ | ✅ | **✅** |
| **Debug breakpoints** | ❌ | ✅ | ❌ | **✅** |
| **Screenshots GPU** | ❌ | ✅ | ❌ | **✅** |
| **Validación escenas** | ❌ | ❌ | ❌ | **✅** |
| **Shaders y materiales** | ❌ | ✅ | ✅ | **✅** |
| **TileMap/Terrain** | ❌ | ✅ | ✅ | **✅** |
| **Skeleton/Rigging** | ❌ | ❌ | ❌ | **✅** |
| **LSP (autocompletado)** | ❌ | ✅ | ❌ | ❌ |
| **DAP (debugger avanzado)** | ❌ | ✅ | ❌ | ❌ |
| **Runtime inspection** | ❌ | ✅ | ❌ | ❌ |
| **Input injection** | ❌ | ✅ | ❌ | ❌ |
| **Asset library** | ❌ | ✅ | ❌ | ❌ |
| **Docs en español** | ❌ | ❌ | ❌ | **✅** |
| **Instalación** | `npx` (npm) | `npx` (npm) | npm | **`pip` (Python)** |

**Lo que tenemos y ellos no:** Daemon persistente con 0s setup, batch operations, fallback automático, validación integrada, debug breakpoints, screenshots GPU, docs en español, sin necesidad de plugin ni Node.js.

**Lo que ellos tienen y nosotros no:** LSP (autocompletado GDScript), DAP (debugger con breakpoints avanzado), runtime inspection, input injection, asset library.

---

## 🌍 Hecho para la comunidad hispanohablante y lusófona

La comunidad de Godot en español y portugués es enorme, pero las herramientas de IA para desarrollo de juegos están diseñadas exclusivamente en inglés. Heren Godot MCP nace de esa realidad:

- 🇪🇸 **España**
- 🇲🇽 **México**
- 🇦🇷 **Argentina**
- 🇨🇴 **Colombia**
- 🇧🇷 **Brasil**
- 🇵🇹 **Portugal**
- Y toda **Iberoamérica**

> **Sin barrera idiomática**: porque hacer juegos no debería requerir hablar inglés.

La documentación está en **español** e **inglés**. Los nombres de funciones y variables mantienen consistencia con Godot (inglés), pero toda la documentación, guías y comunicación están en nuestras lenguas.

---

## 📦 Instalación

### Desde fuente

```bash
git clone https://github.com/tu-usuario/heren-mcp.git
cd heren-mcp
pip install -e .
```

### Instalador automático

```bash
python install.py
```

### Requisitos

- 🐍 **Python** >= 3.10
- 🎮 **Godot** >= 4.2 (recomendado 4.6+)
- 💻 **Sistema operativo**: Windows, Linux, macOS

---

## ⚙️ Configuración MCP

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

## 🚀 Uso Rápido

```python
# Iniciar sesión
session_tool(action="open", project_path="D:/MiJuego")
# → {"success": true, "session_id": "abc123", "daemon_active": true}

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

### 🔄 Batch Operations

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

## 🗡️ Herramientas Disponibles

| Tool | Acciones | Descripción |
|------|----------|-------------|
| 🎮 **session** | open, close, list, info, health | Gestión de sesiones con Godot |
| 🎬 **scene** | load, save, get_tree, screenshot | Operaciones de escenas |
| 🔧 **node** | add, remove, set_prop, get_prop, duplicate, rename, move | Manipulación de nodos |
| ⚡ **signal** | connect, disconnect, list, set_script | Conexión de señales y scripts |
| 🎭 **animation** | create_player, create, add_track, add_key, state_machine | Sistema de animaciones |
| 🎨 **shader** | create, edit, validate, material, uniform | Shaders y materiales |
| 🦴 **skeleton** | create, add_bone, set_rest, skin, attachment | Rigging 2D/3D |
| 🗺️ **tilemap** | inspect_set, inspect_map, set_cell, terrain, pattern | TileMaps y TileSets |
| 📦 **resource** | create, read, update, delete, list | Gestión de recursos .tres |
| ⚙️ **project** | setting, autoload, remove_autoload, shader_global | Configuración del proyecto |
| 🔄 **batch** | - | Operaciones batch de alto rendimiento |
| 🐛 **debug** | breakpoint, stack_trace, watch, console | Herramientas de debugging |
| ✅ **validate** | scene, script, node, resource | Validación de archivos |
| 📚 **index** | list, info, example | Descubrimiento de tools |

---

## 🏰 Arquitectura

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────────────┐
│  Agente IA  │──────▶│  Heren MCP Server │─────▶│  Godot Daemon (WS)  │
└─────────────┘      └──────────────────┘      └─────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ Session Manager  │
                    │ + Cache (LRU)    │
                    └──────────────────┘
```

### Flujo de operación

1. **Agente** envía petición al servidor MCP
2. **Heren MCP** verifica si hay sesión activa
3. Si hay **daemon activo** → WebSocket (~20ms)
4. Si no hay daemon → **Fallback** a scripts (~370ms)
5. **Godot** ejecuta la operación y responde
6. **Cache** almacena resultados frecuentes

---

## 📚 Documentación

- 📖 [AGENTS.md](AGENTS.md) — Guía completa para agentes de IA
- 📥 [docs/INSTALL.md](docs/INSTALL.md) — Instalación detallada
- 📋 [docs/API.md](docs/API.md) — Referencia completa de la API
- 🏗️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Arquitectura técnica
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) — Cómo contribuir
- 📝 [CHANGELOG.md](CHANGELOG.md) — Historial de cambios

---

## 📊 Benchmarks

Ver [benchmarks/BENCHMARKS.md](benchmarks/BENCHMARKS.md) para comparativas reales con metodología y resultados detallados.

### Resumen de rendimiento

| Operación | Con Daemon | Sin Daemon |
|-----------|-----------|------------|
| ⚡ Añadir nodo | ~20ms | ~370ms |
| 💾 Guardar escena | ~15ms | ~340ms |
| 📖 Leer árbol | ~25ms | ~400ms |
| 📸 Screenshot | ~50ms | ~800ms |

---

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Lee [CONTRIBUTING.md](CONTRIBUTING.md) para:

- 🔄 Cómo clonar e instalar
- 🧪 Cómo correr tests
- 🐛 Cómo reportar bugs
- 🎨 Estilo de código
- 💡 Cómo proponer features

---

## 📜 Licencia

[MIT](LICENSE) © 2026 Heren MCP Contributors

---

<div align="center">

**Hecho con ❤️ para la comunidad iberoamericana de Godot**

⭐ [Star en GitHub](https://github.com/tu-usuario/heren-mcp) · 🐛 [Reportar bug](https://github.com/tu-usuario/heren-mcp/issues) · 💡 [Proponer feature](https://github.com/tu-usuario/heren-mcp/issues)

🏰 **Plus Ultra: ir más allá.** 🐉

</div>
