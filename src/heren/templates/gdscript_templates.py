"""
Heren MCP - GDScript Templates

Templates para generar scripts GDScript temporales.
Cada template genera un script aut�nomo que se ejecuta con Godot --script.
Usa f-strings para inyecci�n segura de valores.

Filosof�a: Poder. Eficiencia. Rapidez.
"""

import json


def _escape_gdscript_string(value: str) -> str:
    """Escapa un string para usar en GDScript."""
    return value.replace('"', '\\"').replace("\\", "\\\\")


class TemplateEngine:
    """Motor de templates para GDScript usando f-strings."""
    
    @classmethod
    def render(cls, template_name: str, **kwargs) -> str:
        """
        Renderiza un template con variables.
        
        Args:
            template_name: Nombre del template
            **kwargs: Variables para sustituir
        
        Returns:
            GDScript generado
        """
        renderer = getattr(cls, f"_render_{template_name}", None)
        if not renderer:
            raise ValueError(f"Template no encontrado: {template_name}")
        
        return renderer(**kwargs)
    
    @classmethod
    def _render_get_scene_tree(cls, scene_path: str, **kwargs) -> str:
        """Template para obtener el �rbol de nodos de una escena."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var packed_scene = load(scene_path)
    
    if packed_scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo cargar la escena: ' + scene_path + '"}}')
        quit()
        return
    
    var scene = packed_scene.instantiate()
    if scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo instanciar la escena"}}')
        quit()
        return
    
    var nodes = []
    _collect_nodes(scene, nodes, "")
    scene.free()
    
    print('TEST_OUTPUT: ' + JSON.stringify({{
        "success": true,
        "scene_path": scene_path,
        "nodes": nodes
    }}))
    quit()

func _collect_nodes(node, nodes_array, parent_path):
    var path = node.name if parent_path == "" else parent_path + "/" + node.name
    var parent_name = "." if parent_path == "" else parent_path.split("/")[-1]
    
    var node_data = {{
        "name": node.name,
        "type": node.get_class(),
        "path": path,
        "parent": parent_name,
    }}
    
    if node is Node2D:
        node_data["position"] = {{"x": node.position.x, "y": node.position.y}}
        node_data["rotation"] = node.rotation
        node_data["scale"] = {{"x": node.scale.x, "y": node.scale.y}}
    elif node is Node3D:
        node_data["position"] = {{"x": node.position.x, "y": node.position.y, "z": node.position.z}}
        node_data["rotation"] = {{"x": node.rotation.x, "y": node.rotation.y, "z": node.rotation.z}}
        node_data["scale"] = {{"x": node.scale.x, "y": node.scale.y, "z": node.scale.z}}
    
    if node.get_script() != null:
        node_data["script"] = str(node.get_script().resource_path)
    
    node_data["groups"] = node.get_groups()
    
    nodes_array.append(node_data)
    
    for child in node.get_children():
        _collect_nodes(child, nodes_array, path)
'''
    
    @classmethod
    def _render_save_scene(cls, scene_path: str, **kwargs) -> str:
        """Template para guardar una escena."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var packed_scene = load(scene_path)
    
    if packed_scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo cargar la escena"}}')
        quit()
        return
    
    var result = ResourceSaver.save(packed_scene, scene_path)
    
    if result == OK:
        print('TEST_OUTPUT: {{"success": true, "scene_path": "' + scene_path + '"}}')
    else:
        print('TEST_OUTPUT: {{"success": false, "error": "Error guardando escena: ' + str(result) + '"}}')
    
    quit()
