"""
Heren MCP - Godot CLI Interface (Capa 1)

Capa de abstracción entre las Tools y el Session Manager.
Proporciona métodos de alto nivel para operaciones comunes.
Maneja reintentos, timeouts, y errores.

Filosofía: Poder. Eficiencia. Rapidez.
"""

import logging
from typing import Any, Optional

from heren.core.session_manager import SessionManager, get_session_manager

logger = logging.getLogger(__name__)


class GodotInterface:
    """
    Interfaz de alto nivel para comunicación con Godot.
    
    Esta clase encapsula la lógica de:
    - Enviar comandos al Session Manager
    - Manejar timeouts y reintentos
    - Procesar respuestas
    - Actualizar caché
    """
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.session_manager = get_session_manager()
        self._session = None
    
    @property
    def session(self):
        """Obtiene la sesión actual (lazy load)."""
        if self._session is None:
            self._session = self.session_manager.get_session(self.session_id)
        return self._session
    
    def _send(
        self,
        action: str,
        params: dict = None,
        timeout: float = 30.0,
    ) -> dict:
        """
        Envía un comando a Godot y devuelve la respuesta.
        
        Args:
            action: Nombre de la acción
            params: Parámetros
            timeout: Timeout en segundos
        
        Returns:
            Respuesta de Godot
        """
        if not self.session:
            return {"success": False, "error": "Sesión no activa"}
        
        result = self.session_manager.send_command(
            self.session_id,
            action,
            params or {},
        )
        
        return result
    
    # ============ Scene Operations ============
    
    def get_scene_tree(self, scene_path: str) -> dict:
        """Obtiene el árbol de nodos de una escena."""
        # Verificar caché
        cache_key = f"scene_tree:{scene_path}"
        cached = self.session.scene_cache.get(cache_key)
        
        if cached:
            logger.debug(f"Cache hit: {scene_path}")
            return cached
        
        # Obtener de Godot
        result = self._send("get_scene_tree", {"scene_path": scene_path})
        
        if result.get("success"):
            self.session.scene_cache.set(cache_key, result)
        
        return result
    
    def save_scene(self, scene_path: str) -> dict:
        """Guarda una escena."""
        result = self._send("save_scene", {"scene_path": scene_path})
        
        if result.get("success"):
            # Invalidar caché de esta escena
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    # ============ Node Operations ============
    
    def add_node(
        self,
        scene_path: str,
        parent_path: str,
        node_type: str,
        node_name: str,
        properties: dict = None,
    ) -> dict:
        """Añade un nodo a una escena."""
        result = self._send("add_node", {
            "scene_path": scene_path,
            "parent_path": parent_path,
            "node_type": node_type,
            "node_name": node_name,
            "properties": properties or {},
        })
        
        if result.get("success"):
            # Invalidar caché
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def remove_node(self, scene_path: str, node_path: str) -> dict:
        """Elimina un nodo de una escena."""
        result = self._send("remove_node", {
            "scene_path": scene_path,
            "node_path": node_path,
        })
        
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def set_property(
        self,
        scene_path: str,
        node_path: str,
        property_name: str,
        value: Any,
    ) -> dict:
        """Cambia una propiedad de un nodo."""
        result = self._send("set_property", {
            "scene_path": scene_path,
            "node_path": node_path,
            "property": property_name,
            "value": value,
        })
        
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def get_node_properties(self, scene_path: str, node_path: str) -> dict:
        """Obtiene todas las propiedades de un nodo."""
        return self._send("get_node_properties", {
            "scene_path": scene_path,
            "node_path": node_path,
        })
    
    # ============ Project Operations ============
    
    def get_project_info(self) -> dict:
        """Obtiene información del proyecto."""
        return self._send("get_project_info", {
            "project_path": self.session.project_path,
        })
    
    # ============ Batch Operations ============
    
    def batch_execute(self, operations: list[dict]) -> dict:
        """
        Ejecuta múltiples operaciones en batch.
        
        Args:
            operations: Lista de operaciones
                [{"action": "add_node", "params": {...}}, ...]
        
        Returns:
            Resultados de todas las operaciones
        """
        results = []
        
        for op in operations:
            result = self._send(op["action"], op.get("params", {}))
            results.append(result)
            
            # Si una falla, podemos parar o continuar
            if not result.get("success") and op.get("stop_on_error", True):
                break
        
        return {
            "success": all(r.get("success") for r in results),
            "results": results,
            "completed": len(results),
            "total": len(operations),
        }


def create_interface(session_id: str) -> GodotInterface:
    """Factory para crear una interfaz Godot."""
    return GodotInterface(session_id)
