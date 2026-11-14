class_name OpenToLanScreen
extends MenuScreen
## "Open to LAN" like the classic game's: the settings for the other
## players (their game mode, whether cheats are allowed: for the host too
## while the world is open), "Allow Internet Access" (the router's ports
## through UPnP and an invite code for friends far away: Invite Friends
## shows it) and "Start LAN World".

const MODES := ["Survival", "Creative"]

var _mode := 0
var _cheats := false
var _internet := false
var _mode_button: Button
var _cheats_button: Button
var _internet_button: Button
var _warning: Label


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
	_internet_button = add_list_wide_button("", func() -> void:
		_internet = not _internet
		_update())
	_internet_button.tooltip_text = Lang.t("Opens the port on your router (UPnP) and gives an invite code for friends on the internet") \
		+ "\n" + Lang.t("Only share the code with people you trust")
	_warning = Label.new() # (the warning lives in the button's tooltip now)
	_warning.text = ""
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
	add_bottom_row([["Start LAN World", _start], ["Cancel", func() -> void: menu.back()]])
	_update()


func _update() -> void:
	_mode_button.text = Lang.t("Game Mode: %s") % Lang.t(MODES[_mode])
	_cheats_button.text = Lang.t("Allow Cheats: %s") % Lang.t("ON" if _cheats else "OFF")
	_internet_button.text = Lang.t("Allow Internet Access: %s") % Lang.t("ON" if _internet else "OFF")
	_warning.modulate.a = 1.0 if _internet else 0.0 # (keeps its place)


func _start() -> void:
	Net.lan_game_mode = _mode
	Net.cheats = _cheats
	Net.internet = _internet
	var error := Net.host()
	var chat := menu.chat
	if error == "" and _internet:
		menu.replace(InviteScreen.new()) # the code when the router answers
	else:
		menu.close()
	if chat:
		chat.add_message(Lang.t(error) if error != "" else Lang.t("Local game hosted on port %d") % Net.PORT,
			CommandSource.MessageKind.INFO)
		if error == "" and not _internet:
			chat.add_message(NetCommands.invite_text(false), CommandSource.MessageKind.INFO)
