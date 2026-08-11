# Guia de Instalacion - Heren MCP

> ⚠️ **ESTA GUÍA ESTÁ DESACTUALIZADA** tras la limpieza v4.4.3. El paquete Python
> fue archivado en la rama `archive/v3`. La instalación activa usa el server Rust
> y `scripts/install_mcp.py`. Ver `docs/INSTALL.md` para instrucciones actualizadas.

Heren MCP es un servidor Model Context Protocol (MCP) para Godot Engine 4.x. Permite que asistentes de IA interactuen con proyectos Godot a traves de un sistema de tools centralizado.

## Requisitos

- **Rust**: toolchain estable (solo para compilar; o usa un `.exe` precompilado)
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
python scripts/install_mcp.py
```

O con un proyecto especifico:

```bash
python scripts/install_mcp.py --project-path D:/TuJuego
```

El instalador hace:
1. **Compila** `heren-server.exe` (release) con Cargo.
2. **Registra** el MCP `heren` en `opencode.jsonc` (u otro cliente).
3. **Verifica** que el server responde al handshake MCP.

Opciones utiles:

```bash
python scripts/install_mcp.py --no-build          # ya compilado, solo registrar
python scripts/install_mcp.py --config <archivo> # registrar en otro cliente MCP
python scripts/install_mcp.py --godot-exe <ruta> # forzar ruta de Godot
```

### 3. Configurar tu Cliente MCP

Añade lo siguiente a la configuracion de tu cliente MCP (ej: `opencode.jsonc`):

```json
{
  "mcpServers": {
    "heren": {
      "command": "D:/ruta/a/heren-server.exe",
      "environment": {
        "GODOT_EXE": "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe"
      }
    }
  }
}
```

> ⚠️ En OpenCode la clave es `"environment"` (no `"env"`), y existe `"timeout"` en ms
> para el handshake (default 5000).

### 4. Abrir una Sesion

Desde el cliente MCP, llama a `session` con action `open`:

```python
session(action="open", project_path="D:/TuJuego")
```

Esto hace todo automaticamente:
1. Encuentra el ejecutable Godot (env `GODOT_EXE` o PATH).
2. Instala el plugin v4 (`addons/heren/`) en el proyecto si falta.
3. Habilita `[editor_plugins]` en `project.godot` con el formato Godot 4.
4. Lanza `godot --editor --path <proyecto>`.
5. El plugin conecta al server por WebSocket y se registra.

## Variables de Entorno

| Variable | Descripcion |
|----------|-------------|
| `GODOT_EXE` | Ruta al ejecutable de Godot |
| `GODOT_PATH` | Alias de `GODOT_EXE` |
| `HEREN_PLUGIN_SOURCE` | Ruta al plugin fuente (default `addons/heren/`) |
| `HEREN_LOG_FILE` | Archivo de log (opcional) |
| `HEREN_MCP_PORT` | Puerto del WS plugin server (default 9099) |

## Solucion de Problemas

- **`health` devuelve `connected_projects: []`** → el editor no conecto. Revisa
  que el plugin este habilitado en `project.godot` (`[editor_plugins]`) y que el
  editor este abierto. `session/open` deberia lanzarlo.
- **"no editor connected"** → llama `session/open` primero con el proyecto.
- **Editor zombie que no conecta** → cierra el Godot viejo manualmente y vuelve
  a `session/open` (o relanza limpio automaticamente).
- **El MCP no refresca las tools** → en OpenCode, el toolset MCP se carga al
  inicio de la sesion. Tras recompilar el server, abre una **conversacion nueva**.

Consulta [TROUBLESHOOTING.md](TROUBLESHOOTING.md) para problemas comunes.

## Siguientes Pasos

- Lee la [Referencia API](API.es.md)
- Aprende sobre la [Arquitectura](ARCHITECTURE.md)
- Explora la [documentacion en ingles](INSTALL.md)

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
