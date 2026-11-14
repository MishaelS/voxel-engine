class_name DisconnectedScreen
extends MenuScreen
## "Connection Lost" / "Failed to connect to the server", like the classic
## game's: why (Net's last NetErrors code, in the player's language) and the
## code itself in gray, so it can be told when reporting a problem; one
## button back.

var _code := 0
var _args := PackedStringArray()
var _back_text := ""


## `failed`: the join was refused (else: a game in progress ended).
func _init(code: int, args: PackedStringArray, failed: bool) -> void:
	title = "Failed to connect to the server" if failed else "Connection Lost"
	_code = code
	_args = args
	_back_text = "Back to Server List" if failed else "Back to Title Screen"
	columns = 1
	center_vertically = true


func build() -> void:
	var message := Label.new()
	message.text = NetErrors.text(_code, _args)
	message.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # (translated already)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON * 1.5, 0)
	add_list_item(message)
	var code := EditServerScreen.caption("")
	code.text = Lang.t("Error code: %s") % NetErrors.label(_code)
	code.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.mouse_filter = Control.MOUSE_FILTER_PASS
	code.tooltip_text = Lang.t("Tell this code when you report the problem")
	add_list_item(code)
	add_bottom_button(_back_text, func() -> void: menu.back())
