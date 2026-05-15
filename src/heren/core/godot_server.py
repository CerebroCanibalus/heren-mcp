"""
GodotServer - Persistent HTTP server wrapper for Godot Headless.

Mantiene un proceso Godot abierto para operaciones rapidas.
Ciclo de vida: inicia con sesion, detiene al cerrar sesion.
Fallback a scripts temporales si el servidor crashea.
"""

import json
import logging
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

logger = logging.getLogger("heren.server")


class GodotServer:
    """
    Wrapper para el servidor HTTP de Godot headless.
    
    Ciclo de vida:
    1. __init__: Inicia el proceso godot --headless --script heren_server.gd
    2. execute: Envia HTTP requests al servidor
    3. stop: Detiene el proceso limpiamente
    
    Fallback:
    - Si el servidor no responde, reintenta 2 veces
    - Si sigue fallando, reinicia el servidor
    - Si el reinicio falla, usa scripts temporales (GodotInterface)
    """
    
    def __init__(self, project_path: str, godot_exe: str, port: int = 0):
        """
        Args:
            project_path: Ruta al proyecto Godot (donde esta project.godot)
            godot_exe: Ruta al ejecutable de Godot
            port: Puerto para el servidor (0 = automatico)
        """
        self.project_path = os.path.abspath(project_path)
        self.godot_exe = godot_exe
        self.port = port if port > 0 else self._find_free_port()
        self.process: Optional[subprocess.Popen] = None
        self._ready = False
        self._start_time = 0.0
        
        # Ruta al script del servidor
        self.server_script = os.path.join(
            os.path.dirname(__file__), "heren_server.gd"
        )
        
        self._start()
    
    def _find_free_port(self) -> int:
        """Encuentra un puerto libre en localhost."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            s.listen(1)
            port = s.getsockname()[1]
        return port
    
    def _start(self):
        """Inicia el proceso Godot headless con el servidor HTTP."""
        # Encontrar project.godot
        project_file = self._find_project_file()
        
        cmd = [
            self.godot_exe,
            "--headless",
            "--path", os.path.dirname(project_file),  # Project directory
            "--script", self.server_script,
            "--",  # Separator: everything after this goes to the script
            "--project", project_file,
            "--port", str(self.port)
        ]
        
        logger.info(f"Starting GodotServer on port {self.port} for {project_file}")
        
        # Iniciar proceso sin ventana
        startupinfo = None
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        
        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            startupinfo=startupinfo,
            text=True,
            encoding="utf-8"
        )
        
        self._start_time = time.time()
        
        # Esperar a que el servidor esté listo
        self._wait_for_ready(timeout=30.0)
    
    def _find_project_file(self) -> str:
        """Encuentra project.godot en el path dado."""
        path = Path(self.project_path)
        
        # Si es un archivo, usarlo directamente
        if path.is_file():
            return str(path)
        
        # Si es directorio, buscar project.godot
        project_file = path / "project.godot"
        if project_file.exists():
            return str(project_file)
        
        # Buscar recursivamente (un nivel)
        for child in path.iterdir():
            if child.is_dir():
                candidate = child / "project.godot"
                if candidate.exists():
                    return str(candidate)
        
        raise FileNotFoundError(f"No project.godot found in {self.project_path}")
    
    def _wait_for_ready(self, timeout: float = 30.0):
        """Espera a que el servidor HTTP responda."""
        deadline = time.time() + timeout
        
        while time.time() < deadline:
            if self.process.poll() is not None:
                # Proceso terminó prematuramente
                stdout, stderr = self.process.communicate()
                raise RuntimeError(
                    f"GodotServer exited early. stdout: {stdout}, stderr: {stderr}"
                )
            
            try:
                response = self._http_request("ping", {}, timeout=1.0)
                if response.get("status") == "pong":
                    self._ready = True
                    elapsed = (time.time() - self._start_time) * 1000
                    logger.info(f"GodotServer ready in {elapsed:.1f}ms")
                    return
            except (ConnectionRefusedError, socket.timeout, OSError):
                time.sleep(0.1)
        
        raise TimeoutError(f"GodotServer did not become ready within {timeout}s")
    
    def execute(self, operation: str, params: dict) -> dict:
        """
        Ejecuta una operación en el servidor Godot.
        
        Args:
            operation: Nombre de la operación (get_scene_tree, add_node, etc.)
            params: Parámetros de la operación
        
        Returns:
            dict con el resultado
        
        Raises:
            RuntimeError: Si todas las estrategias fallan
        """
        if not self._ready:
            raise RuntimeError("GodotServer not ready")
        
        # Estrategia 1: Request directo
        for attempt in range(2):
            try:
                return self._http_request(operation, params, timeout=10.0)
            except (ConnectionRefusedError, BrokenPipeError, OSError) as e:
                logger.warning(f"Request failed (attempt {attempt + 1}): {e}")
                if attempt == 0:
                    time.sleep(0.1)
        
        # Estrategia 2: Reiniciar servidor
        logger.info("Restarting GodotServer after failure...")
        self._restart()
        
        try:
            return self._http_request(operation, params, timeout=10.0)
        except Exception as e:
            logger.error(f"Server restart failed: {e}")
        
        # Estrategia 3: Fallback a scripts temporales
        logger.info("Falling back to temp scripts...")
        return self._fallback_execute(operation, params)
    
    def _http_request(self, operation: str, params: dict, timeout: float = 10.0) -> dict:
        """Envía un request HTTP al servidor Godot."""
        request_data = {
            "operation": operation,
            "params": params
        }
        
        body = json.dumps(request_data)
        
        # Crear request HTTP
        request = f"POST /execute HTTP/1.1\r\n"
        request += f"Host: 127.0.0.1:{self.port}\r\n"
        request += f"Content-Type: application/json\r\n"
        request += f"Content-Length: {len(body)}\r\n"
        request += f"Connection: close\r\n"
        request += f"\r\n"
        request += body
        
        # Enviar y recibir
        with socket.create_connection(("127.0.0.1", self.port), timeout=timeout) as sock:
            sock.sendall(request.encode("utf-8"))
            
            # Recibir respuesta
            response = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
        
        # Parsear respuesta HTTP
        response_text = response.decode("utf-8")
        
        # Extraer body JSON
        header_end = response_text.find("\r\n\r\n")
        if header_end == -1:
            header_end = response_text.find("\n\n")
        
        if header_end == -1:
            raise ValueError("Invalid HTTP response")
        
        body_text = response_text[header_end + 4:]
        
        return json.loads(body_text)
    
    def _restart(self):
        """Reinicia el servidor Godot."""
        self.stop()
        self._ready = False
        self._start()
    
    def _fallback_execute(self, operation: str, params: dict) -> dict:
        """
        Fallback a scripts temporales cuando el servidor falla.
        Usa GodotInterface (el método actual).
        """
        from heren.interfaces.godot_cli import GodotInterface
        
        interface = GodotInterface(self.godot_exe, self.project_path)
        
        # Mapear operaciones a templates
        template_map = {
            "get_scene_tree": "get_scene_tree",
            "save_scene": "save_scene",
            "add_node": "add_node",
            "remove_node": "remove_node",
            "set_property": "set_property",
            "get_node_properties": "get_node_properties"
        }
        
        template_name = template_map.get(operation)
        if not template_name:
            return {"error": f"Operation '{operation}' not available in fallback mode"}
        
        return interface.execute_template(template_name, params)
    
    def is_alive(self) -> bool:
        """Verifica si el proceso Godot sigue corriendo."""
        if self.process is None:
            return False
        return self.process.poll() is None
    
    def stop(self):
        """Detiene el servidor Godot limpiamente."""
        if self.process is None:
            return
        
        logger.info("Stopping GodotServer...")
        
        try:
            # Enviar quit
            self._http_request("quit", {}, timeout=2.0)
        except Exception:
            pass
        
        # Esperar a que termine
        try:
            self.process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            # Forzar kill
            self.process.terminate()
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.process.kill()
        
        self.process = None
        self._ready = False
        logger.info("GodotServer stopped")
    
    def __del__(self):
        """Destructor: asegura que el proceso se detenga."""
        self.stop()


class GodotServerManager:
    """
    Gestiona múltiples servidores Godot (uno por sesión).
    """
    
    def __init__(self):
        self.servers: dict[str, GodotServer] = {}
    
    def create_server(self, session_id: str, project_path: str, godot_exe: str) -> GodotServer:
        """Crea un nuevo servidor para una sesión."""
        if session_id in self.servers:
            raise ValueError(f"Server already exists for session {session_id}")
        
        server = GodotServer(project_path, godot_exe)
        self.servers[session_id] = server
        return server
    
    def get_server(self, session_id: str) -> Optional[GodotServer]:
        """Obtiene el servidor para una sesión."""
        return self.servers.get(session_id)
    
    def remove_server(self, session_id: str):
        """Detiene y elimina el servidor de una sesión."""
        server = self.servers.pop(session_id, None)
        if server:
            server.stop()
    
    def stop_all(self):
        """Detiene todos los servidores."""
        for session_id, server in list(self.servers.items()):
            server.stop()
        self.servers.clear()
