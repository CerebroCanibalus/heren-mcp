#!/usr/bin/env python3
"""
Heren MCP - Instalador Automático

Instala y configura Heren MCP para Godot Engine 4.x
- Detecta sistema operativo
- Detecta Godot instalado
- Instala dependencias Python
- Configura Godot Daemon
- Configura MCP Server

Uso:
    python install.py
    python install.py --project-path D:/MiJuego

Idempotente: ejecutar múltiples veces no rompe nada.
"""

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

# Forzar UTF-8 en Windows
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# Importar sistema i18n
sys.path.insert(0, str(Path(__file__).parent / "src"))
from heren.i18n import get_text, get_current_language

# Banner ASCII
BANNER = r"""
                                                     
   	   ▄█    █▄       ▄████████    ▄████████    ▄████████ ███▄▄▄▄        
  	  ███    ███     ███    ███   ███    ███   ███    ███ ███▀▀▀██▄      
 	  ███    ███     ███    █▀    ███    ███   ███    █▀  ███   ███      
	 ▄███▄▄▄▄███▄▄  ▄███▄▄▄      ▄███▄▄▄▄██▀  ▄███▄▄▄     ███   ███      
	▀▀███▀▀▀▀███▀  ▀▀███▀▀▀     ▀▀███▀▀▀▀▀   ▀▀███▀▀▀     ███   ███      
	  ███    ███     ███    █▄  ▀███████████   ███    █▄  ███   ███      
 	  ███    ███     ███    ███   ███    ███   ███    ███ ███   ███      
	  ███    █▀      ██████████   ███    ███   ██████████  ▀█   █▀       
                               ███    ███ 

                                                          
                                                          
	 ▄████   ▄▄▄  ▄▄▄▄   ▄▄▄ ▄▄▄▄▄▄   ██▄  ▄██ ▄█████ █████▄ 
	██  ▄▄▄ ██▀██ ██▀██ ██▀██  ██     ██ ▀▀ ██ ██     ██▄▄█▀ 
	 ▀███▀  ▀███▀ ████▀ ▀███▀  ██     ██    ██ ▀█████ ██     
                                                           

▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ 
▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀                                                                              
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
                    ,'---\ \              ,---`,;,
                          ```
       ┓     ┓          ┓ 
┏┓┏┓╋  ┣┓┓┏  ┃┏┏┓┏┓┏┓┏┓╋┣┓
┗┻┛ ┗  ┗┛┗┫  ┛┗┗┛┛ ┛ ┗┻┗┛┗
          ┛               
"""


def print_banner():
    """Muestra el banner ASCII."""
    try:
        print(BANNER)
    except UnicodeEncodeError:
        # Fallback para terminales sin soporte Unicode
        print("\n" + "=" * 70)
        print("  HEREN MCP")
        print("  Godot Engine Model Context Protocol Server")
        print("=" * 70 + "\n")
    print("\n" + "=" * 70)
    print(f"  {get_text('ui.title_main')}")
    print("  Version: 2.0.0")
    print("=" * 70 + "\n")


def detect_os():
    """Detecta el sistema operativo."""
    system = platform.system().lower()
    if system == "windows":
        return "windows"
    elif system == "darwin":
        return "macos"
    elif system == "linux":
        return "linux"
    else:
        return system


def find_godot(os_type):
    """Busca Godot instalado en rutas comunes."""
    candidates = []
    
    if os_type == "windows":
        candidates = [
            r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
            r"D:\Mis Juegos\Godot\Godot_v4.5-stable_win64.exe",
            r"D:\Mis Juegos\Godot\Godot.exe",
            r"C:\Program Files\Godot\Godot.exe",
            r"C:\Program Files (x86)\Godot\Godot.exe",
            r"C:\Tools\Godot\Godot.exe",
            os.path.expanduser(r"~\AppData\Local\Godot\Godot.exe"),
            os.path.expanduser(r"~\Godot\Godot.exe"),
        ]
        # Buscar en PATH
        for path_dir in os.environ.get("PATH", "").split(os.pathsep):
            for name in ["godot.exe", "Godot.exe"]:
                candidates.append(os.path.join(path_dir.strip('"'), name))
    
    elif os_type == "macos":
        candidates = [
            "/Applications/Godot.app/Contents/MacOS/Godot",
            os.path.expanduser("~/Applications/Godot.app/Contents/MacOS/Godot"),
            "/usr/local/bin/godot",
            "/opt/homebrew/bin/godot",
        ]
        # Buscar en PATH
        godot_path = shutil.which("godot")
        if godot_path:
            candidates.insert(0, godot_path)
    
    elif os_type == "linux":
        candidates = [
            "/usr/bin/godot",
            "/usr/local/bin/godot",
            "/usr/games/godot",
            "/opt/godot/godot",
            os.path.expanduser("~/.local/bin/godot"),
        ]
        # Buscar en PATH
        godot_path = shutil.which("godot")
        if godot_path:
            candidates.insert(0, godot_path)
        # Flatpak
        candidates.append(os.path.expanduser("~/.local/share/flatpak/exports/bin/org.godotengine.Godot"))
    
    # Buscar en candidatos
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    
    return None


