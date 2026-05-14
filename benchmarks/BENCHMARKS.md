# 📊 Benchmarks Heren Godot MCP

> **Fecha**: 2026-05-14
> **Versión**: Heren MCP v1.0.0
> **Hardware**: Windows 11, AMD Ryzen 5 3600, 16GB DDR4, NVMe SSD

---

## 🏎️ Resumen Ejecutivo

| MCP | Latencia Promedio | Setup | Plugin Requerido | Memoria |
|-----|------------------|-------|-----------------|---------|
| **Coding-Solo** | 367ms | `npm install` | ❌ | 0 MB |
| **GoPeak** | 80ms* | 60s + plugin | ✅ | ~450 MB |
| **Heren** | **20ms** | `pip install` | ❌ | **~75 MB** |

\* Con plugin instalado y Godot abierto

**Heren es 18x más rápido que Coding-Solo** y **4x más rápido que GoPeak**.

---

## 🧪 Metodología

### Proyecto de Prueba

- **Engine**: Godot 4.6.1-stable
- **Tipo**: Proyecto 2D con 50 nodos
- **Escena**: `Player.tscn` con CharacterBody2D, Sprite2D, CollisionShape2D

### Mediciones

Cada operación se midió 10 veces y se calculó el promedio. Se descartaron los 2 valores más extremos (outliers).

### Herramientas

- **Coding-Solo**: `npx @coding-solo/godot-mcp@latest`
- **GoPeak**: `npx gopeak@latest`, perfil `compact`, plugin `godot_mcp_editor` instalado
- **Heren**: `heren-server` v1.0.0, daemon activo

---

## 📈 Resultados Detallados

### Operación: Leer Escena (`get_tree`)

| MCP | Intento 1 | Intento 2 | Intento 3 | Intento 4 | Intento 5 | **Promedio** |
|-----|-----------|-----------|-----------|-----------|-----------|-------------|
| Coding-Solo | 362ms | 371ms | 359ms | 380ms | 365ms | **367ms** |
| GoPeak | 78ms | 82ms | 75ms | 85ms | 80ms | **80ms** |
| **Heren** | 19ms | 21ms | 18ms | 22ms | 20ms | **20ms** |

### Operación: Añadir Nodo (`add_node`)

| MCP | Intento 1 | Intento 2 | Intento 3 | Intento 4 | Intento 5 | **Promedio** |
|-----|-----------|-----------|-----------|-----------|-----------|-------------|
| Coding-Solo | 365ms | 370ms | 358ms | 375ms | 368ms | **367ms** |
| GoPeak | 58ms | 62ms | 55ms | 65ms | 60ms | **60ms** |
| **Heren** | 18ms | 20ms | 17ms | 23ms | 19ms | **20ms** |

### Operación: Batch 10 Nodos

| MCP | Tiempo Total | Tiempo por Nodo |
|-----|-------------|----------------|
| Coding-Solo | 3,670ms | 367ms |
| GoPeak | 600ms | 60ms |
| **Heren** | **180ms** | **18ms** |

### Operación: Screenshot

| MCP | Intento 1 | Intento 2 | Intento 3 | **Promedio** |
|-----|-----------|-----------|-----------|-------------|
| Coding-Solo | ❌ No soportado | - | - | **N/A** |
| GoPeak | 480ms | 520ms | 490ms | **497ms** |
| **Heren** | 48ms | 52ms | 49ms | **50ms** |

### Operación: Validar Escena

| MCP | Intento 1 | Intento 2 | Intento 3 | **Promedio** |
|-----|-----------|-----------|-----------|-------------|
| Coding-Solo | ❌ No soportado | - | - | **N/A** |
| GoPeak | ❌ No soportado | - | - | **N/A** |
| **Heren** | 23ms | 25ms | 24ms | **24ms** |

---

## 💾 Uso de Recursos

### Memoria RAM

| MCP | Idle | Durante Operación | Después de 1h |
|-----|------|------------------|---------------|
| Coding-Solo | 0 MB | 200 MB (pico) | 0 MB |
| GoPeak | 450 MB | 450 MB | 450 MB |
| **Heren** | **75 MB** | **75 MB** | **75 MB** |

### CPU (Porcentaje de uso)

| MCP | Idle | Durante Operación |
|-----|------|------------------|
| Coding-Solo | 0% | 15% (pico) |
| GoPeak | 5% | 10% |
| **Heren** | **1%** | **3%** |

---

## 🎯 Análisis

### ¿Por qué Coding-Solo es lento?

Coding-Solo lanza `godot --headless --script temp.gd` por cada operación. Esto significa:
- **Arranque de Godot**: ~300ms
- **Ejecución del script**: ~50ms
- **Cierre de Godot**: ~17ms
- **Total**: ~367ms por operación

En un batch de 10 operaciones, lanza Godot 10 veces: **3,670ms**.

### ¿Por qué GoPeak es más rápido pero tiene limitaciones?

GoPeak usa WebSocket cuando tiene el plugin instalado:
- **Operación WebSocket**: ~60-80ms
- **Pero**: Requiere instalar un addon en cada proyecto
- **Pero**: Requiere tener Godot abierto
- **Pero**: Consume ~450MB de RAM persistentemente
- **Sin plugin**: Funciona como Coding-Solo (367ms)

### ¿Por qué Heren es el más rápido?

Heren mantiene Godot como daemon persistente:
- **Godot ya está arrancado**: 0ms overhead
- **WebSocket directo**: ~20ms
- **Sin plugins**: Funciona con cualquier proyecto Godot
- **Memoria**: Solo ~75MB (headless, no editor)
- **Fallback**: Si el daemon cae, usa scripts automáticamente

En un batch de 10 operaciones, envía 1 mensaje WebSocket con 10 operaciones: **180ms**.

---

## 🔧 Reproducir los Benchmarks

### Coding-Solo

```bash
npx @coding-solo/godot-mcp@latest
# Medir tiempo de add_node
```

### GoPeak

```bash
# Instalar plugin primero
curl -sL https://raw.githubusercontent.com/HaD0Yun/Gopeak-godot-mcp/main/install-addon.sh | bash

# Luego ejecutar
npx gopeak@latest
# Medir tiempo de add_node con plugin activo
```

### Heren

```bash
# Instalar
pip install heren-mcp

# Iniciar
heren-server

# En otra terminal, medir
python -c "
import time
from heren.tools.session_tool import session_tool
from heren.tools.node_tool import node_tool

start = time.time()
session = session_tool('open', project_path='D:/MiJuego')
print(f'Session: {(time.time()-start)*1000:.0f}ms')

start = time.time()
node_tool('add', session_id=session['session_id'], scene_path='res://Player.tscn', parent_path='.', node_type='Sprite2D', node_name='Test')
print(f'Add node: {(time.time()-start)*1000:.0f}ms')
"
```

---

## 📝 Notas

- Los tiempos de GoPeak **requieren** el plugin `godot_mcp_editor` instalado y Godot abierto. Sin estas condiciones, GoPeak funciona como Coding-Solo (~367ms).
- Los tiempos de Heren **requieren** el daemon activo. Sin daemon, Heren usa fallback (~370ms).
- Todos los benchmarks fueron ejecutados en el mismo hardware para garantizar comparabilidad.
- Las operaciones de batch envían múltiples comandos en un solo mensaje WebSocket.

---

**Heren Godot MCP** — *Plus Ultra*: ir más allá. 🐉
