"""
Heren MCP - Session Manager (Capa 0)

El núcleo del sistema. Se inicializa primero. Sin sesión, no hay operaciones.
Mantiene Godot headless vivo, gestiona caché, y coordina todo.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import json
import logging
import os
import subprocess
import sys
import threading
import time
import uuid
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)


class LRUCache:
    """Cache LRU simple con TTL."""
    
    def __init__(self, max_size: int = 100, ttl_seconds: float = 300):
        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self._cache: OrderedDict[str, dict] = OrderedDict()
        self._lock = threading.RLock()
    
    def get(self, key: str) -> Optional[Any]:
        with self._lock:
            if key not in self._cache:
                return None
            
            entry = self._cache[key]
            if time.time() - entry["timestamp"] > self.ttl_seconds:
                del self._cache[key]
                return None
            
            # Mover al final (más recientemente usado)
            self._cache.move_to_end(key)
            return entry["value"]
    
    def set(self, key: str, value: Any):
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
            
            self._cache[key] = {
                "value": value,
                "timestamp": time.time(),
            }
            
            # Evict oldest if over limit
            while len(self._cache) > self.max_size:
                self._cache.popitem(last=False)
    
    def invalidate(self, key: str):
        with self._lock:
            self._cache.pop(key, None)
    
    def clear(self):
        with self._lock:
            self._cache.clear()


@dataclass
class ProjectState:
    """Estado de un proyecto Godot."""
    project_path: str
    godot_path: Optional[str] = None
    main_scene: Optional[str] = None
    autoloads: dict = field(default_factory=dict)
    global_groups: list = field(default_factory=list)
    
    def to_dict(self) -> dict:
        return {
            "project_path": self.project_path,
            "godot_path": self.godot_path,
            "main_scene": self.main_scene,
            "autoloads": self.autoloads,
            "global_groups": self.global_groups,
        }


@dataclass 
class Session:
    """Una sesión activa con Godot."""
    id: str
    project_path: str
    project_state: ProjectState
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    
    # Godot process
    godot_process: Optional[subprocess.Popen] = None
    godot_lock: threading.RLock = field(default_factory=threading.RLock)
    
    # Cache
    scene_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=50, ttl_seconds=600))
    resource_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=100, ttl_seconds=300))
    
    # Operation history
    operations: list = field(default_factory=list)
    undo_stack: list = field(default_factory=list)
    redo_stack: list = field(default_factory=list)
    
    def touch(self):
        """Actualiza timestamp de última actividad."""
        self.last_activity = time.time()
    
    def is_expired(self, timeout_seconds: float = 3600) -> bool:
        """Verifica si la sesión expiró por inactividad."""
        return time.time() - self.last_activity > timeout_seconds


class SessionManager:
    """
    Gestor de sesiones Heren MCP.
    
    Singleton que coordina todas las sesiones activas.
    Mantiene Godot corriendo y gestiona caché.
    """
    
    _instance: Optional["SessionManager"] = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        
        self._initialized = True
        self._sessions: dict[str, Session] = {}
        self._sessions_lock = threading.RLock()
        self._cleanup_thread: Optional[threading.Thread] = None
        self._shutdown = False
        
        # Iniciar cleanup thread
        self._start_cleanup_thread()
    
    def _start_cleanup_thread(self):
        """Inicia thread de limpieza de sesiones expiradas."""
        def cleanup_loop():
            while not self._shutdown:
                time.sleep(60)  # Cada minuto
                self._cleanup_expired_sessions()
        
        self._cleanup_thread = threading.Thread(target=cleanup_loop, daemon=True)
        self._cleanup_thread.start()
    
    def _cleanup_expired_sessions(self):
        """Limpia sesiones expiradas."""
        expired = []
        with self._sessions_lock:
            for session_id, session in list(self._sessions.items()):
                if session.is_expired():
                    expired.append(session_id)
        
        for session_id in expired:
            logger.info(f"Sesión expirada: {session_id}")
            self.end_session(session_id)
    
    def start_session(
        self,
        project_path: str,
        godot_path: Optional[str] = None,
    ) -> Session:
        """
        Inicia una nueva sesión con Godot.
        
        Args:
            project_path: Ruta absoluta al proyecto Godot
            godot_path: Ruta al ejecutable de Godot (auto-detecta si no se proporciona)
        
        Returns:
            Sesión activa
        """
        project_path = os.path.abspath(project_path)
        
        if not os.path.exists(project_path):
            raise ValueError(f"Proyecto no encontrado: {project_path}")
        
        if not os.path.exists(os.path.join(project_path, "project.godot")):
            raise ValueError(f"No es un proyecto Godot válido: {project_path}")
        
        # Auto-detectar Godot
        if godot_path is None:
            godot_path = self._find_godot_executable()
        
        if not os.path.exists(godot_path):
            raise ValueError(f"Godot no encontrado: {godot_path}")
        
        # Crear sesión
        session_id = str(uuid.uuid4())[:8]
        project_state = ProjectState(
            project_path=project_path,
            godot_path=godot_path,
        )
        
        session = Session(
            id=session_id,
            project_path=project_path,
            project_state=project_state,
        )
        
        # Iniciar Godot
        self._start_godot_process(session)
        
        with self._sessions_lock:
            self._sessions[session_id] = session
        
        logger.info(f"Sesión iniciada: {session_id} | Proyecto: {project_path}")
        return session
    
    def _find_godot_executable(self) -> str:
        """Auto-detecta el ejecutable de Godot."""
        # Windows - ubicaciones comunes
        if sys.platform == "win32":
            candidates = [
                r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
                r"D:\Mis Juegos\Godot\Godot_v4.5-stable_win64.exe",
                r"D:\Mis Juegos\Godot\Godot.exe",
                r"C:\Program Files\Godot\Godot.exe",
            ]
            for candidate in candidates:
                if os.path.exists(candidate):
                    return candidate
            
            # Buscar en PATH
            for path in os.environ.get("PATH", "").split(os.pathsep):
                for name in ["godot.exe", "Godot.exe"]:
                    full = os.path.join(path.strip('"'), name)
                    if os.path.exists(full):
                        return full
        
        # Linux/Mac
        else:
            import shutil
            godot = shutil.which("godot")
            if godot:
                return godot
        
        raise RuntimeError(
            "Godot no encontrado. Proporciona godot_path o añade Godot al PATH."
        )
    
    def _start_godot_process(self, session: Session):
        """Inicia el proceso Godot headless con el bridge."""
        bridge_path = self._get_bridge_path()
        
        cmd = [
            session.project_state.godot_path,
            "--headless",
            "--path", session.project_path,
            "--script", bridge_path,
        ]
        
        try:
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,  # Line buffered
            )
            
            session.godot_process = process
            
            # Esperar a que el bridge esté listo
            self._wait_for_bridge_ready(session)
            
            logger.info(f"Godot iniciado para sesión {session.id}")
            
        except Exception as e:
            logger.error(f"Error iniciando Godot: {e}")
            raise RuntimeError(f"No se pudo iniciar Godot: {e}")
    
    def _get_bridge_path(self) -> str:
        """Obtiene la ruta al bridge GDScript."""
        # El bridge está en src/heren/bridges/heren_bridge.gd
        current_dir = Path(__file__).parent.parent
        bridge_path = current_dir / "bridges" / "heren_bridge.gd"
        
        if not bridge_path.exists():
            raise RuntimeError(f"Bridge no encontrado: {bridge_path}")
        
        return str(bridge_path.absolute())
    
    def _wait_for_bridge_ready(self, session: Session, timeout: float = 10.0):
        """Espera a que el bridge GDScript esté listo."""
        start = time.time()
        
        while time.time() - start < timeout:
            if session.godot_process.poll() is not None:
                # Godot terminó inesperadamente
                stderr = session.godot_process.stderr.read()
                raise RuntimeError(f"Godot terminó inesperadamente: {stderr}")
            
            # Leer stdout buscando señal de ready
            import select
            if sys.platform != "win32":
                ready, _, _ = select.select([session.godot_process.stdout], [], [], 0.5)
                if ready:
                    line = session.godot_process.stdout.readline().strip()
                    if line == "HEREN_BRIDGE_READY":
                        return
            else:
                # Windows: polling
                time.sleep(0.5)
                line = session.godot_process.stdout.readline().strip()
                if line == "HEREN_BRIDGE_READY":
                    return
        
        raise RuntimeError("Timeout esperando a que el bridge esté listo")
    
    def get_session(self, session_id: str) -> Optional[Session]:
        """Obtiene una sesión por ID."""
        with self._sessions_lock:
            session = self._sessions.get(session_id)
            if session:
                session.touch()
            return session
    
    def end_session(self, session_id: str) -> bool:
        """
        Termina una sesión y cierra Godot.
        
        Returns:
            True si se cerró correctamente
        """
        with self._sessions_lock:
            session = self._sessions.pop(session_id, None)
        
        if not session:
            return False
        
        # Cerrar Godot
        if session.godot_process and session.godot_process.poll() is None:
            try:
                # Enviar comando de shutdown
                self._send_command_raw(session, {"action": "shutdown"})
                session.godot_process.wait(timeout=5)
            except:
                # Forzar kill
                session.godot_process.kill()
                session.godot_process.wait()
        
        # Limpiar caché
        session.scene_cache.clear()
        session.resource_cache.clear()
        
        logger.info(f"Sesión terminada: {session_id}")
        return True
    
    def send_command(
        self,
        session_id: str,
        action: str,
        params: dict = None,
    ) -> dict:
        """
        Envía un comando a Godot y devuelve la respuesta.
        
        Args:
            session_id: ID de la sesión
            action: Nombre de la acción
            params: Parámetros de la acción
        
        Returns:
            Respuesta JSON de Godot
        """
        session = self.get_session(session_id)
        if not session:
            return {"success": False, "error": f"Sesión no encontrada: {session_id}"}
        
        cmd = {
            "id": str(uuid.uuid4())[:8],
            "action": action,
            "params": params or {},
        }
        
        return self._send_command_raw(session, cmd)
    
    def _send_command_raw(self, session: Session, cmd: dict) -> dict:
        """Envía un comando crudo a Godot usando archivos temporales."""
        import time
        
        with session.godot_lock:
            if not session.godot_process or session.godot_process.poll() is not None:
                return {"success": False, "error": "Godot no está corriendo"}
            
            try:
                temp_dir = "D:\\Mis Juegos\\GodotMCP\\heren-mcp\\.temp"
                cmd_file = os.path.join(temp_dir, "heren_cmd.json")
                resp_file = os.path.join(temp_dir, "heren_resp.json")
                
                # Limpiar respuesta anterior
                if os.path.exists(resp_file):
                    os.remove(resp_file)
                
                # Escribir comando
                with open(cmd_file, "w", encoding="utf-8") as f:
                    f.write(json.dumps(cmd))
                
                # Esperar respuesta (polling)
                timeout = 30.0
                start = time.time()
                while time.time() - start < timeout:
                    if os.path.exists(resp_file):
                        with open(resp_file, "r", encoding="utf-8") as f:
                            response_line = f.read().strip()
                        
                        if response_line:
                            return json.loads(response_line)
                        else:
                            return {"success": False, "error": "Respuesta vacía de Godot"}
                    
                    time.sleep(0.05)  # 50ms polling
                
                return {"success": False, "error": "Timeout esperando respuesta de Godot"}
                
            except Exception as e:
                logger.error(f"Error enviando comando: {e}")
                return {"success": False, "error": str(e)}
    
    def shutdown_all(self):
        """Cierra todas las sesiones."""
        self._shutdown = True
        
        with self._sessions_lock:
            session_ids = list(self._sessions.keys())
        
        for session_id in session_ids:
            self.end_session(session_id)
        
        logger.info("Todas las sesiones cerradas")


# Singleton global
session_manager = SessionManager()


def get_session_manager() -> SessionManager:
    """Obtiene el Session Manager global."""
    return session_manager