def install_python_dependencies():
    """Instala dependencias Python desde requirements.txt."""
    print(f"📦 {get_text('installer.installing_deps')}")
    
    requirements_file = Path(__file__).parent / "requirements.txt"
    
    if not requirements_file.exists():
        print("⚠️  requirements.txt not found. Creating basic one...")
        with open(requirements_file, "w") as f:
            f.write("fastmcp>=1.0.0\n")
            f.write("pydantic>=2.0.0\n")
            f.write("websocket-client>=1.6.0\n")
    
    try:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "-r", str(requirements_file)],
            check=True,
            capture_output=False,
        )
        print(f"✅ {get_text('installer.deps_installed')}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {get_text('installer.deps_error', error=str(e))}")
        return False
    except FileNotFoundError:
        print("❌ pip not found. Please install pip first.")
        return False


def setup_godot_daemon(project_path=None):
    """Configura Godot Daemon en el proyecto."""
    print(f"🔌 {get_text('installer.configuring_daemon')}")
    
    # Buscar el archivo del daemon
    daemon_source = Path(__file__).parent / "src" / "heren" / "daemon" / "godot_daemon.py"
    
    if not daemon_source.exists():
        print("⚠️  godot_daemon.py not found in installation")
        return False
    
    if project_path:
        # Copiar daemon al proyecto
        project_daemon_dir = Path(project_path) / "addons" / "heren_daemon"
        project_daemon_dir.mkdir(parents=True, exist_ok=True)
        
        # Crear script GDScript del daemon
        daemon_gd = project_daemon_dir / "heren_daemon.gd"
        daemon_gd_content = '''extends Node

class_name HerenDaemon

# Heren MCP - Godot Daemon
# This script runs inside Godot editor
# to allow WebSocket communication with Heren MCP

const PORT = 9742
var server: TCPServer
var peers: Array[StreamPeerTCP] = []
var websocket: WebSocketPeer

func _ready():
    print("[HerenDaemon] Starting...")
    start_server()

func start_server():
    server = TCPServer.new()
    var err = server.listen(PORT)
    if err != OK:
        push_error("[HerenDaemon] Could not start server on port " + str(PORT))
        return
    print("[HerenDaemon] WebSocket server listening on port " + str(PORT))

func _process(delta):
    if server and server.is_connection_available():
        var peer = server.take_connection()
        peers.append(peer)
        print("[HerenDaemon] Client connected")
    
    for peer in peers:
        if peer.get_available_bytes() > 0:
            var data = peer.get_utf8_string(peer.get_available_bytes())
            handle_message(data, peer)

func handle_message(data: String, peer: StreamPeerTCP):
    var response = JSON.stringify({"success": true, "message": "received", "data": data})
    peer.put_utf8_string(response)

func _exit_tree():
    if server:
        server.stop()
    print("[HerenDaemon] Server stopped")
'''
        with open(daemon_gd, "w") as f:
            f.write(daemon_gd_content)
        
        print(f"✅ {get_text('installer.daemon_configured', path=str(project_daemon_dir))}")
        return True
    else:
        print("ℹ️  No project_path provided. Skipping daemon setup.")
        return True


