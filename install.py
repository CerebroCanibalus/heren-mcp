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
    print(BANNER)
    print("\n" + "=" * 70)
    print("  Heren MCP - Godot Engine Model Context Protocol Server")
    print("  Versión: 2.0.0")
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
    print("📦 Instalando dependencias Python...")
    
    requirements_file = Path(__file__).parent / "requirements.txt"
    
    if not requirements_file.exists():
        print("⚠️  requirements.txt no encontrado. Creando uno básico...")
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
        print("✅ Dependencias instaladas correctamente")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Error instalando dependencias: {e}")
        return False
    except FileNotFoundError:
        print("❌ pip no encontrado. Instala pip primero.")
        return False


def setup_godot_daemon(project_path=None):
    """Configura Godot Daemon en el proyecto."""
    print("🔌 Configurando Godot Daemon...")
    
    # Buscar el archivo del daemon
    daemon_source = Path(__file__).parent / "src" / "heren" / "daemon" / "godot_daemon.py"
    
    if not daemon_source.exists():
        print("⚠️  godot_daemon.py no encontrado en la instalación")
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
# Este script se ejecuta dentro del editor de Godot
# para permitir comunicación WebSocket con Heren MCP

const PORT = 9742
var server: TCPServer
var peers: Array[StreamPeerTCP] = []
var websocket: WebSocketPeer

func _ready():
    print("[HerenDaemon] Iniciando...")
    start_server()

func start_server():
    server = TCPServer.new()
    var err = server.listen(PORT)
    if err != OK:
        push_error("[HerenDaemon] No se pudo iniciar servidor en puerto " + str(PORT))
        return
    print("[HerenDaemon] Servidor WebSocket escuchando en puerto " + str(PORT))

func _process(delta):
    if server and server.is_connection_available():
        var peer = server.take_connection()
        peers.append(peer)
        print("[HerenDaemon] Cliente conectado")
    
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
    print("[HerenDaemon] Servidor detenido")
'''
        with open(daemon_gd, "w") as f:
            f.write(daemon_gd_content)
        
        print(f"✅ Godot Daemon configurado en: {project_daemon_dir}")
        return True
    else:
        print("ℹ️  No se proporcionó project_path. Omite configuración del daemon.")
        return True


def configure_mcp_server(project_path=None, godot_path=None):
    """Muestra instrucciones de configuración MCP."""
    print("\n" + "=" * 70)
    print("  CONFIGURACIÓN MCP SERVER")
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
    
    print("Añade esto a tu configuración de MCP (opencode.jsonc o similar):\n")
    print(json.dumps(config, indent=2))
    
    print("\n" + "-" * 70)
    print("INSTRUCCIONES:")
    print("-" * 70)
    print("""
1. Asegúrate de que Python 3.10+ esté instalado
2. Verifica que las dependencias estén instaladas:
   pip install -r requirements.txt

3. Configura tu cliente MCP (OpenCode, Claude Desktop, etc.)
   con la configuración mostrada arriba.

4. Abre tu proyecto Godot antes de usar Heren MCP.

5. Inicia una sesión:
   session(action="open", project_path="D:/TuProyecto")

6. ¡Listo! Puedes usar todas las tools disponibles.
   Usa index(action="list") para ver las tools.
""")


def print_summary(os_type, godot_path, project_path, success):
    """Muestra resumen de la instalación."""
    print("\n" + "=" * 70)
    print("  RESUMEN DE INSTALACIÓN")
    print("=" * 70 + "\n")
    
    print(f"Sistema Operativo: {os_type.upper()}")
    print(f"Python: {sys.version.split()[0]}")
    print(f"Godot: {godot_path if godot_path else 'NO ENCONTRADO ⚠️'}")
    print(f"Proyecto: {project_path if project_path else 'No configurado'}")
    print(f"Estado: {'✅ ÉXITO' if success else '❌ CON ERRORES'}")
    
    print("\n" + "=" * 70)
    print("  Heren MCP está listo para usar")
    print("=" * 70 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Instalador de Heren MCP para Godot Engine",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ejemplos:
  python install.py                          # Instalación básica
  python install.py --project-path D:/Juego  # Con proyecto Godot
  python install.py --godot-path /usr/bin/godot  # Godot específico
        """
    )
    
    parser.add_argument(
        "--project-path",
        help="Ruta al proyecto Godot (opcional)"
    )
    parser.add_argument(
        "--godot-path",
        help="Ruta al ejecutable de Godot (auto-detecta si no se proporciona)"
    )
    parser.add_argument(
        "--skip-deps",
        action="store_true",
        help="Omitir instalación de dependencias Python"
    )
    parser.add_argument(
        "--skip-daemon",
        action="store_true",
        help="Omitir configuración del Godot Daemon"
    )
    
    args = parser.parse_args()
    
    # Mostrar banner
    print_banner()
    
    # Detectar OS
    os_type = detect_os()
    print(f"🖥️  Sistema operativo detectado: {os_type.upper()}\n")
    
    # Detectar Godot
    godot_path = args.godot_path or find_godot(os_type)
    if godot_path:
        print(f"✅ Godot encontrado: {godot_path}\n")
    else:
        print("⚠️  Godot no encontrado en las rutas comunes.")
        print("   Puedes proporcionarlo con --godot-path\n")
    
    # Verificar proyecto
    project_path = None
    if args.project_path:
        project_path = os.path.abspath(args.project_path)
        if os.path.exists(os.path.join(project_path, "project.godot")):
            print(f"✅ Proyecto Godot válido: {project_path}\n")
        else:
            print(f"⚠️  La ruta no parece ser un proyecto Godot válido: {project_path}\n")
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
