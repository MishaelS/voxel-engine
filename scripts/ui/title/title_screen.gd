class_name TitleScreen
extends Node3D
## The title screen: a live, slightly blurred panorama (a floating island
## building itself out of a generated world) behind the logo,
## a pulsing splash text and the main buttons (Singleplayer, Options,
## Quit). Singleplayer opens the world list (or world creation when there
## are no worlds yet). Playing a world fades to black and loads the game
## scene, which shows the loading screen.
## On the first start the studio logo is shown for a moment (click or any
## key skips it).

const GAME_SCENE := "res://scenes/main.tscn"
const P := UiTheme.PIXEL
const LOGO_WIDTH := 280 * P
## The logo stands this much higher than right above the buttons.
const LOGO_RAISE := 14 * P
const SPLASH_COLOR := Color("ffff00")
const SPLASHES := [
	"Made with Godot!", "Now with 3D clouds!", "Voxels all the way down!",
	"Sky light 0..15!", "Analemma included!", "Bedrock Edition!",
	"100% GDScript!", "Smooth lighting!", "Chunks load 4x faster!",
	"Look at the moon phases!", "Also try sand!", "Seeds are hashed!",
	"Falling sand, smoothly!", "Beta 1.7.3 terrain!", "Press F3!",
]
const INTRO_FADE := 0.4
const INTRO_HOLD := 1.2

static var _intro_shown := false

var _ui: Control
var _main: Control
var _splash: Label
var _menu: Menu
var _curtain: ColorRect
var _intro: TextureRect
var _intro_time := 0.0
var _starting := false


func _ready() -> void:
	GameInput.reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(TitlePanorama.new())

	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiTheme.theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)

	# The panorama is slightly blurred behind the menu.
	_ui.add_child(UiTheme.blur_rect())

	var shade := TextureRect.new()
	shade.texture = TexturePacks.load_texture(UiTheme.GUI + "titleBlur.png")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_main)
	_build_main()

	_menu = Menu.new()
	_menu.in_game = false
	_ui.add_child(_menu)
	_menu.opened.connect(func() -> void: _main.visible = false)
	_menu.closed.connect(func() -> void: _main.visible = true)

	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.modulate.a = 0.0
	_ui.add_child(_curtain)

	if not _intro_shown:
		_intro_shown = true
		_intro = TextureRect.new()
		_intro.texture = TexturePacks.load_texture(UiTheme.GUI + "titleIntroLogo.png")
		_intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_intro.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_intro.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_intro.mouse_filter = Control.MOUSE_FILTER_STOP
		_ui.add_child(_intro)
	else:
		# Coming back from a world: fade in from black.
		_curtain.modulate.a = 1.0
		create_tween().tween_property(_curtain, "modulate:a", 0.0, 0.5)