'''
    
    @classmethod
    def _render_add_node(cls, scene_path: str, parent_path: str, node_type: str, 
                         node_name: str, properties_json: dict = None, **kwargs) -> str:
        """Template para a�adir un nodo."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        parent_path_escaped = _escape_gdscript_string(parent_path)
        node_type_escaped = _escape_gdscript_string(node_type)
        node_name_escaped = _escape_gdscript_string(node_name)
        properties_str = json.dumps(properties_json or {}, ensure_ascii=False)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var parent_path = "{parent_path_escaped}"
    var node_type = "{node_type_escaped}"
    var node_name = "{node_name_escaped}"
    
    var packed_scene = load(scene_path)
    var scene
    var new_node = null
    var is_new_scene = false
    
    if packed_scene == null:
        # Crear nueva escena si no existe
        if parent_path != "." and parent_path != "":
            print('TEST_OUTPUT: {{"success": false, "error": "Escena no existe y parent no es root"}}')
            quit()
            return
        scene = ClassDB.instantiate(node_type)
        if scene == null:
            print('TEST_OUTPUT: {{"success": false, "error": "No se pudo crear nodo de tipo: ' + node_type + '"}}')
            quit()
            return
        scene.name = node_name
        packed_scene = PackedScene.new()
        new_node = scene
        is_new_scene = true
    else:
        scene = packed_scene.instantiate()
    
    if not is_new_scene:
        var parent
        if parent_path == scene.name or parent_path == "." or parent_path == "":
            parent = scene
        else:
            parent = scene.get_node_or_null(parent_path)
        
        if parent == null:
            scene.free()
            print('TEST_OUTPUT: {{"success": false, "error": "Nodo padre no encontrado: ' + parent_path + '"}}')
            quit()
            return
        
        # Verificar duplicados
        if parent.has_node(node_name):
            scene.free()
            print('TEST_OUTPUT: {{"success": false, "error": "Nodo ya existe: ' + node_name + '"}}')
            quit()
            return
        
        new_node = ClassDB.instantiate(node_type)
        if new_node == null:
            scene.free()
            print('TEST_OUTPUT: {{"success": false, "error": "No se pudo crear nodo de tipo: ' + node_type + '"}}')
            quit()
            return
        
        new_node.name = node_name
        parent.add_child(new_node)
        new_node.owner = scene
    
    # Set properties
    var properties = JSON.parse_string('{properties_str}')
    for prop_name in properties.keys():
        var value = dict_to_var(properties[prop_name])
        if new_node.get(prop_name) != null or new_node.get_property_list().any(func(p): return p.name == prop_name):
            new_node.set(prop_name, value)
    
    packed_scene.pack(scene)
    var save_result = ResourceSaver.save(packed_scene, scene_path)
    scene.free()
    
    if save_result == OK:
        var node_path_result = node_name if is_new_scene else parent_path + "/" + node_name
        print('TEST_OUTPUT: ' + JSON.stringify({{
            "success": true,
            "scene_path": scene_path,
            "node_name": node_name,
            "node_path": node_path_result
        }}))
    else:
        print('TEST_OUTPUT: {{"success": false, "error": "Error guardando: ' + str(save_result) + '"}}')
    
    quit()

func dict_to_var(val):
    if val is Dictionary:
        # Auto-detectar Vector2/Vector3/Color sin __type
        if val.has("x") and val.has("y") and val.has("z"):
            return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
        elif val.has("x") and val.has("y"):
            return Vector2(val.get("x", 0), val.get("y", 0))
        elif val.has("r") and val.has("g") and val.has("b"):
            return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
        # Con __type expl�cito
        elif val.has("__type"):
            match val["__type"]:
                "Vector2":
                    return Vector2(val.get("x", 0), val.get("y", 0))
                "Vector3":
                    return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
                "Color":
                    return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
    return val
'''
    
    @classmethod
    def _render_remove_node(cls, scene_path: str, node_path: str, **kwargs) -> str:
        """Template para eliminar un nodo."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        node_path_escaped = _escape_gdscript_string(node_path)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var node_path_str = "{node_path_escaped}"
    
    var packed_scene = load(scene_path)
    if packed_scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo cargar la escena"}}')
        quit()
        return
    
    var scene = packed_scene.instantiate()
    var node = scene.get_node_or_null(node_path_str)
    
    if node == null:
        scene.free()
        print('TEST_OUTPUT: {{"success": false, "error": "Nodo no encontrado: ' + node_path_str + '"}}')
        quit()
        return
    
    # Eliminar nodo y sus hijos
    _remove_node_recursive(node)
    
    packed_scene.pack(scene)
    var save_result = ResourceSaver.save(packed_scene, scene_path)
    scene.free()
    
    if save_result == OK:
        print('TEST_OUTPUT: ' + JSON.stringify({{"success": true, "removed_path": node_path_str}}))
    else:
        print('TEST_OUTPUT: ' + JSON.stringify({{"success": false, "error": "Error guardando: " + str(save_result)}}))
    
    quit()

func _remove_node_recursive(node):
    # Eliminar hijos primero
    while node.get_child_count() > 0:
        var child = node.get_child(0)
        _remove_node_recursive(child)
    # Eliminar nodo de su padre
    node.get_parent().remove_child(node)
    node.free()
'''
    
    @classmethod
    def _render_set_property(cls, scene_path: str, node_path: str, property: str,
                             value_json: any, **kwargs) -> str:
        """Template para cambiar una propiedad."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        node_path_escaped = _escape_gdscript_string(node_path)
        property_escaped = _escape_gdscript_string(property)
        value_str = json.dumps(value_json, ensure_ascii=False)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var node_path_str = "{node_path_escaped}"
    var property = "{property_escaped}"
    var value = dict_to_var(JSON.parse_string('{value_str}'))
    
    var packed_scene = load(scene_path)
    if packed_scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo cargar la escena"}}')
        quit()
        return
    
    var scene = packed_scene.instantiate()
    var node
    
    # Si node_path es el nombre del root o ".", usar scene directamente
    if node_path_str == scene.name or node_path_str == ".":
        node = scene
    else:
        node = scene.get_node_or_null(node_path_str)
    
    if node == null:
        scene.free()
        print('TEST_OUTPUT: {{"success": false, "error": "Nodo no encontrado: ' + node_path_str + '"}}')
        quit()
        return
    
    node.set(property, value)
    
    packed_scene.pack(scene)
    var save_result = ResourceSaver.save(packed_scene, scene_path)
    scene.free()
    
    if save_result == OK:
        print('TEST_OUTPUT: ' + JSON.stringify({{
            "success": true,
            "node_path": node_path_str,
            "property": property,
            "value": var_to_dict(value)
        }}))
    else:
        print('TEST_OUTPUT: {{"success": false, "error": "Error guardando: ' + str(save_result) + '"}}')
    
    quit()

