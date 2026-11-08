extends Node
## Autoload: window behavior for development.
## The window starts maximized (project setting) and can be resized freely;
## F11 or Alt+Enter toggles fullscreen, F3 toggles VSync.
## UI is scaled by the screen's DPI factor so the HUD stays readable on Retina.
## VSync is off by default so FPS is not capped by the monitor refresh rate.

const MIN_SIZE := Vector2i(640, 360)


func _ready() -> void:
	var window := get_window()
	window.min_size = MIN_SIZE
	window.content_scale_factor = DisplayServer.screen_get_scale(window.current_screen)
	# Needed for the render CPU time in the HUD.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var window := get_window()
		if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			window.mode = Window.MODE_MAXIMIZED
		else:
			window.mode = Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_vsync"):
		var enabled := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if enabled else DisplayServer.VSYNC_ENABLED)
		get_viewport().set_input_as_handled()
