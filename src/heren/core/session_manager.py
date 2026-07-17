"""
Heren MCP - Session Manager (Capa 0)

El nucleo del sistema. Se inicializa primero. Sin sesion, no hay operaciones.
Gestiona cache agresiva y mantiene GodotDaemon persistente via WebSocket.

Filosofia: Poder. Eficiencia. Rapidez.
Modo UNICO: GodotDaemon. Sin fallback a scripts CLI.
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
from typing import Any, Optional

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

    def to_dict(self) -> dict:
        return {
            "project_path": self.project_path,
            "godot_path": self.godot_path,
        }


@dataclass
class Session:
    """Una sesion activa con un proyecto Godot."""
    id: str
    project_path: str
    project_state: ProjectState
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)

    scene_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=50, ttl_seconds=300))
    resource_cache: LRUCache = field(default_factory=lambda: LRUCache(max_size=100, ttl_seconds=300))

    godot_daemon: Optional[GodotDaemon] = None
    daemon_error: Optional[str] = None

    operations: list = field(default_factory=list)
    undo_stack: list = field(default_factory=list)
    redo_stack: list = field(default_factory=list)

    def touch(self):
        self.last_activity = time.time()

    def is_expired(self, timeout_seconds: float = 3600) -> bool:
        return time.time() - self.last_activity > timeout_seconds


class SessionManager:
    """
    Gestor de sesiones Heren MCP. Singleton.

    Solo soporta GodotDaemon (WebSocket). Sin fallback a scripts CLI.
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

        self._start_cleanup_thread()

    def _start_cleanup_thread(self):
        def cleanup_loop():
            heartbeat_counter = 0
            while not self._shutdown:
                time.sleep(60)
                self._cleanup_expired_sessions()

                heartbeat_counter += 1
                if heartbeat_counter >= 2:
                    heartbeat_counter = 0
                    with self._sessions_lock:
                        sessions_copy = list(self._sessions.values())
                    for session in sessions_copy:
                        if session.godot_daemon and session.godot_daemon.is_alive():
                            self.send_daemon_heartbeat(session.id)

        self._cleanup_thread = threading.Thread(target=cleanup_loop, daemon=True)
        self._cleanup_thread.start()

    def send_daemon_heartbeat(self, session_id: str) -> bool:
        session = self.get_session(session_id)
        if not session or not session.godot_daemon:
            return False
        try:
            result = session.godot_daemon.call("ping", {})
            return result.get("success", False)
        except Exception as e:
            logger.warning(f"[Heartbeat] Daemon no responde para sesion {session_id}: {e}")
            return False

    def _cleanup_expired_sessions(self):
        expired = []
        dead_daemons = []

        with self._sessions_lock:
            for session_id, session in list(self._sessions.items()):
                if session.is_expired():
                    expired.append(session_id)
                elif session.godot_daemon and not session.godot_daemon.is_alive():
                    dead_daemons.append(session_id)

        for session_id in expired:
            logger.info(f"Sesion expirada: {session_id}")
            self.end_session(session_id)

        for session_id in dead_daemons:
            logger.warning(f"[Daemon] Sesion {session_id} tiene daemon muerto. Limpiando...")
            self._cleanup_dead_session(self._sessions.get(session_id))

    def _cleanup_dead_session(self, session: Session):
        if not session:
            return
        session_id = session.id

        if session.godot_daemon:
            try:
                session.godot_daemon.kill()
            except Exception:
                pass

        session.scene_cache.clear()
        session.resource_cache.clear()

        with self._sessions_lock:
            self._sessions.pop(session_id, None)

        logger.info(f"[Daemon] Sesion muerta limpiada: {session_id}")

    def start_session(
        self,
        project_path: str,
        godot_path: Optional[str] = None,
    ) -> Session:
        project_path = os.path.abspath(project_path)

        if not os.path.exists(project_path):
            raise ValueError(f"Proyecto no encontrado: {project_path}")

        if not os.path.exists(os.path.join(project_path, "project.godot")):
            raise ValueError(
                f"No es un proyecto Godot valido: {project_path}\n"
                f"No se encontro project.godot. "
                f"Crea el proyecto primero con: project('create', ...)"
            )

        with self._sessions_lock:
            for session in list(self._sessions.values()):
                if session.project_path == project_path:
                    if session.godot_daemon and session.godot_daemon.is_alive():
                        logger.info(f"Sesion reutilizada: {session.id} | Proyecto: {project_path}")
                        session.touch()
                        return session
                    else:
                        logger.warning(f"[Daemon] Sesion {session.id} tiene daemon muerto. Limpiando...")
                        self._cleanup_dead_session(session)
                        break

        if godot_path is None:
            godot_path = self._find_godot_executable()

        if not os.path.exists(godot_path):
            raise ValueError(f"Godot no encontrado: {godot_path}")

        daemon_script = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "daemon", "heren_daemon.gd"
        )
        if not os.path.exists(daemon_script):
            raise RuntimeError(
                f"Daemon no encontrado: {daemon_script}\n"
                f"Reinstala el paquete heren-mcp."
            )

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

        daemon = self._start_daemon_with_retry(session_id, project_path, godot_path)
        if daemon:
            session.godot_daemon = daemon
        else:
            daemon_error = (
                "GodotDaemon no pudo iniciarse tras 3 intentos. Posibles causas:\n"
                "1. Godot no tiene permisos para ejecutar scripts\n"
                "2. El proyecto tiene errores que impiden iniciar\n"
                "3. Puerto bloqueado por firewall\n"
                "4. El proyecto no tiene el addon heren configurado\n\n"
                "Solucion: Ejecuta project('setup_daemon', project_path='...') "
                "para configurar el daemon en este proyecto."
            )
            logger.warning(f"[Daemon] {daemon_error}")
            session.daemon_error = daemon_error

        with self._sessions_lock:
            self._sessions[session_id] = session

        logger.info(f"Sesion iniciada: {session_id} | Proyecto: {project_path}")
        return session

    def _find_godot_executable(self) -> str:
        env_godot = os.environ.get("GODOT_EXE") or os.environ.get("GODOT_PATH")
        if env_godot and os.path.exists(env_godot):
            return env_godot

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

            for path in os.environ.get("PATH", "").split(os.pathsep):
                for name in ["godot.exe", "Godot.exe"]:
                    full = os.path.join(path.strip('"'), name)
                    if os.path.exists(full):
                        return full
        else:
            import shutil
            godot = shutil.which("godot")
            if godot:
                return godot

        raise RuntimeError(
            "Godot no encontrado. Proporciona godot_path o anade Godot al PATH."
        )

    def _start_daemon_with_retry(self, session_id: str, project_path: str, godot_path: str, max_retries: int = 3) -> Optional[GodotDaemon]:
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(f"[Daemon] Intento {attempt}/{max_retries} de iniciar GodotDaemon para sesion {session_id}...")
                daemon = GodotDaemon(
                    project_path=project_path,
                    godot_path=godot_path
                )
                if daemon.start():
                    logger.info(f"[Daemon] GodotDaemon iniciado en puerto {daemon.port} (intento {attempt})")
                    return daemon
                else:
                    logger.warning(f"[Daemon] Intento {attempt} fallo: daemon.start() retorno False")
            except Exception as e:
                logger.warning(f"[Daemon] Intento {attempt} fallo con excepcion: {e}")

            if attempt < max_retries:
                delay = attempt * 2
                logger.info(f"[Daemon] Esperando {delay}s antes del siguiente intento...")
                time.sleep(delay)

        logger.error(f"[Daemon] Todos los intentos fallaron despues de {max_retries} reintentos")
        return None

    def get_godot_daemon(self, session_id: str) -> Optional[GodotDaemon]:
        session = self.get_session(session_id)
        if session and session.godot_daemon and session.godot_daemon.is_alive():
            return session.godot_daemon
        return None

    def execute_via_daemon(
        self,
        session_id: str,
        method: str,
        params: dict,
        retries: int = 1
    ) -> dict:
        session = self.get_session(session_id)
        if not session:
            return {
                "success": False,
                "error": "session_not_found",
                "message": f"Sesion no encontrada: {session_id}"
            }

        for attempt in range(retries + 1):
            daemon = self.get_godot_daemon(session_id)
            if not daemon:
                if attempt < retries:
                    logger.warning(f"[Daemon] Intento {attempt + 1}: daemon no disponible, reintentando...")
                    time.sleep(1)
                    continue
                return {
                    "success": False,
                    "error": "daemon_not_available",
                    "message": "GodotDaemon no esta disponible para esta sesion"
                }

            try:
                result = daemon.call(method, params)
                session.touch()
                return result
            except Exception as e:
                if attempt < retries:
                    logger.warning(f"[Daemon] Intento {attempt + 1} fallo para {method}: {e}, reintentando...")
                    time.sleep(1)
                else:
                    logger.error(f"[Daemon] Fallo despues de {retries} reintentos: {e}")
                    return {"success": False, "error": str(e)}

        return {"success": False, "error": "daemon_unavailable_after_retries"}

    def execute_batch_via_daemon(
        self,
        session_id: str,
        operations: list,
        stop_on_error: bool = False
    ) -> dict:
        daemon = self.get_godot_daemon(session_id)
        if not daemon:
            return {
                "success": False,
                "error": "daemon_not_available",
                "message": "GodotDaemon no esta disponible para esta sesion"
            }

        session = self.get_session(session_id)
        if session:
            session.touch()

        return daemon.batch(operations, stop_on_error)

    def get_session(self, session_id: str) -> Optional[Session]:
        with self._sessions_lock:
            session = self._sessions.get(session_id)
            if session:
                session.touch()
            return session

    def get_active_session(self) -> Optional[Session]:
        with self._sessions_lock:
            if not self._sessions:
                return None
            return max(self._sessions.values(), key=lambda s: s.last_activity)

    def list_sessions(self) -> list[Session]:
        with self._sessions_lock:
            return list(self._sessions.values())

    def end_session(self, session_id: str) -> bool:
        with self._sessions_lock:
            session = self._sessions.pop(session_id, None)

        if not session:
            return False

        if session.godot_daemon:
            try:
                session.godot_daemon.stop()
                logger.info(f"[Daemon] GodotDaemon detenido para sesion {session_id}")
            except Exception as e:
                logger.warning(f"[Daemon] Error deteniendo GodotDaemon: {e}")

        session.scene_cache.clear()
        session.resource_cache.clear()

        logger.info(f"Sesion terminada: {session_id}")
        return True

    def shutdown_all(self):
        self._shutdown = True
        with self._sessions_lock:
            session_ids = list(self._sessions.keys())
        for session_id in session_ids:
            self.end_session(session_id)
        logger.info("Todas las sesiones cerradas")


session_manager = SessionManager()


def get_session_manager() -> SessionManager:
    return session_manager
