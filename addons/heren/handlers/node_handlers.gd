@tool
extends Node

# Heren MCP v4 - Node handlers (Fase 2).
# CRUD completo de nodos sobre la escena VIVA del editor (ADR-002):
# la escena editada es el cache — no hay scene_cache aparte.
# Todas las mutaciones pasan por EditorUndoRedoManager (Ctrl+Z undoable).
#
# Actions (heredadas de v3 node_tool.py, sin session_id/scene_path:
# el editor ya sabe en qué escena está):
#   add, remove, set_prop, set_props, get_prop, get_info, get_children,
#   find, duplicate, rename, move, set_owner, reorder,
#   array_append, array_remove

const HerenCoordsScript := preload("coords.gd")

var _editor_plugin: EditorPlugin
var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


# ---------------------------------------------------------------- helpers

func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root() -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	return ei.get_edited_scene_root()


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized))


func _node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path()
	var root_path := root.get_path()
	var path_str := str(path)
	if path_str.begins_with(str(root_path) + "/"):
		return path_str.substr(str(root_path).length() + 1)
	return path_str


## Accepts a Dictionary directly, or a JSON string (clients may send either).
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _serialize_props(node: Node, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		if key in node:
			out[key] = HerenCoordsScript.serialize_value(node.get(key))
	return out


func _get_children_list(root: Node, node: Node, recursive: bool, out: Array, depth: int = 0) -> void:
	for child in node.get_children():
		out.append({
			"name": child.name,
			"type": child.get_class(),
			"path": _node_path_relative(child, root),
			"owner": _node_path_relative(child.get_owner(), root) if child.get_owner() else "",
			"depth": depth,
		})
		if recursive:
			_get_children_list(root, child, true, out, depth + 1)


# ---------------------------------------------------------------- handlers

func handle_add(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_type: String = str(args.get("node_type", "Node"))
	var node_name: String = str(args.get("node_name", ""))
	if node_name == "":
		return {"ok": false, "error": "node_name required"}

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	if parent.get_node_or_null(NodePath(node_name)) != null:
		return {"ok": false, "error": "node_exists: " + node_name}

	var new_node: Variant = ClassDB.instantiate(node_type)
	if new_node == null or not new_node is Node:
		return {"ok": false, "error": "invalid_node_type: " + node_type}
	var node := new_node as Node
	node.name = node_name

	# Apply properties (deserialized via unified coords).
	var properties := _args_dict(args, "properties")
	for prop_name in properties.keys():
		if prop_name in node:
			node.set(prop_name, HerenCoordsScript.deserialize_value(properties[prop_name]))

	# Optional script.
	if args.has("script") and str(args.get("script", "")) != "":
		var script_path: String = str(args.get("script"))
		if ResourceLoader.exists(script_path):
			node.set_script(load(script_path))

	# Canonical editor pattern: add_child + owner INSIDE the undo action.
	# (callv in the wrapper makes add_child receive the node, not an Array.)
	_undo_redo.begin_action("Heren Add %s" % node_name)
	_undo_redo.add_do_method(parent, &"add_child", [node])
	_undo_redo.add_do_property(node, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [node])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_name": node.name,
		"node_type": node_type,
		"parent_path": _node_path_relative(parent, root),
		"node_path": _node_path_relative(node, root),
		"count": _count_scene_nodes(root),
		"coords": _node_coords(node, root),
	}


# ------------------------------------------------------------- coords proactivas
# §13.6 NIVEL 0: cada mutación devuelve las coordenadas del nodo afectado
# (pos + bbox + parent) para que el agente sepa DÓNDE quedó sin llamada extra.

func _node_coords(node: Node, root: Node) -> Dictionary:
	var out := {
		"parent_path": _node_path_relative(node.get_parent(), root) if node.get_parent() else "",
	}
	if node is CanvasItem:
		var ci := node as CanvasItem
		out["pos"] = HerenCoordsScript.serialize_value(ci.global_position)
	elif node is Node3D:
		var n3 := node as Node3D
		out["pos"] = HerenCoordsScript.serialize_value(n3.global_position)
	# Bounding box when derivable.
	var bbox := {}
	if node is Sprite2D:
		var s := node as Sprite2D
		if s.texture != null:
			bbox = {"x": s.global_position.x - s.texture.get_width() * s.scale.x * 0.5,
					"y": s.global_position.y - s.texture.get_height() * s.scale.y * 0.5,
					"w": s.texture.get_width() * s.scale.x, "h": s.texture.get_height() * s.scale.y}
	elif node is CollisionShape2D:
		var cs := node as CollisionShape2D
		var shape: Shape2D = cs.shape
		if shape is RectangleShape2D:
			var size: Vector2 = (shape as RectangleShape2D).size
			bbox = {"x": cs.global_position.x - size.x * 0.5, "y": cs.global_position.y - size.y * 0.5,
					"w": size.x, "h": size.y}
		elif shape is CircleShape2D:
			var radius: float = (shape as CircleShape2D).radius
			bbox = {"x": cs.global_position.x - radius, "y": cs.global_position.y - radius,
					"w": radius * 2.0, "h": radius * 2.0}
	if not bbox.is_empty():
		out["bbox"] = bbox
	return out


func _count_scene_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_scene_nodes(child)
	return total


func handle_remove(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if node == root:
		return {"ok": false, "error": "cannot_remove_root"}

	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "no_parent"}
	var index := node.get_index()
	var had_children := node.get_child_count() > 0
	var node_path_str := _node_path_relative(node, root)

	_undo_redo.begin_action("Heren Remove %s" % node.name)
	_undo_redo.add_do_method(parent, &"remove_child", [node])
	_undo_redo.add_undo_method(parent, &"add_child", [node])
	_undo_redo.add_undo_method(parent, &"move_child", [node, index])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"removed": node_path_str,
		"had_children": had_children,
		"parent_path": _node_path_relative(parent, root),
		"coords": _node_coords(node, root),
	}


