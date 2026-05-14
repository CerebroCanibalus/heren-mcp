"""
Heren MCP - Session Manager (Capa 0)

El n�cleo del sistema. Se inicializa primero. Sin sesi�n, no hay operaciones.
Gestiona cach� agresiva y ejecuta scripts GDScript temporales via Godot CLI.

Filosof�a: Poder. Eficiencia. Rapidez.
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

# GodotServer integration
from heren.core.godot_server import GodotServer

# GodotDaemon integration (WebSocket persistente)
from heren.daemon.godot_daemon import GodotDaemon

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
            
            # Mover al final (m�s recientemente usado)
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
    """Una sesi�n activa con un proyecto Godot."""
    id: str
    project_path: str
    project_state: ProjectState
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    
    # Cache
    scene_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=50, ttl_seconds=300))
    resource_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=100, ttl_seconds=300))
    
    # GodotServer (persistent HTTP server)
    godot_server: Optional[GodotServer] = None
    
    # GodotDaemon (persistent WebSocket server - NUEVO)
    godot_daemon: Optional[GodotDaemon] = None
    
    # Operation history
    operations: list = field(default_factory=list)
    undo_stack: list = field(default_factory=list)
    redo_stack: list = field(default_factory=list)
    
    def touch(self):
        """Actualiza timestamp de �ltima actividad."""
        self.last_activity = time.time()
    
    def is_expired(self, timeout_seconds: float = 3600) -> bool:
        """Verifica si la sesi�n expir� por inactividad."""
        return time.time() - self.last_activity > timeout_seconds


class SessionManager:
    """
    Gestor de sesiones Heren MCP.
    
    Singleton que coordina todas las sesiones activas.
    Usa scripts GDScript temporales para comunicaci�n con Godot.
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
        self._temp_files: list[str] = []
        
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
        dead_daemons = []
        
        with self._sessions_lock:
            for session_id, session in list(self._sessions.items()):
                if session.is_expired():
                    expired.append(session_id)
                elif session.godot_daemon and not session.godot_daemon.is_alive():
                    dead_daemons.append(session_id)
        
        for session_id in expired:
            logger.info(f"Sesi�n expirada: {session_id}")
            self.end_session(session_id)
        
        for session_id in dead_daemons:
            logger.warning(f"[Daemon] Sesi�n {session_id} tiene daemon muerto. Limpiando...")
            self._cleanup_dead_session(self._sessions.get(session_id))
    
    def _cleanup_dead_session(self, session: Session):
        """Limpia una sesi�n con daemon muerto."""
        if not session:
            return
        
        session_id = session.id
        
        # Forzar cierre del proceso Godot si sigue vivo
        if session.godot_daemon:
            try:
                session.godot_daemon.kill()
            except Exception:
                pass
        
        # Limpiar cach�
        session.scene_cache.clear()
        session.resource_cache.clear()
        
        # Eliminar de sesiones activas
        with self._sessions_lock:
            self._sessions.pop(session_id, None)
        
        logger.info(f"[Daemon] Sesi�n muerta limpiada: {session_id}")
    
    def start_session(
        self,
        project_path: str,
        godot_path: Optional[str] = None,
        use_server: bool = False,  # GodotServer HTTP (legacy, no funciona en headless)
        use_daemon: bool = True,   # GodotDaemon WebSocket (NUEVO - recomendado)
    ) -> Session:
        """
        Inicia una nueva sesi�n.
        
        Args:
            project_path: Ruta absoluta al proyecto Godot
            godot_path: Ruta al ejecutable de Godot (auto-detecta si no se proporciona)
        
        Returns:
            Sesi�n activa
        """
        project_path = os.path.abspath(project_path)
        
        if not os.path.exists(project_path):
            raise ValueError(f"Proyecto no encontrado: {project_path}")
        
        if not os.path.exists(os.path.join(project_path, "project.godot")):
            raise ValueError(f"No es un proyecto Godot v�lido: {project_path}")
        
        # Reutilizar sesi�n existente para el mismo proyecto (solo si daemon sigue vivo)
        with self._sessions_lock:
            for session in list(self._sessions.values()):
                if session.project_path == project_path:
                    # Verificar si el daemon sigue vivo
                    if session.godot_daemon and session.godot_daemon.is_alive():
                        logger.info(f"Sesi�n reutilizada: {session.id} | Proyecto: {project_path}")
                        session.touch()
                        return session
                    else:
                        # Daemon muri�, limpiar sesi�n vieja
                        logger.warning(f"[Daemon] Sesi�n {session.id} tiene daemon muerto. Limpiando...")
                        self._cleanup_dead_session(session)
                        break
        
        # Auto-detectar Godot
        if godot_path is None:
            godot_path = self._find_godot_executable()
        
        if not os.path.exists(godot_path):
            raise ValueError(f"Godot no encontrado: {godot_path}")
        
        # Crear sesi�n
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
        
        # Verificar que Godot funciona
        self._verify_godot(godot_path)
        
        # Iniciar GodotDaemon (WebSocket persistent server) si se solicita
        if use_daemon:
            try:
                logger.info(f"[Daemon] Iniciando GodotDaemon para sesi�n {session_id}...")
                daemon = GodotDaemon(
                    project_path=project_path,
                    godot_path=godot_path
                )
                if daemon.start():
                    session.godot_daemon = daemon
                    logger.info(f"[Daemon] GodotDaemon iniciado en puerto {daemon.port}")
                else:
                    logger.warning("[Daemon] No se pudo iniciar GodotDaemon. Usando scripts temporales.")
                    session.godot_daemon = None
            except Exception as e:
                logger.warning(f"[Daemon] Error iniciando GodotDaemon: {e}. Usando scripts temporales.")
                session.godot_daemon = None
        else:
            session.godot_daemon = None
        
        # Iniciar GodotServer (HTTP legacy) solo si se solicita expl�citamente
        if use_server and not use_daemon:
            try:
                logger.info(f"Iniciando GodotServer legacy para sesi�n {session_id}...")
                session.godot_server = GodotServer(
                    project_path=project_path,
                    godot_exe=godot_path
                )
                logger.info(f"GodotServer iniciado en puerto {session.godot_server.port}")
            except Exception as e:
                logger.warning(f"No se pudo iniciar GodotServer: {e}")
                session.godot_server = None
        
        with self._sessions_lock:
            self._sessions[session_id] = session
        
        logger.info(f"Sesi�n iniciada: {session_id} | Proyecto: {project_path}")
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
            "Godot no encontrado. Proporciona godot_path o a�ade Godot al PATH."
        )
    
    def _verify_godot(self, godot_path: str):
        """Verifica que Godot funciona."""
        try:
            result = subprocess.run(
                [godot_path, "--version"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode != 0:
                raise RuntimeError(f"Godot no responde: {result.stderr}")
            logger.info(f"Godot version: {result.stdout.strip()}")
        except Exception as e:
            raise RuntimeError(f"No se pudo verificar Godot: {e}")
    
    def execute_gdscript(
        self,
        session_id: str,
        script_content: str,
        timeout: float = 30.0,
    ) -> dict:
        """
        Ejecuta c�digo GDScript via Godot CLI --script.
        
        Args:
            session_id: ID de la sesi�n
            script_content: C�digo GDScript (debe extender SceneTree)
            timeout: Timeout en segundos
        
        Returns:
            Resultado con success, output, errors, test_output
        """
        session = self.get_session(session_id)
        if not session:
            return {"success": False, "error": f"Sesi�n no encontrada: {session_id}"}
        
        session.touch()
        
        # Crear archivo temporal
        script_file = os.path.join(
            tempfile.gettempdir(), f"heren_{session_id}_{uuid.uuid4().hex[:8]}.gd"
        )
        self._temp_files.append(script_file)
        
        try:
            with open(script_file, "w", encoding="utf-8") as f:
                f.write(script_content)
            
            # Ejecutar Godot
            cmd = [
                session.project_state.godot_path,
                "--headless",
                "--path", session.project_path,
                "--script", script_file,
            ]
            
            logger.debug(f"Ejecutando Godot: {' '.join(cmd)}")
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            # Parsear output
            output_lines = result.stdout.strip().split("\n") if result.stdout else []
            error_lines = result.stderr.strip().split("\n") if result.stderr else []
            
            # Buscar TEST_OUTPUT
            test_output = None
            for line in output_lines:
                if line.startswith("TEST_OUTPUT:"):
                    try:
                        test_output = json.loads(line[12:].strip())
                    except json.JSONDecodeError:
                        test_output = line[12:].strip()
                    break
            
            return {
                "success": result.returncode == 0,
                "output": output_lines,
                "errors": error_lines,
                "test_output": test_output,
                "exit_code": result.returncode,
            }
            
        except subprocess.TimeoutExpired:
            return {"success": False, "error": f"Timeout ejecutando script (>{timeout}s)"}
        except Exception as e:
            logger.error(f"Error ejecutando GDScript: {e}")
            return {"success": False, "error": str(e)}
        finally:
            # Limpiar archivo temporal
            try:
                if os.path.exists(script_file):
                    os.remove(script_file)
                    self._temp_files.remove(script_file)
            except Exception:
                pass
    
    def get_godot_server(self, session_id: str) -> Optional[GodotServer]:
        """Obtiene el GodotServer de una sesi�n."""
        session = self.get_session(session_id)
        if session and session.godot_server and session.godot_server.is_alive():
            return session.godot_server
        return None
    
    def get_godot_daemon(self, session_id: str) -> Optional[GodotDaemon]:
        """Obtiene el GodotDaemon de una sesi�n."""
        session = self.get_session(session_id)
        if session and session.godot_daemon and session.godot_daemon.is_alive():
            return session.godot_daemon
        return None
    
    def execute_via_daemon(
        self,
        session_id: str,
        method: str,
        params: dict
    ) -> dict:
        """Ejecuta una operaci�n via GodotDaemon (WebSocket)."""
        daemon = self.get_godot_daemon(session_id)
        if not daemon:
            return {
                "success": False,
                "error": "daemon_not_available",
                "message": "GodotDaemon no est� disponible para esta sesi�n"
            }
        
        session = self.get_session(session_id)
        if session:
            session.touch()
        
        return daemon.call(method, params)
    
    def execute_batch_via_daemon(
        self,
        session_id: str,
        operations: list,
        stop_on_error: bool = False
    ) -> dict:
        """Ejecuta m�ltiples operaciones via GodotDaemon en una sola llamada."""
        daemon = self.get_godot_daemon(session_id)
        if not daemon:
            return {
                "success": False,
                "error": "daemon_not_available",
                "message": "GodotDaemon no est� disponible para esta sesi�n"
            }
        
        session = self.get_session(session_id)
        if session:
            session.touch()
        
        return daemon.batch(operations, stop_on_error)
    
    def get_session(self, session_id: str) -> Optional[Session]:
        """Obtiene una sesi�n por ID."""
        with self._sessions_lock:
            session = self._sessions.get(session_id)
            if session:
                session.touch()
            return session
    
    def get_active_session(self) -> Optional[Session]:
        """Obtiene la sesi�n m�s reciente (�ltima actividad)."""
        with self._sessions_lock:
            if not self._sessions:
                return None
            # Retornar la sesi�n con last_activity m�s reciente
            return max(self._sessions.values(), key=lambda s: s.last_activity)
    
    def list_sessions(self) -> list[Session]:
        """Lista todas las sesiones activas."""
        with self._sessions_lock:
            return list(self._sessions.values())
    
    def end_session(self, session_id: str) -> bool:
        """
        Termina una sesi�n.
        
        Returns:
            True si se cerr� correctamente
        """
        with self._sessions_lock:
            session = self._sessions.pop(session_id, None)
        
        if not session:
            return False
        
        # Detener GodotDaemon
        if session.godot_daemon:
            try:
                session.godot_daemon.stop()
                logger.info(f"[Daemon] GodotDaemon detenido para sesi�n {session_id}")
            except Exception as e:
                logger.warning(f"[Daemon] Error deteniendo GodotDaemon: {e}")
        
        # Detener GodotServer (legacy)
        if session.godot_server:
            try:
                session.godot_server.stop()
                logger.info(f"GodotServer detenido para sesi�n {session_id}")
            except Exception as e:
                logger.warning(f"Error deteniendo GodotServer: {e}")
        
        # Limpiar cach�
        session.scene_cache.clear()
        session.resource_cache.clear()
        
        logger.info(f"Sesi�n terminada: {session_id}")
        return True
    
    def cleanup_temp_files(self):
        """Limpia archivos temporales."""
        for file_path in self._temp_files:
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
            except Exception:
                pass
        self._temp_files.clear()
    
    def shutdown_all(self):
        """Cierra todas las sesiones."""
        self._shutdown = True
        
        with self._sessions_lock:
            session_ids = list(self._sessions.keys())
        
        for session_id in session_ids:
            self.end_session(session_id)
        
        self.cleanup_temp_files()
        logger.info("Todas las sesiones cerradas")


# Singleton global
session_manager = SessionManager()


def get_session_manager() -> SessionManager:
    """Obtiene el Session Manager global."""
    return session_manager
