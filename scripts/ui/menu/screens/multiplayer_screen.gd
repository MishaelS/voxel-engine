class_name MultiplayerScreen
extends MenuScreen
## "Play Multiplayer", like the classic game's server list: the player's
## name, the saved servers (name, message of the day or why it can't be
## reached, address; the signal bars and players on the right, from a
## ServerStatus ping that doesn't join), then the games found on the local
## network. Click selects, double click joins. Buttons: Join Server, Direct
## Connect, Add Server, Create Server (a server in the background for
## friends; while it runs: My Server, its addresses); Edit, Delete (asks
## first), Refresh, Cancel. A refused join shows why (DisconnectedScreen),
## or asks for the password.
## The servers are kept in user://servers.cfg; Net does the connecting and
## the game starts when the host answers.

const P := UiTheme.PIXEL
const ENTRY_WIDTH := 270 * P
const ENTRY_HEIGHT := 36 * P
const SERVERS_PATH := "user://servers.cfg"
const NAME_COLOR := Color.WHITE
const MOTD_COLOR := Color("808080")
const ADDRESS_COLOR := Color("303030")
const ERROR_COLOR := Color("aa0000")

## The saved servers: {"name", "address"}.
var _servers: Array[Dictionary] = []
## Saved servers' entries, then the LAN games' (with their keys).
var _entries: Array[ServerEntry] = []
var _lan_keys: Array[String] = []
var _selected := -1
var _rows: VBoxContainer
var _lan_rows: VBoxContainer
var _scanning: Label
var _status: Label
var _join: Button
var _create: Button
var _edit: Button
var _delete: Button


func _init() -> void:
	title = "Play Multiplayer"
	columns = 1


func build() -> void:
	add_list_item(_name_row())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	add_list_item(_rows)
	_lan_rows = VBoxContainer.new()
	_lan_rows.add_theme_constant_override("separation", 0)
	add_list_item(_lan_rows)
	_scanning = Label.new()
	_scanning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scanning.custom_minimum_size = Vector2(ENTRY_WIDTH, 0)
	_scanning.add_theme_color_override("font_color", MOTD_COLOR)
	add_list_item(_scanning)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("a0a0a0"))
	_bottom.add_child(_status)
	var width := (UiTheme.WIDE_BUTTON * 2.0 - 3 * COLUMN_GAP) / 4.0
	var top := add_bottom_row([
		["Join Server", func() -> void: _join_selected()],
		["Direct Connect", func() -> void: menu.push(DirectConnectScreen.new(_join_address))],
		["Add Server", func() -> void: menu.push(EditServerScreen.new(Lang.t("Minecraft Server"), "", _add))],
		["Create Server", func() -> void: _open_server()],
	], width)
	var bottom_width := width
	var bottom := add_bottom_row([
		["Edit", func() -> void: _edit_selected()],
		["Delete", func() -> void: _ask_delete()],
		["Refresh", func() -> void: _refresh_all()],
		["Cancel", func() -> void: menu.back()],
	], bottom_width)
	_join = top[0]
	_create = top[3]
	_create.tooltip_text = Lang.t("A server for friends that runs in the background while you play")
	_edit = bottom[0]
	_delete = bottom[1]

	_servers = load_servers()
	_show_servers()
	Net.listen_lan()
	Net.lan_games_changed.connect(_show_lan_games)
	Net.players_changed.connect(_show_status)
	Net.local_server.changed.connect(_show_server_button)
	_show_server_button()
	_show_lan_games()
	_show_status()
	_select(-1)


func _exit_tree() -> void:
	Net.stop_listening_lan()
	if Net.lan_games_changed.is_connected(_show_lan_games):
		Net.lan_games_changed.disconnect(_show_lan_games)
	if Net.players_changed.is_connected(_show_status):
		Net.players_changed.disconnect(_show_status)
	if Net.local_server.changed.is_connected(_show_server_button):
		Net.local_server.changed.disconnect(_show_server_button)


func _process(_delta: float) -> void:
	# The classic "O o o" while scanning the local network.
	var frame := int(Time.get_ticks_msec() / 300) % 4
	var dots: String = ["O o o", "o O o", "o o O", "o O o"][frame]
	_scanning.text = "%s\n%s" % [Lang.t("Scanning for games on your local network"), dots]


## "Your Name" (shown to the others) above the list.
func _name_row() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ENTRY_WIDTH, 0)
	row.add_theme_constant_override("separation", 4 * P)
	var label := EditServerScreen.caption("Your Name")
	row.add_child(label)
	var edit := EditServerScreen.field(Net.player_name)
	edit.max_length = 16
	edit.custom_minimum_size = Vector2(0, UiTheme.BUTTON_HEIGHT)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			Net.player_name = text.strip_edges()
			Net.save_config())
	row.add_child(edit)
	return row


# --- The list ------------------------------------------------------------------------

