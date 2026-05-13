extends MainLoop

var server: TCPServer
var running: bool = true

func _initialize():
	print("DEBUG: Starting simple server test...")
	
	server = TCPServer.new()
	var err = server.listen(9110, "127.0.0.1")
	print("DEBUG: listen() returned: %d" % err)
	
	if err == OK:
		print(JSON.stringify({"status": "ready", "port": 9110}))
	else:
		print(JSON.stringify({"error": "Failed to listen", "code": err}))
		running = false
		return
	
	# Test: wait for connection or timeout
	var start_time = Time.get_ticks_msec()
	while running and (Time.get_ticks_msec() - start_time) < 10000:
		if server.is_connection_available():
			var client = server.take_connection()
			if client:
				print("DEBUG: Client connected!")
				var response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!"
				client.put_data(response.to_utf8_buffer())
				running = false
				break
		OS.delay_msec(10)
	
	print("DEBUG: Server loop ended")

func _process(delta: float) -> bool:
	return not running

func _finalize():
	if server:
		server.stop()
	print("DEBUG: Server stopped")
