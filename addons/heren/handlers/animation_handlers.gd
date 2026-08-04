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

var _editor_plugin: EditorPlugin
var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


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
	var root := _scene_root()
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
	var root := _scene_root()
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


func handle_add_track(args: Dictionary) -> Dictionary:
	var root := _scene_root()
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

	var track_idx := -1
	match track_type:
		"value":
			track_idx = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, node_path + ":" + property)
		"position_3d", "rotation_3d", "scale_3d", "method":
			track_idx = anim.add_track(Animation.TYPE_POSITION_3D if track_type == "position_3d" else Animation.TYPE_ROTATION_3D if track_type == "rotation_3d" else Animation.TYPE_SCALE_3D if track_type == "scale_3d" else Animation.TYPE_METHOD)
			anim.track_set_path(track_idx, node_path)
		_:
			return {"ok": false, "error": "invalid_track_type: " + track_type}

	return {"ok": true, "track_idx": track_idx, "track_type": track_type, "anim_name": anim_name}


func handle_add_key(args: Dictionary) -> Dictionary:
	var root := _scene_root()
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
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}

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

	var tree := AnimationTree.new()
	tree.tree_root = state_machine
	tree.anim_player = player.get_path()

	_undo_redo.begin_action("Heren Create State Machine")
	_undo_redo.add_do_method(player, &"add_child", [tree])
	_undo_redo.add_do_property(tree, &"owner", root)
	_undo_redo.add_undo_method(player, &"remove_child", [tree])
	_undo_redo.commit_action()

	return {"ok": true, "state_machine": true, "states": states.size(), "transitions": transitions.size()}


# ---------------------------------------------------------------- skeleton

func handle_skeleton_create(args: Dictionary) -> Dictionary:
	var root := _scene_root()
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
	var root := _scene_root()
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
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var rest_transform: Dictionary = _args_dict(args, "rest_transform")

	# Fix H4: branch by actual type (Skeleton2D vs Skeleton3D) instead of
	# forcing Skeleton3D. 2D rest is a Transform2D (position/rotation).
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var bone_idx := skel2d.find_bone(bone_name)
		if bone_idx < 0:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var angle: float = float(rest_transform.get("angle", rest_transform.get("rotation", 0.0)))
		var origin := Vector2(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0))
		)
		skel2d.set_bone_rest(bone_idx, Transform2D(angle, origin))
		return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx := skeleton.find_bone(bone_name)
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
	var root := _scene_root()
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
		var bone_idx := skeleton.find_bone(str(bone_name))
		if bone_idx == -1:
			return {"ok": false, "error": "bone_not_found: " + str(bone_name)}
		polygon.set_bone_weights(bone_idx, PackedFloat32Array(weights))
		bones.append(bone_name)

	return {"ok": true, "polygon": polygon.name, "skeleton": skeleton.name, "bones": bones}


func handle_skeleton_attachment(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var attachment_name: String = str(args.get("attachment_name", "Attachment"))

	# Fix H4: branch by type. 2D uses BoneAttachment2D, 3D uses BoneAttachment3D.
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var bone_idx := skel2d.find_bone(bone_name)
		if bone_idx < 0:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var att2d := BoneAttachment2D.new()
		att2d.name = attachment_name
		att2d.bone_name = bone_name
		skel2d.add_child(att2d)
		att2d.owner = root
		return {"ok": true, "attachment": att2d.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"ok": false, "error": "bone_not_found: " + bone_name}

	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.owner = root

	return {"ok": true, "attachment": attachment.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment3D"}
