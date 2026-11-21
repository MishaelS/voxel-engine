class_name SleepScreen
extends Control
## The screen while lying in a bed, like the game's in-bed screen: the
## world darkens as the player falls asleep, a "Leave Bed" button at the
## bottom wakes up, Enter (or T, /) opens the chat to type. It lies over the
## HUD and under the chat, the inventory and the menus (Game puts it into
## the UI layer right after the status bars).

const P := UiTheme.PIXEL

var player: Player
var chat: Chat
var menu: Menu

var _fade: ColorRect
var _leave: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.03, 0.06, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	# 40 pixels above the bottom, like the game's button.
	_leave = Button.new()
	_leave.text = "Leave Bed"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.anchor_left = 0.5
	_leave.anchor_right = 0.5
	_leave.anchor_top = 1.0
	_leave.anchor_bottom = 1.0
	_leave.offset_left = -UiTheme.WIDE_BUTTON / 2.0
	_leave.offset_right = UiTheme.WIDE_BUTTON / 2.0
	_leave.offset_top = -40 * P
	_leave.offset_bottom = -20 * P
	_leave.pressed.connect(func() -> void:
		if player:
			player.wake_up())
	_leave.visible = false
	add_child(_leave)


func _process(_delta: float) -> void:
	var asleep := player != null and player.sleeping and not player.dead
	_fade.color.a = player.sleep_darkness() if asleep else 0.0
	var menu_open := menu != null and menu.is_open()
	_leave.visible = asleep and not menu_open
	if _leave.visible and GameInput.is_captured():
		GameInput.capture(false) # for the button


func _unhandled_input(event: InputEvent) -> void:
	if not _leave.visible or chat == null or chat.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		chat.open()
		get_viewport().set_input_as_handled()
