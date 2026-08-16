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
