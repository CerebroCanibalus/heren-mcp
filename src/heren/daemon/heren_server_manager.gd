class_name HerenServerManager


# ============================================================
# SERVER LIFECYCLE MANAGEMENT
# Extracted from heren_daemon.gd
# ============================================================

func start_server() -> bool:
	_server = TCPServer.new()
	
	# Intentar puertos en rango
	for p in range(DEFAULT_PORT, DEFAULT_PORT + PORT_RANGE):
		var err = _server.listen(p, "127.0.0.1")
		if err == OK:
			_port = p
			print("[HEREN] Servidor TCP escuchando en 127.0.0.1:", _port)
			return true
		else:
			print("[HEREN] Puerto ", p, " no disponible, intentando siguiente...")
	
	return false


func process_heartbeat(delta):
	# Heartbeat basado en acumulador de tiempo
	_heartbeat_accumulator += delta
	if _heartbeat_accumulator >= HEARTBEAT_INTERVAL:
		_heartbeat_accumulator = 0.0
		on_heartbeat()


func on_heartbeat():
	# Enviar heartbeat a peers conectados
	var dead_peers = []
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var heartbeat = {
				"type": "heartbeat",
				"timestamp": Time.get_unix_time_from_system()
			}
			peer.send_text(JSON.stringify(heartbeat))
		else:
			dead_peers.append(peer_id)
	
	# Limpiar peers muertos
	for peer_id in dead_peers:
		_peers.erase(peer_id)
		_clients.erase(peer_id)


func handle_message(peer_id: int, peer: WebSocketPeer, msg: String):
	_inactivity_timer = 0.0  # Reset en CADA mensaje recibido
	var cmd = JSON.parse_string(msg)
	if not cmd or not cmd is Dictionary:
		send_error(peer, "invalid_json", "Mensaje JSON inválido")
		return
	
	var method = cmd.get("method", "")
	var params = cmd.get("params", {})
	var request_id = cmd.get("id", "")
	
	print("[HEREN] Comando recibido: ", method, " (id: ", request_id, ")")
	
	var result = dispatch(method, params)
	result["id"] = request_id
	result["method"] = method
	
	var response_json = JSON.stringify(result)
	var err = peer.send_text(response_json)
	if err != OK:
		print("[HEREN] Error enviando respuesta: ", err)


func dispatch(method: String, params: Dictionary) -> Dictionary:
	if not _handlers.has(method):
		return {
			"success": false,
			"error": "unknown_method",
			"message": "Método no encontrado: " + method
		}
	
	var handler = _handlers[method]
	return handler.call(params)


func send_error(peer: WebSocketPeer, error_code: String, message: String):
	peer.send_text(JSON.stringify({
		"success": false,
		"error": error_code,
		"message": message
	}))
