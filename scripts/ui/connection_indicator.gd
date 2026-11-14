class_name ConnectionIndicator
extends Control
## The top right corner in a network game (a client): the signal bars and
## "Bad connection" while the connection is poor (Net.connection_bad: no
## word from the host for a moment, a slow round trip, or the host saying
## it hears this player badly). Nothing while it's fine. Lag is never
## punished: the game waits it out (Net's timeouts) and this only says why
## things freeze.

const P := UiTheme.PIXEL
## Seconds it stays after the connection is fine again (no flicker).
const LINGER_SECONDS := 1.0

var _icons: Texture2D
var _shown_until := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icons = load(PlayerList.ICONS)
	visible = false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if Net.is_client() and Net.connection_bad():
		_shown_until = now + LINGER_SECONDS
	var shown := now < _shown_until
	if shown != visible:
		visible = shown
	if visible:
		queue_redraw()


func _draw() -> void:
	var quality := Net.connection_quality()
	var stalled := float(quality.silent) > Net.STALL_SECONDS
	var bars := 5 if stalled else PlayerList.bars_of(int(quality.ping))
	var text := Lang.t("Bad connection")
	var font := UiTheme.font()
	var font_size := UiTheme.FONT_SIZE
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := text_width + 14.0 * P
	var origin := Vector2(size.x - width - 4.0 * P, 4.0 * P)
	draw_rect(Rect2(origin, Vector2(width, 12.0 * P)), Color(0, 0, 0, 0.5))
	draw_texture_rect_region(_icons, Rect2(origin + Vector2(2.0 * P, 2.0 * P), Vector2(10, 8) * P),
		Rect2(PlayerList.BARS_ORIGIN + Vector2(0, bars * 8), Vector2(10, 8)))
	var color := UiTheme.WARNING_COLOR if stalled else Color("ffff55")
	draw_string(font, origin + Vector2(13.0 * P, 9.5 * P), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
