# Guía de Instalación - Heren MCP

Heren MCP es un servidor Model Context Protocol (MCP) para Godot Engine 4.x. Permite que asistentes de IA interactúen con proyectos Godot a través de un sistema de tools centralizado.

## Requisitos

- **Python**: 3.10 o superior
- **Godot Engine**: 4.0 o superior (4.2+ recomendado)
- **Sistema Operativo**: Windows, Linux o macOS

## Inicio Rápido

### 1. Clonar el Repositorio

```bash
git clone https://github.com/your-org/heren-mcp.git
cd heren-mcp
```

### 2. Ejecutar el Instalador

```bash
python install.py
```

El instalador hará:
- Detectar tu sistema operativo
- Buscar tu instalación de Godot
- Instalar dependencias de Python
- Configurar el Godot Daemon
- Mostrar instrucciones de configuración MCP

### 3. Configurar tu Cliente MCP

Añade lo siguiente a la configuración de tu cliente MCP (ej: `opencode.jsonc`):

```json
{
  "mcpServers": {
    "heren-godot": {
      "command": "python",
      "args": ["-m", "heren.server"],
      "env": {
        "PYTHONPATH": "./src"
      }
    }
  }
}
```

### 4. Empezar a Usar Heren MCP

Abre un proyecto Godot e inicia una sesión:

```python
session(action="open", project_path="D:/TuJuego")
```

## Instalación Manual

Si prefieres la instalación manual o el instalador automático falla:

### Paso 1: Instalar Dependencias Python

```bash
pip install -r requirements.txt
```

Paquetes requeridos:
- `fastmcp>=1.0.0` - Framework MCP
- `pydantic>=2.0.0` - Validación de datos
- `websocket-client>=1.6.0` - Comunicación WebSocket con Godot

### Paso 2: Configurar Godot Daemon (Opcional pero Recomendado)

El Godot Daemon proporciona operaciones rápidas (~20ms). Para configurarlo:

1. Copia `src/heren/daemon/heren_daemon.gd` a la carpeta `addons/heren_daemon/` de tu proyecto Godot
2. Habilita el addon en Configuración del Proyecto

### Paso 3: Configurar Variables de Entorno (Opcional)

```bash
# Windows
set GODOT_PATH=D:\Mis Juegos\Godot\Godot.exe
set GODOT_PROJECT_PATH=D:\TuJuego

# Linux/macOS
export GODOT_PATH=/usr/bin/godot
export GODOT_PROJECT_PATH=/home/user/TuJuego
```

## Notas por Plataforma

### Windows

- Godot se instala comúnmente en `D:\Mis Juegos\Godot\` o `C:\Program Files\Godot\`
- El instalador busca en estas rutas automáticamente
- Si no encuentra Godot, especifica la ruta con `--godot-path`

### Linux

- Instala Godot via gestor de paquetes o descarga de godotengine.org
- Rutas comunes: `/usr/bin/godot`, `/usr/local/bin/godot`
- El instalador verifica el `PATH` para el ejecutable `godot`

### macOS

- Godot típicamente está en `/Applications/Godot.app`
- El instalador verifica directorios comunes de aplicaciones
- También puedes instalar via Homebrew: `brew install --cask godot`

## Verificación

Prueba tu instalación:

```bash
python -c "from heren.server import mcp; print('Heren MCP cargado exitosamente')"
```

Lista las tools disponibles:

```python
index(action="list")
```

## Solución de Problemas

Consulta [TROUBLESHOOTING.md](TROUBLESHOOTING.md) para problemas comunes.

## Siguientes Pasos

- Lee la [Referencia API](API.es.md)
- Aprende sobre la [Arquitectura](ARCHITECTURE.md)
- Explora la [documentación en inglés](INSTALL.md)
