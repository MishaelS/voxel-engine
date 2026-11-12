class_name OpenToLanScreen
extends MenuScreen
## "Open to LAN" like the classic game's: the settings for the other
## players (their game mode, whether cheats are allowed: for the host too
## while the world is open) and "Start LAN World".

const MODES := ["Survival", "Creative"]

var _mode := 0
var _cheats := false
var _mode_button: Button
var _cheats_button: Button


func _init() -> void:
	title = "Settings for Other Players"
	columns = 1
	center_vertically = true


func build() -> void:
	var save := WorldSave.current
	_mode = save.game_mode if save else 0
	_cheats = save.allow_cheats if save else false
	_mode_button = add_list_wide_button("", func() -> void:
		_mode = (_mode + 1) % MODES.size()
		_update())
	_cheats_button = add_list_wide_button("", func() -> void:
		_cheats = not _cheats
		_update())
	add_bottom_row([["Start LAN World", _start], ["Cancel", func() -> void: menu.back()]])
	_update()


func _update() -> void:
	_mode_button.text = Lang.t("Game Mode: %s") % Lang.t(MODES[_mode])
	_cheats_button.text = Lang.t("Allow Cheats: %s") % Lang.t("ON" if _cheats else "OFF")


func _start() -> void:
	Net.lan_game_mode = _mode
	Net.cheats = _cheats
	var error := Net.host()
	var chat := menu.chat
	menu.close()
	if chat:
		chat.add_message(Lang.t(error) if error != "" else Lang.t("Local game hosted on port %d") % Net.PORT,
			CommandSource.MessageKind.INFO)
