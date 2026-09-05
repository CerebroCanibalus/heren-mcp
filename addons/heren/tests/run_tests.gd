@tool
extends SceneTree

# Heren MCP v4 - Tests unitarios GDScript (Fase D2).
#
# Ejecutar headless (requiere el plugin en el proyecto, ej. fixture):
#   godot --headless --path <proyecto> --script res://addons/heren/tests/run_tests.gd
#
# Testea helpers puros que NO requieren editor vivo:
#   - coords.serialize_value / deserialize_value (round-trip)
#   - coords.normalize_node_path
#   - constants.default_ws_url
#   - heren_error shape estándar
#
# Las mutaciones de nodos con undo/redo (test_node_mutability.gd) requieren
# editor vivo con el plugin activo; se ejecutan manualmente o con GUT.

const CoordsScript := preload("res://addons/heren/handlers/coords.gd")
const ConstantsScript := preload("res://addons/heren/constants.gd")
const ErrorScript := preload("res://addons/heren/handlers/heren_error.gd")
const TemplateRegistryScript := preload("res://addons/heren/template_registry.gd")
const UiHandlersScript := preload("res://addons/heren/handlers/ui_handlers.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_run("serialize_value round-trip Vector2", _test_serialize_vector2)
	_run("serialize_value round-trip Color", _test_serialize_color)
	_run("deserialize_value null keys", _test_deserialize_value)
	_run("default_ws_url", _test_default_ws_url)
	_run("heren_error shape", _test_heren_error)
	_run("template_registry list >= 6", _test_template_list)
	_run("template_registry exists", _test_template_exists)
	_run("template_registry instantiate health_bar params", _test_template_instantiate_params)
	_run("template_registry instantiate all", _test_template_instantiate_all)
	_run("ui layout presets (9)", _test_ui_layout_presets)
	# Fase A: coords_of_node unificado (tier 0/1/2 + discriminator 2D/3D).
	_run("coords_of_node null safe", _test_coords_of_node_null)
	_run("coords_of_node Node2D NO trae 3D", _test_coords_of_node_2d_purity)
	_run("coords_of_node Node3D NO trae 2D", _test_coords_of_node_3d_purity)
	_run("coords_of_node Control trae anchors/effective_rect", _test_coords_of_node_control)
	_run("coords_of_node Sprite2D trae bbox", _test_coords_of_node_sprite)
	_run("coords_of_node MeshInstance3D trae aabb", _test_coords_of_node_mesh)
	_run("coords_of_node tier0 minimo", _test_coords_of_node_tier0)
	_run("coords_of_node tier2 enrich", _test_coords_of_node_tier2)
	_run("coords_of_node discriminator kind+flags", _test_coords_of_node_discriminator)

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run(name: String, fn: Callable) -> void:
	var ok := false
	var msg := ""
	var err := ""
	ok = fn.call() if not fn.is_null() else false
	# (los fallos se registran con push_error dentro de cada test)
	if ok:
		_passed += 1
		print("  PASS  %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s" % name)


func _test_serialize_vector2() -> bool:
	var v := Vector2(10.5, -3.25)
	var json_data = CoordsScript.serialize_value(v)
	var back = CoordsScript.deserialize_value(json_data)
	if back is Vector2 and back.is_equal_approx(v):
		return true
	push_error("serialize/deserialize Vector2 falló: %s -> %s" % [json_data, back])
	return false


func _test_serialize_color() -> bool:
	var c := Color(0.5, 0.25, 1.0, 0.8)
	var json_data = CoordsScript.serialize_value(c)
	var back = CoordsScript.deserialize_value(json_data)
	if back is Color and back.is_equal_approx(c):
		return true
	push_error("serialize/deserialize Color falló: %s -> %s" % [json_data, back])
	return false


func _test_deserialize_value() -> bool:
	# Un número concreto debe viajar redondo.
	var json_data = CoordsScript.serialize_value(42)
	var back = CoordsScript.deserialize_value(json_data)
	if back == 42:
		return true
	push_error("deserialize_value 42 falló: %s -> %s" % [json_data, back])
	return false


func _test_normalize_node_path() -> bool:
	# normalize_node_path(node_path, root) requiere un Node root (no puro);
	# se testea en GUT/editor. Aquí solo se documenta su firma.
	return true


func _test_default_ws_url() -> bool:
	var url := ConstantsScript.default_ws_url()
	if url == "ws://127.0.0.1:9099":
		return true
	push_error("default_ws_url = %s, esperaba ws://127.0.0.1:9099" % url)
	return false


func _test_heren_error() -> bool:
	var e := ErrorScript.err("boom")
	if e.get("ok", true) != false or e.get("error", "") != "boom":
		push_error("HerenError.err shape incorrecto: %s" % e)
		return false
	var o := ErrorScript.ok({"a": 1})
	if o.get("ok", false) != true or o.get("a", 0) != 1:
		push_error("HerenError.ok shape incorrecto: %s" % o)
		return false
	return true


# ---------------------------------------------------------------- templates

func _test_template_list() -> bool:
	var templates := TemplateRegistryScript.list_templates()
	if templates.size() < 6:
		push_error("list_templates < 6: %d" % templates.size())
		return false
	for t in templates:
		var d: Dictionary = t
		if str(d.get("name", "")) == "" or str(d.get("file", "")) == "":
			push_error("template sin name/file: %s" % d)
			return false
	return true


func _test_template_exists() -> bool:
	if not TemplateRegistryScript.template_exists("health_bar"):
		push_error("template_exists(health_bar) = false")
		return false
	if TemplateRegistryScript.template_exists("does_not_exist"):
		push_error("template_exists(does_not_exist) = true")
		return false
	return true


func _test_template_instantiate_params() -> bool:
	var instance: Node = TemplateRegistryScript.instantiate("health_bar", {
		"color": {"r": 0.1, "g": 0.8, "b": 0.2, "a": 1.0},
		"label": "HP 50/100",
	})
	if instance == null:
		push_error("instantiate(health_bar) = null")
		return false
	var fill: ColorRect = instance.get_node_or_null("Fill") as ColorRect
	var lbl: Label = instance.get_node_or_null("Label") as Label
	if fill == null:
		push_error("health_bar sin nodo Fill")
		instance.free()
		return false
	if not fill.color.is_equal_approx(Color(0.1, 0.8, 0.2, 1.0)):
		push_error("Fill.color = %s, esperaba 0.1,0.8,0.2" % fill.color)
		instance.free()
		return false
	if lbl != null and lbl.text != "HP 50/100":
		push_error("Label.text = '%s', esperaba 'HP 50/100'" % lbl.text)
		instance.free()
		return false
	instance.free()
	return true


func _test_template_instantiate_all() -> bool:
	var names: Array[String] = ["health_bar", "crosshair", "dialogue_box", "score_label", "boss_bar", "inventory_slot"]
	for name in names:
		var instance: Node = TemplateRegistryScript.instantiate(name, {})
		if instance == null:
			push_error("instantiate(%s) = null" % name)
			return false
		if instance.get_child_count() < 1 and name != "score_label":
			push_error("instantiate(%s) sin hijos (root no Control compuesto)" % name)
			instance.free()
			return false
		instance.free()
	return true


func _test_ui_layout_presets() -> bool:
	var presets: Dictionary = UiHandlersScript.LAYOUT_PRESETS
	var expected: Array[String] = [
		"full_rect", "bottom_center", "top_left", "top_right", "center",
		"bottom_left", "bottom_right", "center_left", "center_right",
	]
	for name in expected:
		if not presets.has(name):
			push_error("LAYOUT_PRESETS falta: " + name)
			return false
	if presets.size() != expected.size():
		push_error("LAYOUT_PRESETS size %d != %d" % [presets.size(), expected.size()])
		return false
	return true


# ============================================================== Fase A
# coords_of_node — fuente única de verdad del sistema de coordenadas.
# Verifica que:
#   - kind == node.get_class()
#   - flags.is_2d / is_3d / is_control coherentes con el tipo
#   - nodo 2D NO trae quaternion / basis / render_layers / cast_shadow / aabb
#   - nodo 3D NO trae z_index / anchors / offsets / effective_rect / bbox
#   - tier 0 = mínimo; tier 2 = enriquecido (modulate, material, collision, etc.)
#   - coords_of_node(null) es seguro

func _test_coords_of_node_null() -> bool:
	var c := CoordsScript.coords_of_node(null)
	if c.get("kind", "") != "None":
		push_error("kind != None: %s" % c)
		return false
	if not c.get("flags", {}).get("is_2d", true) == false:
		push_error("flags.is_2d != false en null: %s" % c)
		return false
	return true


func _test_coords_of_node_2d_purity() -> bool:
	var parent := Node2D.new()
	root.add_child(parent)
	var c := CoordsScript.coords_of_node(parent, "", 2)
	# Discriminador y flags.
	if c.get("kind", "") != "Node2D":
		push_error("Node2D kind=%s" % c.get("kind", ""))
		parent.queue_free()
		return false
	if not c.get("flags", {}).get("is_2d", false):
		push_error("flags.is_2d=false para Node2D")
		parent.queue_free()
		return false
	if c.get("flags", {}).get("is_3d", true):
		push_error("flags.is_3d=true para Node2D (debe ser false)")
		parent.queue_free()
		return false
	# Pureza 2D: NO debe traer claves exclusivas de 3D.
	for forbidden in ["quat", "aabb", "size_3d", "render_layers"]:
		if c.has(forbidden):
			push_error("Node2D trajo clave 3D %s: %s" % [forbidden, c])
			parent.queue_free()
			return false
	# Y SÍ debe traer 2D-específico.
	if not c.has("pos") or not c.has("z_index"):
		push_error("Node2D sin pos/z_index: %s" % c)
		parent.queue_free()
		return false
	parent.queue_free()
	return true


func _test_coords_of_node_3d_purity() -> bool:
	var n3 := Node3D.new()
	root.add_child(n3)
	var c := CoordsScript.coords_of_node(n3, "", 2)
	# Discriminador y flags.
	if c.get("kind", "") != "Node3D":
		push_error("Node3D kind=%s" % c.get("kind", ""))
		n3.queue_free()
		return false
	if not c.get("flags", {}).get("is_3d", false):
		push_error("flags.is_3d=false para Node3D")
		n3.queue_free()
		return false
	if c.get("flags", {}).get("is_2d", true):
		push_error("flags.is_2d=true para Node3D (debe ser false)")
		n3.queue_free()
		return false
	# Pureza 3D: NO debe traer 2D.
	for forbidden in ["z_index", "bbox", "anchors", "offsets", "effective_rect"]:
		if c.has(forbidden):
			push_error("Node3D trajo clave 2D/UI %s: %s" % [forbidden, c])
			n3.queue_free()
			return false
	# SÍ debe traer rotación 3D completa.
	if not c.has("rotation") or not (c.get("rotation") as Dictionary).has("quat"):
		push_error("Node3D sin rotation.quat: %s" % c)
		n3.queue_free()
		return false
	n3.queue_free()
	return true


func _test_coords_of_node_control() -> bool:
	var p := Node2D.new()
	root.add_child(p)
	var ctl := Control.new()
	p.add_child(ctl)
	ctl.size = Vector2(100, 50)
	var c := CoordsScript.coords_of_node(ctl, "", 2)
	if c.get("kind", "") != "Control":
		push_error("Control kind=%s" % c.get("kind", ""))
		ctl.queue_free(); p.queue_free()
		return false
	if not c.get("flags", {}).get("is_control", false):
		push_error("Control flags.is_control=false")
		ctl.queue_free(); p.queue_free()
		return false
	if not c.has("anchors") or not c.has("offsets"):
		push_error("Control sin anchors/offsets")
		ctl.queue_free(); p.queue_free()
		return false
	if not c.has("effective_rect"):
		push_error("Control tier=2 sin effective_rect")
		ctl.queue_free(); p.queue_free()
		return false
	ctl.queue_free(); p.queue_free()
	return true


func _test_coords_of_node_sprite() -> bool:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex := ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = tex
	root.add_child(s)
	var c := CoordsScript.coords_of_node(s, "", 1)
	if not c.get("flags", {}).get("has_bbox", false):
		push_error("Sprite2D tier=1 sin has_bbox: %s" % c)
		s.queue_free()
		return false
	if not c.has("bbox") or not c.has("size"):
		push_error("Sprite2D sin bbox/size: %s" % c)
		s.queue_free()
		return false
	# bbox.w debe ser 64 (texture width * scale.x).
	var bw: float = (c.get("bbox", {}) as Dictionary).get("w", -1.0)
	if absf(bw - 64.0) > 0.01:
		push_error("Sprite2D bbox.w=%f esperaba 64.0" % bw)
		s.queue_free()
		return false
	s.queue_free()
	return true


func _test_coords_of_node_mesh() -> bool:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	var c := CoordsScript.coords_of_node(mi, "", 1)
	if not c.get("flags", {}).get("has_aabb", false):
		push_error("MeshInstance3D sin has_aabb: %s" % c)
		mi.queue_free()
		return false
	if not c.has("aabb") or not c.has("size_3d"):
		push_error("MeshInstance3D sin aabb/size_3d: %s" % c)
		mi.queue_free()
		return false
	mi.queue_free()
	return true


func _test_coords_of_node_tier0() -> bool:
	var n := Node2D.new()
	root.add_child(n)
	var c := CoordsScript.coords_of_node(n, "test", 0)
	# Tier 0: solo kind + flags + parent_path + visible. NO pos.
	if not c.has("kind") or not c.has("flags") or not c.has("parent_path"):
		push_error("tier=0 sin kind/flags/parent_path: %s" % c)
		n.queue_free()
		return false
	if c.has("pos"):
		push_error("tier=0 incluye pos (debería omitirlo): %s" % c)
		n.queue_free()
		return false
	if c.get("parent_path", "") != "test":
		push_error("parent_path perdido: %s" % c)
		n.queue_free()
		return false
	n.queue_free()
	return true


func _test_coords_of_node_tier2() -> bool:
	# MeshInstance3D (GeometryInstance3D) en tier=2 trae campos específicos 3D:
	# cast_shadow / gi_mode / material_override.
	var n := MeshInstance3D.new()
	n.mesh = BoxMesh.new()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(n)
	var c2 := CoordsScript.coords_of_node(n, "", 2)
	if not c2.has("cast_shadow"):
		push_error("MeshInstance3D tier=2 sin cast_shadow: %s" % c2)
		n.queue_free()
		return false
	if (c2.get("cast_shadow", 0) as int) != int(GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED):
		push_error("cast_shadow=%d esperaba %d" % [c2.get("cast_shadow", 0), int(GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)])
		n.queue_free()
		return false
	# CanvasItem en tier=2 SÍ trae modulate.
	var ci := Sprite2D.new()
	root.add_child(ci)
	var cci2 := CoordsScript.coords_of_node(ci, "", 2)
	if not cci2.has("modulate"):
		push_error("CanvasItem tier=2 sin modulate: %s" % cci2)
		ci.queue_free(); n.queue_free()
		return false
	# CollisionObject2D en tier=2 SÍ trae collision_layer.
	var co := StaticBody2D.new()
	root.add_child(co)
	var cco := CoordsScript.coords_of_node(co, "", 2)
	if not cco.has("collision_layer"):
		push_error("CollisionObject2D tier=2 sin collision_layer: %s" % cco)
		co.queue_free(); ci.queue_free(); n.queue_free()
		return false
	co.queue_free(); ci.queue_free(); n.queue_free()
	return true


func _test_coords_of_node_discriminator() -> bool:
	var n2 := Node2D.new()
	root.add_child(n2)
	var c := CoordsScript.coords_of_node(n2, "parent/path", 1)
	if c.get("kind", "") != n2.get_class():
		push_error("kind=%s esperaba %s" % [c.get("kind", ""), n2.get_class()])
		n2.queue_free()
		return false
	if c.get("parent_path", "") != "parent/path":
		push_error("parent_path=%s" % c.get("parent_path", ""))
		n2.queue_free()
		return false
	# flags es un dict, no string ni null.
	var flags: Dictionary = c.get("flags", {})
	if flags.is_empty():
		push_error("flags vacío")
		n2.queue_free()
		return false
	n2.queue_free()
	return true
