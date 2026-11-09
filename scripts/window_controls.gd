extends Node
## Autoload: window behavior: resizing, fullscreen and VSync hotkeys, and a
## lower frame cap while the game is in the background.
## The window starts maximized (project setting) and can be resized freely;
## F11 or Alt+Enter toggles fullscreen, F4 toggles VSync.
## The hotkeys change the same options as the Video Settings menu
## (UI scale, VSync and fullscreen are applied by Settings).

const MIN_SIZE := Vector2i(640, 360)
## "Dynamic FPS" like the modern game's mod: frame cap while the window is
## in the background / minimized (Reduce FPS in Background setting).
const BACKGROUND_FPS := 15
const MINIMIZED_FPS := 1

var _focused := true


func _ready() -> void:
	var window := get_window()
	window.min_size = MIN_SIZE
	process_mode = Node.PROCESS_MODE_ALWAYS # hotkeys also work in menus
	# Needed for the render CPU time in the HUD.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			apply_frame_cap()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			apply_frame_cap()


func _process(_delta: float) -> void:
	# Minimizing has no notification of its own.
	if not _focused:
		apply_frame_cap()


## The frame cap: Max Framerate, lowered in the background.
func apply_frame_cap() -> void:
	var cap: int = Settings.MAX_FPS_CHOICES[Settings.get_value("max_fps")]
	if not _focused and Settings.get_value("background_fps"):
		var minimized := get_window().mode == Window.MODE_MINIMIZED
		cap = MINIMIZED_FPS if minimized else BACKGROUND_FPS
	if Engine.max_fps != cap:
		Engine.max_fps = cap


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_vsync"):
		Settings.set_value("vsync", not Settings.get_value("vsync"))
		get_viewport().set_input_as_handled()
