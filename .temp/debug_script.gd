extends SceneTree

func _init():
    var scene_path = "res://src/infra/main_scene.tscn"
    var parent_path = "UI Holder"
    var node_type = "Control"
    var node_name = "DebugPanel"
    
    var packed_scene = load(scene_path)
    if packed_scene == null:
        print('TEST_OUTPUT: {"success": false, "error": "No se pudo cargar la escena"}')
        quit()
        return
    
    var scene = packed_scene.instantiate()
    var parent = scene.get_node_or_null(parent_path)
    
    if parent == null:
        scene.free()
        print('TEST_OUTPUT: {"success": false, "error": "Nodo padre no encontrado: ' + parent_path + '"}')
        quit()
        return
    
    var new_node = ClassDB.instantiate(node_type)
    if new_node == null:
        scene.free()
        print('TEST_OUTPUT: {"success": false, "error": "No se pudo crear nodo de tipo: ' + node_type + '"}')
        quit()
        return
    
    new_node.name = node_name
    parent.add_child(new_node)
    new_node.owner = scene
    
    # Set properties
    var properties = JSON.parse_string('{"position": {"__type": "Vector2", "x": 20, "y": 20}}')
    for prop_name in properties.keys():
        var value = dict_to_var(properties[prop_name])
        if new_node.get(prop_name) != null or new_node.get_property_list().any(func(p): return p.name == prop_name):
            new_node.set(prop_name, value)
    
    packed_scene.pack(scene)
    var save_result = ResourceSaver.save(packed_scene, scene_path)
    scene.free()
    
    if save_result == OK:
        print('TEST_OUTPUT: ' + JSON.stringify({
            "success": true,
            "scene_path": scene_path,
            "node_path": parent_path + "/" + node_name
        }))
    else:
        print('TEST_OUTPUT: {"success": false, "error": "Error guardando: ' + str(save_result) + '"}')
    
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
