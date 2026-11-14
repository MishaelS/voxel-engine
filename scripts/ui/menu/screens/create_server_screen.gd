class_name CreateServerScreen
extends MenuScreen
## "Create Server" (the Multiplayer screen): a server for friends that runs
## in the background on this computer (LocalServer) while this player plays
## on it. Few choices: the world (one of the saved ones, or a new one), a
## password and internet access; the rest has friendly defaults and can be
## changed in its server.properties. Start Server waits until the server
## answers, then joins it (`on_join` with the address and the password).

var _on_join := Callable()
var _worlds: Array[WorldSave] = []
## Index into _worlds; _worlds.size() is "New World".
var _world := 0
var _internet := true
var _world_button: Button
var _name_caption: Label
var _name: LineEdit
var _password: LineEdit
var _internet_button: Button
var _status: Label
var _start: Button
var _joined := false


func _init(on_join: Callable) -> void:
	title = "Create Server"
	columns = 1
	center_vertically = true
	_on_join = on_join


func build() -> void:
	_worlds = WorldSave.list_all()
	_world_button = add_list_wide_button("", func() -> void:
		_world = (_world + 1) % (_worlds.size() + 1)
		_update())
	_world_button.tooltip_text = Lang.t("Click to choose another world (or a new one)") + "\n" \
		+ Lang.t("Don't open this world in Singleplayer while the server runs")
	_name_caption = EditServerScreen.caption("World Name")
	add_list_item(_name_caption)
	_name = EditServerScreen.field(Lang.t("New World"))
	_name.max_length = 32
	_name.text_changed.connect(func(_text: String) -> void: _update())
	add_list_item(_name)
	var caption := EditServerScreen.caption("Password")
	caption.mouse_filter = Control.MOUSE_FILTER_PASS
	add_list_item(caption)
	_password = EditServerScreen.field("")
	_password.max_length = 64
	_password.placeholder_text = Lang.t("None")
	_password.tooltip_text = Lang.t("Friends type it once when joining") + "\n" \
		+ Lang.t("Empty: anyone who knows the address can join")
	caption.tooltip_text = _password.tooltip_text
	add_list_item(_password)
	_internet_button = add_list_wide_button("", func() -> void:
		_internet = not _internet
		_update())
	_internet_button.tooltip_text = Lang.t("Opens the port on your router (UPnP) and gives an invite code for friends on the internet") \
		+ "\n" + Lang.t("Only share the code with people you trust")
	_status = EditServerScreen.caption("")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, 0)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_list_item(_status)
	var buttons := add_bottom_row([["Start Server", _start_server], ["Cancel", func() -> void: menu.back()]])
	_start = buttons[0]
	_start.tooltip_text = Lang.t("The server keeps running while you play; friends join it like any server") \
		+ "\n" + Lang.t("More settings: server.properties in the game folder's server folder")
	Net.local_server.changed.connect(_on_server_changed)
	_update()


func _exit_tree() -> void:
	if Net.local_server.changed.is_connected(_on_server_changed):
		Net.local_server.changed.disconnect(_on_server_changed)


func _process(_delta: float) -> void:
	if Net.local_server.state == LocalServer.State.STARTING:
		var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		_status.text = Lang.t("Starting the server") + dots


func _update() -> void:
	var new_world := _world >= _worlds.size()
	_world_button.text = Lang.t("World: %s") % (Lang.t("New World") if new_world else _worlds[_world].name)
	_name_caption.visible = new_world
	_name.visible = new_world
	_internet_button.text = Lang.t("Allow Internet Access: %s") % Lang.t("ON" if _internet else "OFF")
	var busy := Net.local_server.is_running()
	_start.disabled = busy or (new_world and _name.text.strip_edges() == "")


func _start_server() -> void:
	var folder := ""
	var game_mode := 0
	if _world < _worlds.size():
		folder = _worlds[_world].folder
		game_mode = _worlds[_world].game_mode
	else:
		var save := WorldSave.create(_name.text, randi(), VoxelWorld.Generator.BETA, 0, false)
		folder = save.folder
	_status.remove_theme_color_override("font_color")
	Net.local_server.start(folder, game_mode, _password.text, _internet)
	_update()


func _on_server_changed() -> void:
	var server := Net.local_server
	match server.state:
		LocalServer.State.RUNNING:
			if _joined or not is_inside_tree() or menu == null:
				return
			_joined = true
			var join := _on_join
			var address := server.address()
			var secret := server.password
			menu.back()
			join.call(address, secret)
		LocalServer.State.FAILED:
			_status.text = NetErrors.text(server.error_code, server.error_args) + "  (%s)" % NetErrors.label(server.error_code)
			_status.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
	_update()