func _build_main() -> void:
	var logo := TextureRect.new()
	logo.texture = _scaled_logo()
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var logo_size := logo.texture.get_size()
	# The logo and the buttons together sit in the middle of the screen.
	var total := logo_size.y + 12 * P + UiTheme.BUTTON_HEIGHT * 2 + 4 * P
	var top := -total / 2.0
	logo.anchor_top = 0.5
	logo.anchor_bottom = 0.5
	logo.offset_left = -logo_size.x / 2
	logo.offset_right = logo_size.x / 2
	logo.offset_top = top - LOGO_RAISE
	logo.offset_bottom = top - LOGO_RAISE + logo_size.y
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(logo)

	_splash = Label.new()
	_splash.text = SPLASHES[randi() % SPLASHES.size()]
	_splash.add_theme_color_override("font_color", SPLASH_COLOR)
	_splash.add_theme_color_override("font_shadow_color", Color("3f3f00"))
	_splash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash.reset_size()
	_splash.pivot_offset = _splash.size / 2
	_splash.rotation_degrees = -20.0
	_splash.set_anchors_preset(Control.PRESET_CENTER)
	_splash.position = Vector2(logo_size.x * 0.43 - _splash.size.x / 2, top - LOGO_RAISE + logo_size.y * 0.72)
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(_splash)

	var buttons := VBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_CENTER)
	buttons.offset_left = -UiTheme.WIDE_BUTTON / 2.0
	buttons.offset_right = UiTheme.WIDE_BUTTON / 2.0
	buttons.offset_top = top + logo_size.y + 12 * P
	buttons.offset_bottom = buttons.offset_top
	buttons.add_theme_constant_override("separation", 4 * P)
	_main.add_child(buttons)
	buttons.add_child(_button("Singleplayer", UiTheme.WIDE_BUTTON, _open_singleplayer))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 * P)
	row.add_child(_button("Options...", 98 * P, func() -> void: _menu.push(OptionsScreen.new())))
	row.add_child(_button("Quit Game", 98 * P, func() -> void: get_tree().quit()))
	buttons.add_child(row)

	var version := Label.new()
	version.text = "%s %s" % [ProjectSettings.get_setting("application/config/name"),
		ProjectSettings.get_setting("application/config/version", "dev")]
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position += Vector2(2, -2) * P
	_main.add_child(version)
	var credits := Label.new()
	credits.text = ProjectSettings.get_setting("application/config/developer", "")
	credits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	credits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credits.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credits.position += Vector2(-2, -2) * P
	_main.add_child(credits)


## The logo image is large and smooth: scaled down once with a good filter.
func _scaled_logo() -> Texture2D:
	var image: Image = TexturePacks.load_texture(UiTheme.GUI + "titleLogo.png").get_image()
	if image.is_compressed():
		image.decompress()
	var scale := float(LOGO_WIDTH) / image.get_width()
	var screen_scale := get_tree().root.content_scale_factor
	# Rendered at screen pixels, shown at UI size: sharp on Retina.
	image.resize(roundi(LOGO_WIDTH * screen_scale), roundi(image.get_height() * scale * screen_scale), Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(LOGO_WIDTH, roundi(image.get_height() / screen_scale)))
	return texture


func _button(text: String, width: float, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, UiTheme.BUTTON_HEIGHT)
	button.pressed.connect(on_pressed)
	return button


func _process(delta: float) -> void:
	# The classic splash pulse.
	var pulse := 1.0 + absf(sin(Time.get_ticks_msec() / 1000.0 * TAU)) * 0.08
	_splash.scale = Vector2.ONE * pulse
	if _intro:
		_intro_time += delta
		var total := INTRO_FADE * 2.0 + INTRO_HOLD
		var alpha := clampf(minf(_intro_time / INTRO_FADE, (total - _intro_time) / INTRO_FADE), 0.0, 1.0)
		# The intro covers the title: fade the logo out over the title.
		_intro.modulate.a = 1.0 if _intro_time < INTRO_FADE + INTRO_HOLD else alpha
		if _intro_time >= total:
			_intro.queue_free()
			_intro = null


func _input(event: InputEvent) -> void:
	if _intro and _intro_time > 0.2 and event.is_pressed() and not event.is_echo():
		_intro_time = maxf(_intro_time, INTRO_FADE + INTRO_HOLD)
		get_viewport().set_input_as_handled()


func _open_singleplayer() -> void:
	if WorldSave.list_all().is_empty():
		_menu.push(CreateWorldScreen.new(_play))
	else:
		_menu.push(SelectWorldScreen.new(_play))


## Fades to black and loads the game with this world.
func _play(save: WorldSave) -> void:
	if _starting:
		return
	_starting = true
	save.last_played = int(Time.get_unix_time_from_system())
	if save.needs_height_upgrade():
		save.upgrade_height() # made when the world was 128 high
	save.write_level()
	WorldSave.current = save
	var tween := create_tween()
	tween.tween_property(_curtain, "modulate:a", 1.0, 0.35)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
