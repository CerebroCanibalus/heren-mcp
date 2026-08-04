@tool
extends Node

# Heren MCP v4 - WebSocket client.
# Connects to the FlojoMCP MCP server (ADR-003: plugin = WS CLIENT).
# Speaks MCP JSON-RPC: receives `tools/call` requests, replies with
# `tools/call` results. Auto-reconnect with exponential backoff.

signal connected
signal disconnected
signal tool_invoke_received(request_id: String, tool_name: String, args: Dictionary)
signal error_reported(message: String)

const DEFAULT_URL := "ws://127.0.0.1:9099"
const RECONNECT_DELAY := 2.0
const MAX_RECONNECT_DELAY := 30.0
const PING_INTERVAL := 10.0

var socket: WebSocketPeer = WebSocketPeer.new()
var server_url: String = DEFAULT_URL
var _is_connected := false
var _initialized := false
var _should_reconnect := true
var _current_reconnect_delay := RECONNECT_DELAY
var _reconnect_timer: Timer
var _ping_timer: Timer
var _project_path: String = ""


func _ready() -> void:
	_project_path = ProjectSettings.globalize_path("res://")

	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timer)
	add_child(_reconnect_timer)

	_ping_timer = Timer.new()
	_ping_timer.wait_time = PING_INTERVAL
	_ping_timer.timeout.connect(_send_ping)
	add_child(_ping_timer)

	set_process(true)
	_initialized = true


func _process(_delta: float) -> void:
	if not _initialized:
		return

	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_handle_disconnect()
		return

	socket.poll()

	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_handle_connect()
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				_handle_message(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_handle_disconnect()


func connect_to_server(url: String = "") -> void:
	server_url = _resolve_server_url(url)
	_should_reconnect = true
	_current_reconnect_delay = RECONNECT_DELAY
	_attempt_connection()


func _resolve_server_url(explicit_url: String) -> String:
	if explicit_url != "":
		return explicit_url
	var env_port := OS.get_environment("HEREN_MCP_PORT")
	if env_port != "" and env_port.is_valid_int():
		var port := int(env_port)
		if port >= 1 and port <= 65535:
			return "ws://127.0.0.1:%d" % port
	return DEFAULT_URL


func disconnect_from_server() -> void:
	_should_reconnect = false
	if _reconnect_timer:
		_reconnect_timer.stop()
	if _ping_timer:
		_ping_timer.stop()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close()
	_is_connected = false


func _attempt_connection() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	var err := socket.connect_to_url(server_url)
	print("[HEREN] ws connect attempt -> url=%s err=%d" % [server_url, err])
	if err != OK:
		error_reported.emit("ws connect failed: %d" % err)
		_schedule_reconnect()


func _handle_connect() -> void:
	_is_connected = true
	_current_reconnect_delay = RECONNECT_DELAY
	if _ping_timer:
		_ping_timer.start()
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/godot_ready",
		"params": {"project_path": _project_path},
	})
	connected.emit()


func _handle_disconnect() -> void:
	_is_connected = false
	if _ping_timer:
		_ping_timer.stop()
	disconnected.emit()
	if _should_reconnect:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	if _reconnect_timer == null:
		return
	_reconnect_timer.start(_current_reconnect_delay)
	_current_reconnect_delay = min(_current_reconnect_delay * 2.0, MAX_RECONNECT_DELAY)


func _on_reconnect_timer() -> void:
	_attempt_connection()


func _send_ping() -> void:
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/ping",
		"params": {},
	})


## Send a push notification to the server (e.g. selection_changed).
## Used by the editor plugin for event push (§13.6) with rate-limit.
func send_notification(name: String, params: Dictionary = {}) -> void:
	if not _is_connected:
		return
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/" + name,
		"params": params,
	})


func _handle_message(json_string: String) -> void:
	var message = JSON.parse_string(json_string)
	if message == null:
		error_reported.emit("failed to parse message")
		return
	if not message is Dictionary:
		return

	var method: String = message.get("method", "")
	match method:
		"tools/call":
			var request_id: String = str(message.get("id", ""))
			var params: Dictionary = message.get("params", {})
			var tool_name: String = str(params.get("name", ""))
			var args: Dictionary = params.get("arguments", {})
			tool_invoke_received.emit(request_id, tool_name, args)
		"ping":
			_send_message({"jsonrpc": "2.0", "id": message.get("id", null), "result": {}})
		"notifications/pong":
			pass
		_:
			pass


func send_tool_result(request_id: String, success: bool, result: Dictionary, error: String) -> void:
	var response: Dictionary = {"jsonrpc": "2.0", "id": request_id}
	if success:
		response["result"] = {"content": [{"type": "text", "text": JSON.stringify(result)}]}
	else:
		response["error"] = {"code": -32000, "message": error}
	_send_message(response)


func _send_message(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))


func is_connected_to_server() -> bool:
	return _is_connected
