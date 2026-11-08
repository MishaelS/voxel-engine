class_name UiTheme
extends RefCounted
## Shared look of all UI: the Minecraft Rus pixel font with a drop shadow,
## buttons and sliders drawn with the GUI widget textures. One texture pixel
## is PIXEL UI units, so the pixel art stays crisp at any GUI scale.

const FONT_PATH := "res://assets/fonts/Minecraft Rus/minecraft.ttf"
const FONT_SIZE := 16
const PIXEL := 2
const GUI := "res://assets/textures/gui/"

const TEXT_COLOR := Color("e0e0e0")
const HOVER_TEXT_COLOR := Color("ffffa0")
const DISABLED_TEXT_COLOR := Color("a0a0a0")
const SHADOW_COLOR := Color("3f3f3f")
const WARNING_COLOR := Color("ff5555")
const TITLE_COLOR := Color("ffffff")

## Button sizes in UI units (texture pixels * PIXEL), like the classic game.
const BUTTON_HEIGHT := 20 * PIXEL
const WIDE_BUTTON := 200 * PIXEL
const HALF_BUTTON := 150 * PIXEL

static var _font: FontFile
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE

	for type in ["Label", "Button"]:
		t.set_color("font_shadow_color", type, SHADOW_COLOR)
		t.set_constant("shadow_offset_x", type, PIXEL)
		t.set_constant("shadow_offset_y", type, PIXEL)
	t.set_color("font_color", "Label", TEXT_COLOR)

	# Buttons: widget1 normal, widget2 highlighted, widget0 disabled.
	var normal := _texture_box("widgets/widget1.png", 2)
	var hover := _texture_box("widgets/widget2.png", 2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("hover_pressed", "Button", hover)
	t.set_stylebox("disabled", "Button", _texture_box("widgets/widget0.png", 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT_COLOR)
	t.set_color("font_hover_color", "Button", HOVER_TEXT_COLOR)
	t.set_color("font_pressed_color", "Button", HOVER_TEXT_COLOR)
	t.set_color("font_hover_pressed_color", "Button", HOVER_TEXT_COLOR)
	t.set_color("font_focus_color", "Button", TEXT_COLOR)
	t.set_color("font_disabled_color", "Button", DISABLED_TEXT_COLOR)

	# Sliders: dark track (widget0) with a small handle (widget3 / widget4).
	var track := _texture_box("widgets/widget0.png", 2)
	track.content_margin_top = BUTTON_HEIGHT / 2.0
	track.content_margin_bottom = BUTTON_HEIGHT / 2.0
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("grabber_area_highlight", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	t.set_icon("grabber", "HSlider", _scaled_texture("widgets/widget3.png"))
	t.set_icon("grabber_highlight", "HSlider", _scaled_texture("widgets/widget4.png"))

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


## Drops the cached theme and font (at exit).
static func release() -> void:
	_theme = null
	_font = null


## A GUI texture scaled by PIXEL with nearest filtering.
static func _scaled_texture(path: String) -> Texture2D:
	var image: Image = (load(GUI + path) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	image.resize(image.get_width() * PIXEL, image.get_height() * PIXEL, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


## Nine-patch box from a GUI texture; `border` in texture pixels.
static func _texture_box(path: String, border: int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _scaled_texture(path)
	box.set_texture_margin_all(border * PIXEL)
	box.set_content_margin_all(2 * PIXEL)
	return box


## Any GUI texture (path relative to the gui folder), scaled by PIXEL.
static func gui_texture(path: String) -> Texture2D:
	return _scaled_texture(path)


## Tiled background (the options dirt texture), darkened.
static func background_texture() -> Texture2D:
	return _scaled_texture("optionsBackground.png")
