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
## The GUI's scale (window.content_scale_factor) was set again: a new
## setting or a window size it doesn't fit (rebuild pixel-sized things).
signal gui_rescaled(factor: float)

const PATH := "user://settings.cfg"
const SECTION := "settings"

const MAX_FPS_CHOICES: Array[int] = [30, 60, 120, 144, 240, 0] # 0 = unlimited
## Chunk meshes uploaded to the GPU per frame (Chunk Updates).
const CHUNK_UPDATE_CHOICES: Array[int] = [1, 2, 4, 8, 16, 32]
const ANISOTROPY_LEVELS := [
	Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X,
	Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X,
]
const GUI_SCALES: Array[float] = [0.0, 1.0, 1.5, 2.0, 3.0, 4.0] # 0 = auto (the largest that fits)
## Like the game: the GUI is at least 320 x 240 of its pixels (here x
## UiTheme.PIXEL); a chosen scale too big for the window steps down to the
## largest that fits, and back up when the window grows again.
const GUI_MIN_SIZE := Vector2(320, 240) * UiTheme.PIXEL
var _gui_factor := 0.0

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
	get_tree().root.size_changed.connect(_apply_gui_scale)


func _exit_tree() -> void:
	UiTheme.release() # static caches would otherwise be reported as leaks at exit


func _register_all() -> void:
	# Language (Language screen)
	define("language", Setting.choice("language", "Language",
		PackedStringArray(Lang.LANGUAGES.map(func(entry: Array) -> String: return entry[1])), 0))
	# General (shown on the main options screen)
	define("general", Setting.range_of("music_volume", "Music", 0, 100, 100, 5) \
		.format_with(func(v: float) -> String: return Lang.t("OFF") if v <= 0.0 else "%d%%" % int(v)))
	define("general", Setting.range_of("sound_volume", "Sound", 0, 100, 100, 5) \
		.format_with(func(v: float) -> String: return Lang.t("OFF") if v <= 0.0 else "%d%%" % int(v)))
	# Caves and rooms echo (Player._update_acoustics); off: no rays, no reverb.
	define("general", Setting.toggle("cave_echo", "Echo in Caves", true))
	define("general", Setting.range_of("fov", "FOV", 30, 110, 75))
	define("general", Setting.choice("difficulty", "Difficulty", PackedStringArray(["Peaceful", "Easy", "Normal", "Hard"]), 2))
	# Video Settings: the main list, laid out like the classic game (two
	# columns: Graphics | Render Distance, Smooth Lighting | Max Framerate...).
	define("video", Setting.choice("graphics", "Graphics", PackedStringArray(["Fast", "Fancy"]), 1))
	# Texture packs (TexturePacks): picked on their own screen, used from the next start.
	define("texture_packs", Setting.choice("texture_pack", "Texture Pack", TexturePacks.choices(), 0))
	# Up to 16 chunks the real ones; further (up to 32) the far terrain beyond
	# 16 (FarTerrain).
	define("video", Setting.range_of("render_distance", "Render Distance", 2, 32, 6) \
		.format_with(func(v: float) -> String: return Lang.t("%d chunks") % int(v)))
	define("video", Setting.choice("smooth_lighting", "Smooth Lighting",
		PackedStringArray(["OFF", "Minimum", "Maximum"]), 2))
	define("video", Setting.choice("max_fps", "Max Framerate",
		PackedStringArray(["30", "60", "120", "144", "240", "Unlimited"]), 5))
	define("video", Setting.toggle("vsync", "Use VSync", false))
	define("video", Setting.toggle("view_bobbing", "View Bobbing", true))
	define("video", Setting.choice("gui_scale", "GUI Scale",
		PackedStringArray(["Auto", "1", "1.5", "2", "3", "4"]), 0))
	define("video", Setting.range_of("brightness", "Brightness", 0, 100, 50) \
		.format_with(func(v: float) -> String:
			return Lang.t("Moody") if v <= 0.0 else (Lang.t("Bright") if v >= 100.0 else "%d%%" % int(v))))
	define("video", Setting.choice("clouds", "Clouds", PackedStringArray(["OFF", "Fast", "Fancy"]), 2))
	define("video", Setting.toggle("fullscreen", "Fullscreen", false))
	define("video", Setting.toggle("fog", "Fog", true))
	define("video", Setting.range_of("fog_distance", "Fog Distance", 20, 100, 60, 10) \
		.format_with(func(v: float) -> String: return "%d%%" % int(v)))
	# Details: what is drawn.
	define("details", Setting.toggle("stars", "Stars", true))
	define("details", Setting.toggle("sun_moon", "Sun & Moon", true))
	define("details", Setting.toggle("vignette", "Vignette", true))

	# Quality: how sharp it looks.
	define("quality", Setting.choice("antialiasing", "Anti-aliasing",
		PackedStringArray(["OFF", "FXAA", "MSAA 2x", "MSAA 4x"]), 1))
	define("quality", Setting.choice("anisotropic", "Anisotropic Filtering",
		PackedStringArray(["OFF", "2x", "4x", "8x", "16x"]), 2))
	define("quality", Setting.range_of("ambient_occlusion", "Ambient Occlusion", 0, 100, 100, 10) \
		.format_with(func(v: float) -> String: return Lang.t("OFF") if v <= 0.0 else "%d%%" % int(v)))
	define("quality", Setting.toggle("random_rotation", "Random Texture Rotation", true))

	# Performance: how much work per frame.
	define("performance", Setting.range_of("render_scale", "Render Scale", 50, 100, 100, 5) \
		.format_with(func(v: float) -> String: return "%d%%" % int(v)))
	define("performance", Setting.toggle("cave_culling", "Cave Culling", true))
	define("performance", Setting.choice("chunk_updates", "Chunk Updates",
		PackedStringArray(["1", "2", "4", "8", "16", "32"]), 4).format_with(
			func(v: int) -> String: return Lang.t("%s per frame") % CHUNK_UPDATE_CHOICES[v]))
	# Animations: what moves.
	define("animations", Setting.toggle("animated_water", "Animated Water", true))
	define("animations", Setting.toggle("star_twinkle", "Star Twinkle", true))
	define("animations", Setting.toggle("cloud_motion", "Cloud Movement", true))
	define("animations", Setting.toggle("hand_animation", "Hand Animation", true))
	# Other.
	define("other", Setting.toggle("debug_screen", "Debug Screen (F3)", false))
	define("other", Setting.toggle("background_fps", "Reduce FPS in Background", true))
	# World Diorama (F6) and its screenshots (F7); the controls are in its view.
	define("isometric", Setting.range_of("iso_area", "Area", 1, 16, 4) \
		.format_with(func(v: float) -> String: return Lang.t("%d×%d chunks") % [int(v) * 2 + 1, int(v) * 2 + 1]))
	define("isometric", Setting.range_of("iso_zoom", "Zoom", 16, 512, 96, 8) \
		.format_with(func(v: float) -> String: return Lang.t("%d blocks") % int(v)))
	define("isometric", Setting.range_of("iso_tilt", "Tilt", 10, 80, 30) \
		.format_with(func(v: float) -> String: return "%d°" % int(v)))
	define("isometric", Setting.range_of("iso_rotation", "Rotation", 0, 359, 45) \
		.format_with(func(v: float) -> String: return "%d°" % int(v)))
	define("isometric", Setting.range_of("iso_time", "Time", -1, 23, -1) \
		.format_with(func(v: float) -> String: return Lang.t("Current") if v < 0 else "%02d:00" % int(v)))
	define("isometric", Setting.range_of("iso_fog_amount", "Fog", 0, 100, 0, 5) \
		.format_with(func(v: float) -> String: return Lang.t("OFF") if v <= 0 else "%d%%" % int(v)))
	define("isometric", Setting.toggle("iso_clouds", "Clouds", false))
	define("isometric", Setting.toggle("iso_players", "Players", true))
	define("isometric", Setting.toggle("iso_mobs", "Mobs", true))
	define("isometric", Setting.choice("iso_render_size", "Screenshot Size",
		PackedStringArray(["2048 px", "4096 px", "8192 px"]), 1))
	define("isometric", Setting.choice("iso_background", "Screenshot Background",
		PackedStringArray(["Sky", "Transparent"]), 0))
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
	return forced.get(key, _values.get(key))