func _show_servers() -> void:
	for entry in _entries:
		entry.queue_free()
	_entries.clear()
	_lan_keys.clear()
	for i in _servers.size():
		var entry := ServerEntry.new(self)
		entry.show_server(_servers[i].name, _servers[i].address)
		_rows.add_child(entry)
		_entries.append(entry)
	_show_lan_games()


func _show_lan_games() -> void:
	if _lan_rows == null:
		return
	var lan_index := _selected - _servers.size()
	var selected_key := _lan_keys[lan_index] if lan_index >= 0 and lan_index < _lan_keys.size() else ""
	for i in range(_entries.size() - 1, _servers.size() - 1, -1):
		_entries[i].queue_free()
		_entries.remove_at(i)
	_lan_keys.clear()
	for key: String in Net.lan_games:
		var game: Dictionary = Net.lan_games[key]
		var entry := ServerEntry.new(self)
		entry.show_lan_game(str(game.world), str(game.name), key)
		_lan_rows.add_child(entry)
		_entries.append(entry)
		_lan_keys.append(key)
	if _selected >= _servers.size():
		var index := _lan_keys.find(selected_key)
		_select(_servers.size() + index if index >= 0 else -1)


## Pings every saved server again (and rebuilds the list).
func _refresh_all() -> void:
	var keep := _selected
	_show_servers()
	_select(keep if keep < _entries.size() else -1)


func _select(index: int) -> void:
	_selected = index
	for i in _entries.size():
		_entries[i].set_selected(i == index)
	var is_server := index >= 0 and index < _servers.size()
	_join.disabled = index < 0
	_edit.disabled = not is_server
	_delete.disabled = not is_server


## An entry was clicked (ServerEntry).
func entry_clicked(entry: ServerEntry, double: bool) -> void:
	_select(_entries.find(entry))
	if double:
		_join_selected()


# --- Buttons -------------------------------------------------------------------------

## The address being joined (for the password screen).
var _joining := ""


func _join_selected() -> void:
	if _selected < 0:
		return
	if _selected < _servers.size():
		_join_address(_servers[_selected].address)
	else:
		_join_address(_lan_keys[_selected - _servers.size()])


## Whether a join started here is still waiting for its answer (a refusal
## is shown once).
var _waiting := false


func _join_address(address: String) -> void:
	if address != _joining:
		Net.join_password = "" # (a password is for the server it was typed for)
	_joining = address
	var error := Net.join(address)
	_waiting = error == 0
	if error != 0:
		menu.push(DisconnectedScreen.new(error, Net.last_args, true))
	_status.text = "" if error != 0 else Lang.t("Connecting to the server...")


## Joins with a password known already (Create Server's own).
func join_with_password(address: String, secret: String) -> void:
	_joining = address
	Net.join_password = secret
	_join_address(address)


## Create Server, or (while it runs) its addresses, Join and Stop.
func _open_server() -> void:
	if Net.local_server.is_running():
		menu.push(InviteScreen.new(true, func() -> void:
			join_with_password(Net.local_server.address(), Net.local_server.password)))
	else:
		menu.push(CreateServerScreen.new(join_with_password))


func _show_server_button() -> void:
	if _create:
		_create.text = Lang.t("My Server" if Net.local_server.is_running() else "Create Server")


func _add(server_name: String, address: String) -> void:
	_servers.append({"name": server_name, "address": address})
	save_servers(_servers)
	_show_servers()
	_select(_servers.size() - 1)


func _edit_selected() -> void:
	if _selected < 0 or _selected >= _servers.size():
		return
	var index := _selected
	menu.push(EditServerScreen.new(_servers[index].name, _servers[index].address,
		func(server_name: String, address: String) -> void:
			_servers[index] = {"name": server_name, "address": address}
			save_servers(_servers)
			_show_servers()
			_select(index)))


func _ask_delete() -> void:
	if _selected < 0 or _selected >= _servers.size():
		return
	var index := _selected
	menu.push(ConfirmScreen.new("Are you sure you want to remove this server?",
		Lang.t("'%s' will be lost forever! (A long time!)") % _servers[index].name, "Delete", func() -> void:
			_servers.remove_at(index)
			save_servers(_servers)
			_show_servers()
			_select(-1)))


func _show_status() -> void:
	if not _waiting or Net.is_online() or Net.last_code == 0 or not is_inside_tree() or menu == null:
		return
	_waiting = false
	_status.text = ""
	if Net.password_wanted:
		# The server wants a password: asked for, then joined again.
		Net.password_wanted = false
		menu.push(PasswordScreen.new(_joining, _join_address))
	else:
		menu.push(DisconnectedScreen.new(Net.last_code, Net.last_args, true))


# --- Saving --------------------------------------------------------------------------

## The saved servers ({"name", "address"}). The first time (no file yet)
## the list starts with the last address joined, so it isn't lost.
static func load_servers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(SERVERS_PATH):
		result.append({"name": Lang.t("Minecraft Server"), "address": Net.last_address})
		save_servers(result)
		return result
	var config := ConfigFile.new()
	if config.load(SERVERS_PATH) != OK:
		return result
	for value: Variant in config.get_value("servers", "list", []):
		if value is Dictionary and value.has("address"):
			result.append({"name": str(value.get("name", "")), "address": str(value.address)})
	return result


