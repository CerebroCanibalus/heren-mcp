@tool
extends "res://addons/heren/handlers/heren_handler.gd"
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
const HerenSceneRegistryScript := preload("../scene_registry.gd")



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


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path_to(root) if root else node.get_path()
	return str(path)


func _walk(node: Node, root: Node, out: Dictionary, depth: int, max_depth: int) -> void:
	if max_depth >= 0 and depth > max_depth:
		return
	# Fase A: coords unificadas — fuente única HerenCoords.coords_of_node.
	# El entry expone solo los campos que NIVEL 0 necesita en el mapa textual;
	# si el agente quiere más detalle (modulate, anchors, effective_rect),
	# llama a node_query/get_info o coords_of_node con tier=2.
	var coords := HerenCoordsScript.coords_of_node(node, _path_relative(node, root), 1)
	var entry: Dictionary = {
		"type": coords.get("kind", node.get_class()),
		"pos": coords.get("pos", {}),
	}
	if coords.has("bbox"):
		entry["bbox"] = coords["bbox"]
	out[_path_relative(node, root)] = entry
	for child in node.get_children():
		_walk(child, root, out, depth + 1, max_depth)


# ---------------------------------------------------------------- NIVEL 0: coords

func handle_scene_coords(args: Dictionary) -> Dictionary:
	# P0.2 (2026-09-03): usar _scene_root(args) para honrar scene_path del args
	# (antes _root_node ignoraba scene_path → retornaba pestaña activa incorrecta).
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var max_depth: int = int(args.get("max_depth", -1))
	var out := {}
	_walk(root, root, out, 0, max_depth)
	return {"ok": true, "root": root.name, "node_count": out.size(), "coords": out}


# ---------------------------------------------------------------- NIVEL 1: summary + ascii

func handle_scene_summary(args: Dictionary) -> Dictionary:
	# P0.2 (2026-09-03): _scene_root(args) — soportar scene_path explícito.
	var root := _scene_root(args)
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
	# P0.2 (2026-09-03): _scene_root(args) — soportar scene_path explícito.
	var root := _scene_root(args)
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

# ---------------------------------------------------------------- captura
# Fix 2026-08-07: el viewport del EDITOR devuelve 2x2 (placeholder) con
# get_texture().get_image() → captura inservible. Render off-screen de la
# ESCENA en un SubViewport dedicado = fiable. `source: scene|viewport`.
# Fix 2026-09-03: resolución Full HD por defecto + presets de calidad.

const OFFSCREEN_SIZE := Vector2i(1920, 1080)  # Full HD (antes 1280×720)

# Presets de calidad: el agente pasa `quality` y se resuelve a max_side.
const QUALITY_PRESETS := {
	"low": 640,
	"medium": 1280,
	"high": 1920,
	"ultra": 2560,
}

# Pool de SubViewports reusables (2D y 3D separados).
# Evita crear+destruir en cada captura (~50-200ms de overhead).
var _svp_2d: SubViewport = null
var _svp_3d: SubViewport = null


func _is_tiny_image(img: Image) -> bool:
	# El placeholder 2x2 de un render target no renderizado es inservible.
	return img == null or (img.get_width() <= 2 and img.get_height() <= 2)


func _resolve_max_side(args: Dictionary) -> int:
	# Prioridad: quality preset > max_side explícito > default 1920.
	var quality: String = str(args.get("quality", ""))
	if quality != "" and QUALITY_PRESETS.has(quality):
		return QUALITY_PRESETS[quality]
	var max_side: int = int(args.get("max_side", 0))
	if max_side > 0:
		return max_side
	return 1920  # Full HD default (antes 2048)


func _encode_image(img: Image, max_side: int, format: String = "png") -> Dictionary:
	if _is_tiny_image(img):
		return {}
	if max_side > 0:
		img = _resize_image(img, max_side)
	# Flip: la textura del viewport es Y-invertida en Godot 4.
	img.flip_y()
	var buf: PackedByteArray
	var mime: String
	if format == "jpeg" or format == "jpg":
		buf = img.save_jpg_to_buffer(0.92)  # quality 92%
		mime = "image/jpeg"
	else:
		buf = img.save_png_to_buffer()
		mime = "image/png"
	if buf.is_empty():
		return {}
	return {
		"__image_base64": Marshalls.raw_to_base64(buf),
		"__image_format": mime,
		"__image_w": img.get_width(),
		"__image_h": img.get_height(),
	}


