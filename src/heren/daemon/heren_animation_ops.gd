class_name HerenAnimationOps

var _daemon: SceneTree = null

func init(daemon: SceneTree) -> void:
	_daemon = daemon


# ============================================================
# ANIMATION HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_create_animation_player(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", ".")
	var player_name = params.get("player_name", "AnimationPlayer")
	
	if not scene_path or not player_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		var load_result = _daemon._scene_ops.handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _daemon._scene_cache[scene_path]
	var parent: Node
	
	if parent_path == "." or parent_path == root.name:
		parent = root
	else:
		parent = root.get_node_or_null(parent_path)
		if not parent:
			return {"success": false, "error": "parent_not_found"}
	
	if parent.get_node_or_null(player_name):
		return {"success": false, "error": "node_exists"}
	
	var player = AnimationPlayer.new()
	player.name = player_name
	parent.add_child(player)
	player.owner = root
	
	return {
		"success": true,
		"scene_path": scene_path,
		"player_path": str(parent.get_path()) + "/" + player_name,
		"player_name": player_name
	}


func handle_create_animation(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var length = params.get("length", 1.0)
	var loop = params.get("loop", false)
	
	if not scene_path or not player_path or not anim_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	
	# Godot 4 usa AnimationLibrary para persistir animaciones
	var anim_lib = player.get_animation_library("")
	if not anim_lib:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)
	
	return {
		"success": true,
		"scene_path": scene_path,
		"player_path": player_path,
		"anim_name": anim_name,
		"length": length,
		"loop": loop
	}


func handle_add_animation_track(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var track_type = params.get("track_type", "value")
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	
	if not scene_path or not player_path or not anim_name or not node_path or not property:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = player.get_animation(anim_name)
	if not anim:
		return {"success": false, "error": "animation_not_found"}
	
	var track_idx = -1
	match track_type:
		"value":
			track_idx = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, node_path + ":" + property)
		"position_3d":
			track_idx = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(track_idx, node_path)
		"rotation_3d":
			track_idx = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track_idx, node_path)
		"scale_3d":
			track_idx = anim.add_track(Animation.TYPE_SCALE_3D)
			anim.track_set_path(track_idx, node_path)
		"method":
			track_idx = anim.add_track(Animation.TYPE_METHOD)
			anim.track_set_path(track_idx, node_path)
		_:
			return {"success": false, "error": "invalid_track_type"}
	
	return {
		"success": true,
		"track_idx": track_idx,
		"track_type": track_type,
		"node_path": node_path,
		"property": property
	}


func handle_add_animation_key(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var anim_name = params.get("anim_name", "")
	var track_idx = params.get("track_idx", 0)
	var time = params.get("time", 0.0)
	var value = params.get("value", null)
	var transition = params.get("transition", 1.0)
	
	if not scene_path or not player_path or not anim_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var anim = player.get_animation(anim_name)
	if not anim:
		return {"success": false, "error": "animation_not_found"}
	
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "invalid_track_idx"}
	
	var deserialized = _daemon._core_utils.deserialize_value(value)
	var key_idx = anim.track_insert_key(track_idx, time, deserialized, transition)
	
	return {
		"success": true,
		"key_idx": key_idx,
		"track_idx": track_idx,
		"time": time
	}


