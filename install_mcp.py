#!/usr/bin/env python3
"""
Heren MCP v4.2 - Instalador automatico del server Rust.

Hace 3 cosas en 1 comando:
  1. Compila heren-server.exe (release) desde el workspace FlojoMCP.
  2. Registra/actualiza la entrada MCP "heren" en opencode.jsonc
     (o en el archivo de config que se indique con --config).
  3. Verifica que el binario arranca (health-check de stdio).

Uso:
  python install_mcp.py                       # todo automatico (defaults)
  python install_mcp.py --no-build            # solo registrar, sin compilar
  python install_mcp.py --config <archivo>    # registrar en otro cliente
  python install_mcp.py --godot-exe <ruta>    # forzar ruta de Godot
  python install_mcp.py --server <ruta.exe>   # forzar ruta del binario

Default:
  - workspace FlojoMCP      : (env HEREN_WS o default conocido)
  - server                  : <workspace>\target\release\heren-server.exe
  - config OpenCode         : %APPDATA%\opencode\opencode.jsonc  (o ~/.config/opencode)
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Forzar UTF-8 en stdout/stderr (Windows usa cp1252 por defecto; sin esto,
# caracteres del banner y del output rompen el print).
if sys.platform == "win32":
    import io
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")
    except Exception:
        pass

# ---------------------------------------------------------------------------
# Rutas por defecto
# ---------------------------------------------------------------------------

HEREN_MCP_DIR = os.path.dirname(os.path.abspath(__file__))

# Banner ASCII del dragon (Heren). Reutilizado del instalador v1.
BANNER = r"""

                    -,,,__
                     \    ``~~--,,__                /   /
                     /              ``~~--,,_     //--//
          _,,,,-----,\              ,,,,---- >   (c  c)\
      ,;''            `\,,,,----''''   ,,-'''---/   /_ ;___        -,_
     ( ''---,;====;,----/             (-,,_____/  /'/ `;   '''''----\ `:.
     (                 '               `      (oo)/   ;~~~~~~~~~~~~~/--~
      `;_           ;    \            ;   \   `  ' ,,'
         ```-----...|     )___________|    )-----'''
                     \   /             \   \\
	             /  /,             `\   \\
                   ,'---\ \              ,---`,;,,
                         ```
"""


def print_banner():
    """Muestra el banner ASCII del dragon (con fallback si no hay Unicode)."""
    try:
        print(BANNER)
    except UnicodeEncodeError:
        print("\n" + "=" * 70)
        print("  HEREN MCP v4.2")
        print("  Godot Engine Model Context Protocol Server (Rust/FlojoMCP)")
        print("=" * 70 + "\n")
    print("\n" + "=" * 70)
    print("  HEREN MCP v4.2 — server Rust (FlojoMCP)")
    print("  Instalador automatico")
    print("=" * 70 + "\n")


def default_workspace():
    env = os.environ.get("HEREN_WS")
    if env:
        return env
    # Reestructurado 2026-08-07: el workspace Rust (crates/heren-server)
    # vive AQUÍ (heren-mcp), no en FlojoMCP. El binario sale en
    # <workspace>\target\release\heren-server.exe.
    cands = [HEREN_MCP_DIR]
    for c in cands:
        if os.path.isdir(os.path.join(c, "crates", "heren-server")):
            return c
    return HEREN_MCP_DIR


def default_config_path():
    # OpenCode: %APPDATA%\opencode\opencode.jsonc (Windows)
    appdata = os.environ.get("APPDATA")
    if appdata:
        p = os.path.join(appdata, "opencode", "opencode.jsonc")
        if os.path.exists(p):
            return p
    # Linux/macOS: ~/.config/opencode/opencode.jsonc
    home = os.path.expanduser("~")
    p = os.path.join(home, ".config", "opencode", "opencode.jsonc")
    if os.path.exists(p):
        return p
    # fallback
    if appdata:
        return os.path.join(appdata, "opencode", "opencode.jsonc")
    return os.path.join(home, ".config", "opencode", "opencode.jsonc")


def detect_godot_exe():
    env = os.environ.get("GODOT_EXE")
    if env and os.path.exists(env):
        return env
    cands = [
        r"D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64.exe",
        r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
        r"D:\Mis Juegos\Godot\Godot_v4.6-stable_win64.exe",
    ]
    for c in cands:
        if os.path.exists(c):
            return c
    return ""


# ---------------------------------------------------------------------------
# 1. Compilar
# ---------------------------------------------------------------------------

def build_server(workspace):
    print("[1/3] Compilando heren-server (release)...")
    if not os.path.isdir(os.path.join(workspace, "crates", "heren-server")):
        print(f"  ! workspace no valido: {workspace}")
        return False
    # Ejecutar el build script si existe, si no cargo build --release
    bat = os.path.join(workspace, "heren-build.bat")
    if os.path.exists(bat) and os.name == "nt":
        print(f"  usando {bat}")
        r = subprocess.run(["cmd", "/c", bat], cwd=workspace)
    else:
        r = subprocess.run(["cargo", "build", "--release", "-p", "heren-server"],
                           cwd=workspace)
    if r.returncode != 0:
        print("  ! fallo la compilacion")
        return False
    exe = os.path.join(workspace, "target", "release", "heren-server.exe")
    if not os.path.exists(exe):
        print(f"  ! no se encontro el binario: {exe}")
        return False
    print(f"  OK -> {exe}")
    return True


# ---------------------------------------------------------------------------
# 2. Registrar MCP en opencode.jsonc
# ---------------------------------------------------------------------------

def ensure_escaped_path(p):
    """JSON-escapa backslashes para paths de Windows."""
    return p.replace("\\", "\\\\")


def register_mcp(config_path, server_exe, godot_exe, log_file):
    print(f"[2/3] Registrando MCP 'heren' en {config_path}")
    if not os.path.exists(config_path):
        print(f"  ! no existe config: {config_path}")
        return False

    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()

    # El bloque que queremos generar (formato OpenCode).
    block = (
        '    "heren": {\n'
        '      "type": "local",\n'
        '      "command": [\n'
        f'        "{ensure_escaped_path(server_exe)}"\n'
        '      ],\n'
        '      "environment": {\n'
        f'        "GODOT_EXE": "{ensure_escaped_path(godot_exe)}",\n'
        f'        "HEREN_LOG_FILE": "{ensure_escaped_path(log_file)}"\n'
        '      },\n'
        '      "timeout": 30000\n'
        '    }'
    )

    # Buscar la entrada "heren" dentro del bloque "mcp": {...}
    mcp_match = re.search(r'"mcp"\s*:\s*\{', content)
    if not mcp_match:
        print("  ! no hay bloque \"mcp\" en la config")
        return False

    # Encontrar el bloque de llaves del mcp (balanceando).
    open_idx = content.index("{", mcp_match.start())
    depth = 0
    close_idx = -1
    for i in range(open_idx, len(content)):
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
            if depth == 0:
                close_idx = i
                break
    if close_idx == -1:
        print("  ! no se pudo balancear el bloque mcp")
        return False

    mcp_body = content[open_idx + 1:close_idx]

    # Quitar la entrada "heren" existente si la hay (regex sobre el body).
    # Captura de "heren" : { ... } hasta el } de cierre de esa entrada.
    def _remove_heren(body):
        m = re.search(r'"heren"\s*:\s*\{', body)
        if not m:
            return body
        start = m.start()
        open_b = body.index("{", m.start())
        d = 0
        for i in range(open_b, len(body)):
            if body[i] == "{":
                d += 1
            elif body[i] == "}":
                d -= 1
                if d == 0:
                    # borrar desde start hasta i (incluye trailing comma)
                    end = i + 1
                    # consumir coma y espacio posterior
                    while end < len(body) and body[end] in " \t\r\n,":
                        end += 1
                    return body[:start] + body[end:]
        return body

    new_body = _remove_heren(mcp_body)

    # Añadir la entrada al final del bloque mcp. Gestionar coma si hay contenido.
    if new_body.strip():
        # Asegurar coma final del último elemento
        new_body = new_body.rstrip()
        if not new_body.endswith(","):
            new_body += ","
        new_body += "\n" + block
    else:
        new_body = "\n" + block

    new_content = content[:open_idx + 1] + new_body + content[close_idx:]

    # Escribir con respaldo
    backup = config_path + ".bak"
    shutil.copyfile(config_path, backup)
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  OK. Respaldo: {backup}")
    return True


# ---------------------------------------------------------------------------
# 3. Verificar
# ---------------------------------------------------------------------------

def verify_server(server_exe):
    print("[3/3] Verificando que arranca (handshake stdio)...")
    if not os.path.exists(server_exe):
        print(f"  ! no existe el binario: {server_exe}")
        return False
    # Enviar initialize y leer respuesta; timeout corto.
    payload = (
        '{"jsonrpc":"2.0","id":1,"method":"initialize",'
        '"params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"install","version":"1"}}}\n'
    )
    try:
        proc = subprocess.Popen(
            [server_exe],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        out, _ = proc.communicate(payload.encode(), timeout=8)
        text = out.decode("utf-8", "replace")
        if "jsonrpc" in text:
            print("  OK: el server responde al handshake MCP.")
            proc.terminate()
            return True
        print(f"  ! respuesta inesperada: {text[:200]}")
        proc.terminate()
        return False
    except FileNotFoundError:
        print("  ! no se pudo ejecutar el binario")
        return False
    except subprocess.TimeoutExpired:
        print("  ! timeout esperando respuesta (puede estar esperando stdin)")
        proc.kill()
        return False


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Instalador Heren MCP v4.2")
    ap.add_argument("--no-build", action="store_true", help="no compilar")
    ap.add_argument("--config", help="archivo de config MCP (default opencode.jsonc)")
    ap.add_argument("--godot-exe", help="ruta del ejecutable Godot")
    ap.add_argument("--server", help="ruta del binario heren-server.exe")
    ap.add_argument("--workspace", help="workspace FlojoMCP")
    args = ap.parse_args()

    workspace = args.workspace or default_workspace()
    server_exe = args.server or os.path.join(
        workspace, "target", "release", "heren-server.exe")
    config_path = args.config or default_config_path()
    godot_exe = args.godot_exe or detect_godot_exe()

    print_banner()

    print(f"Workspace FlojoMCP : {workspace}")
    print(f"Server             : {server_exe}")
    print(f"Config MCP         : {config_path}")
    print(f"GODOT_EXE          : {godot_exe or '(no detectado)'}")
    print()

    if not godot_exe:
        print("[!]  No se detecto GODOT_EXE. Usa --godot-exe para indicarlo.")

    if not args.no_build:
        ok = build_server(workspace)
        if not ok:
            print("\n[ERROR] Compilacion fallida. Usa --no-build si ya tienes el binario.")
            sys.exit(1)

    reg_ok = register_mcp(config_path, server_exe, godot_exe or "",
                          os.path.join(HEREN_MCP_DIR, ".temp", "opencode-server.log"))
    if not reg_ok:
        print("\n[ERROR] No se pudo registrar el MCP. Revisa la config.")
        sys.exit(2)

    if verify_server(server_exe):
        print("\n[OK] Instalacion completada. Reinicia la sesion MCP del cliente.")
    else:
        print("\n[!]  El server se registro pero la verificacion de arranque fallo.")
        sys.exit(3)


if __name__ == "__main__":
    main()
