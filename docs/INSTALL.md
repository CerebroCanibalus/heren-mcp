# 📦 Instalación — Heren Godot MCP v4.2

> **Nota**: desde la v4.2, Heren MCP es un **server en Rust** (`heren-server.exe`)
> construido sobre FlojoMCP. Ya NO requiere Python ni Node.js. Solo necesitas
> Rust para compilar (o un `.exe` precompilado) y Godot instalado.

---

## Requisitos

| Requisito | Mínimo | Recomendado |
|-----------|--------|-------------|
| 🦀 **Rust** (solo para compilar) | 1.75+ | stable actual |
| ⚙️ **Godot** | 4.2 | 4.6+ / 4.7 |
| 💻 **OS** | — | Windows, Linux, macOS |

---

## Paso 1 — Compilar el server Rust

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp

# Compilar en release
cargo build --release
# → target/release/heren-server.exe   (~7 MB)
```

> 💡 En Windows, `scripts/run.bat` ya compila y lanza el server. También hay un
> `scripts/heren-build.bat` que carga VsDevCmd del Build Tools 2022 antes de compilar.

---

## Paso 1b — Instalador automático (recomendado)

En vez de compilar y configurar a mano, ejecuta el instalador de **1 comando**:

```bash
python install_mcp.py
```

Esto hace todo por ti:
1. **Compila** `heren-server.exe` (release) desde el workspace FlojoMCP.
2. **Registra** el MCP `heren` en `opencode.jsonc` (detecta la ruta, GODOT_EXE y log).
3. **Verifica** que el server responde al handshake MCP.

Opciones útiles:

```bash
python install_mcp.py --no-build            # ya compilado, solo registrar
python install_mcp.py --config <archivo>    # registrar en otro cliente MCP
python install_mcp.py --godot-exe <ruta>    # forzar ruta de Godot
```

---

## Paso 2 — Configurar el MCP en tu cliente

Añade el server a tu configuración de MCP (OpenCode, Claude Desktop, Cursor, etc.):

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

> ⚠️ En OpenCode la clave es `"environment"` (no `"env"`), y `"timeout"` en ms
> para el handshake (default 5000).

---

## Paso 3 — Abrir una sesión

Desde el cliente MCP, llama a `session` con action `open`:

```python
session(action="open", project_path="D:/MiJuego")
```

Esto hará todo automáticamente:
1. Encuentra el ejecutable Godot (env `GODOT_EXE` o PATH).
2. **Instala el plugin v4** (`addons/heren/`) en el proyecto si falta.
3. **Habilita `[editor_plugins]`** en `project.godot` con el formato Godot 4.
4. **Lanza `godot --editor --path <proyecto>`**.
5. El plugin conecta al server por WebSocket y se registra.

Si el editor ya está abierto, se reutiliza (o se relanza limpio si quedó zombie).

---

## Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `GODOT_EXE` | Ruta al ejecutable de Godot |
| `GODOT_PATH` | Alias de `GODOT_EXE` |
| `HEREN_PLUGIN_SOURCE` | Ruta al plugin fuente (default `addons/heren/`) |
| `HEREN_LOG_FILE` | Archivo de log (opcional) |
| `HEREN_MCP_PORT` | Puerto del WS plugin server (default 9099) |

---

## Solución de problemas

- **`health` devuelve `connected_projects: []`** → el editor no conectó. Revisa
  que el plugin esté habilitado en `project.godot` (`[editor_plugins]`) y que el
  editor esté abierto. `session/open` debería lanzarlo.
- **"no editor connected"** → llama `session/open` primero con el proyecto.
- **Editor zombie que no conecta** → cierra el Godot viejo manualmente y vuelve
  a `session/open` (o relanza limpio automáticamente).
- **El MCP no refresca las tools** → en OpenCode, el toolset MCP se carga al
  inicio de la sesión. Tras recompilar el server, abre una **conversación nueva**.

Ver [TROUBLESHOOTING.md](TROUBLESHOOTING.md) para más detalle.
