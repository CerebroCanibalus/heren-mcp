extends SceneTree

func _init():
	var file = FileAccess.open("D:/Mis Juegos/GodotMCP/heren-mcp/.temp/test_output.txt", FileAccess.WRITE)
	if file:
		file.store_line("HELLO FROM GODOT")
		file.close()
	else:
		# Si falla, escribir error
		var err_file = FileAccess.open("D:/Mis Juegos/GodotMCP/heren-mcp/.temp/test_error.txt", FileAccess.WRITE)
		if err_file:
			err_file.store_line("ERROR: " + str(FileAccess.get_open_error()))
			err_file.close()
	quit()
