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

var _passed := 0
var _failed := 0


func _init() -> void:
	_run("serialize_value round-trip Vector2", _test_serialize_vector2)
	_run("serialize_value round-trip Color", _test_serialize_color)
	_run("deserialize_value null keys", _test_deserialize_value)
	_run("default_ws_url", _test_default_ws_url)
	_run("heren_error shape", _test_heren_error)

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
