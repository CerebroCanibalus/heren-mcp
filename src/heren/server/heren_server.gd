extends MainLoop
## Heren MCP Server - HTTP Server for Godot Headless
## Uses _process for the main loop instead of blocking _initialize

var server: TCPServer
var port: int = 9090
var project_path: String = ""
var running: bool = true
var client: StreamPeerTCP = null
var initialized: bool = false

func _initialize():
	_parse_args()
	
	if project_path.is_empty():
		print(JSON.stringify({"error": "No project path provided. Use --project <path>"}))
		running = false
		return
	
	# Start HTTP server
	server = TCPServer.new()
	var bind_err = server.listen(port, "127.0.0.1")
	if bind_err != OK:
		print(JSON.stringify({"error": "Failed to bind to port %d" % port, "code": bind_err}))
		running = false
		return
	
	print(JSON.stringify({
		"status": "ready",
		"port": port,
		"project": project_path,
		"pid": OS.get_process_id()
	}))
	
	initialized = true

func _process(delta: float) -> bool:
	if not initialized:
		return false
	
	if not running:
		return true  # Exit loop
	
	# Accept new connections
	if server.is_connection_available():
		client = server.take_connection()
		if client:
			client.set_no_delay(true)
	
	# Process existing connection
	if client and client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var bytes_available = client.get_available_bytes()
		if bytes_available > 0:
			var data = client.get_utf8_string(bytes_available)
			_handle_request(data)
			client = null
	
	return false  # Continue loop

func _handle_request(data: String):
	var body_start = data.find("\r\n\r\n")
	if body_start == -1:
		body_start = data.find("\n\n")
	
	if body_start == -1:
		_send_response({"error": "Invalid HTTP request"}, 400)
		return
	
	var body = data.substr(body_start + 4)
	if body.is_empty():
		body = data.substr(body_start + 2)
	
	var json = JSON.new()
	var parse_err = json.parse(body)
	if parse_err != OK:
		_send_response({"error": "Invalid JSON", "details": json.get_error_message()}, 400)
		return
	
	var request = json.get_data()
	if typeof(request) != TYPE_DICTIONARY:
		_send_response({"error": "Request must be a JSON object"}, 400)
		return
	
	var result = _execute_operation(request)
	_send_response(result, 200 if not result.has("error") else 500)

func _execute_operation(request: Dictionary) -> Dictionary:
	var operation = request.get("operation", "")
	var params = request.get("params", {})
	
	match operation:
		"ping":
			return {"status": "pong", "timestamp": Time.get_ticks_msec()}
		"quit":
			running = false
			return {"status": "shutting_down"}
		"health":
			return {"status": "healthy", "project": project_path}
		_:
			return {"error": "Unknown operation: %s" % operation}

func _send_response(data: Dictionary, status_code: int = 200):
	if not client:
		return
	
	var body = JSON.stringify(data)
	var response = "HTTP/1.1 %d OK\r\n" % status_code
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: %d\r\n" % body.length()
	response += "Connection: close\r\n"
	response += "\r\n"
	response += body
	
	client.put_data(response.to_utf8_buffer())

func _parse_args():
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg = args[i]
		match arg:
			"--project":
				if i + 1 < args.size():
					project_path = args[i + 1]
			"--port":
				if i + 1 < args.size():
					port = args[i + 1].to_int()

func _finalize():
	if server:
		server.stop()
	print(JSON.stringify({"status": "stopped"}))
