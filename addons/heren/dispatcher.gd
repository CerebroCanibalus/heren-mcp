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

	# Resolver método en orden:
	#   1. "node/add" → handle_node_add
	#   2. "node" + args.action="add" (scene/plan + GenericStep normaliza tool/action) → handle_add
	#   3. "scene/create" → handle_create (fallback strip prefix)
	var method_name := "handle_" + tool_name.replace("/", "_")
	if not handler.has_method(method_name):
		var action := str(args.get("action", ""))
		if action != "":
			method_name = "handle_" + action
	if not handler.has_method(method_name):
		var parts := tool_name.split("/", true, 1)
		if parts.size() > 1:
			method_name = "handle_" + parts[1]
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