static func save_servers(servers: Array[Dictionary]) -> void:
	var config := ConfigFile.new()
	config.set_value("servers", "list", servers)
	config.save(SERVERS_PATH)


## One row of the list: three lines of text (name, message or error,
## address), the players and the signal bars on the right. A saved server
## pings itself (ServerStatus) when shown.
class ServerEntry:
	extends PanelContainer

	var _screen: MultiplayerScreen
	var _lines: Array[Label] = []
	var _count: Label
	var _bars: SignalBars
	var _ping: ServerStatus

	func _init(screen: MultiplayerScreen) -> void:
		_screen = screen
		custom_minimum_size = Vector2(ENTRY_WIDTH, ENTRY_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 0)
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lines)
		for color: Color in [NAME_COLOR, MOTD_COLOR, ADDRESS_COLOR]:
			var label := Label.new()
			label.add_theme_color_override("font_color", color)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # names and addresses as typed
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lines.add_child(label)
			_lines.append(label)
		var right := HBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_END
		right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		right.add_theme_constant_override("separation", 2 * P)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)
		_count = Label.new()
		_count.add_theme_color_override("font_color", MOTD_COLOR)
		_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(_count)
		_bars = SignalBars.new()
		right.add_child(_bars)
		set_selected(false)
		gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_screen.entry_clicked(self, event.double_click))

	func show_server(server_name: String, address: String) -> void:
		_lines[0].text = server_name
		_lines[1].text = Lang.t("Pinging...")
		var decoded := InviteCode.decode(address)
		_lines[2].text = "%s (%s)" % [address, decoded] if decoded != "" else address
		_ping = ServerStatus.new(address)
		_bars.row = SignalBars.PINGING
		_update_ping()

	func show_lan_game(world_name: String, host_name: String, address: String) -> void:
		_lines[0].text = Lang.t("LAN World")
		_lines[1].text = "%s - %s" % [host_name, world_name]
		_lines[2].text = address
		_bars.visible = false

	func set_selected(selected: bool) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 1) if selected else Color(0, 0, 0, 0)
		box.border_color = Color("808080")
		box.set_border_width_all(P if selected else 0)
		box.set_content_margin_all(3 * P)
		add_theme_stylebox_override("panel", box)

	func _process(_delta: float) -> void:
		if _ping and _ping.is_waiting():
			_ping.poll()
			_update_ping()

	func _exit_tree() -> void:
		if _ping:
			_ping.close()

	func _update_ping() -> void:
		match _ping.state:
			ServerStatus.State.DONE:
				_lines[1].text = _ping.motd
				_lines[1].add_theme_color_override("font_color", MOTD_COLOR)
				var game_version := str(ProjectSettings.get_setting("application/config/version", "dev"))
				if _ping.version != game_version:
					_count.text = Lang.t("Version %s") % _ping.version
					_count.add_theme_color_override("font_color", ERROR_COLOR)
				else:
					_count.text = "%d/%d" % [_ping.players, _ping.max_players]
				_bars.row = PlayerList.bars_of(_ping.ping)
				_bars.tooltip_text = Lang.t("%d ms") % _ping.ping
			ServerStatus.State.UNREACHABLE, ServerStatus.State.UNRESOLVED:
				var unresolved: bool = _ping.state == ServerStatus.State.UNRESOLVED
				_lines[1].text = Lang.t("Can't resolve hostname" if unresolved else "Can't reach server")
				_lines[1].add_theme_color_override("font_color", ERROR_COLOR)
				_count.text = ""
				_bars.row = PlayerList.bars_of(-1)
				_bars.tooltip_text = ""
		_bars.queue_redraw()


## The signal bars (the Tab list's icons): a row of the icons, or the
## classic "pinging" animation (the bars lighting up one by one).
class SignalBars:
	extends Control

	const PINGING := -1

	var row := PINGING
	var _icons: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(10, 8) * P
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_PASS # the tooltip; clicks go on to the entry
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_icons = load(PlayerList.ICONS)

	func _process(_delta: float) -> void:
		if row == PINGING:
			queue_redraw()

	func _draw() -> void:
		var shown := row
		var tint := Color.WHITE
		if row == PINGING:
			# 1 to 5 bars and back, gray, like the classic "Pinging...".
			var frame := int(Time.get_ticks_msec() / 100) % 8
			var lit := frame + 1 if frame < 5 else 9 - frame
			shown = 5 - lit
			tint = Color(0.6, 0.6, 0.6)
		draw_texture_rect_region(_icons, Rect2(Vector2.ZERO, Vector2(10, 8) * P),
			Rect2(PlayerList.BARS_ORIGIN + Vector2(0, shown * 8), Vector2(10, 8)), tint)
