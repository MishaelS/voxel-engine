extends Node
## Autoload: window behavior: resizing, fullscreen and VSync hotkeys, and a
## lower frame cap while the game is in the background.
## The window opens with the size it had last time (or maximized, if it
## was), always in the middle of the screen; the size is kept in
## user://window.cfg. The first time it takes 3/4 of the screen.
## F11 or Alt+Enter toggles fullscreen, F4 toggles VSync.
## The hotkeys change the same options as the Video Settings menu
## (UI scale, VSync and fullscreen are applied by Settings).

const MIN_SIZE := Vector2i(640, 360)
const WINDOW_FILE := "user://window.cfg"
## Share of the screen a window takes the first time.
const FIRST_SIZE := 0.75
## Seconds after the last resize before the size is written.
const SAVE_DELAY := 1.0
## "Dynamic FPS" like the modern game's mod: frame cap while the window is
## in the background / minimized (Reduce FPS in Background setting).
const BACKGROUND_FPS := 15
const MINIMIZED_FPS := 1

var _focused := true
var _size := Vector2i.ZERO   # last windowed size
var _maximized := false
var _save_timer := -1.0


func _ready() -> void:
	var window := get_window()
	window.min_size = MIN_SIZE
	_load_window()
	restore_window()
	window.size_changed.connect(_on_size_changed)
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


func _process(delta: float) -> void:
	# Minimizing has no notification of its own.
	if not _focused:
		apply_frame_cap()
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			_save_window()


func _exit_tree() -> void:
	_save_window()


## Back to a normal window (start, leaving fullscreen): maximized if it was,
## else the saved size in the middle of the screen.
func restore_window() -> void:
	var window := get_window()
	if _maximized:
		window.mode = Window.MODE_MAXIMIZED
		return
	window.mode = Window.MODE_WINDOWED
	var screen := window.current_screen
	var area := DisplayServer.screen_get_usable_rect(screen)
	var size := _size
	if size == Vector2i.ZERO:
		size = Vector2i(Vector2(area.size) * FIRST_SIZE)
	size = size.clamp(MIN_SIZE, area.size)
	window.size = size
	window.position = area.position + (area.size - size) / 2


func _on_size_changed() -> void:
	var window := get_window()
	match window.mode:
		Window.MODE_WINDOWED:
			_size = window.size
			_maximized = false
		Window.MODE_MAXIMIZED:
			_maximized = true
		_:
			return # fullscreen / minimized: keep the window's own size
	_save_timer = SAVE_DELAY


func _load_window() -> void:
	var config := ConfigFile.new()
	if config.load(WINDOW_FILE) != OK:
		return
	_size = config.get_value("window", "size", Vector2i.ZERO)
	_maximized = config.get_value("window", "maximized", false)


func _save_window() -> void:
	_save_timer = -1.0
	var config := ConfigFile.new()
	config.set_value("window", "size", _size)
	config.set_value("window", "maximized", _maximized)
	config.save(WINDOW_FILE)


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