func dict_to_var(val):
    if val is Dictionary and val.has("__type"):
        match val["__type"]:
            "Vector2":
                return Vector2(val.get("x", 0), val.get("y", 0))
            "Vector3":
                return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
            "Color":
                return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
    return val

func var_to_dict(val):
    if val is Vector2:
        return {{"__type": "Vector2", "x": val.x, "y": val.y}}
    elif val is Vector3:
        return {{"__type": "Vector3", "x": val.x, "y": val.y, "z": val.z}}
    elif val is Color:
        return {{"__type": "Color", "r": val.r, "g": val.g, "b": val.b, "a": val.a}}
    return val
'''
    
    @classmethod
    def _render_get_node_properties(cls, scene_path: str, node_path: str, **kwargs) -> str:
        """Template para obtener propiedades de un nodo."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        node_path_escaped = _escape_gdscript_string(node_path)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var node_path_str = "{node_path_escaped}"
    
    var packed_scene = load(scene_path)
    if packed_scene == null:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo cargar la escena"}}')
        quit()
        return
    
    var scene = packed_scene.instantiate()
    var node = scene.get_node_or_null(node_path_str)
    
    if node == null:
        scene.free()
        print('TEST_OUTPUT: {{"success": false, "error": "Nodo no encontrado: ' + node_path_str + '"}}')
        quit()
        return
    
    var properties = {{}}
    for prop in node.get_property_list():
        if prop.usage & PROPERTY_USAGE_EDITOR != 0 or prop.usage & PROPERTY_USAGE_STORAGE != 0:
            properties[prop.name] = var_to_dict(node.get(prop.name))
    
    scene.free()
    
    print('TEST_OUTPUT: ' + JSON.stringify({{
        "success": true,
        "node_path": node_path_str,
        "properties": properties
    }}))
    quit()

func var_to_dict(val):
    if val is Vector2:
        return {{"__type": "Vector2", "x": val.x, "y": val.y}}
    elif val is Vector3:
        return {{"__type": "Vector3", "x": val.x, "y": val.y, "z": val.z}}
    elif val is Color:
        return {{"__type": "Color", "r": val.r, "g": val.g, "b": val.b, "a": val.a}}
    return val
'''
    
    @classmethod
    def _render_get_project_info(cls, project_path: str, **kwargs) -> str:
        """Template para obtener informaci�n del proyecto."""
        project_path_escaped = _escape_gdscript_string(project_path)
        
        return f'''extends SceneTree

func _init():
    var project_path = "{project_path_escaped}"
    
    var config = ConfigFile.new()
    var err = config.load(project_path.path_join("project.godot"))
    
    if err != OK:
        print('TEST_OUTPUT: {{"success": false, "error": "No se pudo leer project.godot"}}')
        quit()
        return
    
    var features = config.get_value("application", "config/features", [])
    if features is PackedStringArray:
        features = Array(features)
    
    print('TEST_OUTPUT: ' + JSON.stringify({{
        "success": true,
        "project_name": config.get_value("application", "config/name", "Unknown"),
        "main_scene": config.get_value("application", "run/main_scene", ""),
        "version": features
    }}))
    quit()
'''
    
    @classmethod
    def _render_create_scene(cls, scene_path: str, root_type: str = "Node2D", root_name: str = "Root", **kwargs) -> str:
        """Template para crear una nueva escena."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var root_type = "{root_type}"
    var root_name = "{root_name}"
    
    # Check if file exists
    if FileAccess.file_exists(scene_path):
        print('TEST_OUTPUT: {{"success": false, "error": "Scene already exists"}}')
        quit()
        return
    
    # Create root node
    var root = ClassDB.instantiate(root_type)
    if root == null:
        print('TEST_OUTPUT: {{"success": false, "error": "Invalid root type"}}')
        quit()
        return
    
    root.name = root_name
    
    # Create PackedScene
    var packed = PackedScene.new()
    var err = packed.pack(root)
    if err != OK:
        root.free()
        print('TEST_OUTPUT: {{"success": false, "error": "Pack failed"}}')
        quit()
        return
    
    # Save
    err = ResourceSaver.save(packed, scene_path)
    root.free()
    
    if err != OK:
        print('TEST_OUTPUT: {{"success": false, "error": "Save failed"}}')
        quit()
        return
    
    print('TEST_OUTPUT: ' + JSON.stringify({{
        "success": true,
        "scene_path": scene_path,
        "root_type": root_type,
        "root_name": root_name
    }}))
    quit()
'''
    
    @classmethod
    def _render_delete_scene(cls, scene_path: str, **kwargs) -> str:
        """Template para eliminar una escena."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    
    if not FileAccess.file_exists(scene_path):
        print('TEST_OUTPUT: {{"success": false, "error": "Scene not found"}}')
        quit()
        return
    
    var err = DirAccess.remove_absolute(scene_path)
    if err != OK:
        print('TEST_OUTPUT: {{"success": false, "error": "Delete failed"}}')
        quit()
        return
    
    print('TEST_OUTPUT: {{"success": true, "deleted": "' + scene_path + '"}}')
    quit()
'''
    
    @classmethod
    def _render_rename_scene(cls, scene_path: str, new_path: str, **kwargs) -> str:
        """Template para renombrar una escena."""
        scene_path_escaped = _escape_gdscript_string(scene_path)
        new_path_escaped = _escape_gdscript_string(new_path)
        
        return f'''extends SceneTree

func _init():
    var scene_path = "{scene_path_escaped}"
    var new_path = "{new_path_escaped}"
    
    if not FileAccess.file_exists(scene_path):
        print('TEST_OUTPUT: {{"success": false, "error": "Scene not found"}}')
        quit()
        return
    
    if FileAccess.file_exists(new_path):
        print('TEST_OUTPUT: {{"success": false, "error": "Destination exists"}}')
        quit()
        return
    
    var err = DirAccess.rename_absolute(scene_path, new_path)
    if err != OK:
        print('TEST_OUTPUT: {{"success": false, "error": "Rename failed"}}')
        quit()
        return
    
    print('TEST_OUTPUT: ' + JSON.stringify({{
        "success": true,
        "old_path": scene_path,
        "new_path": new_path
    }}))
    quit()
'''
