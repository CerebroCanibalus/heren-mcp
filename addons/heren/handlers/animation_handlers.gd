@tool
extends Node

# Heren MCP v4 - Animation + Skeleton handlers (Fase 2).
# Animaciones (AnimationPlayer + AnimationLibrary), state machines
# (AnimationTree + AnimationNodeStateMachine) y esqueletos (Skeleton2D/3D).
# Todas las mutaciones contra la escena viva con EditorUndoRedoManager.
#
# Actions (heredadas de v3 animation_tool.py + skeleton_tool.py, adaptadas):
#   create_player  -> AnimationPlayer en escena viva (undoable)
#   create         -> Animation en AnimationLibrary del player
#   add_track      -> track en animación (value/position_3d/rotation_3d/scale_3d/method)
#   add_key        -> key en track (time, value, transition)
#   state_machine  -> AnimationTree + AnimationNodeStateMachine
#   skeleton_create -> Skeleton2D/3D en escena viva (undoable)
#   skeleton_add_bone -> Bone2D / Skeleton3D.add_bone
#   skeleton_set_rest -> set_bone_rest
#   skeleton_skin  -> Polygon2D.skeleton + weights
#   skeleton_attachment -> BoneAttachment3D en bone

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")

var _editor_plugin: EditorPlugin
var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


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


func _get_animation_player(root: Node, player_path: Variant) -> AnimationPlayer:
	var player := _resolve_node(root, player_path) as AnimationPlayer
	return player


## Accepts a Dictionary directly, or a JSON string.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


# ---------------------------------------------------------------- animation

func handle_create_player(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	var player_name: String = str(args.get("player_name", "AnimationPlayer"))
	if parent.get_node_or_null(NodePath(player_name)) != null:
		return {"ok": false, "error": "node_exists: " + player_name}

	var player := AnimationPlayer.new()
	player.name = player_name

	_undo_redo.begin_action("Heren Add AnimationPlayer")
	_undo_redo.add_do_method(parent, &"add_child", [player])
	_undo_redo.add_do_property(player, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [player])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"player_name": player.name,
		"player_path": _node_path_relative(parent, root) + "/" + player.name,
	}


func handle_create(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}

	var anim := Animation.new()
	anim.length = float(args.get("length", 1.0))
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"player_path": _node_path_relative(player, root),
		"anim_name": anim_name,
		"length": anim.length,
	}


func handle_add_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	var track_idx: int = int(args.get("track_idx", 0))
	var time: float = float(args.get("time", 0.0))
	var transition: float = float(args.get("transition", 1.0))

	var anim: Animation = player.get_animation(anim_name) if player.has_animation(anim_name) else null
	if anim == null:
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value"))
	var key_idx := anim.track_insert_key(track_idx, time, value, transition)

	return {"ok": true, "key_idx": key_idx, "track_idx": track_idx, "time": time}


func handle_state_machine(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}

	# Fase 3: soporta AnimationNodeStateMachine (default) o AnimationNodeBlendTree
	# con blend spaces 1D/2D, one-shot, time-scale, transición y parámetros.
	var graph_type: String = str(args.get("graph_type", "state_machine"))
	var graph_root: AnimationNode

	match graph_type:
		"blend_tree":
			graph_root = _build_blend_tree(args)
		"blend_space_1d":
			graph_root = _build_blend_space_1d(args)
		"blend_space_2d":
			graph_root = _build_blend_space_2d(args)
		_:
			graph_root = _build_state_machine(args)

	if graph_root == null:
		return {"ok": false, "error": "failed to build graph"}

	var tree := AnimationTree.new()
	tree.tree_root = graph_root
	tree.anim_player = player.get_path()

	# Parámetros iniciales (si el grafo los expone).
	var params: Dictionary = _args_dict(args, "parameters")
	if not params.is_empty():
		for key in params.keys():
			var param_name := "parameters/" + str(key)
			if tree.get(param_name) != null:
				tree.set(param_name, HerenCoordsScript.deserialize_value(params[key]))

	_undo_redo.begin_action("Heren Create AnimationTree")
	_undo_redo.add_do_method(player, &"add_child", [tree])
	_undo_redo.add_do_property(tree, &"owner", root)
	_undo_redo.add_undo_method(player, &"remove_child", [tree])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"state_machine": true,
		"graph_type": graph_type,
		"tree_path": _node_path_relative(player, root) + "/" + tree.name,
		"parameters": params.size(),
	}


func _build_state_machine(args: Dictionary) -> AnimationNodeStateMachine:
	var state_machine := AnimationNodeStateMachine.new()
	var states: Array = args.get("states", [])
	for state in states:
		var state_dict: Dictionary = state if state is Dictionary else {}
		var state_name: String = str(state_dict.get("name", ""))
		var anim_name: String = str(state_dict.get("animation", ""))
		if state_name != "" and anim_name != "":
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			state_machine.add_node(state_name, anim_node)

	var transitions: Array = args.get("transitions", [])
	for transition in transitions:
		var trans_dict: Dictionary = transition if transition is Dictionary else {}
		var from_state: String = str(trans_dict.get("from", ""))
		var to_state: String = str(trans_dict.get("to", ""))
		var condition: String = str(trans_dict.get("condition", ""))
		if from_state != "" and to_state != "":
			var trans := AnimationNodeStateMachineTransition.new()
			if condition != "":
				trans.advance_condition = condition
			state_machine.add_transition(from_state, to_state, trans)
	return state_machine


func _build_blend_tree(args: Dictionary) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var nodes: Array = args.get("nodes", [])
	for n in nodes:
		var nd: Dictionary = n if n is Dictionary else {}
		var name: String = str(nd.get("name", ""))
		var node_type: String = str(nd.get("type", ""))
		if name == "" or node_type == "":
			continue
		var anim_node: AnimationNode = null
		match node_type:
			"animation":
				var an := AnimationNodeAnimation.new()
				an.animation = str(nd.get("animation", ""))
				anim_node = an
			"blend2":
				anim_node = AnimationNodeBlend2.new()
			"blend3":
				anim_node = AnimationNodeBlend3.new()
			"add2":
				anim_node = AnimationNodeAdd2.new()
			"add3":
				anim_node = AnimationNodeAdd3.new()
			"sub2":
				anim_node = AnimationNodeSub2.new()
			"sync":
				anim_node = AnimationNodeSync.new()
			"one_shot":
				anim_node = AnimationNodeOneShot.new()
			"time_scale":
				anim_node = AnimationNodeTimeScale.new()
			"time_seek":
				anim_node = AnimationNodeTimeSeek.new()
			"transition":
				anim_node = AnimationNodeTransition.new()
			"output":
				anim_node = AnimationNodeOutput.new()
			_:
				continue
		bt.add_node(name, anim_node)

	var connections: Array = args.get("connections", [])
	for c in connections:
		var cd: Dictionary = c if c is Dictionary else {}
		var from_node: String = str(cd.get("from", ""))
		var from_port: int = int(cd.get("from_port", 0))
		var to_node: String = str(cd.get("to", ""))
		var to_port: int = int(cd.get("to_port", 0))
		if from_node != "" and to_node != "":
			bt.connect_node(from_node, from_port, to_node)
	return bt


func _build_blend_space_1d(args: Dictionary) -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = float(args.get("min", 0.0))
	bs.max_space = float(args.get("max", 1.0))
	bs.blend_mode = int(args.get("blend_mode", 0))
	bs.snap = float(args.get("snap", 0.1))
	var points: Array = args.get("points", [])
	for p in points:
		var pd: Dictionary = p if p is Dictionary else {}
		var anim_name: String = str(pd.get("animation", ""))
		var pos: float = float(pd.get("position", 0.0))
		if anim_name != "":
			var an := AnimationNodeAnimation.new()
			an.animation = anim_name
			bs.add_blend_point(an, pos)
	return bs


