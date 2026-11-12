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
const HALF_BUTTON := 160 * PIXEL

static var _font: FontFile
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		var own: FontFile = load(FONT_PATH)
		own.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		own.hinting = TextServer.HINTING_NONE
		own.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = own
		var pack := pack_font()
		if pack:
			pack.fallbacks = [own] # (letters Beta's font has not: Cyrillic...)
			_font = pack
	return _font


## Beta 1.7.3's characters after "~" in its font (font.txt): cell 32 + the
## index in " !\"#...~" + this.
const BETA_FONT_EXTRA := "⌂ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»"


## A texture pack's font/default.png like Beta's: 16 x 16 cells of 8 x 8,
## a letter as wide as its pixels reach (+1 apart, the space 4), drawn at
## whole multiples of 8 pixels. Null without one.
static func pack_font() -> FontFile:
	var image := TexturePacks.pack_image("font/default.png")
	if image == null:
		return null
	var font := FontFile.new()
	font.fixed_size = 8
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var size := Vector2i(8, 0)
	font.set_cache_ascent(0, 8, 7)
	font.set_cache_descent(0, 8, 1)
	font.set_texture_image(0, size, 0, image)
	var chars := []
	for code in range(32, 127):
		chars.append(code)
	for letter in BETA_FONT_EXTRA:
		chars.append(letter.unicode_at(0))
	for i in chars.size():
		var cell := 32 + i
		var origin := Vector2i((cell % 16) * 8, (cell / 16) * 8)
		var width := 0
		for x in range(7, -1, -1):
			for y in 8:
				if image.get_pixel(origin.x + x, origin.y + y).a > 0.0:
					width = x + 1
					break
			if width > 0:
				break
		var glyph: int = chars[i]
		font.set_glyph_advance(0, 8, glyph, Vector2(4 if glyph == 32 else width + 1, 0))
		font.set_glyph_offset(0, size, glyph, Vector2(0, -7))
		font.set_glyph_size(0, size, glyph, Vector2(8, 8))
		font.set_glyph_uv_rect(0, size, glyph, Rect2(origin, Vector2(8, 8)))
		font.set_glyph_texture_idx(0, size, glyph, 0)
	return font


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

	# Text fields: black box with a gray border (white when focused).
	var field := StyleBoxFlat.new()
	field.bg_color = Color.BLACK
	field.border_color = Color("a0a0a0")
	field.set_border_width_all(PIXEL)
	field.set_content_margin_all(4 * PIXEL)
	var focused_field := field.duplicate() as StyleBoxFlat
	focused_field.border_color = Color.WHITE
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focused_field)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT_COLOR)
	t.set_color("font_placeholder_color", "LineEdit", Color("707070"))
	t.set_color("caret_color", "LineEdit", TEXT_COLOR)
	t.set_color("selection_color", "LineEdit", Color(0.2, 0.3, 0.8, 0.6))
	t.set_constant("caret_width", "LineEdit", PIXEL)
	_theme = t
	return t


## A full-screen layer that slightly blurs whatever is drawn behind it
## (the world behind menus and inventories, the title panorama).
## It copies the whole screen first: the crosshair copies only its own small
## rectangle, and without a full copy the blur would read an old frame.
static func blur_rect() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	root.add_child(copy)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/background_blur.gdshader")
	rect.material = material
	root.add_child(rect)
	return root


## Drops the cached theme and font (at exit).
static func release() -> void:
	_theme = null
	_font = null


## The GUI pictures by name, and where they are in Beta 1.7.3's files
## (TexturePacks): [file, rect], [file, size, [[rect, place]...]] (drawn in
## pieces like Beta), or a file of the game's own (extra/).
const GUI_PARTS := {
	"hotbar.png": ["gui/gui.png", Rect2i(0, 0, 182, 22)],
	"hotbarSelector.png": ["gui/gui.png", Rect2i(0, 22, 24, 24)],
	"widgets/widget0.png": ["gui/gui.png", Rect2i(0, 46, 200, 20)], # disabled button
	"widgets/widget1.png": ["gui/gui.png", Rect2i(0, 66, 200, 20)], # button
	"widgets/widget2.png": ["gui/gui.png", Rect2i(0, 86, 200, 20)], # button under the mouse
	# A slider's knob: the button's ends, like Beta's.
	"widgets/widget3.png": ["gui/gui.png", Vector2i(7, 20), [[Rect2i(0, 66, 4, 20), Vector2i(0, 0)], [Rect2i(197, 66, 3, 20), Vector2i(4, 0)]]],
	"widgets/widget4.png": ["gui/gui.png", Vector2i(7, 20), [[Rect2i(0, 86, 4, 20), Vector2i(0, 0)], [Rect2i(197, 86, 3, 20), Vector2i(4, 0)]]],
	"cursor.png": ["gui/icons.png", Rect2i(2, 2, 11, 11)],
	"optionsBackground.png": ["gui/background.png", Rect2i(0, 0, 16, 16)],
	"container/container0.png": ["gui/inventory.png", Rect2i(0, 0, 176, 166)],
	"container/container1.png": ["gui/crafting.png", Rect2i(0, 0, 176, 166)],
	"container/container2.png": ["gui/furnace.png", Rect2i(0, 0, 176, 166)],
	"container/fuelProgress.png": ["gui/furnace.png", Rect2i(176, 0, 14, 14)],
	"container/smeltingProgress.png": ["gui/furnace.png", Rect2i(176, 14, 24, 17)],
	# A chest: container.png's three rows and its inventory part, like Beta.
	"container/container3.png": ["gui/container.png", Vector2i(176, 166), [[Rect2i(0, 0, 176, 71), Vector2i(0, 0)], [Rect2i(0, 127, 176, 95), Vector2i(0, 71)]]],
	"container/container4.png": ["gui/container.png", Rect2i(0, 0, 176, 222)],
	"container/dispenser.png": ["gui/trap.png", Rect2i(0, 0, 176, 166)],
	"container/container5.png": "res://assets/textures/extra/creative.png",
}


## A GUI picture by name (GUI_PARTS), from the texture pack or the game.
static func gui_image(name: String) -> Image:
	var part: Variant = GUI_PARTS.get(name)
	if part is String:
		return TexturePacks.load_image(part)
	if part is Array and (part as Array).size() == 2:
		return TexturePacks.region(part[0], part[1])
	if part is Array:
		return TexturePacks.pieces(part[0], part[1], part[2])
	return TexturePacks.load_image(GUI + name)


## A GUI texture scaled by PIXEL with nearest filtering.
static func _scaled_texture(path: String) -> Texture2D:
	var image := gui_image(path)
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
