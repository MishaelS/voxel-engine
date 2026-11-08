extends Node
## Autoload: window behavior for development.
## The window starts maximized (project setting) and can be resized freely;
## F11 or Alt+Enter toggles fullscreen, F4 toggles VSync.
## The hotkeys change the same options as the Video Settings menu
## (UI scale, VSync and fullscreen are applied by Settings).

const MIN_SIZE := Vector2i(640, 360)


func _ready() -> void:
	var window := get_window()
	window.min_size = MIN_SIZE
	process_mode = Node.PROCESS_MODE_ALWAYS # hotkeys also work in menus
	# Needed for the render CPU time in the HUD.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_vsync"):
		Settings.set_value("vsync", not Settings.get_value("vsync"))
		get_viewport().set_input_as_handled()
