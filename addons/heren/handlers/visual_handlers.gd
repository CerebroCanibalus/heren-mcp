@tool
extends Node

# Heren MCP v4 - Visual handlers (Fase 3, §13.6).
# "Ojos con Control": jerarquía de costo (coords → ascii → low → full).
#
# NIVEL 0: scene_coords   -> mapa textual de coordenadas {nodo: {pos, bbox, parent}}
# NIVEL 1: scene_summary  -> conteo por tipo, bbox total
#          scene_ascii    -> árbol ASCII de la escena
# NIVEL 2/3: capture      -> viewport REAL del editor (2D/3D) → PNG base64
#            capture_node -> framing de un nodo
#
# Output AGNÓSTICO: la imagen viaja como `__image_base64` + `__image_format`
# en el resultado; el bridge la convierte a `image_content` MCP estándar.
# Cualquier cliente MCP (OpenCode, Claude Desktop...) la interpreta.

const HerenCoordsScript := preload("coords.gd")

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


# ---------------------------------------------------------------- utils

func _root_node() -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	return ei.get_edited_scene_root()


func _node_pos(node: Node) -> Dictionary:
	if node is CanvasItem:
		return HerenCoordsScript.serialize_value((node as CanvasItem).global_position)
	if node is Node3D:
		return HerenCoordsScript.serialize_value((node as Node3D).global_position)
	return {}


func _node_bbox(node: Node) -> Dictionary:
	var bbox := {}
	if node is Control:
		var c := node as Control
		bbox = {"x": c.global_position.x, "y": c.global_position.y, "w": c.size.x, "h": c.size.y}
	elif node is Sprite2D:
		var s := node as Sprite2D
		var tex: Texture2D = s.texture
		if tex != null:
			bbox = {"x": s.global_position.x - tex.get_width() * s.scale.x * 0.5,
					"y": s.global_position.y - tex.get_height() * s.scale.y * 0.5,
					"w": tex.get_width() * s.scale.x, "h": tex.get_height() * s.scale.y}
	elif node is CollisionShape2D:
		var cs := node as CollisionShape2D
		var shape: Shape2D = cs.shape
		if shape is RectangleShape2D:
			var size: Vector2 = (shape as RectangleShape2D).size
			bbox = {"x": cs.global_position.x - size.x * 0.5, "y": cs.global_position.y - size.y * 0.5,
					"w": size.x, "h": size.y}
	return bbox


func _path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path_to(root) if root else node.get_path()
	return str(path)


func _walk(node: Node, root: Node, out: Dictionary, depth: int, max_depth: int) -> void:
	if max_depth >= 0 and depth > max_depth:
		return
	var entry := {
		"type": node.get_class(),
		"parent": _path_relative(node.get_parent(), root) if node.get_parent() else "",
	}
	var pos := _node_pos(node)
	if not pos.is_empty():
		entry["pos"] = pos
	var bbox := _node_bbox(node)
	if not bbox.is_empty():
		entry["bbox"] = bbox
	out[_path_relative(node, root)] = entry
	for child in node.get_children():
		_walk(child, root, out, depth + 1, max_depth)


# ---------------------------------------------------------------- NIVEL 0: coords

func handle_scene_coords(args: Dictionary) -> Dictionary:
	var root := _root_node()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var max_depth: int = int(args.get("max_depth", -1))
	var out := {}
	_walk(root, root, out, 0, max_depth)
	return {"ok": true, "root": root.name, "node_count": out.size(), "coords": out}


# ---------------------------------------------------------------- NIVEL 1: summary + ascii

func handle_scene_summary(args: Dictionary) -> Dictionary:
	var root := _root_node()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var by_type := {}
	var total := 0
	var count := func(node: Node) -> void:
		var t: String = node.get_class()
		by_type[t] = int(by_type.get(t, 0)) + 1
		total += 1
	count.call(root)
	for child in root.get_children():
		count.call(child)
	return {"ok": true, "root": root.name, "node_count": total, "by_type": by_type}


func handle_scene_ascii(args: Dictionary) -> Dictionary:
	var root := _root_node()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var max_depth: int = int(args.get("max_depth", -1))
	var lines: Array[String] = []
	var build := _ascii_build.bind(lines, max_depth)
	build.call(root, "", true, 0)
	return {"ok": true, "ascii": "\n".join(lines)}


func _ascii_build(node: Node, prefix: String, is_last: bool, depth: int, lines: Array[String], max_depth: int) -> void:
	if max_depth >= 0 and depth > max_depth:
		return
	var branch := "└─ " if is_last else "├─ "
	lines.append(prefix + branch + node.name + " [" + node.get_class() + "]")
	var children := node.get_children()
	for i in children.size():
		var last := i == children.size() - 1
		var next_prefix := prefix + ("    " if is_last else "│   ")
		_ascii_build(children[i], next_prefix, last, depth + 1, lines, max_depth)


# ---------------------------------------------------------------- NIVEL 2/3: capture

func _capture_viewport(viewport: Viewport) -> Dictionary:
	if viewport == null:
		return {}
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {}
	# Flip: viewport texture es Y-invertida en Godot 4.
	img.flip_y()
	var png := img.save_png_to_buffer()
	if png.is_empty():
		return {}
	return {
		"__image_base64": Marshalls.raw_to_base64(png),
		"__image_format": "png",
		"__image_w": img.get_width(),
		"__image_h": img.get_height(),
	}


