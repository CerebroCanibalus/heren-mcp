# Contributing to Heren MCP

¡Gracias por tu interés en contribuir a Heren MCP! / Thank you for your interest in contributing to Heren MCP!

## 🌍 Languages / Idiomas

- **Español**: La documentación principal está en español para servir a la comunidad iberoamericana.
- **English**: This guide is bilingual to welcome all contributors.

---

## 🚀 Cómo empezar / How to Get Started

### 1. Clonar el repositorio / Clone the repository

```bash
git clone https://github.com/tu-usuario/heren-mcp.git
cd heren-mcp
```

### 2. Crear entorno virtual / Create virtual environment

```bash
# Windows (PowerShell)
python -m venv venv
.\venv\Scripts\Activate.ps1

# Linux/macOS
python -m venv venv
source venv/bin/activate
```

### 3. Instalar dependencias / Install dependencies

```bash
pip install -e ".[dev]"
```

Esto instalará:
- Todas las dependencias de producción
- Dependencias de desarrollo (pytest, black, flake8, mypy)
- El paquete en modo editable

---

## 🧪 Cómo correr tests / How to Run Tests

### Tests completos / Full test suite

```bash
pytest tests/ -v
```

### Tests con cobertura / Tests with coverage

```bash
pytest tests/ --cov=heren --cov-report=html
```

### Tests específicos / Specific tests

```bash
pytest tests/test_session.py -v
pytest tests/test_scene.py::test_create_scene -v
```

### Benchmarks

```bash
python benchmarks/run_benchmarks.py
```

---

## 🐛 Cómo reportar bugs / How to Report Bugs

### Antes de reportar / Before reporting

1. Busca en [Issues](https://github.com/tu-usuario/heren-mcp/issues) si ya existe
2. Intenta reproducir con la última versión
3. Prueba con el daemon desactivado para aislar el problema

### Plantilla de bug / Bug template

```markdown
**Descripción:** Breve descripción del problema

**Pasos para reproducir:**
1. Paso 1
2. Paso 2
3. Paso 3

**Comportamiento esperado:** Qué debería pasar

**Comportamiento actual:** Qué pasa realmente

**Entorno:**
- OS: Windows 11 / Ubuntu 22.04 / macOS 14
- Python: 3.11.4
- Godot: 4.6.1-stable
- Versión Heren MCP: 1.0.0

**Logs:**
```
Pega aquí los logs relevantes
```

**Configuración MCP:**
```json
Tu configuración de mcpServers
```
```

---

## 💡 Cómo proponer features / How to Propose Features

1. Abre un [Issue](https://github.com/tu-usuario/heren-mcp/issues/new) con el tag `enhancement`
2. Describe el problema que resuelve
3. Explica el uso esperado
4. Si es posible, incluye ejemplos de código

### Características deseables / Desired features

- Soporte para Godot 3.x (backport)
- Más herramientas de debugging (profiling, memory analysis)
- Integración con CI/CD
- GUI para configuración

---

## 📝 Estilo de código / Code Style

### Python (PEP 8 + Black)

```bash
# Formatear código
black heren/ tests/

# Verificar estilo
flake8 heren/ tests/

# Type checking
mypy heren/
```

### Reglas específicas / Specific rules

- **Máximo 120 caracteres** por línea
- **Docstrings** en Google style para todas las funciones públicas
- **Type hints** obligatorios para parámetros y retornos
- **Comentarios** en español para lógica compleja
- **Nombres de variables** en inglés (consistencia con Godot)

### Ejemplo / Example

```python
def create_scene(
    session_id: str,
    scene_path: str,
    root_type: str = "Node2D",
    root_name: str = "Root"
) -> dict:
    """Crea una nueva escena en el proyecto.

    Args:
        session_id: ID de sesión activa.
        scene_path: Ruta de la escena (e.g., "res://Player.tscn").
        root_type: Tipo del nodo raíz.
        root_name: Nombre del nodo raíz.

    Returns:
        Dict con success y scene_path.
    """
    # Validación de parámetros
    if not scene_path.endswith(".tscn"):
        raise ValueError("La escena debe tener extensión .tscn")
    
    # ... implementación
```

### Commits

Usa [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: añadir soporte para TileMap terrain painting
fix: corregir fallback cuando daemon no responde
docs: actualizar README con ejemplos de batch
test: añadir benchmarks para scene_tool
refactor: simplificar manejo de errores en WebSocket
```

---

## 🔧 Estructura del proyecto / Project Structure

```
heren-mcp/
├── heren/              # Código fuente principal
│   ├── __init__.py
│   ├── server.py       # Servidor MCP
│   ├── session.py      # Gestión de sesiones
│   ├── tools/          # Implementación de tools
│   ├── daemon/         # Código del daemon GDScript
│   └── cache.py        # Sistema de cache
├── tests/              # Tests
│   ├── test_session.py
│   ├── test_scene.py
│   └── conftest.py
├── docs/               # Documentación
├── benchmarks/         # Benchmarks
├── scripts/            # Scripts útiles
├── pyproject.toml      # Configuración del proyecto
├── LICENSE
├── CHANGELOG.md
└── README.md
```

---

## 🏆 Cómo contribuir código / How to Contribute Code

1. **Fork** el repositorio
2. **Crea una rama** para tu feature: `git checkout -b feat/mi-feature`
3. **Haz commits** siguiendo Conventional Commits
4. **Añade tests** para tu código
5. **Asegúrate** de que todos los tests pasan: `pytest`
6. **Actualiza** la documentación si es necesario
7. **Abre un Pull Request** con descripción clara

### Checklist del PR / PR Checklist

- [ ] Código pasa `black`, `flake8`, y `mypy`
- [ ] Tests añadidos y pasando
- [ ] Documentación actualizada
- [ ] CHANGELOG.md actualizado
- [ ] No hay breaking changes sin justificación

---

## 🌐 Comunidad / Community

- **Issues**: [github.com/tu-usuario/heren-mcp/issues](https://github.com/tu-usuario/heren-mcp/issues)
- **Discussions**: Usa GitHub Discussions para preguntas generales
- **Discord**: [link-to-discord] (próximamente)

---

## 📜 Código de conducta / Code of Conduct

Este proyecto sigue el [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

- Sé respetuoso/a con todos los contribuidores
- Acepta críticas constructivas
- Enfócate en lo que es mejor para la comunidad
- Muestra empatía hacia otros miembros

---

¡Gracias por contribuir! / Thank you for contributing! 🎉
