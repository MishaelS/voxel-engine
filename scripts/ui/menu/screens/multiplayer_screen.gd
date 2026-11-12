class_name MultiplayerScreen
extends MenuScreen
## "Multiplayer": the player's name, the games found on the local network
## (a button each, like the classic game's LAN worlds) and a server address
## to join by hand. Net does the connecting; the game starts when the host
## answers.

var _name: LineEdit
var _address: LineEdit
var _status: Label
var _games: VBoxContainer


func _init() -> void:
	title = "Play Multiplayer"
	columns = 1


func build() -> void:
	add_list_item(_caption("Your Name"))
	_name = _field(Net.player_name)
	_name.text_changed.connect(func(text: String) -> void:
		Net.player_name = text.strip_edges() if text.strip_edges() != "" else Net.player_name
		Net.save_config())
	add_list_item(_name)
	add_list_item(_caption("Games on the Local Network"))
	_games = VBoxContainer.new()
	_games.add_theme_constant_override("separation", 4 * UiTheme.PIXEL)
	add_list_item(_games)
	add_list_item(_caption("Server Address"))
	_address = _field(Net.last_address)
	_address.text_submitted.connect(func(text: String) -> void: _join(text))
	add_list_item(_address)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("a0a0a0"))
	add_list_item(_status)
	add_bottom_row([["Join Server", func() -> void: _join(_address.text)], ["Cancel", func() -> void: menu.back()]])
	Net.listen_lan()
	Net.lan_games_changed.connect(_show_games)
	Net.players_changed.connect(_show_status)
	_show_games()
	_show_status()


func _exit_tree() -> void:
	Net.stop_listening_lan()
	if Net.lan_games_changed.is_connected(_show_games):
		Net.lan_games_changed.disconnect(_show_games)
	if Net.players_changed.is_connected(_show_status):
		Net.players_changed.disconnect(_show_status)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = Lang.t(text)
	label.add_theme_color_override("font_color", Color("a0a0a0"))
	return label


func _field(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.max_length = 48
	field.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	return field


func _show_games() -> void:
	for child in _games.get_children():
		child.queue_free()
	if Net.lan_games.is_empty():
		var label := _caption("Scanning for games on your local network")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_games.add_child(label)
		return
	for key: String in Net.lan_games:
		var game: Dictionary = Net.lan_games[key]
		var button := _make_button("%s - %s" % [game.name, game.world], func() -> void: _join(key))
		button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
		_games.add_child(button)


func _join(address: String) -> void:
	var error := Net.join(address)
	_status.text = Lang.t(error) if error != "" else Lang.t("Connecting to the server...")


func _show_status() -> void:
	if Net.last_error != "" and _status:
		_status.text = Lang.t(Net.last_error)
