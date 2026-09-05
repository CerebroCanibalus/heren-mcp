# LSP Bridge para OpenCode — Setup Guide

> **Estado**: v1 (2026-09-03) — incluido en `heren-server v4.10+`.
>
> El **LSP bridge** es un sub-comando del binario `heren-server` que conecta
> OpenCode (que habla LSP por **stdio**) con el **LSP nativo de Godot**
> (que habla LSP por **TCP** en `127.0.0.1:6005`). Permite autocompletado,
> chequeo de errores, goto-definition y hover **mientras el agente escribe
> código GDScript** en OpenCode.

---

## TL;DR — 3 pasos

1. Habilita el LSP nativo en tu proyecto Godot (una sola vez por proyecto).
2. Configura OpenCode para usar el bridge (una vez globalmente).
3. Abre el editor de Godot y arranca OpenCode → LSP funciona solo.

---

## 1. Habilitar LSP nativo en el proyecto Godot

Edita `project.godot` y añade (o modifica) la sección `[network]`:

```ini
[network]

language_server/enabled=true
language_server/port=6005
```

> **¿Por qué?** El LSP nativo de Godot está **dentro del editor** (no es un
> binario standalone). El bridge habla con él por TCP en el puerto 6005.
> Ver [godot-proposals#7558](https://github.com/godotengine/godot-proposals/issues/7558).

Reinicia Godot después de tocar `project.godot` (Godot recarga, pero el
LSP necesita un restart limpio).

### Verificación rápida

Abre Godot con el proyecto, luego:

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 6005
```

O en bash:
```bash
nc -zv 127.0.0.1 6005
```

Si responde `TcpTestSucceeded` / `succeeded`, el LSP está vivo.

---

## 2. Configurar OpenCode

Edita (o crea) `~/.config/opencode/opencode.jsonc` (Windows:
`C:\Users\<USER>\.config\opencode\opencode.jsonc`) y añade la sección `lsp`:

```jsonc
{
  // ... tu config existente ...

  "lsp": {
    "gdscript": {
      "command": [
        "D:/path/to/heren-server.exe",
        "lsp-bridge",
        "--project-path", "D:/path/to/tu/proyecto/godot"
      ],
      "extensions": [".gd", ".gdshader"],
      "env": {
        "HEREN_LSP_LOG_FILE": "D:/logs/heren-lsp.log"
      }
    }
  }
}
```

> **Ajusta** las rutas absolutas a tu `heren-server.exe` y a tu proyecto Godot.

### ¿Qué hace cada flag?

| Flag | Default | Qué hace |
|------|---------|----------|
| `--lsp-host <HOST>` | `127.0.0.1` | Host del LSP nativo. |
| `--lsp-port <PORT>` | `0` (auto) | Puerto del LSP. `0` = **auto-detect** (escanea el rango y conecta al primero que responda). Pasa un número explícito para forzar uno fijo. |
| `--lsp-port-range <RANGE>` | `6005-6010` | Rango a escanear cuando `--lsp-port=0`. Formato `START-END` inclusivo. |
| `--auto-launch-godot` | `true` | Si nadie escucha, auto-lanza Godot headless (`--editor --headless --audio-driver Dummy`). |
| `--no-auto-launch-godot` | (off) | Desactiva el auto-launch. Si nadie escucha y está puesto, el bridge falla con error claro. Útil en CI/scripts donde quieres controlar el lifecycle de Godot externamente. |
| `--project-path <DIR>` | `HEREN_LSP_PROJECT` | Path al proyecto Godot (obligatorio para auto-launch). |
| `--godot-path <EXE>` | `GODOT_PATH` | Path a `godot.exe`. Si se omite, busca en `PATH` + `C:/Program Files/Godot/`. |
| `--launch-timeout-ms <MS>` | `20000` | Cuánto esperar a que el LSP esté listo tras auto-launch. |
| `--reconnect-max-ms <MS>` | `60000` | Ventana de reconexión cuando el LSP se cae a mitad de sesión. |
| `-v, --verbose` | `false` | Logs minimalistas: preview de 80 chars por mensaje LSP. |

### Auto-detect del puerto (cómo funciona)

El bridge **no hardcodea** el puerto 6005. Por defecto `--lsp-port=0` significa
"auto-detect": el bridge escanea el rango `--lsp-port-range` (default `6005-6010`)
y conecta al primer puerto que tenga algo escuchando.

**Ventajas**:
- Si tienes varios Godots abiertos en distintos puertos (por ejemplo 6005, 6006,
  6007), el bridge encuentra el primero que esté en el rango.
- Si cambias el puerto en `project.godot` (digamos `language_server/port=6008`),
  solo amplía el rango: `--lsp-port-range 6005-6015`.

**Limitación**: el scan es **puramente TCP** — no valida que el puerto tenga
un LSP válido (eso requeriría enviar `initialize` con timeout). Si tienes otra
app escuchando en uno de los puertos del rango, el bridge conectará a esa app
y el proxy fallará al recibir el primer mensaje (error JSON-RPC inválido).
Workaround: pasa `--lsp-port <N>` explícito.

### Variables de entorno equivalentes

Cualquier flag tiene su env var equivalente:
- `HEREN_LSP_HOST`, `HEREN_LSP_PORT`, `HEREN_LSP_PROJECT`
- `GODOT_PATH`
- `HEREN_LSP_LOG_FILE`, `HEREN_LOG_LEVEL` (para el archivo de log)
- `RUST_LOG` (también soportado, formato `tracing`)

---

## 3. Modos de operación

### Modo A — Editor ya abierto (más común)

Si tu flujo normal es tener el editor de Godot abierto mientras OpenCode
trabaja, el bridge **solo se conecta** al LSP del editor (no auto-lanza nada).

```jsonc
"command": ["D:/path/to/heren-server.exe", "lsp-bridge"]
```

### Modo B — Auto-launch headless (consume apenas recursos)

Si OpenCode se invoca sin que el editor esté abierto (CI, scripts, agentes
aislados), el bridge auto-lanza un Godot en modo **headless liviano**:

```bash
godot --editor --headless --audio-driver Dummy --lsp-port 6005 --path <project>
```

| Flag | Por qué |
|------|---------|
| `--editor` | El LSP nativo de Godot **solo** corre dentro del editor. |
| `--headless` | No display, no renderer GPU. |
| `--audio-driver Dummy` | Sin audio (ahorra memoria). |
| `--lsp-port 6005` | Puerto LSP (debe coincidir con `project.godot`). |

**Recursos consumidos**: ~150-250 MB RAM (vs ~500-800 MB con ventana del editor).

### Modo C — Forzar conexión (sin auto-launch)

Si quieres que el bridge NUNCA auto-lance Godot (porque tú controlas el
lifecycle externamente):

```jsonc
"command": ["D:/path/to/heren-server.exe", "lsp-bridge", "--no-auto-launch-godot"]
```

---

## 4. Troubleshooting

### "LSP not enabled in project.godot"

Edita `project.godot` y añade a la sección `[network]`:

```ini
[network]
language_server/enabled=true
language_server/port=6005
```

### "LSP not reachable at 127.0.0.1:6005 and --no-auto-launch-godot"

Estás en modo `--no-auto-launch-godot` pero nadie escucha. Soluciones:
- Quita `--no-auto-launch-godot` y deja que el bridge auto-lance.
- O abre el editor de Godot manualmente primero.

### "project.godot not found at ..."

`--project-path` apunta a un directorio que no contiene `project.godot`.
Verifica la ruta absoluta.

### "Could not find Godot executable"

Instala Godot en `C:/Program Files/Godot/godot.exe`, en el PATH, o pasa
`--godot-path` explícito.

### "LSP did not become ready within 20000ms"

El bridge no pudo conectar al puerto LSP en 20s. Posibles causas:
- Godot está arrancando todavía (sube `--launch-timeout-ms` a 60000).
- El firewall bloquea el puerto 6005.
- El editor no tiene `language_server/enabled=true`.

### LSP funciona pero autocomplete es lento

Activa verbose para ver el tráfico: `-v`. Si ves miles de
`textDocument/didChange` por segundo, es porque OpenCode reindexa el buffer
frecuentemente. Esto es normal en sesiones largas; no es un bug del bridge.

---

## 5. Comparativa con alternativas

| Solución | Lenguaje | Pros | Contras |
|----------|----------|------|---------|
| **heren-server lsp-bridge** (esta) | Rust puro (0 deps Node) | Reusa editor existente, auto-launch liviano, reconnect, verbose, integrado en nuestro binario | Auto-launch solo si no hay editor abierto |
| [MasuRii/opencode-godot-lsp](https://github.com/MasuRii/opencode-godot-lsp) | Node.js (Bridge script) | 42⭐, probado | Dep externa Node.js, levanta 2do Godot paralelo |
| [gopeak](https://github.com/godot-mcp/gopeak) (competidor MCP) | TypeScript | 4 tools MCP integradas (`lsp_get_*`) | Requiere editor abierto, NO es LSP real para OpenCode (es proxy vía tools) |

Nuestra elección: **bridge stdio↔TCP en Rust** (esta). Justificación en
AGENTS.md §0.9 (histórico).

---

## 6. Tests

```bash
cargo test -p heren-server --lib lsp_bridge  # 23 tests unitarios
cargo test -p heren-server --test lsp_bridge  # 2 tests integración (proxy + fake server)
```

El test de integración levanta un fake LSP server TCP en `127.0.0.1:0`
(puerto aleatorio), conecta el bridge, escribe un frame al stdin in-memory,
y verifica que llega al fake server con el framing correcto.

---

## 7. Logs

```jsonc
"env": { "HEREN_LSP_LOG_FILE": "D:/logs/heren-lsp.log" }
```

Si no defines `HEREN_LSP_LOG_FILE`, el bridge es **silencioso** (mismo patrón
que el MCP server — OpenCode no drena stderr, el log debe ir a archivo).

Para modo verbose (`-v`), el preview de 80 chars por mensaje va a stderr
(NO al log file), solo si el usuario tiene un terminal que drene stderr.

---

**Recuerda**: Poder. Eficiencia. Rapidez. Sostenibilidad. Visibilidad. Control.

*Herensuge vigila tu código.*