func _resize_image(img: Image, max_side: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if max_side <= 0 or max(w, h) <= max_side:
		return img
	var scale := float(max_side) / float(max(w, h))
	var nw := max(1, int(w * scale))
	var nh := max(1, int(h * scale))
	img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	return img


func handle_capture(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	var mode: String = str(args.get("viewport", "2d"))
	var max_side: int = int(args.get("max_side", 0))
	var viewport: Viewport = null
	if mode == "3d":
		viewport = ei.get_editor_viewport_3d()
	else:
		viewport = ei.get_editor_viewport_2d()
	if viewport == null:
		return {"ok": false, "error": "viewport not available: " + mode}

	# P1: si se pasa `animation` {player_path, anim_name, time}, hacer seek
	# ANTES de capturar — el agente ve un frame concreto sin llamadas extra.
	var anim_info: Dictionary = _args_dict(args, "animation")
	if not anim_info.is_empty():
		var root := ei.get_edited_scene_root()
		if root != null:
			var player := _resolve_animation_player(root, anim_info.get("player_path", ""))
			if player != null:
				var anim_name: String = str(anim_info.get("anim_name", ""))
				if anim_name == "" or player.has_animation(anim_name):
					if anim_name != "":
						player.current_animation = anim_name
					player.seek(float(anim_info.get("time", 0.0)), true)
					player.pause()

	# Forzar sync de rendering antes de capturar.
	RenderingServer.force_draw(true)

	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "capture failed: no image from viewport"}
	img.flip_y()
	if max_side > 0:
		img = _resize_image(img, max_side)
	var png := img.save_png_to_buffer()
	if png.is_empty():
		return {"ok": false, "error": "capture failed: png encode"}
	var root := ei.get_edited_scene_root()
	var out := {
		"ok": true,
		"viewport": mode,
		"__image_base64": Marshalls.raw_to_base64(png),
		"__image_format": "png",
		"__image_w": img.get_width(),
		"__image_h": img.get_height(),
		"scene": root.name if root else "",
		"node_count": root.get_child_count() + 1 if root else 0,
	}
	if not anim_info.is_empty():
		out["animation"] = {
			"player_path": anim_info.get("player_path", ""),
			"anim_name": anim_info.get("anim_name", ""),
			"time": anim_info.get("time", 0.0),
		}
	return out


func _resolve_animation_player(root: Node, player_path: Variant) -> AnimationPlayer:
	if player_path == null or str(player_path) == "":
		# Buscar el primer AnimationPlayer del root.
		for child in root.get_children():
			if child is AnimationPlayer:
				return child as AnimationPlayer
		return null
	var normalized := HerenCoordsScript.normalize_node_path(player_path, root)
	if normalized == ".":
		return root as AnimationPlayer
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized)) as AnimationPlayer


func handle_capture_node(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	var root := ei.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = null
	if node_path == "." or node_path == root.name:
		node = root
	else:
		node = root.get_node_or_null(node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + node_path}

	# La captura se hace del viewport 2D/3D; el framing es metadato de bbox.
	var mode: String = str(args.get("viewport", "2d"))
	var max_side: int = int(args.get("max_side", 0))
	var viewport: Viewport = null
	if mode == "3d":
		viewport = ei.get_editor_viewport_3d()
	else:
		viewport = ei.get_editor_viewport_2d()
	if viewport == null:
		return {"ok": false, "error": "viewport not available: " + mode}
	RenderingServer.force_draw(true)
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "capture failed"}
	img.flip_y()
	if max_side > 0:
		img = _resize_image(img, max_side)
	var png := img.save_png_to_buffer()
	return {
		"ok": true,
		"node_path": node_path,
		"viewport": mode,
		"__image_base64": Marshalls.raw_to_base64(png),
		"__image_format": "png",
		"__image_w": img.get_width(),
		"__image_h": img.get_height(),
		"bbox": _node_bbox(node),
		"pos": _node_pos(node),
	}


# ---------------------------------------------------------------- previews

func handle_preview_resource(args: Dictionary) -> Dictionary:
	# Thumbnail de un recurso vía EditorResourcePreview. Síncrono no es
	# posible (el preview es async en Godot 4); usamos make_mesh_previews
	# para meshes y un path de recurso para el resto (el editor lo genera).
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}
	var resource_path: String = str(args.get("resource_path", ""))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}
	if not ResourceLoader.exists(resource_path):
		return {"ok": false, "error": "resource_not_found: " + resource_path}
	var res: Resource = load(resource_path)
	var max_size: int = int(args.get("max_size", 128))

	# Mesh preview: EditorInterface.make_mesh_previews genera la imagen SÍNCRONA.
	if res is Mesh:
		var previews := ei.make_mesh_previews([res], max_size)
		if previews.size() > 0 and previews[0] is Texture2D:
			var tex := previews[0] as Texture2D
			var img: Image = tex.get_image()
			if img != null:
				img.flip_y()
				var png := img.save_png_to_buffer()
				if not png.is_empty():
					return {
						"ok": true,
						"resource_path": resource_path,
						"__image_base64": Marshalls.raw_to_base64(png),
						"__image_format": "png",
						"__image_w": img.get_width(),
						"__image_h": img.get_height(),
						"preview": "mesh",
					}

	# Textures: get_image() directo.
	if res is Texture2D:
		var img: Image = (res as Texture2D).get_image()
		if img != null:
			if max_size > 0:
				img = _resize_image(img, max_size)
			var png := img.save_png_to_buffer()
			if not png.is_empty():
				return {
					"ok": true,
					"resource_path": resource_path,
					"__image_base64": Marshalls.raw_to_base64(png),
					"__image_format": "png",
					"__image_w": img.get_width(),
					"__image_h": img.get_height(),
					"preview": "texture",
				}

	return {
		"ok": false,
		"error": "preview_not_available: solo Mesh/Texture2D sincrónico",
		"resource_path": resource_path,
	}
