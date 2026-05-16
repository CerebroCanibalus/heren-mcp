"""
GodotDaemon - Wrapper Python para el daemon Godot via WebSocket.

Mantiene un proceso Godot vivo y se comunica via WebSocket para operaciones rápidas.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import tempfile
import time
from typing import Any, Optional

import websocket


def _find_godot_executable() -> str:
    """Auto-detecta el ejecutable de Godot."""
    import sys
    import shutil
    
    # Windows - ubicaciones comunes del General
    if sys.platform == "win32":
        candidates = [
            r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
            r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64_console.exe",
            r"D:\Mis Juegos\Godot\Godot_v4.5-stable_win64.exe",
            r"D:\Mis Juegos\Godot\Godot.exe",
            r"C:\Program Files\Godot\Godot.exe",
        ]
        for candidate in candidates:
            if os.path.exists(candidate):
                return candidate
        
        # Buscar en PATH
        for path_dir in os.environ.get("PATH", "").split(os.pathsep):
            for name in ["godot.exe", "Godot.exe"]:
                full = os.path.join(path_dir.strip('"'), name)
                if os.path.exists(full):
                    return full
    
    # Linux/Mac
    godot = shutil.which("godot")
    if godot:
        return godot
    
    raise RuntimeError("Godot no encontrado. Proporciona godot_path o añade Godot al PATH.")


logger = logging.getLogger(__name__)


class GodotDaemon:
    """Wrapper para el daemon Godot persistente via WebSocket."""
    
    def __init__(
        self,
        project_path: str,
        godot_path: Optional[str] = None,
        auto_port: bool = True,
        timeout: int = 30
    ):
        self.project_path = os.path.abspath(project_path)
        self.godot_path = godot_path or _find_godot_executable()
        self.timeout = timeout
        
        self.process: Optional[subprocess.Popen] = None
        self.ws: Optional[websocket.WebSocket] = None
        self.port: int = 0
        
        # Usar daemon del proyecto si existe (para class_name), sino fallback al paquete
        project_daemon = os.path.join(self.project_path, "addons", "heren", "daemon", "heren_daemon.gd")
        package_daemon = os.path.join(os.path.dirname(__file__), "heren_daemon.gd")
        
        if os.path.exists(project_daemon):
            self.daemon_path = project_daemon
            logger.info(f"[Daemon] Usando daemon del proyecto: {project_daemon}")
        else:
            self.daemon_path = package_daemon
            logger.info(f"[Daemon] Usando daemon del paquete: {package_daemon}")
        
        self._is_connected = False
        self._request_counter = 0
        self._last_error_output: str = ""  # Para diagnóstico
    
    def start(self) -> bool:
        """Inicia el daemon Godot y espera a que esté listo."""
        if self._is_connected:
            logger.debug("[Daemon] Ya está conectado")
            return True
        
        logger.info("[Daemon] Iniciando daemon Godot...")
        logger.info(f"[Daemon] Proyecto: {self.project_path}")
        
        # Verificar que existe el script del daemon
        if not os.path.exists(self.daemon_path):
            logger.error(f"[Daemon] No se encontró: {self.daemon_path}")
            return False
        
        # Preparar argumentos
        args = [
            self.godot_path,
            "--path", self.project_path,
            "--script", self.daemon_path,
            "--",  # Separador para user args
            self.project_path
        ]
        
        logger.debug(f"[Daemon] Comando: {' '.join(args)}")
        
        try:
            # Iniciar proceso
            self.process = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,  # Line-buffered
                cwd=self.project_path
            )
            
            # Esperar a que el daemon esté listo
            if not self._wait_for_ready():
                logger.error("[Daemon] Timeout esperando daemon")
                self.stop()
                return False
            
            # Conectar WebSocket con retry
            if not self._connect_websocket_with_retry():
                logger.error("[Daemon] No se pudo conectar WebSocket después de 3 intentos")
                self.stop()
                return False
            
            self._is_connected = True
            logger.info(f"[Daemon] Conectado exitosamente en puerto {self.port}")
            
            # Hacer ping de verificación
            if not self.is_healthy():
                logger.error("[Daemon] Health check inicial falló")
                self.stop()
                return False
            
            logger.info("[Daemon] Health check exitoso")
            return True
                
        except Exception as e:
            logger.error(f"[Daemon] Error iniciando: {e}")
            self.stop()
            return False
    
    def _connect_websocket_with_retry(self, max_retries: int = 3, retry_delay: float = 1.0) -> bool:
        """Conecta WebSocket con reintentos."""
        ws_url = f"ws://127.0.0.1:{self.port}"
        logger.info(f"[Daemon] Conectando a {ws_url}...")
        
        for attempt in range(1, max_retries + 1):
            try:
                self.ws = websocket.create_connection(
                    ws_url,
                    timeout=self.timeout,
                    enable_multithread=True
                )
                logger.info(f"[Daemon] Conectado en intento {attempt}")
                return True
            except Exception as e:
                logger.warning(f"[Daemon] Intento {attempt}/{max_retries} falló: {e}")
                if attempt < max_retries:
                    time.sleep(retry_delay)
        
        return False
    
    def _wait_for_ready(self) -> bool:
        """Espera a que el daemon imprima HEREN_DAEMON_READY:<port>."""
        start_time = time.time()
        
        # Leer stdout y stderr combinados para evitar problemas de buffering en Windows
        import threading
        
        output_buffer = []
        
        def reader_thread(pipe, label):
            try:
                for line in iter(pipe.readline, ''):
                    line = line.strip()
                    if line:
                        output_buffer.append((label, line))
                        logger.debug(f"[Daemon {label}] {line}")
            except Exception:
                pass
        
        stdout_thread = threading.Thread(
            target=reader_thread, 
            args=(self.process.stdout, "stdout"),
            daemon=True
        )
        stderr_thread = threading.Thread(
            target=reader_thread, 
            args=(self.process.stderr, "stderr"),
            daemon=True
        )
        stdout_thread.start()
        stderr_thread.start()
        
        while time.time() - start_time < self.timeout:
            if self.process.poll() is not None:
                # Proceso muri�
                stdout_thread.join(timeout=1)
                stderr_thread.join(timeout=1)
                logger.error(f"[Daemon] Proceso muri�. Output: {output_buffer}")
                return False
            
            # Buscar en el buffer
            for label, line in output_buffer:
                if "HEREN_DAEMON_READY:" in line:
                    parts = line.split("HEREN_DAEMON_READY:")
                    if len(parts) > 1:
                        port_str = parts[1].replace("]", "").strip()
                        try:
                            self.port = int(port_str)
                            logger.info(f"[Daemon] Puerto detectado: {self.port}")
                            return True
                        except ValueError:
                            continue
            
            time.sleep(0.1)
        
        # Timeout
        logger.error(f"[Daemon] Timeout esperando ready. Output: {output_buffer}")
        return False
    
    def is_healthy(self, timeout_sec: float = 5.0) -> bool:
        """Envía un ping y espera pong. Retorna False si no responde en timeout_sec."""
        if not self._is_connected or not self.ws:
            return False
        
        try:
            self._request_counter += 1
            request_id = f"health_{self._request_counter}"
            
            payload = {
                "id": request_id,
                "method": "ping",
                "params": {}
            }
            
            self.ws.send(json.dumps(payload))
            
            # Esperar respuesta con timeout específico
            start_time = time.time()
            while time.time() - start_time < timeout_sec:
                self.ws.settimeout(timeout_sec)
                try:
                    response = self.ws.recv()
                    result = json.loads(response)
                    
                    if result.get("type") == "heartbeat":
                        continue
                    
                    if result.get("id") == request_id:
                        return result.get("success", False)
                    
                    # Respuesta que no es nuestro ping, continuar
                    continue
                    
                except websocket.WebSocketTimeoutException:
                    return False
            
            return False
            
        except Exception as e:
            logger.error(f"[Daemon] Error en health check: {e}")
            return False
    
    def call(self, method: str, params: dict) -> dict:
        """Llama a un método en el daemon."""
        if not self._is_connected or not self.ws:
            return {
                "success": False,
                "error": "not_connected",
                "message": "Daemon no está conectado"
            }
        
        # Health check antes de cada operación
        if not self.is_healthy():
            return {
                "success": False,
                "error": "not_healthy",
                "message": "Daemon no responde al health check"
            }
        
        self._request_counter += 1
        request_id = f"req_{self._request_counter}"
        
        payload = {
            "id": request_id,
            "method": method,
            "params": params
        }
        
        try:
            logger.debug(f"[Daemon] >>> {method}: {params}")
            self.ws.send(json.dumps(payload))
            
            # Esperar respuesta con timeout de 30 segundos
            start_time = time.time()
            while time.time() - start_time < self.timeout:
                self.ws.settimeout(self.timeout)
                try:
                    response = self.ws.recv()
                    result = json.loads(response)
                    
                    # Ignorar heartbeats
                    if result.get("type") == "heartbeat":
                        logger.debug("[Daemon] <<< heartbeat")
                        continue
                    
                    logger.debug(f"[Daemon] <<< {method}: {result.get('success', False)}")
                    return result
                    
                except websocket.WebSocketTimeoutException:
                    logger.error(f"[Daemon] Timeout en {method} después de {self.timeout}s")
                    return {
                        "success": False,
                        "error": "timeout",
                        "message": f"Operation timeout after {self.timeout}s",
                        "method": method
                    }
            
            # Timeout global
            logger.error(f"[Daemon] Timeout global en {method}")
            return {
                "success": False,
                "error": "timeout",
                "message": f"Operation timeout after {self.timeout}s",
                "method": method
            }
            
        except websocket.WebSocketTimeoutException:
            logger.error(f"[Daemon] Timeout en {method}")
            return {
                "success": False,
                "error": "timeout",
                "message": f"Operation timeout after {self.timeout}s",
                "method": method
            }
        except Exception as e:
            logger.error(f"[Daemon] Error en {method}: {e}")
            return {
                "success": False,
                "error": str(e),
                "message": f"Error en operación {method}: {e}",
                "method": method
            }
    
    def batch(self, operations: list, stop_on_error: bool = False) -> dict:
        """Ejecuta múltiples operaciones en una sola llamada."""
        return self.call("batch", {
            "operations": operations,
            "stop_on_error": stop_on_error
        })
    
    def health(self) -> dict:
        """Verifica salud del daemon."""
        return self.call("health", {})
    
    def is_alive(self) -> bool:
        """Verifica si el proceso sigue vivo."""
        if not self.process:
            return False
        return self.process.poll() is None and self._is_connected
    
    def stop(self):
        """Detiene el daemon de forma limpia."""
        logger.info("[Daemon] Deteniendo daemon...")
        
        # Enviar quit al daemon
        if self.ws and self._is_connected:
            try:
                self.call("quit", {})
                self.ws.close()
            except Exception as e:
                logger.debug(f"[Daemon] Error enviando quit: {e}")
        
        self.ws = None
        self._is_connected = False
        
        # Matar proceso si sigue vivo
        if self.process and self.process.poll() is None:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.warning("[Daemon] Forzando kill del proceso")
                self.process.kill()
                self.process.wait()
            except Exception as e:
                logger.error(f"[Daemon] Error matando proceso: {e}")
        
        self.process = None
        self.port = 0
        logger.info("[Daemon] Daemon detenido")
    
    def kill(self):
        """Fuerza el cierre del daemon inmediatamente (para limpieza de sesiones muertas)."""
        logger.info("[Daemon] Forzando cierre del daemon...")
        
        # Cerrar WebSocket
        if self.ws:
            try:
                self.ws.close()
            except Exception:
                pass
        
        self.ws = None
        self._is_connected = False
        
        # Matar proceso
        if self.process:
            try:
                import signal
                # Enviar SIGTERM primero
                if hasattr(self.process, 'send_signal'):
                    self.process.send_signal(signal.SIGTERM)
                else:
                    self.process.terminate()
                
                # Esperar un poco
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    # Forzar kill
                    if hasattr(self.process, 'kill'):
                        self.process.kill()
                    self.process.wait(timeout=2)
            except Exception:
                pass
        
        self.process = None
        self.port = 0
        logger.info("[Daemon] Daemon cerrado forzosamente")
    
    def __enter__(self):
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