def configure_mcp_server(project_path=None, godot_path=None):
    """Muestra instrucciones de configuración MCP."""
    print("\n" + "=" * 70)
    print(f"  {get_text('installer.mcp_config')}")
    print("=" * 70 + "\n")
    
    config = {
        "mcpServers": {
            "heren-godot": {
                "command": sys.executable,
                "args": [
                    "-m",
                    "heren.server"
                ],
                "env": {
                    "PYTHONPATH": str(Path(__file__).parent / "src")
                }
            }
        }
    }
    
    if project_path:
        config["mcpServers"]["heren-godot"]["env"]["GODOT_PROJECT_PATH"] = str(project_path)
    
    if godot_path:
        config["mcpServers"]["heren-godot"]["env"]["GODOT_PATH"] = str(godot_path)
    
    print("Add this to your MCP configuration (opencode.jsonc or similar):\n")
    print(json.dumps(config, indent=2))
    
    print("\n" + "-" * 70)
    print(f"{get_text('installer.instructions')}")
    print("-" * 70)
    print(f"""
{get_text('installer.step1')}
{get_text('installer.step2')}:
   pip install -r requirements.txt

{get_text('installer.step3')}
   with the configuration shown above.

{get_text('installer.step4')}

{get_text('installer.step5')}

{get_text('installer.step6')}
""")


def print_summary(os_type, godot_path, project_path, success):
    """Muestra resumen de la instalación."""
    print("\n" + "=" * 70)
    print(f"  {get_text('installer.summary_title')}")
    print("=" * 70 + "\n")
    
    print(get_text('installer.summary_os', os=os_type.upper()))
    print(get_text('installer.summary_python', version=sys.version.split()[0]))
    print(get_text('installer.summary_godot', path=godot_path if godot_path else 'NOT FOUND ⚠️'))
    print(get_text('installer.summary_project', path=project_path if project_path else 'Not configured'))
    status = get_text('installer.status_success') if success else get_text('installer.status_error')
    print(get_text('installer.summary_status', status=status))
    
    print("\n" + "=" * 70)
    print(f"  {get_text('installer.ready')}")
    print("=" * 70 + "\n")


def main():
    # Detectar idioma del sistema para i18n
    current_lang = get_current_language()
    print(f"🌍 Language / Idioma: {current_lang.upper()}\n")
    
    parser = argparse.ArgumentParser(
        description="Heren MCP Installer for Godot Engine",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples / Ejemplos:
  python install.py                          # Basic installation
  python install.py --project-path D:/Game   # With Godot project
  python install.py --godot-path /usr/bin/godot  # Specific Godot
        """
    )
    
    parser.add_argument(
        "--project-path",
        help="Path to Godot project (optional) / Ruta al proyecto Godot (opcional)"
    )
    parser.add_argument(
        "--godot-path",
        help="Path to Godot executable (auto-detect if not provided) / Ruta al ejecutable de Godot"
    )
    parser.add_argument(
        "--skip-deps",
        action="store_true",
        help="Skip Python dependencies installation / Omitir instalación de dependencias"
    )
    parser.add_argument(
        "--skip-daemon",
        action="store_true",
        help="Skip Godot Daemon configuration / Omitir configuración del daemon"
    )
    parser.add_argument(
        "--lang",
        choices=["es", "en"],
        help="Force language / Forzar idioma (es/en)"
    )
    
    args = parser.parse_args()
    
    # Forzar idioma si se proporciona
    if args.lang:
        from heren.i18n import set_language
        set_language(args.lang)
        print(f"🌍 Language forced to / Idioma forzado a: {args.lang.upper()}\n")
    
    # Mostrar banner
    print_banner()
    
    # Detectar OS
    os_type = detect_os()
    print(f"🖥️  {get_text('installer.detected_os', os=os_type.upper())}\n")
    
    # Detectar Godot
    godot_path = args.godot_path or find_godot(os_type)
    if godot_path:
        print(f"✅ {get_text('installer.godot_found', path=godot_path)}\n")
    else:
        print(f"⚠️  {get_text('installer.godot_not_found')}\n")
    
    # Verificar proyecto
    project_path = None
    if args.project_path:
        project_path = os.path.abspath(args.project_path)
        if os.path.exists(os.path.join(project_path, "project.godot")):
            print(f"✅ {get_text('installer.project_found', path=project_path)}\n")
        else:
            print(f"⚠️  {get_text('installer.project_invalid', path=project_path)}\n")
            project_path = None
    
    # Instalar dependencias
    deps_success = True
    if not args.skip_deps:
        deps_success = install_python_dependencies()
        print()
    
    # Configurar daemon
    daemon_success = True
    if not args.skip_daemon:
        daemon_success = setup_godot_daemon(project_path)
        print()
    
    # Configurar MCP
    configure_mcp_server(project_path, godot_path)
    
    # Resumen
    success = deps_success and daemon_success
    print_summary(os_type, godot_path, project_path, success)
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
