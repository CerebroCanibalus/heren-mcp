"""
Heren MCP - Godot CLI Interface (Capa 1)

Capa de abstracci�n entre las Tools y el Session Manager.
Proporciona m�todos de alto nivel para operaciones comunes.
Maneja reintentos, timeouts, y errores.

Filosof�a: Poder. Eficiencia. Rapidez.
"""

import json
import logging
from typing import Any, Optional

from heren.core.session_manager import SessionManager, get_session_manager
from heren.templates.gdscript_templates import TemplateEngine

logger = logging.getLogger(__name__)


class GodotInterface:
    """
    Interfaz de alto nivel para comunicaci�n con Godot.
    
    Esta clase encapsula la l�gica de:
    - Generar scripts GDScript temporales
    - Ejecutar via Session Manager
    - Procesar respuestas
    - Actualizar cach�
    """
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.session_manager = get_session_manager()
        self._session = None
    
    @property
    def session(self):
        """Obtiene la sesi�n actual (lazy load)."""
        if self._session is None:
            self._session = self.session_manager.get_session(self.session_id)
        return self._session
    
    def _execute_template(self, template_name: str, **kwargs) -> dict:
        """
        Genera y ejecuta un template GDScript.
        
        Args:
            template_name: Nombre del template
            **kwargs: Variables del template
        
        Returns:
            Resultado de Godot
        """
        if not self.session:
            return {"success": False, "error": "Sesi�n no activa"}
        
        # Generar script
        script_content = TemplateEngine.render(template_name, **kwargs)
        
        # Ejecutar
        result = self.session_manager.execute_gdscript(
            self.session_id,
            script_content,
        )
        
        # Extraer test_output
        if result.get("success") and result.get("test_output"):
            return result["test_output"]
        
        # Si el script ejecutó bien pero no hay test_output, puede ser error de sintaxis
        if result.get("success") and not result.get("test_output"):
            # Revisar si hay errores en stderr
            errors = result.get("errors", [])
            script_errors = [e for e in errors if "SCRIPT ERROR" in e or "ERROR" in e]
            if script_errors:
                return {
                    "success": False,
                    "error": "Error en script GDScript: " + script_errors[0],
                    "godot_errors": errors,
                }
            return {
                "success": False,
                "error": "Script ejecutado pero no produjo output. Verifica que imprima TEST_OUTPUT.",
                "godot_output": result.get("output", []),
            }
        
        return {
            "success": False,
            "error": result.get("error", "Error desconocido ejecutando template"),
            "godot_output": result.get("output", []),
            "godot_errors": result.get("errors", []),
        }
    
    # ============ Scene Operations ============
    
    def get_scene_tree(self, scene_path: str) -> dict:
        """Obtiene el �rbol de nodos de una escena."""
        # Verificar cach�
        cache_key = f"scene_tree:{scene_path}"
        cached = self.session.scene_cache.get(cache_key)
        
        if cached:
            logger.debug(f"Cache hit: {scene_path}")
            return cached
        
        # Obtener de Godot
        result = self._execute_template("get_scene_tree", scene_path=scene_path)
        
        if result.get("success"):
            self.session.scene_cache.set(cache_key, result)
        
        return result
    
    def save_scene(self, scene_path: str) -> dict:
        """Guarda una escena."""
        result = self._execute_template("save_scene", scene_path=scene_path)
        
        if result.get("success"):
            # Invalidar cach� de esta escena
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
        """A�ade un nodo a una escena."""
        result = self._execute_template(
            "add_node",
            scene_path=scene_path,
            parent_path=parent_path,
            node_type=node_type,
            node_name=node_name,
            properties_json=properties or {},
        )
        
        if result.get("success"):
            # Invalidar cach�
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def remove_node(self, scene_path: str, node_path: str) -> dict:
        """Elimina un nodo de una escena."""
        result = self._execute_template(
            "remove_node",
            scene_path=scene_path,
            node_path=node_path,
        )
        
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
        result = self._execute_template(
            "set_property",
            scene_path=scene_path,
            node_path=node_path,
            property=property_name,
            value_json=value,
        )
        
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def get_node_properties(self, scene_path: str, node_path: str) -> dict:
        """Obtiene todas las propiedades de un nodo."""
        return self._execute_template(
            "get_node_properties",
            scene_path=scene_path,
            node_path=node_path,
        )
    
    # ============ Project Operations ============
    
    def get_project_info(self) -> dict:
        """Obtiene informaci�n del proyecto."""
        return self._execute_template(
            "get_project_info",
            project_path=self.session.project_path,
        )
    
    # ============ Batch Operations ============
    
    def batch_execute(self, operations: list[dict]) -> dict:
        """
        Ejecuta m�ltiples operaciones en batch.
        
        Args:
            operations: Lista de operaciones
                [{"action": "add_node", "params": {...}}, ...]
        
        Returns:
            Resultados de todas las operaciones
        """
        results = []
        
        for op in operations:
            template_name = op["action"]
            params = op.get("params", {})
            
            result = self._execute_template(template_name, **params)
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
