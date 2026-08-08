@tool
extends Node

# Heren MCP v4 - Tool dispatcher.
# Routes `tools/call` tool names to registered handler nodes. Each handler
# exposes a `handle_<tool>(args: Dictionary) -> Dictionary` method.

var _handlers: Dictionary = {}


func register_handler(prefix: String, handler: Node) -> void:
	_handlers[prefix] = handler


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	var prefix := tool_name.split("/", true, 1)[0]
	var handler: Node = _handlers.get(prefix, null)
	if handler == null:
		return {"ok": false, "error": "no handler for prefix: " + prefix}

	var method_name := "handle_" + tool_name.replace("/", "_")
	if not handler.has_method(method_name):
		# Fallback: strip prefix for tools like scene/create -> handle_create
		var short_name := tool_name.split("/", true, 1)[1]
		method_name = "handle_" + short_name
	if not handler.has_method(method_name):
		return {"ok": false, "error": "tool method not found: " + method_name}

	var result = handler.call(method_name, args)
	if result is Dictionary:
		return result
	# Soporte handlers coroutine (contienen `await`, ej: visual/capture off-screen):
	# completar la coroutine antes de devolver. GDScriptFunctionState no es un
	# tipo usable en `is` (Godot 4) → detectar por get_class(). Requiere que el
	# caller use `await`.
	if result != null and result.get_class() == "GDScriptFunctionState":
		result = await result
		if result is Dictionary:
			return result
	return {"ok": false, "error": "invalid tool result from: " + tool_name}