func handle_create_state_machine(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var player_path = params.get("player_path", "")
	var states = params.get("states", [])
	var transitions = params.get("transitions", [])
	
	if not scene_path or not player_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var player = root.get_node_or_null(player_path)
	
	if not player or not player is AnimationPlayer:
		return {"success": false, "error": "animation_player_not_found"}
	
	var state_machine = AnimationNodeStateMachine.new()
	
	# Add states
	for state in states:
		var state_name = state.get("name", "")
		var anim_name = state.get("animation", "")
		
		if state_name and anim_name:
			var anim_node = AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			state_machine.add_node(state_name, anim_node)
	
	# Add transitions
	for transition in transitions:
		var from_state = transition.get("from", "")
		var to_state = transition.get("to", "")
		var condition = transition.get("condition", "")
		
		if from_state and to_state:
			var trans = AnimationNodeStateMachineTransition.new()
			if condition:
				trans.advance_condition = condition
			state_machine.add_transition(from_state, to_state, trans)
	
	# Create tree root
	var tree = AnimationTree.new()
	tree.tree_root = state_machine
	tree.anim_player = player.get_path()
	
	player.add_child(tree)
	tree.owner = root
	
	return {
		"success": true,
		"state_machine": true,
		"states": states.size(),
		"transitions": transitions.size()
	}


# ============================================================
# SKELETON HANDLERS
# Extracted from heren_daemon.gd
# ============================================================

func handle_create_skeleton(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var parent_path = params.get("parent_path", ".")
	var skeleton_name = params.get("skeleton_name", "Skeleton2D")
	var is_3d = params.get("is_3d", false)
	
	if not scene_path or not skeleton_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		var load_result = _daemon._scene_ops.handle_load_scene({"scene_path": scene_path})
		if not load_result.success:
			return load_result
	
	var root = _daemon._scene_cache[scene_path]
	var parent: Node
	
	if parent_path == "." or parent_path == root.name:
		parent = root
	else:
		parent = root.get_node_or_null(parent_path)
		if not parent:
			return {"success": false, "error": "parent_not_found"}
	
	var skeleton
	if is_3d:
		skeleton = Skeleton3D.new()
	else:
		skeleton = Skeleton2D.new()
	
	skeleton.name = skeleton_name
	parent.add_child(skeleton)
	skeleton.owner = root
	
	return {
		"success": true,
		"scene_path": scene_path,
		"skeleton_path": str(parent.get_path()) + "/" + skeleton_name,
		"skeleton_type": "Skeleton3D" if is_3d else "Skeleton2D"
	}


func handle_add_bone(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var rest_transform = params.get("rest_transform", {})
	var length = params.get("length", 32.0)
	var bone_angle = params.get("bone_angle", 0.0)
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton:
		return {"success": false, "error": "skeleton_not_found"}
	
	if skeleton is Skeleton2D:
		var bone = Bone2D.new()
		bone.name = bone_name
		bone.rest = Transform2D(bone_angle, Vector2(rest_transform.get("x", 0), rest_transform.get("y", 0)))
		bone.default_length = length
		skeleton.add_child(bone)
		bone.owner = root
		
		return {
			"success": true,
			"bone_name": bone_name,
			"skeleton": skeleton_path,
			"type": "Bone2D"
		}
	
	elif skeleton is Skeleton3D:
		var bone_idx = skeleton.add_bone(bone_name)
		
		var origin = Vector3(
			rest_transform.get("x", 0),
			rest_transform.get("y", 0),
			rest_transform.get("z", 0)
		)
		var basis = Basis()
		if rest_transform.has("rotation"):
			var rot = rest_transform["rotation"]
			basis = Basis.from_euler(Vector3(rot.get("x", 0), rot.get("y", 0), rot.get("z", 0)))
		
		var transform = Transform3D(basis, origin)
		skeleton.set_bone_rest(bone_idx, transform)
		
		return {
			"success": true,
			"bone_name": bone_name,
			"bone_idx": bone_idx,
			"skeleton": skeleton_path,
			"type": "Skeleton3D"
		}
	
	return {"success": false, "error": "invalid_skeleton_type"}


func handle_set_bone_rest(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var rest_transform = params.get("rest_transform", {})
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton or not skeleton is Skeleton3D:
		return {"success": false, "error": "skeleton3d_not_found"}
	
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"success": false, "error": "bone_not_found", "bone": bone_name}
	
	var origin = Vector3(
		rest_transform.get("x", 0),
		rest_transform.get("y", 0),
		rest_transform.get("z", 0)
	)
	var basis = Basis()
	if rest_transform.has("rotation"):
		var rot = rest_transform["rotation"]
		basis = Basis.from_euler(Vector3(rot.get("x", 0), rot.get("y", 0), rot.get("z", 0)))
	
	var transform = Transform3D(basis, origin)
	skeleton.set_bone_rest(bone_idx, transform)
	
	return {
		"success": true,
		"bone_name": bone_name,
		"bone_idx": bone_idx
	}


func handle_skin_polygon2d(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var polygon_path = params.get("polygon_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_weights = params.get("bone_weights", {})
	
	if not scene_path or not polygon_path or not skeleton_path:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var polygon = root.get_node_or_null(polygon_path)
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not polygon or not polygon is Polygon2D:
		return {"success": false, "error": "polygon2d_not_found"}
	
	if not skeleton or not skeleton is Skeleton2D:
		return {"success": false, "error": "skeleton2d_not_found"}
	
	polygon.skeleton = skeleton.get_path()
	
	# Set bone weights
	for bone_name in bone_weights.keys():
		var weights = bone_weights[bone_name]
		polygon.set_bone_weigths(bone_name, PackedFloat32Array(weights))
	
	return {
		"success": true,
		"polygon": polygon_path,
		"skeleton": skeleton_path,
		"bones": bone_weights.keys()
	}


func handle_add_bone_attachment(params: Dictionary) -> Dictionary:
	var scene_path = params.get("scene_path", "")
	var skeleton_path = params.get("skeleton_path", "")
	var bone_name = params.get("bone_name", "")
	var attachment_name = params.get("attachment_name", "Attachment")
	
	if not scene_path or not skeleton_path or not bone_name:
		return {"success": false, "error": "missing_params"}
	
	if not _daemon._scene_cache.has(scene_path):
		return {"success": false, "error": "scene_not_loaded"}
	
	var root = _daemon._scene_cache[scene_path]
	var skeleton = root.get_node_or_null(skeleton_path)
	
	if not skeleton or not skeleton is Skeleton3D:
		return {"success": false, "error": "skeleton3d_not_found"}
	
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"success": false, "error": "bone_not_found"}
	
	var attachment = BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.owner = root
	
	return {
		"success": true,
		"attachment": attachment_name,
		"bone": bone_name,
		"bone_idx": bone_idx
	}
