extends Node
## Autoload: window behavior for development.
## The window starts maximized (project setting) and can be resized freely;
## F11 or Alt+Enter toggles fullscreen.
## UI is scaled by the screen's DPI factor so the HUD stays readable on Retina.

const MIN_SIZE := Vector2i(640, 360)


func _ready() -> void:
	var window := get_window()
	window.min_size = MIN_SIZE
	window.content_scale_factor = DisplayServer.screen_get_scale(window.current_screen)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var window := get_window()
		if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			window.mode = Window.MODE_MAXIMIZED
		else:
			window.mode = Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
