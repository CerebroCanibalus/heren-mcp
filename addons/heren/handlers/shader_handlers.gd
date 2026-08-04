@tool
extends Node

# Heren MCP v4 - Shader handlers (Fase 2).
# Shaders .gdshader y ShaderMaterial sobre la escena viva (ADR-002).
#
# Actions (heredadas de v3 shader_tool.py + daemon shader_ops, adaptadas):
#   create   -> escribir .gdshader (dedup de shader_type, heredado de v3)
#   edit     -> append/reemplazar código
#   validate -> ResourceLoader.load + verificar es Shader
#   material -> crear ShaderMaterial en nodo (CanvasItem material,
#               GeometryInstance3D override/overlay, MeshInstance3D surface)
#   uniform  -> set_shader_parameter en el material del nodo

const HerenCoordsScript := preload("coords.gd")

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Contexto de escena explícito: si se pide scene_path y no es la activa,
	# activarla. Así el contexto NO cambia impredeciblemente con la pestaña.
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path != "":
		var active := ei.get_edited_scene_root()
		if active == null or active.scene_file_path != scene_path:
			if not ResourceLoader.exists(scene_path):
				return null
			ei.open_scene_from_path(scene_path)
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


func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _ensure_gdshader_ext(shader_path: String) -> String:
	if shader_path.ends_with(".gdshader"):
		return shader_path
	return shader_path + ".gdshader"


func _ensure_parent_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


# ---------------------------------------------------------------- handlers

func handle_create(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	var shader_type: String = str(args.get("shader_type", "canvas_item"))
	var code: String = str(args.get("code", ""))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_exists: " + shader_path}

	# v3 fix heredado: no duplicar shader_type si el usuario ya lo incluyó.
	var full_code := code
	if not code.strip_edges().begins_with("shader_type"):
		full_code = "shader_type " + shader_type + ";\n\n" + code

	_ensure_parent_dir(shader_path)
	var file := FileAccess.open(shader_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "write_failed: " + shader_path}
	file.store_string(full_code)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(shader_path)

	return {"ok": true, "shader_path": shader_path, "shader_type": shader_type}


func handle_edit(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	var code: String = str(args.get("code", ""))
	var append: bool = bool(args.get("append", false))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var existing := ""
	if append:
		var rf := FileAccess.open(shader_path, FileAccess.READ)
		if rf:
			existing = rf.get_as_text()
			rf = null

	var file := FileAccess.open(shader_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "write_failed: " + shader_path}
	file.store_string(existing + code)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(shader_path)

	return {"ok": true, "shader_path": shader_path, "append": append}


func handle_validate(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var shader: Resource = load(shader_path)
	if shader == null or not shader is Shader:
		return {"ok": false, "error": "invalid_shader: " + shader_path}
	return {"ok": true, "valid": true, "shader_path": shader_path}


func handle_material(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var shader_path: String = str(args.get("shader_path", ""))
	var material_name: String = str(args.get("material_name", ""))

	var material := ShaderMaterial.new()
	# Fix H2: a ShaderMaterial is a Resource, so it has `resource_name`, NOT
	# `name`. Assigning `material.name` threw a runtime error (→ "Unknown error").
	if material_name != "":
		material.resource_name = material_name
	if shader_path != "" and ResourceLoader.exists(shader_path):
		material.shader = load(shader_path)

	var uniforms := _args_dict(args, "uniforms")
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(uniforms[uniform_name]))

	# B9 fix heredado de v3: asignar a TODOS los tipos de nodos.
	var assigned := false
	if node.has_method("set_material"):
		node.set_material(material)
		assigned = true
	elif "material" in node:
		node.material = material
		assigned = true

	if not assigned and node is MeshInstance3D:
		node.set_surface_override_material(0, material)
		assigned = true

	if not assigned and node.has_method("set_material_override"):
		node.set_material_override(material)
		assigned = true
	elif not assigned and "material_override" in node:
		node.material_override = material
		assigned = true

	if not assigned and node.has_method("set_material_overlay"):
		node.set_material_overlay(material)
		assigned = true
	elif not assigned and "material_overlay" in node:
		node.material_overlay = material
		assigned = true

	if not assigned:
		return {
			"ok": false,
			"error": "material_assignment_failed",
			"node_type": node.get_class(),
		}

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"has_shader": shader_path != "",
		"material_assigned": true,
	}


func handle_uniform(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	var uniform_name: String = str(args.get("uniform_name", ""))
	if node_path == "" or uniform_name == "":
		return {"ok": false, "error": "node_path and uniform_name required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var material: ShaderMaterial = null
	if "material" in node and node.material is ShaderMaterial:
		material = node.material
	if material == null and "material_override" in node and node.material_override is ShaderMaterial:
		material = node.material_override
	if material == null and "material_overlay" in node and node.material_overlay is ShaderMaterial:
		material = node.material_overlay
	if material == null and node is MeshInstance3D:
		for i in range((node as MeshInstance3D).get_surface_override_material_count()):
			var surf_mat = (node as MeshInstance3D).get_surface_override_material(i)
			if surf_mat is ShaderMaterial:
				material = surf_mat
				break

	if material == null:
		return {"ok": false, "error": "no_shader_material", "message": "no ShaderMaterial found on node"}

	material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(args.get("value")))
	return {"ok": true, "uniform": uniform_name, "node_path": _node_path_relative(node, root)}