func _build_blend_space_2d(args: Dictionary) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(float(args.get("min_x", -1.0)), float(args.get("min_y", -1.0)))
	bs.max_space = Vector2(float(args.get("max_x", 1.0)), float(args.get("max_y", 1.0)))
	bs.blend_mode = int(args.get("blend_mode", 0))
	bs.snap = Vector2(float(args.get("snap_x", 0.1)), float(args.get("snap_y", 0.1)))
	bs.x_label = str(args.get("x_label", "x"))
	bs.y_label = str(args.get("y_label", "y"))
	var points: Array = args.get("points", [])
	for p in points:
		var pd: Dictionary = p if p is Dictionary else {}
		var anim_name: String = str(pd.get("animation", ""))
		var pos := Vector2(float(pd.get("x", 0.0)), float(pd.get("y", 0.0)))
		if anim_name != "":
			var an := AnimationNodeAnimation.new()
			an.animation = anim_name
			bs.add_blend_point(an, pos)
	return bs


# ---------------------------------------------------------------- edición (Fase 2)

func handle_remove_track(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	anim.remove_track(track_idx)
	return {"ok": true, "anim_name": anim_name, "removed_track": track_idx, "tracks_left": anim.get_track_count()}


func handle_remove_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	var key_idx: int = int(args.get("key_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"ok": false, "error": "invalid_key_idx: " + str(key_idx)}
	anim.track_remove_key(track_idx, key_idx)
	return {"ok": true, "anim_name": anim_name, "track_idx": track_idx, "removed_key": key_idx}


func handle_update_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	var key_idx: int = int(args.get("key_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"ok": false, "error": "invalid_key_idx: " + str(key_idx)}

	if args.has("time"):
		anim.track_set_key_time(track_idx, key_idx, float(args.get("time")))
	if args.has("value"):
		anim.track_set_key_value(track_idx, key_idx, HerenCoordsScript.deserialize_value(args.get("value")))
	if args.has("transition"):
		anim.track_set_key_transition(track_idx, key_idx, float(args.get("transition")))

	return {"ok": true, "anim_name": anim_name, "track_idx": track_idx, "key_idx": key_idx}


func handle_update_props(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	if args.has("length"):
		anim.length = float(args.get("length"))
	if args.has("loop"):
		anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop")) else Animation.LOOP_NONE
	if args.has("loop_mode"):
		match str(args.get("loop_mode")):
			"linear":
				anim.loop_mode = Animation.LOOP_LINEAR
			"pingpong":
				anim.loop_mode = Animation.LOOP_PINGPONG
			_:
				anim.loop_mode = Animation.LOOP_NONE

	return {"ok": true, "anim_name": anim_name, "length": anim.length, "loop_mode": _loop_mode_str(anim.loop_mode)}


# ---------------------------------------------------------------- one_shot (Fase 2)

func handle_one_shot(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}

	var anim := Animation.new()
	anim.length = float(args.get("length", 1.0))
	if args.has("loop_mode"):
		match str(args.get("loop_mode")):
			"linear":
				anim.loop_mode = Animation.LOOP_LINEAR
			"pingpong":
				anim.loop_mode = Animation.LOOP_PINGPONG
			_:
				anim.loop_mode = Animation.LOOP_NONE
	else:
		anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var tracks: Array = args.get("tracks", [])
	var track_count := 0
	var key_count := 0
	for t in tracks:
		var td: Dictionary = t if t is Dictionary else {}
		var node_path: String = str(td.get("node", ""))
		var property: String = str(td.get("property", ""))
		var track_type: String = str(td.get("track_type", "value"))
		if node_path == "":
			continue

		var track_idx := -1
		match track_type:
			"value":
				track_idx = anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(track_idx, node_path + ":" + property)
			"position_3d", "rotation_3d", "scale_3d":
				track_idx = anim.add_track(Animation.TYPE_POSITION_3D if track_type == "position_3d" else Animation.TYPE_ROTATION_3D if track_type == "rotation_3d" else Animation.TYPE_SCALE_3D)
				anim.track_set_path(track_idx, node_path)
			"method":
				track_idx = anim.add_track(Animation.TYPE_METHOD)
				anim.track_set_path(track_idx, node_path)
			"bezier":
				track_idx = anim.add_track(Animation.TYPE_BEZIER)
				anim.track_set_path(track_idx, node_path + ":" + property)
			"audio":
				track_idx = anim.add_track(Animation.TYPE_AUDIO)
				anim.track_set_path(track_idx, node_path)
			_:
				continue
		track_count += 1

		var keys: Array = td.get("keys", [])
		for k in keys:
			var kd: Dictionary = k if k is Dictionary else {}
			var time: float = float(kd.get("time", 0.0))
			var transition: float = float(kd.get("transition", 1.0))
			if track_type == "method":
				var method_name: String = str(kd.get("method", ""))
				var method_args: Array = kd.get("args", [])
				var m := {"method": method_name, "args": method_args}
				anim.track_insert_key(track_idx, time, m, transition)
			else:
				var value: Variant = HerenCoordsScript.deserialize_value(kd.get("value"))
				anim.track_insert_key(track_idx, time, value, transition)
			key_count += 1

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"length": anim.length,
		"loop_mode": _loop_mode_str(anim.loop_mode),
		"tracks": track_count,
		"keys": key_count,
		"player_path": _node_path_relative(player, root),
	}


# ---------------------------------------------------------------- tween (Fase 3)

func handle_tween(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("node_path", ""))
	if node == null:
		return {"ok": false, "error": "node_not_found"}
	var property: String = str(args.get("property", ""))
	if property == "":
		return {"ok": false, "error": "property required"}

	var duration: float = float(args.get("duration", 1.0))
	var to_value: Variant = HerenCoordsScript.deserialize_value(args.get("to"))
	var from_value: Variant = HerenCoordsScript.deserialize_value(args.get("from", null))
	var easing: String = str(args.get("easing", "linear"))
	var transition: String = str(args.get("transition", "linear"))

	var tween := node.create_tween()
	var tween_prop: PropertyTweener
	if from_value != null:
		tween_prop = tween.tween_property(node, property, to_value, duration).from(from_value)
	else:
		tween_prop = tween.tween_property(node, property, to_value, duration)
	tween_prop.set_trans(_tween_transition(transition))
	tween_prop.set_ease(_tween_ease(easing))

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"duration": duration,
		"to": HerenCoordsScript.serialize_value(to_value),
		"easing": easing,
		"transition": transition,
	}


func _tween_transition(name: String) -> int:
	match name:
		"quad": return Tween.TRANS_QUAD
		"cubic": return Tween.TRANS_CUBIC
		"quart": return Tween.TRANS_QUART
		"quint": return Tween.TRANS_QUINT
		"sine": return Tween.TRANS_SINE
		"expo": return Tween.TRANS_EXPO
		"circ": return Tween.TRANS_CIRC
		"elastic": return Tween.TRANS_ELASTIC
		"back": return Tween.TRANS_BACK
		"bounce": return Tween.TRANS_BOUNCE
		_:
			return Tween.TRANS_LINEAR


func _tween_ease(name: String) -> int:
	match name:
		"in": return Tween.EASE_IN
		"out": return Tween.EASE_OUT
		"in_out": return Tween.EASE_IN_OUT
		"out_in": return Tween.EASE_OUT_IN
		_:
			return Tween.EASE_IN_OUT


# ---------------------------------------------------------------- skeleton pose/ik (Fase 3)

func handle_skeleton_get_bones(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}

	var bones: Array = []
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			bones.append({
				"idx": i,
				"name": b.name,
				"rest": HerenCoordsScript.serialize_value(b.rest),
				"default_length": b.default_length,
			})
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		for i in skel3d.get_bone_count():
			bones.append({
				"idx": i,
				"name": skel3d.get_bone_name(i),
				"rest": HerenCoordsScript.serialize_value(skel3d.get_bone_rest(i)),
				"parent": skel3d.get_bone_parent(i),
			})
	else:
		return {"ok": false, "error": "invalid_skeleton_type"}

	return {"ok": true, "skeleton_path": _node_path_relative(node, root), "bones": bones}


func handle_skeleton_get_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}

	var pose: Array = []
	var world_positions: Array = []
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			pose.append({
				"name": b.name,
				"transform": HerenCoordsScript.serialize_value(b.transform),
				"global": HerenCoordsScript.serialize_value(b.global_position),
				"parent": b.get_parent().name if b.get_parent() is Bone2D else "",
			})
			world_positions.append(b.global_position)
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		for i in skel3d.get_bone_count():
			var bone_name: String = skel3d.get_bone_name(i)
			var global_pose: Transform3D = skel3d.get_bone_global_pose(i)
			pose.append({
				"name": bone_name,
				"pose": HerenCoordsScript.serialize_value(skel3d.get_bone_pose(i)),
				"global": HerenCoordsScript.serialize_value(global_pose.origin),
				"global_transform": HerenCoordsScript.serialize_value(global_pose),
				"parent": skel3d.get_bone_parent(i),
			})
			world_positions.append(global_pose.origin)
	else:
		return {"ok": false, "error": "invalid_skeleton_type"}

	# AABB de la pose actual (bounding box de las posiciones mundiales de los huesos).
	var aabb := {}
	if not world_positions.is_empty():
		var min_x := INF; var min_y := INF; var min_z := INF
		var max_x := -INF; var max_y := -INF; var max_z := -INF
		for p in world_positions:
			min_x = min(min_x, p.x); min_y = min(min_y, p.y); min_z = min(min_z, p.z)
			max_x = max(max_x, p.x); max_y = max(max_y, p.y); max_z = max(max_z, p.z)
		aabb = {
			"min": {"x": min_x, "y": min_y, "z": min_z},
			"max": {"x": max_x, "y": max_y, "z": max_z},
			"size": {"x": max_x - min_x, "y": max_y - min_y, "z": max_z - min_z},
		}

	return {"ok": true, "skeleton_path": _node_path_relative(node, root), "pose": pose, "aabb": aabb}


func handle_skeleton_set_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	if bone_name == "":
		return {"ok": false, "error": "bone_name required"}

	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			if b.name == bone_name:
				var t: Dictionary = _args_dict(args, "transform")
				var angle: float = float(t.get("angle", t.get("rotation", 0.0)))
				var origin := Vector2(float(t.get("x", 0)), float(t.get("y", 0)))
				b.transform = Transform2D(angle, origin)
				return {"ok": true, "bone_name": bone_name, "type": "Skeleton2D"}
		return {"ok": false, "error": "bone_not_found: " + bone_name}
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		var bone_idx: int = skel3d.find_bone(bone_name)
		if bone_idx < 0:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var t: Dictionary = _args_dict(args, "transform")
		var origin := Vector3(float(t.get("x", 0)), float(t.get("y", 0)), float(t.get("z", 0)))
		var basis := Basis()
		if t.has("rotation"):
			var rot: Dictionary = t["rotation"] if t["rotation"] is Dictionary else {}
			basis = Basis.from_euler(Vector3(float(rot.get("x", 0)), float(rot.get("y", 0)), float(rot.get("z", 0))))
		skel3d.set_bone_pose(bone_idx, Transform3D(basis, origin))
		return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton3D"}
	return {"ok": false, "error": "invalid_skeleton_type"}


# ---------------------------------------------------------------- innovación (Fase 4)

func handle_record(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found"}
	var property: String = str(args.get("property", "position"))
	var fps: float = float(args.get("fps", 30.0))
	var duration: float = float(args.get("duration", 1.0))

	# Graba el estado del nodo cada frame durante `duration` segundos.
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, node_path + ":" + property)

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var value: Variant = node.get(property)
		anim.track_insert_key(track_idx, t, value, 1.0)
		# Avanzar un frame del editor para capturar el siguiente estado.
		await _editor_interface().get_base_control().get_tree().process_frame

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"property": property,
		"fps": fps,
		"duration": duration,
		"keys": steps + 1,
	}


func handle_from_path(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var path_node := _resolve_node(root, args.get("path_path", ""))
	if path_node == null:
		return {"ok": false, "error": "path_not_found"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var is_3d: bool = path_node is Path3D
	var curve: Variant = null
	if path_node is Path2D:
		curve = (path_node as Path2D).curve
	elif path_node is Path3D:
		curve = (path_node as Path3D).curve
	if curve == null:
		return {"ok": false, "error": "path_has_no_curve"}

	var duration: float = float(args.get("duration", 1.0))
	var fps: float = float(args.get("fps", 30.0))

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE
	var track_idx := anim.add_track(Animation.TYPE_POSITION_3D if is_3d else Animation.TYPE_VALUE)
	var prop: String = "position" if is_3d else "position"
	anim.track_set_path(track_idx, node_path + (":" + prop if not is_3d else ""))

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var offset: float = t / duration
		if is_3d:
			var pos3: Vector3 = (path_node as Path3D).curve.sample_baked(offset * (path_node as Path3D).curve.get_baked_length())
			anim.track_insert_key(track_idx, t, pos3, 1.0)
		else:
			var pos2: Vector2 = (path_node as Path2D).curve.sample_baked(offset * (path_node as Path2D).curve.get_baked_length())
			anim.track_insert_key(track_idx, t, pos2, 1.0)

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"path": _node_path_relative(path_node, root),
		"duration": duration,
		"keys": steps + 1,
		"is_3d": is_3d,
	}


func handle_loop_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found"}

	# Genera keyframes de bucle procedural (idle bob / breathing / walk simple).
	var property: String = str(args.get("property", "position"))
	var amplitude: float = float(args.get("amplitude", 10.0))
	var frequency: float = float(args.get("frequency", 2.0))
	var duration: float = float(args.get("duration", 1.0))
	var fps: float = float(args.get("fps", 30.0))
	var axis: String = str(args.get("axis", "y"))
	var base_value: Variant = node.get(property)

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, node_path + ":" + property)

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var phase: float = t * frequency * TAU
		var offset: float = sin(phase) * amplitude
		var value: Variant = base_value
		if value is Vector2:
			var v2 := value as Vector2
			if axis == "x":
				v2.x += offset
			else:
				v2.y += offset
			value = v2
		elif value is Vector3:
			var v3 := value as Vector3
			if axis == "x":
				v3.x += offset
			elif axis == "z":
				v3.z += offset
			else:
				v3.y += offset
			value = v3
		elif value is float:
			value = float(value) + offset
		anim.track_insert_key(track_idx, t, value, 1.0)

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"property": property,
		"amplitude": amplitude,
		"frequency": frequency,
		"axis": axis,
		"keys": steps + 1,
	}


func handle_curve(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	# Aplica easing a todos los keyframes del track (Fase 4: animation/curve).
	var easing: String = str(args.get("easing", "linear"))
	var transition: float = _easing_transition(easing)
	for k in anim.track_get_key_count(track_idx):
		anim.track_set_key_transition(track_idx, k, transition)

	return {
		"ok": true,
		"anim_name": anim_name,
		"track_idx": track_idx,
		"easing": easing,
		"keys_updated": anim.track_get_key_count(track_idx),
	}


func _easing_transition(easing: String) -> float:
	# Mapea nombres de easing a valores de transition de Godot (0..1).
	match easing:
		"linear": return 0.0
		"ease_in": return 0.2
		"ease_out": return 0.8
		"ease_in_out": return 0.5
		"elastic": return 0.9
		"bounce": return 0.7
		_:
			return 0.0


# ------------------------------------------------- playback + inspección (Fase 1)

func _player_or_error(root: Node, args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	return {"ok": true, "player": player}


func handle_play(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	var custom_blend: float = float(args.get("custom_blend", -1.0))

	if anim_name != "":
		if not player.has_animation(anim_name):
			return {"ok": false, "error": "animation_not_found: " + anim_name}
		if custom_blend >= 0.0:
			player.play(anim_name, custom_blend)
		else:
			player.play(anim_name)
	else:
		# Reproduce la animación actual (o la primera si no hay ninguna).
		player.play()

	return {
		"ok": true,
		"playing": player.is_playing(),
		"current_animation": player.current_animation,
		"position": player.current_animation_position,
		"player_path": _node_path_relative(player, root),
	}


func handle_stop(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	player.stop()
	return {
		"ok": true,
		"playing": false,
		"player_path": _node_path_relative(player, root),
	}


func handle_seek(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var time: float = float(args.get("time", 0.0))
	player.seek(time, true)
	return {
		"ok": true,
		"position": player.current_animation_position,
		"player_path": _node_path_relative(player, root),
	}


func handle_speed(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var speed: float = float(args.get("speed", 1.0))
	player.speed_scale = speed
	return {
		"ok": true,
		"speed_scale": player.speed_scale,
		"player_path": _node_path_relative(player, root),
	}


func handle_get_animations(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player

	var libs: Array = []
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		var anims: Array = []
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			anims.append({
				"name": anim_name,
				"length": anim.length,
				"loop_mode": _loop_mode_str(anim.loop_mode),
				"tracks": anim.get_track_count(),
			})
		libs.append({"library": lib_name if lib_name != "" else "<default>", "animations": anims})

	return {
		"ok": true,
		"current_animation": player.current_animation,
		"playing": player.is_playing(),
		"position": player.current_animation_position,
		"libraries": libs,
		"player_path": _node_path_relative(player, root),
	}


func handle_get_tracks(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	var tracks: Array = []
	for i in anim.get_track_count():
		var track_type: int = anim.track_get_type(i)
		var track_path: String = str(anim.track_get_path(i))
		tracks.append({
			"idx": i,
			"type": _track_type_str(track_type),
			"path": track_path,
			"keys": anim.track_get_key_count(i),
			"enabled": anim.track_is_enabled(i),
		})

	return {
		"ok": true,
		"anim_name": anim_name,
		"length": anim.length,
		"loop_mode": _loop_mode_str(anim.loop_mode),
		"tracks": tracks,
	}


func handle_get_keyframes(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	var keys: Array = []
	for k in anim.track_get_key_count(track_idx):
		var key := {
			"idx": k,
			"time": anim.track_get_key_time(track_idx, k),
			"transition": anim.track_get_key_transition(track_idx, k),
		}
		if anim.track_get_type(track_idx) != Animation.TYPE_METHOD:
			key["value"] = HerenCoordsScript.serialize_value(anim.track_get_key_value(track_idx, k))
		else:
			var m: Dictionary = anim.track_get_key_value(track_idx, k)
			key["method"] = str(m.get("method", ""))
			key["args"] = HerenCoordsScript.serialize_value(m.get("args", []))
		keys.append(key)

	return {
		"ok": true,
		"anim_name": anim_name,
		"track_idx": track_idx,
		"track_type": _track_type_str(anim.track_get_type(track_idx)),
		"keys": keys,
	}


func handle_get_state_machine(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tree_path: Variant = args.get("tree_path", "")
	var tree: AnimationTree = null
	if tree_path != null and str(tree_path) != "":
		tree = _resolve_node(root, tree_path) as AnimationTree
	else:
		# Buscar el AnimationTree hijo del player (o cualquier AnimationTree del root).
		var resolved := _player_or_error(root, args)
		if resolved.ok:
			var player: AnimationPlayer = resolved.player
			for child in player.get_children():
				if child is AnimationTree:
					tree = child as AnimationTree
					break
		if tree == null:
			for child in root.get_children():
				if child is AnimationTree:
					tree = child as AnimationTree
					break
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}

	var graph_root: AnimationNode = tree.tree_root
	var info := {
		"root_type": graph_root.get_class() if graph_root != null else "",
		"tree_path": _node_path_relative(tree, root),
		"parameters": [],
	}

	if graph_root is AnimationNodeStateMachine:
		var sm := graph_root as AnimationNodeStateMachine
		var states: Array = []
		for state_name in sm.get_node_list():
			var state_node: AnimationNode = sm.get_node(state_name)
			var state_info := {"name": str(state_name), "type": state_node.get_class()}
			if state_node is AnimationNodeAnimation:
				state_info["animation"] = (state_node as AnimationNodeAnimation).animation
			states.append(state_info)
		info["states"] = states

		var transitions: Array = []
		for t in sm.get_transition_list():
			transitions.append({
				"from": str(t.get("from", "")),
				"to": str(t.get("to", "")),
				"advance_condition": str(t.get("advance_condition", "")),
			})
		info["transitions"] = transitions
	elif graph_root is AnimationNodeBlendSpace2D:
		var bs := graph_root as AnimationNodeBlendSpace2D
		var points: Array = []
		for p in bs.get_blend_points():
			var anim_node := bs.get_blend_point_node(p) as AnimationNodeAnimation
			points.append({
				"point": bs.get_blend_point_position(p),
				"animation": anim_node.animation if anim_node else "",
			})
		info["blend_space_2d"] = {
			"blend_positions": bs.blend_positions,
			"blend_point_count": points.size(),
			"x_label": bs.x_label, "y_label": bs.y_label,
		}
		info["points"] = points
	elif graph_root is AnimationNodeBlendTree:
		var bt := graph_root as AnimationNodeBlendTree
		var nodes: Array = []
		for n in bt.get_node_list():
			nodes.append({"name": str(n), "type": bt.get_node(n).get_class()})
		info["blend_tree"] = {"nodes": nodes, "connections": bt.get_connection_list().size()}

	for p in tree.get_parameter_list():
		info["parameters"].append(str(p))
	if graph_root != null:
		info["root_parameters"] = tree.get_parameter_list().size()

	return {"ok": true, "state_machine": info}


func _loop_mode_str(mode: int) -> String:
	match mode:
		Animation.LOOP_LINEAR:
			return "linear"
		Animation.LOOP_PINGPONG:
			return "pingpong"
		Animation.LOOP_NONE:
			return "none"
	return "none"


func _track_type_str(type_id: int) -> String:
	match type_id:
		Animation.TYPE_VALUE:
			return "value"
		Animation.TYPE_POSITION_3D:
			return "position_3d"
		Animation.TYPE_ROTATION_3D:
			return "rotation_3d"
		Animation.TYPE_SCALE_3D:
			return "scale_3d"
		Animation.TYPE_BEZIER:
			return "bezier"
		Animation.TYPE_AUDIO:
			return "audio"
		Animation.TYPE_METHOD:
			return "method"
	return "unknown"


# ---------------------------------------------------------------- skeleton

func handle_skeleton_create(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	var skeleton_name: String = str(args.get("skeleton_name", "Skeleton2D"))
	var is_3d: bool = bool(args.get("is_3d", false))
	if parent.get_node_or_null(NodePath(skeleton_name)) != null:
		return {"ok": false, "error": "node_exists: " + skeleton_name}

	var skeleton: Node
	if is_3d:
		skeleton = Skeleton3D.new()
	else:
		skeleton = Skeleton2D.new()
	skeleton.name = skeleton_name

	_undo_redo.begin_action("Heren Add Skeleton")
	_undo_redo.add_do_method(parent, &"add_child", [skeleton])
	_undo_redo.add_do_property(skeleton, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [skeleton])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(parent, root) + "/" + skeleton.name,
		"skeleton_type": "Skeleton3D" if is_3d else "Skeleton2D",
	}


func handle_skeleton_add_bone(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var skeleton_path: Variant = args.get("skeleton_path", "")
	var skeleton := _resolve_node(root, skeleton_path)
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	if bone_name == "":
		return {"ok": false, "error": "bone_name required"}

	var rest_transform: Dictionary = _args_dict(args, "rest_transform")

	if skeleton is Skeleton2D:
		var bone := Bone2D.new()
		bone.name = bone_name
		var angle: float = float(args.get("bone_angle", 0.0))
		bone.rest = Transform2D(angle, Vector2(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0))
		))
		bone.default_length = float(args.get("length", 32.0))
		skeleton.add_child(bone)
		bone.owner = root
		return {"ok": true, "bone_name": bone_name, "type": "Bone2D"}

	elif skeleton is Skeleton3D:
		var skel3d := skeleton as Skeleton3D
		var bone_idx := skel3d.find_bone(bone_name)
		if bone_idx < 0:
			bone_idx = skel3d.add_bone(bone_name)
		var origin := Vector3(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0)),
			float(rest_transform.get("z", 0))
		)
		var basis := Basis()
		if rest_transform.has("rotation"):
			var rot: Dictionary = rest_transform["rotation"] if rest_transform["rotation"] is Dictionary else {}
			basis = Basis.from_euler(Vector3(
				float(rot.get("x", 0)),
				float(rot.get("y", 0)),
				float(rot.get("z", 0))
			))
		skel3d.set_bone_rest(bone_idx, Transform3D(basis, origin))
		return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton3D"}

	return {"ok": false, "error": "invalid_skeleton_type"}


func handle_skeleton_set_rest(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var rest_transform: Dictionary = _args_dict(args, "rest_transform")

	# Fix H4: branch by actual type (Skeleton2D vs Skeleton3D) instead of
	# forcing Skeleton3D.
	#
	# IMPORTANT (Godot 4.7): Skeleton2D has NO set_bone_rest / find_bone
	# (those are Skeleton3D methods). In Skeleton2D each bone IS a Bone2D
	# child node; the rest pose is `bone.rest = Transform2D(...)`. So we
	# find the Bone2D child by name and set its .rest directly.
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var angle: float = float(rest_transform.get("angle", rest_transform.get("rotation", 0.0)))
		var origin := Vector2(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0))
		)
		var bone: Node = null
		for child in skel2d.get_children():
			if child is Bone2D and child.name == bone_name:
				bone = child
				break
		if bone == null:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		(bone as Bone2D).rest = Transform2D(angle, origin)
		return {"ok": true, "bone_name": bone_name, "type": "Skeleton2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"ok": false, "error": "bone_not_found: " + bone_name}

	var origin := Vector3(
		float(rest_transform.get("x", 0)),
		float(rest_transform.get("y", 0)),
		float(rest_transform.get("z", 0))
	)
	var basis := Basis()
	if rest_transform.has("rotation"):
		var rot: Dictionary = rest_transform["rotation"] if rest_transform["rotation"] is Dictionary else {}
		basis = Basis.from_euler(Vector3(
			float(rot.get("x", 0)),
			float(rot.get("y", 0)),
			float(rot.get("z", 0))
		))
	skeleton.set_bone_rest(bone_idx, Transform3D(basis, origin))

	return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton3D"}


func handle_skeleton_skin(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var polygon := _resolve_node(root, args.get("polygon_path", "")) as Polygon2D
	var skeleton := _resolve_node(root, args.get("skeleton_path", "")) as Skeleton2D
	if polygon == null:
		return {"ok": false, "error": "polygon2d_not_found"}
	if skeleton == null:
		return {"ok": false, "error": "skeleton2d_not_found"}

	polygon.skeleton = skeleton.get_path()

	var bone_weights: Dictionary = _args_dict(args, "bone_weights")
	var bones: Array = []
	for bone_name in bone_weights.keys():
		var weights: Array = bone_weights[bone_name]
		# Fix H3: `set_bone_weights` (not `set_bone_weigths`) and it takes
		# a bone INDEX (int), not a bone name (String).
		#
		# Fix H4: Skeleton2D has NO find_bone (Skeleton3D method) — locate the
		# Bone2D child index by iterating get_bone_count()/get_bone().
		var bone_idx := -1
		for i in skeleton.get_bone_count():
			if skeleton.get_bone(i).name == str(bone_name):
				bone_idx = i
				break
		if bone_idx == -1:
			return {"ok": false, "error": "bone_not_found: " + str(bone_name)}
		polygon.set_bone_weights(bone_idx, PackedFloat32Array(weights))
		bones.append(bone_name)

	return {"ok": true, "polygon": polygon.name, "skeleton": skeleton.name, "bones": bones}


func handle_skeleton_attachment(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var attachment_name: String = str(args.get("attachment_name", "Attachment"))

	# Fix H4: branch by type. 2D uses a plain Node2D child of the Bone2D
	# (BoneAttachment2D does NOT exist in Godot 4); 3D uses BoneAttachment3D.
	# Skeleton2D has no find_bone (Skeleton3D method) — find the Bone2D child.
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var bone: Node = null
		var bone_idx := -1
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			if b.name == bone_name:
				bone = b
				bone_idx = i
				break
		if bone == null:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var att2d := Node2D.new()
		att2d.name = attachment_name
		bone.add_child(att2d)
		att2d.owner = root
		return {"ok": true, "attachment": att2d.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"ok": false, "error": "bone_not_found: " + bone_name}
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.owner = root

	return {"ok": true, "attachment": attachment.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment3D"}


# ---------------------------------------------------------------- P1: capture_pose + bone tracks + tree control

## Resuelve los huesos a capturar: bones (lista exacta) → chain (cadena ordenada)
## → from_bone+depth (desde un hueso hacia abajo) → todos si nada se especifica.
func _resolve_capture_bones(args: Dictionary, skeleton: Node) -> Array:
	var names: Array = []
	if args.has("bones"):
		var raw: Variant = args.get("bones", [])
		if raw is Array:
			for b in raw:
				names.append(str(b))
	if names.is_empty() and args.has("chain"):
		var raw_chain: Variant = args.get("chain", [])
		if raw_chain is Array:
			for b in raw_chain:
				names.append(str(b))
	if names.is_empty() and args.has("from_bone"):
		var start_name: String = str(args.get("from_bone", ""))
		var depth: int = int(args.get("depth", -1))
		names = _bone_chain_from(skeleton, start_name, depth)
	if names.is_empty():
		# Todos los huesos en orden jerárquico (padre→hijo).
		if skeleton is Skeleton2D:
			for i in (skeleton as Skeleton2D).get_bone_count():
				names.append(str((skeleton as Skeleton2D).get_bone(i).name))
		elif skeleton is Skeleton3D:
			for i in (skeleton as Skeleton3D).get_bone_count():
				names.append((skeleton as Skeleton3D).get_bone_name(i))
	return names


## Cadena de huesos desde un hueso raíz hacia abajo (BFS, parent→child).
func _bone_chain_from(skeleton: Node, start_name: String, depth: int) -> Array:
	var all_bones: Array = []
	var children_of := {}
	var root_bone_idx := -1
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		for i in skel.get_bone_count():
			var n := skel.get_bone_name(i)
			all_bones.append(n)
			var parent := skel.get_bone_parent(i)
			if parent >= 0:
				children_of[skel.get_bone_name(parent)] = (children_of.get(skel.get_bone_name(parent), []) as Array) + [n]
			if n == start_name:
				root_bone_idx = i
		if root_bone_idx < 0:
			return []
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		for i in skel.get_bone_count():
			var b := skel.get_bone(i)
			all_bones.append(str(b.name))
			if b.get_parent() is Bone2D:
				children_of[str(b.get_parent().name)] = (children_of.get(str(b.get_parent().name), []) as Array) + [str(b.name)]
		if not all_bones.has(start_name):
			return []

	var result: Array = [start_name]
	var frontier: Array = [start_name]
	var visited := {start_name: true}
	var level := 0
	while not frontier.is_empty() and (depth < 0 or level < depth):
		var next: Array = []
		for f in frontier:
			var kids: Array = children_of.get(f, [])
			for k in kids:
				if not visited.has(k):
					visited[k] = true
					result.append(k)
					next.append(k)
		frontier = next
		level += 1
	return result


## Inserta (o reusa) un track de pose de hueso en la animación.
## 3D: track TYPE_VALUE con path "Skeleton:bones/<idx>/pose" y valor Transform3D.
## 2D: track TYPE_VALUE con path "Bone2D:rotation" o "Bone2D:position".
func _ensure_bone_track(anim: Animation, skeleton: Node, bone_name: String, dim: String) -> int:
	var track_idx := -1
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		var idx: int = skel.find_bone(bone_name)
		if idx < 0:
			return -1
		var path := str(skeleton.get_path()) + ":bones/" + str(idx) + "/pose"
		for i in anim.get_track_count():
			if str(anim.track_get_path(i)) == path:
				return i
		track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, path)
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		var bone: Bone2D = null
		for i in skel.get_bone_count():
			if skel.get_bone(i).name == bone_name:
				bone = skel.get_bone(i)
				break
		if bone == null:
			return -1
		var prop: String = "rotation" if dim == "2d_rotation" else "position"
		var path := str(bone.get_path()) + ":" + prop
		for i in anim.get_track_count():
			if str(anim.track_get_path(i)) == path:
				return i
		track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, path)
	return track_idx


## P1: snapshot de la pose actual del esqueleto como keyframes en un tiempo dado.
## Captura "en cadena" soportada: bones|chain|from_bone+depth.
func handle_capture_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var skeleton := _resolve_node(root, args.get("skeleton_path", ""))
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var time: float = float(args.get("time", 0.0))
	var dim: String = str(args.get("dim", "3d"))
	if skeleton is Skeleton2D:
		dim = "2d"

	var bone_names: Array = _resolve_capture_bones(args, skeleton)
	if bone_names.is_empty():
		return {"ok": false, "error": "no_bones_resolved"}
	var keys_inserted := 0

	for bone_name in bone_names:
		if skeleton is Skeleton3D:
			var skel := skeleton as Skeleton3D
			var idx: int = skel.find_bone(str(bone_name))
			if idx < 0:
				continue
			var track_idx := _ensure_bone_track(anim, skeleton, str(bone_name), "3d")
			if track_idx < 0:
				continue
			var pose: Transform3D = skel.get_bone_pose(idx)
			anim.track_insert_key(track_idx, time, pose, 1.0)
			keys_inserted += 1
		elif skeleton is Skeleton2D:
			var skel := skeleton as Skeleton2D
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == bone_name:
					bone = skel.get_bone(i)
					break
			if bone == null:
				continue
			# Captura rotación y posición del Bone2D.
			var rot_track := _ensure_bone_track(anim, skeleton, str(bone_name), "2d_rotation")
			if rot_track >= 0:
				anim.track_insert_key(rot_track, time, bone.rotation, 1.0)
				keys_inserted += 1
			var pos_track := _ensure_bone_track(anim, skeleton, str(bone_name), "2d_position")
			if pos_track >= 0:
				anim.track_insert_key(pos_track, time, bone.position, 1.0)
				keys_inserted += 1

	return {
		"ok": true,
		"anim_name": anim_name,
		"time": time,
		"bones_captured": bone_names.size(),
		"keys_inserted": keys_inserted,
		"bones": bone_names,
	}


## Amplía add_track para soportar track_type="bone" (resuelve path por nombre).
func handle_add_track(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	var track_type: String = str(args.get("track_type", "value"))
	var node_path: String = str(args.get("node_path", ""))
	var property: String = str(args.get("property", ""))

	var anim: Animation = player.get_animation(anim_name) if player.has_animation(anim_name) else null
	if anim == null:
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	# P1: track_type="bone" — resuelve el path del hueso por nombre.
	if track_type == "bone":
		var skeleton_path: Variant = args.get("skeleton_path", "")
		var skeleton := _resolve_node(root, skeleton_path)
		if skeleton == null:
			return {"ok": false, "error": "skeleton_not_found"}
		if skeleton is Skeleton3D:
			var skel := skeleton as Skeleton3D
			var idx: int = skel.find_bone(node_path)
			if idx < 0:
				return {"ok": false, "error": "bone_not_found: " + node_path}
			var track_idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, str(skeleton.get_path()) + ":bones/" + str(idx) + "/pose")
			return {"ok": true, "track_idx": track_idx, "track_type": "bone", "bone": node_path, "bone_idx": idx, "anim_name": anim_name}
		elif skeleton is Skeleton2D:
			var skel := skeleton as Skeleton2D
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == node_path:
					bone = skel.get_bone(i)
					break
			if bone == null:
				return {"ok": false, "error": "bone_not_found: " + node_path}
			var bone_prop: String = property if property != "" else "rotation"
			var track_idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, str(bone.get_path()) + ":" + bone_prop)
			return {"ok": true, "track_idx": track_idx, "track_type": "bone", "bone": node_path, "bone_prop": bone_prop, "anim_name": anim_name}
		return {"ok": false, "error": "invalid_skeleton_type"}

	var track_idx := -1
	match track_type:
		"value":
			track_idx = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, node_path + ":" + property)
		"position_3d", "rotation_3d", "scale_3d", "method":
			track_idx = anim.add_track(Animation.TYPE_POSITION_3D if track_type == "position_3d" else Animation.TYPE_ROTATION_3D if track_type == "rotation_3d" else Animation.TYPE_SCALE_3D if track_type == "scale_3d" else Animation.TYPE_METHOD)
			anim.track_set_path(track_idx, node_path)
		"bezier":
			track_idx = anim.add_track(Animation.TYPE_BEZIER)
			anim.track_set_path(track_idx, node_path + ":" + property)
		"audio":
			track_idx = anim.add_track(Animation.TYPE_AUDIO)
			anim.track_set_path(track_idx, node_path)
		_:
			return {"ok": false, "error": "invalid_track_type: " + track_type}

	return {"ok": true, "track_idx": track_idx, "track_type": track_type, "anim_name": anim_name}


# ---------------------------------------------------------------- P1: AnimationTree runtime control

func _resolve_tree(root: Node, args: Dictionary) -> AnimationTree:
	var tree_path: Variant = args.get("tree_path", "")
	if tree_path != null and str(tree_path) != "":
		return _resolve_node(root, tree_path) as AnimationTree
	# Buscar cualquier AnimationTree del root.
	for child in root.get_children():
		if child is AnimationTree:
			return child as AnimationTree
	return null


func handle_tree_activate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	tree.active = bool(args.get("active", true))
	# Si se pide reproducir un estado concreto, travel.
	if args.has("state") and str(args.get("state", "")) != "":
		var playback: Variant = tree.get("parameters/playback")
		if playback != null and playback is AnimationNodeStateMachinePlayback:
			playback.travel(str(args.get("state")))
	return {
		"ok": true,
		"active": tree.active,
		"tree_path": _node_path_relative(tree, root),
	}


func handle_tree_travel(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var state: String = str(args.get("state", ""))
	if state == "":
		return {"ok": false, "error": "state required"}
	var playback: Variant = tree.get("parameters/playback")
	if playback == null or not playback is AnimationNodeStateMachinePlayback:
		return {"ok": false, "error": "no state_machine_playback (graph_type debe ser state_machine)"}
	playback.travel(state)
	return {"ok": true, "traveled_to": state, "current_state": str(playback.get_current_node())}


func handle_tree_set_param(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var name: String = str(args.get("name", ""))
	if name == "":
		return {"ok": false, "error": "name required"}
	var param_name := "parameters/" + name
	if tree.get(param_name) == null:
		return {"ok": false, "error": "parameter_not_found: " + param_name}
	tree.set(param_name, HerenCoordsScript.deserialize_value(args.get("value")))
	return {"ok": true, "parameter": param_name, "value": HerenCoordsScript.serialize_value(tree.get(param_name))}


func handle_tree_get_param(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var name: String = str(args.get("name", ""))
	if name == "":
		# Devuelve todos los parámetros.
		var all := {}
		for p in tree.get_parameter_list():
			all[str(p)] = HerenCoordsScript.serialize_value(tree.get(str(p)))
		return {"ok": true, "parameters": all}
	var param_name := "parameters/" + name
	if tree.get(param_name) == null:
		return {"ok": false, "error": "parameter_not_found: " + param_name}
	return {"ok": true, "parameter": param_name, "value": HerenCoordsScript.serialize_value(tree.get(param_name))}


# ---------------------------------------------------------------- P1: IK a profundidad (procedural)

## Amplía skeleton_ik con magnet/influence y soporta "weights" por hueso.
func handle_skeleton_ik(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var skeleton := _resolve_node(root, args.get("skeleton_path", "")) as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "skeleton3d_not_found"}

	var ik_name: String = str(args.get("ik_name", "SkeletonIK3D"))
	var ik := SkeletonIK3D.new()
	ik.name = ik_name
	ik.skeleton = skeleton.get_path()
	ik.root_bone = str(args.get("root_bone", ""))
	ik.tip_bone = str(args.get("tip_bone", ""))
	ik.interpolation = float(args.get("interpolation", 1.0))
	ik.max_iterations = int(args.get("max_iterations", 10))
	ik.override_tip_basis = bool(args.get("override_tip_basis", false))
	ik.influence = float(args.get("influence", 1.0))
	ik.min_distance = float(args.get("min_distance", 0.001))
	ik.use_magnet = bool(args.get("use_magnet", false))
	if args.has("magnet"):
		var magnet_dict: Dictionary = _args_dict(args, "magnet")
		ik.magnet = Vector3(float(magnet_dict.get("x", 0)), float(magnet_dict.get("y", 0)), float(magnet_dict.get("z", 0)))

	var target_path: String = str(args.get("target_path", ""))
	if target_path != "":
		var target := _resolve_node(root, target_path)
		if target != null:
			ik.target_node = target.get_path()
	# target_position alternativo (sin nodo target, usa posición absoluta).
	elif args.has("target_position"):
		var tp: Dictionary = _args_dict(args, "target_position")
		var target := Node3D.new()
		target.name = ik_name + "_Target"
		target.position = Vector3(float(tp.get("x", 0)), float(tp.get("y", 0)), float(tp.get("z", 0)))
		skeleton.add_child(target)
		target.owner = root
		ik.target_node = target.get_path()

	skeleton.add_child(ik)
	ik.owner = root

	if bool(args.get("start", true)):
		ik.start()

	return {
		"ok": true,
		"ik_name": ik_name,
		"skeleton_path": _node_path_relative(skeleton, root),
		"root_bone": ik.root_bone,
		"tip_bone": ik.tip_bone,
		"influence": ik.influence,
		"running": ik.running,
	}


## P1: FABRIK 2D procedural — resuelve una cadena de Bone2D hacia un objetivo.
## Útil para animación procedural (brazos/piernas siguiendo un punto).
func handle_skeleton_fabrik(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var skeleton := _resolve_node(root, args.get("skeleton_path", "")) as Skeleton2D
	if skeleton == null:
		return {"ok": false, "error": "skeleton2d_not_found"}

	var target_pos := Vector2(float(args.get("target_x", 0)), float(args.get("target_y", 0)))
	var chain_names: Array = args.get("chain", [])
	if chain_names.is_empty():
		return {"ok": false, "error": "chain required (lista de nombres de hueso en orden)"}
	var max_iterations: int = int(args.get("max_iterations", 10))
	var tolerance: float = float(args.get("tolerance", 1.0))
	var weights: Dictionary = _args_dict(args, "weights")

	# Colectar huesos de la cadena.
	var bones: Array[Bone2D] = []
	for name in chain_names:
		var found: Bone2D = null
		for i in skeleton.get_bone_count():
			var b := skeleton.get_bone(i)
			if b.name == name:
				found = b
				break
		if found == null:
			return {"ok": false, "error": "bone_not_found: " + str(name)}
		bones.append(found)
	if bones.size() < 2:
		return {"ok": false, "error": "chain needs at least 2 bones"}

	# Guardar poses originales para restaurar en undo.
	var original_rests := {}
	for b in bones:
		original_rests[b.get_instance_id()] = b.transform

	# Posiciones globales de los pivotes (FABRIK clásico).
	var pts: Array[Vector2] = []
	for b in bones:
		pts.append(b.global_position)
	pts.append(target_pos)

	var converged := false
	for _it in max_iterations:
		# Backward (desde el final hacia la raíz).
		pts[pts.size() - 1] = target_pos
		for i in range(pts.size() - 2, -1, -1):
			var seg_len := (pts[i] - pts[i + 1]).length()
			var weight: float = float(weights.get(str(bones[i].name), 1.0))
			pts[i] = pts[i + 1] + (pts[i] - pts[i + 1]).normalized() * seg_len * weight
		# Forward (desde la raíz hacia el final).
		pts[0] = bones[0].global_position
		for i in range(1, pts.size()):
			var seg_len := (pts[i - 1] - pts[i]).length()
			var weight: float = float(weights.get(str(bones[i - 1].name), 1.0))
			pts[i] = pts[i - 1] + (pts[i] - pts[i - 1]).normalized() * seg_len * weight
		if (pts[pts.size() - 1] - target_pos).length() < tolerance:
			converged = true
			break

	# Aplicar: cada hueso apunta al siguiente punto (su rotación local).
	for i in bones.size():
		var b: Bone2D = bones[i]
		var p_cur: Vector2 = pts[i]
		var p_next: Vector2 = pts[i + 1]
		var parent_rot: float = b.get_parent().global_rotation if b.get_parent() is Node2D else 0.0
		var target_angle: float = (p_next - p_cur).angle()
		b.transform = Transform2D(target_angle - parent_rot, b.position)

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(skeleton, root),
		"chain": chain_names,
		"target": {"x": target_pos.x, "y": target_pos.y},
		"iterations": max_iterations,
		"converged": converged,
	}


## P1: preview con imagen — seek + captura del viewport (agente VE el frame).
func handle_preview(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var time: float = float(args.get("time", 0.0))
	player.seek(time, true)
	player.pause()
	RenderingServer.force_draw(true)

	var out := {
		"ok": true,
		"anim_name": anim_name,
		"time": time,
		"position": player.current_animation_position,
	}

	# Si pide imagen, captura el viewport activo.
	if bool(args.get("with_image", false)):
		var ei := _editor_interface()
		if ei != null:
			var viewport: Viewport = ei.get_editor_viewport_3d() if str(args.get("viewport", "2d")) == "3d" else ei.get_editor_viewport_2d()
			if viewport != null:
				RenderingServer.force_draw(true)
				var img: Image = viewport.get_texture().get_image()
				if img != null:
					img.flip_y()
					var png := img.save_png_to_buffer()
					if not png.is_empty():
						out["__image_base64"] = Marshalls.raw_to_base64(png)
						out["__image_format"] = "png"
						out["__image_w"] = img.get_width()
						out["__image_h"] = img.get_height()
	return out


# ---------------------------------------------------------------- P2: gestión de animaciones (duplicate/delete/rename)

func _get_library(player: AnimationPlayer, library: String) -> AnimationLibrary:
	var lib_name := library if library != "" else ""
	var lib := player.get_animation_library(lib_name)
	if lib == null and lib_name == "":
		return null
	return lib


func handle_duplicate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}

	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_copy"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	# duplicate() copia length, loop_mode y TODOS los tracks/keys.
	var copy: Animation = player.get_animation(anim_name).duplicate()
	lib.add_animation(new_name, copy)

	return {
		"ok": true,
		"anim_name": anim_name,
		"new_name": new_name,
		"tracks": copy.get_track_count(),
		"length": copy.length,
	}


func handle_delete(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}

	# Si está reproduciéndose, parar antes de borrar.
	if player.current_animation == anim_name:
		player.stop()
	lib.remove_animation(anim_name)

	return {"ok": true, "deleted": anim_name}


func handle_rename(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		return {"ok": false, "error": "new_name required"}
	if new_name == anim_name:
		return {"ok": false, "error": "new_name equals anim_name"}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	lib.rename_animation(anim_name, new_name)
	return {"ok": true, "renamed": anim_name, "to": new_name}


# ---------------------------------------------------------------- P3: avanzado (reverse/blend_pose/retarget)

## Crea una copia invertida de la animación (walk → walk_rev). Util para ciclos.
func handle_reverse(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_rev"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	var src: Animation = player.get_animation(anim_name)
	var rev: Animation = src.duplicate()
	var length: float = src.length

	# Invertir keys de cada track: t' = length - t. Reordenar por tiempo.
	for t in src.get_track_count():
		var key_count: int = src.track_get_key_count(t)
		# Eliminar keys de la copia y re-insertar invertidas.
		while rev.track_get_key_count(t) > 0:
			rev.track_remove_key(t, 0)
		var pairs: Array = []
		for k in key_count:
			var time: float = src.track_get_key_time(t, k)
			var value: Variant = src.track_get_key_value(t, k)
			var transition: float = src.track_get_key_transition(t, k)
			pairs.append({"t": length - time, "v": value, "tr": transition})
		pairs.sort_custom(func(a, b): return a.t < b.t)
		for p in pairs:
			rev.track_insert_key(t, p.t, p.v, p.tr)

	lib.add_animation(new_name, rev)
	return {"ok": true, "anim_name": anim_name, "new_name": new_name, "length": length}


## P3: blend procedural — interpola la pose actual del skeleton hacia una pose
## objetivo por hueso con factor t (0..1). Útil para transiciones suaves.
func handle_blend_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var skeleton := _resolve_node(root, args.get("skeleton_path", ""))
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var factor: float = clampf(float(args.get("factor", 0.5)), 0.0, 1.0)
	var target_pose: Dictionary = _args_dict(args, "target_pose")
	if target_pose.is_empty():
		return {"ok": false, "error": "target_pose required (map bone_name → transform)"}
	var rest_mode: bool = bool(args.get("rest", true))

	var blended: Array = []
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		for bone_name in target_pose.keys():
			var idx: int = skel.find_bone(str(bone_name))
			if idx < 0:
				continue
			var base: Transform3D = skel.get_bone_rest(idx) if rest_mode else skel.get_bone_pose(idx)
			var target: Variant = HerenCoordsScript.deserialize_value(target_pose[bone_name])
			if target is Transform3D:
				base = base.interpolate_with(target as Transform3D, factor)
				skel.set_bone_pose(idx, base)
				blended.append(str(bone_name))
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		for bone_name in target_pose.keys():
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == bone_name:
					bone = skel.get_bone(i)
					break
			if bone == null:
				continue
			var base: Transform2D = bone.rest if rest_mode else bone.transform
			var target: Variant = HerenCoordsScript.deserialize_value(target_pose[bone_name])
			if target is Transform2D:
				base = base.interpolate_with(target as Transform2D, factor)
				bone.transform = base
				blended.append(str(bone_name))

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(skeleton, root),
		"factor": factor,
		"bones_blended": blended.size(),
		"bones": blended,
	}


## P3: retarget básico — copia una animación de un skeleton fuente a otro
## mapeando por NOMBRE de hueso (3D). Reutiliza animaciones entre personajes
## que comparten rig (hips, spine, upper_arm_L...).
func handle_retarget(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var source := _resolve_node(root, args.get("source_skeleton", "")) as Skeleton3D
	var target := _resolve_node(root, args.get("target_skeleton", "")) as Skeleton3D
	if source == null or target == null:
		return {"ok": false, "error": "source_skeleton and target_skeleton required (Skeleton3D)"}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_rt"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	var src_anim: Animation = player.get_animation(anim_name)
	var dst_anim := Animation.new()
	dst_anim.length = src_anim.length
	dst_anim.loop_mode = src_anim.loop_mode

	# Mapa nombre de hueso source → índice de hueso target.
	var target_idx_by_name := {}
	for i in target.get_bone_count():
		target_idx_by_name[target.get_bone_name(i)] = i

	var mapped := 0
	for t in src_anim.get_track_count():
		var path_str: String = str(src_anim.track_get_path(t))
		if not path_str.contains(":bones/"):
			continue
		var bone_name: String = path_str.split(":bones/")[1].split("/")[0]
		if not target_idx_by_name.has(bone_name):
			continue
		var t_idx := dst_anim.add_track(Animation.TYPE_VALUE)
		dst_anim.track_set_path(t_idx, str(target.get_path()) + ":bones/" + str(target_idx_by_name[bone_name]) + "/pose")
		for k in src_anim.track_get_key_count(t):
			dst_anim.track_insert_key(t_idx, src_anim.track_get_key_time(t, k),
				src_anim.track_get_key_value(t, k), src_anim.track_get_key_transition(t, k))
		mapped += 1

	lib.add_animation(new_name, dst_anim)
	return {
		"ok": true,
		"anim_name": anim_name,
		"new_name": new_name,
		"tracks_mapped": mapped,
		"source_skeleton": source.name,
		"target_skeleton": target.name,
	}
