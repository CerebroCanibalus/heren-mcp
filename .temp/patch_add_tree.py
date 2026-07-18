# coding: utf-8
path = r'D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\daemon\heren_scene_ops.gd'
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Add children param to handle_add_node signature
c = c.replace(
    'var properties = params.get("properties", {})',
    'var properties = params.get("properties", {})\n\tvar children = params.get("children", [])',
)

# 2. Add recursive children creation after owner assign
old = '\tnew_node.owner = root\n\t\n\t# Verificar que el nodo fue a'
new = '\tnew_node.owner = root\n\t\n\t# B15: Crear hijos recursivos si se especificaron\n\tif children.size() > 0:\n\t\tfor child_data in children:\n\t\t\t_add_single_child(new_node, root, child_data)\n\t\n\t# Verificar que el nodo fue a'
c = c.replace(old, new)

# 3. Add children_added to return
old_ret = '\t"original_name": node_name if name_was_sanitized else null\n\t}\n\t\n\t\nfunc handle_remove_node'
new_ret = '\t"original_name": node_name if name_was_sanitized else null,\n\t\t"children_added": children.size(),\n\t\t"total_nodes_added": count_nodes_recursive(new_node)\n\t}\n\t\n\t\nfunc handle_remove_node'
c = c.replace(old_ret, new_ret)

# 4. Add _add_single_child helper
old_helper = '\n\nfunc handle_remove_node(params: Dictionary) -> Dictionary:'
new_helper = '''

# B15: Helper para crear un hijo individual (usado por add_node recursivo)
func _add_single_child(parent: Node, scene_root: Node, data: Dictionary) -> void:
	"""Crea un nodo hijo con sus propiedades y sub-hijos recursivamente."""
	var node_type = data.get("type", "Node")
	var node_name = data.get("name", "Node")
	var props = data.get("properties", {})
	var grandchildren = data.get("children", [])
	
	var child = ClassDB.instantiate(node_type)
	if not child:
		return
	child.name = node_name
	
	# Aplicar propiedades
	for prop_name in props.keys():
		var val = _deserialize_value_callback.call(props[prop_name]) if _deserialize_value_callback else props[prop_name]
		if prop_name in child or prop_name in ["position", "rotation", "scale", "size", "text", "visible", "modulate"]:
			child.set(prop_name, val)
	
	parent.add_child(child)
	child.owner = scene_root
	
	# Recursion: crear hijos del hijo
	if grandchildren.size() > 0:
		for gd in grandchildren:
			_add_single_child(child, scene_root, gd)


func handle_remove_node(params: Dictionary) -> Dictionary:'''
c = c.replace(old_helper, new_helper)

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print('OK - add_tree implemented')