## Values the world being played fixes, whatever the player's settings (a
## Hardcore world's Hard difficulty); not saved, cleared on leaving it.
var forced := {}


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
			var value: Variant = config.get_value(SECTION, key)
			var setting: Setting = _settings[key]
			if value is bool and setting.kind == Setting.Kind.CHOICE:
				value = setting.choices.size() - 1 if value else 0 # was a toggle
			set_value(key, value)
	KeyBindings.load_from(config)
	_loading = false


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in _settings:
		config.set_value(SECTION, key, _values[key])
	KeyBindings.save_to(config)
	config.save(PATH)


# --- Window-level settings -----------------------------------------------------

## The GUI scale for the setting and the window as it is now: the chosen
## one, or the largest step that still fits (Auto: the largest that fits).
## Nothing is redone when it comes out the same (no flicker on resizes).
func _apply_gui_scale() -> void:
	var window := get_tree().root
	var wanted := GUI_SCALES[clampi(int(get_value("gui_scale")), 0, GUI_SCALES.size() - 1)]
	var fits := minf(window.size.x / GUI_MIN_SIZE.x, window.size.y / GUI_MIN_SIZE.y)
	var factor := 0.0
	for step in GUI_SCALES:
		if step > 0.0 and step <= fits + 0.001 and (wanted == 0.0 or step <= wanted):
			factor = step
	if factor == 0.0:
		factor = clampf(fits, 0.5, 1.0) # (a window smaller than the GUI: shrink below 1)
	if is_equal_approx(factor, _gui_factor):
		return
	_gui_factor = factor
	window.content_scale_factor = factor
	gui_rescaled.emit(factor)


func _apply_global(key: String, value: Variant) -> void:
	var window := get_window()
	var viewport := get_viewport()
	match key:
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"fullscreen":
			if value:
				window.mode = Window.MODE_FULLSCREEN
			elif has_node("/root/WindowControls"):
				get_node("/root/WindowControls").restore_window()
			else:
				window.mode = Window.MODE_WINDOWED
		"max_fps", "background_fps":
			if has_node("/root/WindowControls"):
				get_node("/root/WindowControls").apply_frame_cap()
			elif key == "max_fps":
				Engine.max_fps = MAX_FPS_CHOICES[value]
		"render_scale":
			viewport.scaling_3d_scale = value / 100.0
		"antialiasing":
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][value]
		"language":
			Lang.apply(value)
		"anisotropic":
			viewport.anisotropic_filtering_level = ANISOTROPY_LEVELS[value]
		"gui_scale":
			_apply_gui_scale()
