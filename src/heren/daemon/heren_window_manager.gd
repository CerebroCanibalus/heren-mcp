class_name HerenWindowManager

var _daemon: SceneTree = null

## Heren Window Manager - Gestión de ventana no intrusiva para MCP Daemon
## Calidad de vida: evita robar foco, capturar mouse, o molestar al usuario

const DEFAULT_FPS := 5
const DEFAULT_SIZE := Vector2i(320, 200)
const CONFIG_PATH := "user://heren_daemon_config.cfg"

var _config: ConfigFile
var _is_initialized := false

func init(daemon: SceneTree) -> void:
	_daemon = daemon

func _init():
	_config = ConfigFile.new()
	_load_config()

## Configurar ventana para ser completamente no intrusiva
func setup_window() -> void:
	if _is_initialized:
		return
	
	print("[HEREN] Configurando ventana no intrusiva...")
	
	# 1. FPS ultra-bajo para ahorrar recursos
	Engine.max_fps = DEFAULT_FPS
	print("[HEREN] FPS limitado a: ", Engine.max_fps)
	
	# 2. Título descriptivo
	DisplayServer.window_set_title("Heren MCP Daemon")
	
	# 3. Tamaño mínimo
	DisplayServer.window_set_size(DEFAULT_SIZE)
	
	# 4. FLAGS DE CALIDAD DE VIDA (lo más importante)
	# No robar foco al abrir
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	print("[HEREN] FLAG_NO_FOCUS activado")
	
	# Mouse pasa A TRAVÉS de la ventana (como si no existiera)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	print("[HEREN] FLAG_MOUSE_PASSTHROUGH activado")
	
	# Sin bordes
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	print("[HEREN] FLAG_BORDERLESS activado")
	
	# No permitir redimensionar
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	print("[HEREN] FLAG_RESIZE_DISABLED activado")
	
	# No siempre arriba (puede ser molesto)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	print("[HEREN] FLAG_ALWAYS_ON_TOP desactivado")
	
	# 5. Posición: esquina inferior derecha o posición guardada
	var saved_pos = _get_saved_position()
	if saved_pos != Vector2i(-1, -1):
		DisplayServer.window_set_position(saved_pos)
		print("[HEREN] Ventana en posición guardada: ", saved_pos)
	else:
		var screen_size = DisplayServer.screen_get_size()
		var window_size = DisplayServer.window_get_size()
		var pos = screen_size - window_size - Vector2i(20, 20)
		DisplayServer.window_set_position(pos)
		print("[HEREN] Ventana en esquina inferior derecha: ", pos)
	
	# 6. Desactivar transparencia del viewport para evitar problemas de rendering
	# pero mantener ventana funcional
	if _daemon != null and _daemon.root != null:
		RenderingServer.viewport_set_transparent_background(
			_daemon.root.get_viewport_rid(),
			false
		)
	
	_is_initialized = true
	print("[HEREN] Ventana configurada correctamente")

## Guardar posición actual de la ventana
func save_position() -> void:
	var pos = DisplayServer.window_get_position()
	_config.set_value("window", "position_x", pos.x)
	_config.set_value("window", "position_y", pos.y)
	_config.save(CONFIG_PATH)

## Cargar configuración guardada
func _load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		_config.load(CONFIG_PATH)

## Obtener posición guardada o (-1, -1) si no existe
func _get_saved_position() -> Vector2i:
	if _config.has_section_key("window", "position_x"):
		var x = _config.get_value("window", "position_x", -1)
		var y = _config.get_value("window", "position_y", -1)
		return Vector2i(x, y)
	return Vector2i(-1, -1)

## Verificar si la ventana está inicializada
func is_initialized() -> bool:
	return _is_initialized
