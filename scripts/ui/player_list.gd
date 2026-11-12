class_name PlayerList
extends Control
## The players in a network game, shown while Tab is held, like the classic
## game's list: a row each at the top of the screen with the player's face
## (from the skin), the name and the signal bars (gui icons.png, by the
## round trip the host measured: under 150 ms five bars, 300 four, 600
## three, 1000 two, else one; a red cross while unknown).

const P := UiTheme.PIXEL
const ROW := 9 # GUI pixels a row
const ICONS := "res://assets/textures/icons.png"
const BARS_ORIGIN := Vector2(0, 176) # five bars, then four... then the cross

var _icons: Texture2D
var _skin: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons = TexturePacks.load_texture(ICONS)
	_skin = MobModels.default_skin("player")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Net.players_changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	var shown := Net.is_online() and Input.is_physical_key_pressed(KEY_TAB) and not GameInput.is_blocked()
	if shown != visible:
		visible = shown
	if visible:
		queue_redraw()


static func bars_of(ping: int) -> int:
	if ping < 0:
		return 5 # the cross row
	if ping < 150:
		return 0
	if ping < 300:
		return 1
	if ping < 600:
		return 2
	if ping < 1000:
		return 3
	return 4


func _draw() -> void:
	var font := UiTheme.font()
	var font_size := UiTheme.FONT_SIZE
	var ids := Net.players.keys()
	ids.sort()
	var widest := 0.0
	for id: int in ids:
		widest = maxf(widest, font.get_string_size(str(Net.players[id].name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var width := 9.0 * P + widest + 4.0 * P + 10.0 * P + 2.0 * P
	var origin := Vector2((size.x - width) / 2.0, 10.0 * P)
	draw_rect(Rect2(origin - Vector2(P, P), Vector2(width + 2.0 * P, ids.size() * ROW * P + P)), Color(0, 0, 0, 0.5))
	for row in ids.size():
		var id: int = ids[row]
		var info: Dictionary = Net.players[id]
		var top := origin + Vector2(0, row * ROW * P)
		draw_rect(Rect2(top, Vector2(width, (ROW - 1) * P)), Color(1, 1, 1, 0.13))
		# The face and the hat layer of the skin.
		var face := Rect2(top, Vector2(8, 8) * P)
		var skin: Texture2D = Net.skin_of(id)
		if skin == null:
			skin = _skin
		draw_texture_rect_region(skin, face, Rect2(8, 8, 8, 8))
		draw_texture_rect_region(skin, face, Rect2(40, 8, 8, 8))
		var color := PlayerProfile.color_of(Net.color_of(id))
		draw_string(font, top + Vector2(9.0 * P, 7.0 * P), str(info.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		var bars := bars_of(int(info.get("ping", -1)))
		draw_texture_rect_region(_icons, Rect2(top + Vector2(width - 10.0 * P, 0), Vector2(10, 8) * P),
			Rect2(BARS_ORIGIN + Vector2(0, bars * 8), Vector2(10, 8)))
