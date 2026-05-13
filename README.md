# 🐉 Heren Godot MCP

> **El servidor MCP definitivo para Godot Engine 4.x**

[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![Godot 4.x](https://img.shields.io/badge/godot-4.x-%23478cbf.svg)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 ¿Qué es Heren MCP?

Heren MCP es un servidor [Model Context Protocol](https://modelcontextprotocol.io/) que permite a agentes de IA interactuar con proyectos Godot de forma nativa, potente y rápida.

**Filosofía: Poder. Eficiencia. Rapidez.**

### La Diferencia

| Característica | Otros MCPs | Heren MCP |
|----------------|------------|-----------|
| Parser TSCN | Manual, buggy | **Godot nativo (100% preciso)** |
| Tipos Godot | Parcial | **Todos los tipos nativos** |
| Velocidad | ~2-5s por operación | **~50-100ms (Godot persistente)** |
| Validación | Ninguna | **Godot valida antes de guardar** |
| Offline | Sí | Requiere Godot instalado |

## 🚀 Instalación

```bash
# Clonar repositorio
git clone https://github.com/tu-usuario/heren-mcp.git
cd heren-mcp

# Instalar dependencias
pip install -r requirements.txt

# Configurar con tu IDE
# Añadir a tu configuración MCP:
{
  "mcpServers": {
    "heren": {
      "command": "python",
      "args": ["-m", "heren.server", "--project-path", "D:/TuProyectoGodot"]
    }
  }
}
```

## 💻 Uso

### Iniciar sesión
```python
# El agente inicia automáticamente
heren_start_session(project_path="D:/MiProyecto")
```

### Operaciones comunes
```python
# Leer escena
scene = heren_get_scene_tree("res://Player.tscn")

# Añadir nodo
heren_add_node(
    scene_path="res://Player.tscn",
    parent_path=".",
    node_type="Sprite2D",
    node_name="Sprite",
    properties={"position": Vector2(100, 200)}
)

# Guardar cambios
heren_save_scene("res://Player.tscn")
```

### Cerrar sesión
```python
heren_end_session(save=True)
```

## 📚 Documentación

- [AGENTS.md](AGENTS.md) - Guía para agentes desarrolladores
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Arquitectura técnica
- [docs/API.md](docs/API.md) - Referencia completa de la API

## 🏗️ Arquitectura

```
Agente → Heren MCP Server → Godot Engine (headless)
              ↓
         Session Manager (caché + estado)
```

1. **Session Manager** - Mantiene Godot corriendo y gestiona caché
2. **Godot CLI Interface** - Comunicación persistente con Godot
3. **API Tools** - Operaciones de alto nivel (escenas, nodos, recursos)

## ⚡ Rendimiento

- **Primera carga:** ~2s (arrancar Godot)
- **Operaciones subsiguientes:** ~50-100ms
- **Cache hit:** ~1ms
- **Batch de 10 operaciones:** ~100-150ms

## 🤝 Contribuir

1. Fork el repositorio
2. Crea una rama (`git checkout -b feature/nueva-feature`)
3. Commit tus cambios (`git commit -am 'Añadir feature'`)
4. Push a la rama (`git push origin feature/nueva-feature`)
5. Abre un Pull Request

## 📜 Licencia

MIT License - ver [LICENSE](LICENSE) para detalles.

---

**Herensuge vigila tu código.** 🐉
