# Guia de Instalacion - Heren MCP

Heren MCP es un servidor Model Context Protocol (MCP) para Godot Engine 4.x. Permite que asistentes de IA interactuen con proyectos Godot a traves de un sistema de tools centralizado.

## Requisitos

- **Python**: 3.10 o superior
- **Godot Engine**: 4.2 o superior (4.6+ recomendado)
- **Sistema Operativo**: Windows, Linux o macOS

## Inicio Rapido

### 1. Clonar el Repositorio

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp
```

### 2. Ejecutar el Instalador

```bash
python install.py
```

O con un proyecto especifico:

```bash
python install.py --project-path D:/TuJuego
```

El instalador hara:
- Detectar tu sistema operativo
- Buscar tu instalacion de Godot
- Instalar dependencias de Python
- Copiar los archivos del daemon Heren a tu proyecto Godot (`addons/heren/daemon/`)
- Mostrar instrucciones de configuracion MCP

### 3. Configurar tu Cliente MCP

Anade lo siguiente a la configuracion de tu cliente MCP (ej: `opencode.jsonc`):

```json
{
  "mcpServers": {
    "heren-godot": {
      "command": "python",
      "args": ["-m", "heren.server"],
      "env": {
        "PYTHONPATH": "./src",
        "GODOT_EXE": "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe",
        "HEREN_PROJECT_PATH": "D:/TuJuego"
      }
    }
  }
}
```

### 4. Empezar a Usar Heren MCP

Abre un proyecto Godot e inicia una sesion:

```python
session(action="open", project_path="D:/TuJuego")
```

## Instalacion Manual

Si prefieres la instalacion manual o el instalador automatico falla:

### Paso 1: Instalar Dependencias Python

```bash
pip install -r requirements.txt
```

Paquetes requeridos:
- `fastmcp>=1.0.0` - Framework MCP
- `pydantic>=2.0.0` - Validacion de datos
- `websocket-client>=1.6.0` - Comunicacion WebSocket con Godot

### Paso 2: Configurar Godot Daemon en tu Proyecto

El Godot Daemon proporciona operaciones rapidas (~20ms). Para configurarlo, ejecuta desde el directorio de heren-mcp:

```bash
python -m heren.tools.project_tool setup_daemon --project-path D:/TuJuego
```

O programaticamente:

```python
from heren.tools.project_tool import project_tool
project_tool("setup_daemon", project_path="D:/TuJuego")
```

Esto copia todos los archivos del daemon (`heren_daemon.gd` + modulos) a `D:/TuJuego/addons/heren/daemon/`.

### Paso 3: Configurar Variables de Entorno (Opcional)

```bash
# Windows
set GODOT_EXE=D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe
set HEREN_PROJECT_PATH=D:\TuJuego

# Linux/macOS
export GODOT_EXE=/usr/bin/godot
export HEREN_PROJECT_PATH=/home/user/TuJuego
```

Variables soportadas:

| Variable | Descripcion | Ejemplo |
|----------|-------------|---------|
| `GODOT_EXE` | Ruta al ejecutable de Godot | `D:/Godot/Godot.exe` |
| `GODOT_PATH` | Alias de `GODOT_EXE` | `D:/Godot/Godot.exe` |
| `HEREN_PROJECT_PATH` | Ruta por defecto del proyecto Godot | `D:/TuJuego` |
| `HEREN_PORT` | Puerto WebSocket del daemon | `4567` |
| `HEREN_LOG_LEVEL` | Nivel de logging | `INFO`, `DEBUG` |

## Notas por Plataforma

### Windows

- Godot se instala comunmente en `D:\Mis Juegos\Godot\` o `C:\Program Files\Godot\`
- El instalador busca en estas rutas automaticamente
- Si no encuentra Godot, especifica la ruta con `--godot-path`

### Linux

- Instala Godot via gestor de paquetes o descarga de godotengine.org
- Rutas comunes: `/usr/bin/godot`, `/usr/local/bin/godot`
- El instalador verifica el `PATH` para el ejecutable `godot`

### macOS

- Godot tipicamente esta en `/Applications/Godot.app`
- El instalador verifica directorios comunes de aplicaciones
- Tambien puedes instalar via Homebrew: `brew install --cask godot`

## Verificacion

Prueba tu instalacion:

```bash
python -c "from heren.server import mcp; print('Heren MCP cargado exitosamente')"
```

Abre una sesion y lista las escenas cargadas:

```python
from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool

session = session_tool("open", project_path="D:/TuJuego")
print(session)
scene_tool("list_loaded", session_id=session["session_id"])
```

## Solucion de Problemas

Consulta [TROUBLESHOOTING.md](TROUBLESHOOTING.md) para problemas comunes.

## Siguientes Pasos

- Lee la [Referencia API](API.es.md)
- Aprende sobre la [Arquitectura](ARCHITECTURE.md)
- Explora la [documentacion en ingles](INSTALL.md)
