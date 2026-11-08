extends Node
## Autoload "Settings": player options saved in user://settings.cfg.
##
## Every option is a Setting registered in a category; menus list a category
## and build widgets automatically. Window-level options (VSync, fullscreen,
## frame cap, render scale, anti-aliasing, GUI scale) are applied here;
## options that need scene nodes (FOV, shadows, clouds, ...) are applied by
## SettingsApplier in the scene, which listens to `changed`.
## Key bindings are saved in the same file (see KeyBindings).

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"

const MAX_FPS_CHOICES: Array[int] = [30, 60, 120, 144, 240, 0] # 0 = unlimited
const GUI_SCALES: Array[float] = [0.0, 1.0, 1.5, 2.0, 3.0, 4.0] # 0 = auto (screen DPI)

var _settings := {}       # key -> Setting
var _categories := {}     # category -> Array[Setting] (registration order)
var _values := {}         # key -> value
var _loading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_all()
	KeyBindings.capture_defaults()
	load_settings()
	for key: String in _settings:
		_apply_global(key, _values[key])


func _exit_tree() -> void:
	UiTheme.release() # static caches would otherwise be reported as leaks at exit


func _register_all() -> void:
	# General (shown on the main options screen)
	define("general", Setting.range_of("fov", "FOV", 30, 110, 75))
	# Video
	define("video", Setting.range_of("render_distance", "Render Distance", 2, 16, 6) \
		.format_with(func(v: float) -> String: return "%d chunks" % int(v)))
	define("video", Setting.range_of("render_scale", "Render Scale", 50, 100, 100, 5) \
		.format_with(func(v: float) -> String: return "%d%%" % int(v)))
	define("video", Setting.choice("max_fps", "Max Framerate",
		PackedStringArray(["30", "60", "120", "144", "240", "Unlimited"]), 5))
	define("video", Setting.toggle("vsync", "VSync", false))
	define("video", Setting.toggle("fullscreen", "Fullscreen", false))
	define("video", Setting.choice("gui_scale", "GUI Scale",
		PackedStringArray(["Auto", "1", "1.5", "2", "3", "4"]), 0))
	define("video", Setting.choice("antialiasing", "Anti-aliasing",
		PackedStringArray(["Off", "FXAA", "MSAA 2x", "MSAA 4x"]), 1))
	define("video", Setting.choice("shadows", "Shadows", PackedStringArray(["Off", "Low", "High"]), 2))
	define("video", Setting.toggle("smooth_lighting", "Smooth Lighting", true))
	define("video", Setting.toggle("clouds", "Clouds", true))
	define("video", Setting.toggle("fog", "Fog", true))
	define("video", Setting.range_of("brightness", "Brightness", 0, 100, 50) \
		.format_with(func(v: float) -> String:
			return "Moody" if v <= 0.0 else ("Bright" if v >= 100.0 else "%d%%" % int(v))))
	define("video", Setting.toggle("debug_screen", "Debug Screen (F3)", false))
	# Controls (mouse; keys are KeyBindings)
	define("controls", Setting.range_of("mouse_sensitivity", "Sensitivity", 10, 200, 100, 5) \
		.format_with(func(v: float) -> String: return "%d%%" % int(v)))
	define("controls", Setting.toggle("invert_mouse", "Invert Mouse", false))


## Registers a saved setting; its value lives in this store.
func define(category: String, setting: Setting) -> void:
	# The callables capture only the key: capturing `setting` itself would
	# make a reference cycle (Setting -> Callable -> Setting) that never frees.
	var key := setting.key
	setting.bind(
		func() -> Variant: return _values.get(key),
		func(value: Variant) -> void: set_value(key, value))
	_settings[setting.key] = setting
	_values[setting.key] = setting.default_value
	if not _categories.has(category):
		_categories[category] = []
	_categories[category].append(setting)


func get_setting(key: String) -> Setting:
	return _settings.get(key)


func in_category(category: String) -> Array:
	return _categories.get(category, [])


func get_value(key: String) -> Variant:
	return _values.get(key)


func set_value(key: String, value: Variant) -> void:
	var setting: Setting = _settings[key]
	var clean: Variant = setting.sanitize(value)
	if _values.get(key) == clean:
		return
	_values[key] = clean
	_apply_global(key, clean)
	changed.emit(key, clean)
	if not _loading:
		save_settings()


func reset_category(category: String) -> void:
	for setting: Setting in in_category(category):
		set_value(setting.key, setting.default_value)


# --- Persistence -------------------------------------------------------------

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	_loading = true
	for key: String in _settings:
		if config.has_section_key(SECTION, key):
			set_value(key, config.get_value(SECTION, key))
	KeyBindings.load_from(config)
	_loading = false


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in _settings:
		config.set_value(SECTION, key, _values[key])
	KeyBindings.save_to(config)
	config.save(PATH)


# --- Window-level settings -----------------------------------------------------

func _apply_global(key: String, value: Variant) -> void:
	var window := get_window()
	var viewport := get_viewport()
	match key:
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"fullscreen":
			window.mode = Window.MODE_FULLSCREEN if value else Window.MODE_MAXIMIZED
		"max_fps":
			Engine.max_fps = MAX_FPS_CHOICES[value]
		"render_scale":
			viewport.scaling_3d_scale = value / 100.0
		"antialiasing":
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][value]
		"gui_scale":
			var scale := GUI_SCALES[value]
			if scale == 0.0:
				scale = DisplayServer.screen_get_scale(window.current_screen)
			window.content_scale_factor = scale
