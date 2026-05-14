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
        
        # Normalizar rutas a forward slashes para evitar problemas con JSON
        normalized_kwargs = {}
        for key, value in kwargs.items():
            if isinstance(value, str) and ('\\' in value or '/' in value):
                # Probablemente es una ruta
                normalized_kwargs[key] = value.replace('\\', '/')
            else:
                normalized_kwargs[key] = value
        
        # Generar script
        script_content = TemplateEngine.render(template_name, **normalized_kwargs)
        
        # Ejecutar
        result = self.session_manager.execute_gdscript(
            self.session_id,
            script_content,
        )
        
        # Extraer test_output
        test_output = result.get("test_output")
        
        if result.get("success") and test_output:
            # Asegurar que test_output sea un dict
            if isinstance(test_output, dict):
                return test_output
            else:
                # JSON malformado en TEST_OUTPUT
                return {
                    "success": False,
                    "error": f"TEST_OUTPUT malformado: {test_output}",
                    "godot_output": result.get("output", []),
                }
        
        # Si el script ejecutó bien pero no hay test_output, puede ser error de sintaxis
        if result.get("success") and not test_output:
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
    
    def create_scene(self, scene_path: str, root_type: str = "Node2D", root_name: str = "Root") -> dict:
        """Crea una nueva escena."""
        result = self._execute_template(
            "create_scene",
            scene_path=scene_path,
            root_type=root_type,
            root_name=root_name
        )
        return result
    
    def delete_scene(self, scene_path: str) -> dict:
        """Elimina una escena."""
        result = self._execute_template("delete_scene", scene_path=scene_path)
        
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        
        return result
    
    def rename_scene(self, scene_path: str, new_path: str) -> dict:
        """Renombra una escena."""
        result = self._execute_template(
            "rename_scene",
            scene_path=scene_path,
            new_path=new_path
        )
        
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
            self.session.scene_cache.invalidate(f"scene_tree:{new_path}")
        
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
    
    # ============ Signal Operations ============
    
    def connect_signal(self, scene_path: str, from_node: str, signal_name: str,
                       to_node: str, method: str) -> dict:
        """Conecta una señal entre nodos."""
        result = self._execute_template(
            "connect_signal",
            scene_path=scene_path,
            from_node=from_node,
            signal_name=signal_name,
            to_node=to_node,
            method=method,
        )
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        return result
    
    def disconnect_signal(self, scene_path: str, from_node: str, signal_name: str,
                          to_node: str, method: str) -> dict:
        """Desconecta una señal entre nodos."""
        result = self._execute_template(
            "disconnect_signal",
            scene_path=scene_path,
            from_node=from_node,
            signal_name=signal_name,
            to_node=to_node,
            method=method,
        )
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        return result
    
    def list_signals(self, scene_path: str, node_path: str) -> dict:
        """Lista las señales de un nodo."""
        return self._execute_template(
            "list_signals",
            scene_path=scene_path,
            node_path=node_path,
        )
    
    def set_script(self, scene_path: str, node_path: str, script_path: str) -> dict:
        """Asigna un script a un nodo."""
        result = self._execute_template(
            "set_script",
            scene_path=scene_path,
            node_path=node_path,
            script_path=script_path,
        )
        if result.get("success"):
            self.session.scene_cache.invalidate(f"scene_tree:{scene_path}")
        return result
    
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