# Captura el viewport REAL del editor (lo que el usuario ve: gizmos, grid,
# selección). Puede devolver {} (2x2) si el editor no expone su render target
# → el caller hace fallback a scene.
func _capture_editor_viewport(ei: EditorInterface, mode: String, max_side: int, anim_info: Dictionary, root: Node, format: String = "png") -> Dictionary:
	var viewport: Viewport = null
	if mode == "3d":
		viewport = ei.get_editor_viewport_3d()
	else:
		viewport = ei.get_editor_viewport_2d()
	if viewport == null:
		return {}
	# P1: seek del AnimationPlayer REAL antes de capturar (el editor muestra
	# el frame concreto; el off-screen lo hace sobre el clon, escena intacta).
	if not anim_info.is_empty() and root != null:
		var player := _resolve_animation_player(root, anim_info.get("player_path", ""))
		if player != null:
			var anim_name: String = str(anim_info.get("anim_name", ""))
			if anim_name == "" or player.has_animation(anim_name):
				if anim_name != "":
					player.current_animation = anim_name
				player.seek(float(anim_info.get("time", 0.0)), true)
				player.pause()
	RenderingServer.force_draw(true)
	var img: Image = viewport.get_texture().get_image()
	return _encode_image(img, max_side, format)


# Render OFF-SCREEN de la ESCENA real (no el viewport del editor): SubViewport
# dedicado, clon del root sin scripts, framing replicado de la cámara del
# editor (2D/3D). Fiable siempre; no depende del estado del editor.
# Reutiliza SubViewports del pool para evitar overhead de creación/destrucción.
func _render_scene_offscreen(ei: EditorInterface, root: Node, mode: String, max_side: int, anim_info: Dictionary, format: String = "png") -> Dictionary:
	if root == null:
		return {}
	var is_3d := mode == "3d"
	var size := OFFSCREEN_SIZE
	if max(size.x, size.y) > max_side:
		var scale := float(max_side) / float(max(size.x, size.y))
		size = Vector2i(max(64, int(size.x * scale)), max(64, int(size.y * scale)))

	# Reusar SubViewport del pool (o crear uno nuevo la primera vez)
	var svp: SubViewport
	if is_3d:
		if _svp_3d == null:
			_svp_3d = SubViewport.new()
			_svp_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			_svp_3d.own_world_3d = true
			_svp_3d.world_3d = World3D.new()
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.11, 0.12, 0.14)
			_svp_3d.world_3d.environment = env
			get_tree().root.add_child(_svp_3d)
		svp = _svp_3d
	else:
		if _svp_2d == null:
			_svp_2d = SubViewport.new()
			_svp_2d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			_svp_2d.transparent_bg = true
			get_tree().root.add_child(_svp_2d)
		svp = _svp_2d

	svp.size = size

	# Limpiar contenido anterior (clon + cámara previa)
	for child in svp.get_children():
		child.queue_free()
	# Esperar un frame para que queue_free se procese
	await get_tree().process_frame

	var clone := root.duplicate(Node.DUPLICATE_GROUPS)
	if clone == null:
		return {}
	# Replicar el framing de la cámara del editor sobre el clon.
	_fit_camera(ei, clone, is_3d)
	# P1: animación → seek al player del CLON (la escena real intacta).
	_apply_anim_to_clone(root, clone, anim_info)
	svp.add_child(clone)

	# Esperar a que el renderer dibuje al menos 2 frames del SubViewport.
	RenderingServer.force_draw(true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = svp.get_texture().get_image()
	var out := _encode_image(img, max_side, format)
	# NO destruir el SubViewport — se reutiliza en la próxima captura.
	return out


func _fit_camera(ei: EditorInterface, clone: Node, is_3d: bool) -> void:
	if is_3d:
		var vp3 := ei.get_editor_viewport_3d()
		var cam := vp3.get_camera_3d() if vp3 != null else null
		var new_cam := Camera3D.new()
		if cam != null:
			new_cam.global_transform = cam.global_transform
		else:
			new_cam.transform = Transform3D(Basis(), Vector3(0, 2, 8))
		new_cam.current = true
		clone.add_child(new_cam)
	else:
		var vp2 := ei.get_editor_viewport_2d()
		var cam2d := vp2.get_camera_2d() if vp2 != null else null
		if cam2d != null:
			var new_cam := Camera2D.new()
			new_cam.global_transform = cam2d.global_transform
			new_cam.zoom = cam2d.zoom
			new_cam.make_current()
			clone.add_child(new_cam)


func _apply_anim_to_clone(root: Node, clone: Node, anim_info: Dictionary) -> void:
	if anim_info.is_empty():
		return
	var player := _resolve_animation_player(root, anim_info.get("player_path", ""))
	if player == null:
		return
	var rel := root.get_path_to(player)
	var player_clone: AnimationPlayer = clone.get_node_or_null(rel) as AnimationPlayer
	if player_clone == null:
		return
	var anim_name: String = str(anim_info.get("anim_name", ""))
	if anim_name != "" and player_clone.has_animation(anim_name):
		player_clone.current_animation = anim_name
	player_clone.seek(float(anim_info.get("time", 0.0)), true)
	player_clone.pause()


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
	# P0.3 (2026-09-03): capturar durante play COMPITE por GPU → frame_post_draw
	# no resuelve → timeout >30s. Rechazar con error claro para que el agente
	# pare el juego primero con debug/stop_scene.
	if ei.is_playing_scene():
		return {
			"ok": false,
			"error": "capture_blocked_during_play: el renderer está ocupado con el juego; usa debug/stop_scene primero (o captura la pestaña con source='viewport' solo si esperas 2-3s de latencia)",
		}
	var mode: String = str(args.get("viewport", "2d"))
	var max_side: int = _resolve_max_side(args)
	var source: String = str(args.get("source", "scene"))
	var format: String = str(args.get("format", "png"))
	if source != "scene" and source != "viewport":
		source = "scene"
	var anim_info: Dictionary = _args_dict(args, "animation")
	var root := _scene_root(args)

	var img_result: Dictionary = {}
	var used_source := source
	if source == "viewport":
		img_result = await _capture_editor_viewport(ei, mode, max_side, anim_info, root, format)
		if img_result.is_empty():
			# El viewport del editor no expone render target (2x2) → escena.
			used_source = "scene"
			img_result = await _render_scene_offscreen(ei, root, mode, max_side, anim_info, format)
	else:
		img_result = await _render_scene_offscreen(ei, root, mode, max_side, anim_info, format)
	if img_result.is_empty():
		return {"ok": false, "error": "capture failed: no image (source: " + used_source + ")"}
	var out := {
		"ok": true,
		"viewport": mode,
		"source": used_source,
		"scene": root.name if root else "",
		"node_count": root.get_child_count() + 1 if root else 0,
		"max_side": max_side,
		"format": format,
	}
	out.merge(img_result)
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
	var root := _scene_root(args)
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

	# Captura de la escena (off-screen) o del viewport del editor; el framing
	# del nodo es metadato de bbox/pos.
	var mode: String = str(args.get("viewport", "2d"))
	var max_side: int = _resolve_max_side(args)
	var source: String = str(args.get("source", "scene"))
	var format: String = str(args.get("format", "png"))
	if source != "scene" and source != "viewport":
		source = "scene"
	var img_result: Dictionary = {}
	var used_source := source
	if source == "viewport":
		img_result = await _capture_editor_viewport(ei, mode, max_side, {}, root, format)
		if img_result.is_empty():
			used_source = "scene"
			img_result = await _render_scene_offscreen(ei, root, mode, max_side, {}, format)
	else:
		img_result = await _render_scene_offscreen(ei, root, mode, max_side, {}, format)
	if img_result.is_empty():
		return {"ok": false, "error": "capture failed"}
	# Fase A: coords unificadas — kind/flags/pos/bbox/aabb desde coords.gd.
	var node_coords := HerenCoordsScript.coords_of_node(node, node_path, 1)
	var out := {
		"ok": true,
		"node_path": node_path,
		"viewport": mode,
		"source": used_source,
		"max_side": max_side,
		"format": format,
		"coords": node_coords,
	}
	out.merge(img_result)
	return out


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