func handle_set_prop(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property: String = str(args.get("property", args.get("property_name", "")))
	if node_path == "" or property == "":
		return {"ok": false, "error": "node_path and property (or property_name) required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if property not in node:
		return {"ok": false, "error": "property_not_found: " + property}

	var new_value: Variant = HerenCoordsScript.deserialize_value(args.get("value", null))
	var old_value: Variant = node.get(property)

	_undo_redo.begin_action("Heren Set %s.%s" % [node.name, property])
	_undo_redo.add_do_property(node, property, new_value)
	_undo_redo.add_undo_property(node, property, old_value)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"old_value": HerenCoordsScript.serialize_value(old_value),
		"new_value": HerenCoordsScript.serialize_value(new_value),
		"coords": _node_coords(node, root),
	}


func handle_set_props(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var properties := _args_dict(args, "properties")
	if node_path == "" or properties.is_empty():
		return {"ok": false, "error": "node_path and properties (dict) required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var applied: Array = []
	_undo_redo.begin_action("Heren Set Props %s" % node.name)
	for prop_name in properties.keys():
		if prop_name in node:
			var new_value: Variant = HerenCoordsScript.deserialize_value(properties[prop_name])
			var old_value: Variant = node.get(prop_name)
			_undo_redo.add_do_property(node, prop_name, new_value)
			_undo_redo.add_undo_property(node, prop_name, old_value)
			applied.append(prop_name)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"applied": applied,
		"count": applied.size(),
	}


func handle_get_prop(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property: String = str(args.get("property", args.get("property_name", "")))
	if node_path == "" or property == "":
		return {"ok": false, "error": "node_path and property required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if property not in node:
		return {"ok": false, "error": "property_not_found: " + property}

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"value": HerenCoordsScript.serialize_value(node.get(property)),
	}


func handle_get_info(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var children := []
	_get_children_list(root, node, false, children)

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"node_type": node.get_class(),
		"properties": _serialize_props(node, ["position", "rotation", "scale", "modulate", "visible", "text"]),
		"children": children,
		"child_count": children.size(),
		"owner": _node_path_relative(node.get_owner(), root) if node.get_owner() else "",
		"groups": node.get_groups(),
		"scene_file_path": node.scene_file_path if node.scene_file_path != "" else "",
	}


func handle_get_children(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", ".")
	var recursive: bool = bool(args.get("recursive", false))

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var children := []
	_get_children_list(root, node, recursive, children)

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"children": children,
		"count": children.size(),
	}


func handle_find(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var query: String = str(args.get("query", ""))
	var by: String = str(args.get("by", "name"))  # name | type | property
	if query == "":
		return {"ok": false, "error": "query required"}

	var property_name: String = str(args.get("property_name", ""))
	var property_value: Variant = args.get("property_value", null)
	var results := []

	# Iterative stack traversal (no recursive lambdas — GDScript limitation).
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node := stack.pop_back()
		var is_match := false
		match by:
			"name":
				is_match = query in str(node.name)
			"type":
				is_match = query in node.get_class()
			"property":
				is_match = property_name in node and node.get(property_name) == property_value
			_:
				return {"ok": false, "error": "invalid 'by': " + by}
		if is_match:
			results.append({
				"name": node.name,
				"type": node.get_class(),
				"path": _node_path_relative(node, root),
				"owner": _node_path_relative(node.get_owner(), root) if node.get_owner() else "",
			})
		for child in node.get_children():
			stack.append(child)

	return {
		"ok": true,
		"query": query,
		"by": by,
		"results": results,
		"count": results.size(),
	}


func handle_duplicate(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if node == root:
		return {"ok": false, "error": "cannot_duplicate_root"}

	var duplicate: Node = node.duplicate()
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = str(node.name) + "_dup"
	duplicate.name = new_name

	var parent := node.get_parent()
	var index := node.get_index()

	_undo_redo.begin_action("Heren Duplicate %s" % node.name)
	_undo_redo.add_do_method(parent, &"add_child", [duplicate])
	_undo_redo.add_do_method(parent, &"move_child", [duplicate, index + 1])
	_undo_redo.add_do_property(duplicate, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [duplicate])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"original": _node_path_relative(node, root),
		"duplicate": _node_path_relative(duplicate, root),
		"name": duplicate.name,
	}


func handle_rename(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_name: String = str(args.get("new_name", ""))
	if node_path == "" or new_name == "":
		return {"ok": false, "error": "node_path and new_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var old_name := node.name

	_undo_redo.begin_action("Heren Rename %s" % old_name)
	_undo_redo.add_do_property(node, &"name", new_name)
	_undo_redo.add_undo_property(node, &"name", old_name)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"old_name": old_name,
		"new_name": new_name,
		"node_path": _node_path_relative(node, root),
	}


func handle_move(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_parent_path: Variant = args.get("new_parent", "")
	if node_path == "" or new_parent_path == "":
		return {"ok": false, "error": "node_path and new_parent required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if node == root:
		return {"ok": false, "error": "cannot_move_root"}

	var new_parent := _resolve_node(root, new_parent_path)
	if new_parent == null:
		return {"ok": false, "error": "parent_not_found: " + str(new_parent_path)}

	var old_parent := node.get_parent()
	if old_parent == null:
		return {"ok": false, "error": "no_parent"}
	var old_index := node.get_index()

	_undo_redo.begin_action("Heren Move %s" % node.name)
	_undo_redo.add_do_method(old_parent, &"remove_child", [node])
	_undo_redo.add_do_method(new_parent, &"add_child", [node])
	_undo_redo.add_do_property(node, &"owner", root)
	_undo_redo.add_undo_method(new_parent, &"remove_child", [node])
	_undo_redo.add_undo_method(old_parent, &"add_child", [node])
	_undo_redo.add_undo_method(old_parent, &"move_child", [node, old_index])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"new_parent": _node_path_relative(new_parent, root),
	}


func handle_set_owner(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var owner_path: Variant = args.get("owner_path", ".")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var owner := _resolve_node(root, owner_path)
	if owner == null:
		return {"ok": false, "error": "owner_not_found: " + str(owner_path)}
	var old_owner: Node = node.owner

	_undo_redo.begin_action("Heren Set Owner %s" % node.name)
	_undo_redo.add_do_property(node, &"owner", owner)
	_undo_redo.add_undo_property(node, &"owner", old_owner)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"owner_path": _node_path_relative(owner, root),
	}


func handle_reorder(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_index: int = int(args.get("index", args.get("new_index", -1)))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	if new_index < 0:
		return {"ok": false, "error": "index >= 0 required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "no_parent"}
	var old_index := node.get_index()

	_undo_redo.begin_action("Heren Reorder %s" % node.name)
	_undo_redo.add_do_method(parent, &"move_child", [node, new_index])
	_undo_redo.add_undo_method(parent, &"move_child", [node, old_index])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"new_index": new_index,
		"old_index": old_index,
	}


func handle_array_append(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property_name: String = str(args.get("property_name", ""))
	if node_path == "" or property_name == "":
		return {"ok": false, "error": "node_path and property_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var current: Variant = node.get(property_name)
	if current == null or not (current is Array or current is PackedInt32Array):
		return {"ok": false, "error": "property_not_array: " + property_name}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value", null))
	var old_value: Variant = node.get(property_name)

	_undo_redo.begin_action("Heren Array Append %s.%s" % [node.name, property_name])
	_undo_redo.add_do_property(node, property_name, _array_with_append(current, value))
	_undo_redo.add_undo_property(node, property_name, old_value)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property_name": property_name,
		"value_added": HerenCoordsScript.serialize_value(value),
		"array_size": current.size(),
	}


func handle_array_remove(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property_name: String = str(args.get("property_name", ""))
	if node_path == "" or property_name == "":
		return {"ok": false, "error": "node_path and property_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var current: Variant = node.get(property_name)
	if current == null or not (current is Array or current is PackedInt32Array):
		return {"ok": false, "error": "property_not_array: " + property_name}

	var index: int = int(args.get("index", -1))
	var value: Variant = args.get("value", null)
	var old_value: Variant = node.get(property_name)
	var removed_value: Variant = null

	if index >= 0 and index < current.size():
		removed_value = current[index]
	elif value != null:
		var found: int = current.find(HerenCoordsScript.deserialize_value(value))
		if found >= 0:
			index = found
			removed_value = current[found]
		else:
			return {"ok": false, "error": "value_not_found"}
	else:
		return {"ok": false, "error": "index or value required"}

	_undo_redo.begin_action("Heren Array Remove %s.%s" % [node.name, property_name])
	_undo_redo.add_do_property(node, property_name, _array_without_at(current, index))
	_undo_redo.add_undo_property(node, property_name, old_value)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property_name": property_name,
		"removed_value": HerenCoordsScript.serialize_value(removed_value),
		"array_size": old_value.size(),
	}


# ---------------------------------------------------------------- array utils

func _array_with_append(arr: Variant, value: Variant) -> Variant:
	if arr is PackedInt32Array:
		var packed := (arr as PackedInt32Array).duplicate()
		packed.append(int(value))
		return packed
	var out: Array = (arr as Array).duplicate(true)
	out.append(value)
	return out


func _array_without_at(arr: Variant, index: int) -> Variant:
	if arr is PackedInt32Array:
		var packed := (arr as PackedInt32Array).duplicate()
		packed.remove_at(index)
		return packed
	var out: Array = (arr as Array).duplicate(true)
	out.remove_at(index)
	return out
