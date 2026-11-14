class_name InviteScreen
extends MenuScreen
## "Invite Friends" (the pause menu while hosting, and after Open to LAN):
## how others can join this world. Over the internet: the invite code with
## Copy (while the router's ports are open), or why they couldn't be opened
## and what to do instead (a VPN that makes one network of the computers).
## On the same network (or the VPN): this computer's LAN addresses.
##
## For the server this game started (`local`: Create Server's My Server,
## and Invite Friends while playing on it) the same, as the server tells
## (LocalServer.info): its invite code or public address and its LAN
## addresses; from the Multiplayer screen with Join Server and Stop Server.

const P := UiTheme.PIXEL
const GRAY := Color("a0a0a0")
const CODE_COLOR := Color("ffff55")
## Radmin VPN, ZeroTier... when the router can't help.
const VPN_HINT := "Instead, both players can install a VPN such as Radmin VPN or ZeroTier, join the same network in it and connect by the LAN address below (or the game shows up in the list)."

var _status: Label
var _code_row: HBoxContainer
var _code: Label
var _address: Label
var _hint: Label
var _open_button: Button
var _warning: Label
var _lan_label: Label
var _local := false
var _on_join := Callable()


func _init(local: bool = false, on_join: Callable = Callable()) -> void:
	title = "My Server" if local and on_join.is_valid() else "Invite Friends"
	columns = 1
	center_vertically = true
	_local = local
	_on_join = on_join


func build() -> void:
	add_list_item(_caption("Over the Internet"))
	_status = _label("", Color.WHITE)
	add_list_item(_status)
	_code_row = HBoxContainer.new()
	_code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_row.add_theme_constant_override("separation", 6 * P)
	_code = _label("", CODE_COLOR)
	_code.custom_minimum_size = Vector2.ZERO
	_code.autowrap_mode = TextServer.AUTOWRAP_OFF
	_code_row.add_child(_code)
	var copy := _make_button("Copy", func() -> void:
		DisplayServer.clipboard_set(_code.text)
		_status.text = Lang.t("Copied!")
		_status.visible = true)
	copy.custom_minimum_size = Vector2(90 * P, UiTheme.BUTTON_HEIGHT)
	copy.tooltip_text = Lang.t("Only share the code with people you trust")
	_code_row.add_child(copy)
	add_list_item(_code_row)
	_address = _label("", GRAY)
	add_list_item(_address)
	_hint = _label("", GRAY)
	add_list_item(_hint)
	_open_button = _make_button("", func() -> void:
		if _local:
			Net.local_server.allow_internet()
		else:
			Net.allow_internet())
	_open_button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	var centered := CenterContainer.new()
	centered.add_child(_open_button)
	add_list_item(centered)
	# (Short on screen; what to do with the code and the warning are in the
	# tooltips of the code and the Copy button.)
	_warning = _label("", UiTheme.WARNING_COLOR)
	_warning.visible = false
	add_list_item(_gap())
	add_list_item(_caption("On Your Network"))
	_lan_label = _label("", Color.WHITE)
	_lan_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_list_item(_lan_label)
	if _local and _on_join.is_valid():
		var join := _on_join
		add_bottom_row([
			["Join Server", func() -> void:
				menu.back()
				join.call()],
			["Stop Server", func() -> void:
				Net.local_server.stop()
				menu.back()],
		])
	add_done_button()
	Net.port_forward.changed.connect(_update)
	Net.local_server.changed.connect(_update)
	_update()


func _exit_tree() -> void:
	if Net.port_forward.changed.is_connected(_update):
		Net.port_forward.changed.disconnect(_update)
	if Net.local_server.changed.is_connected(_update):
		Net.local_server.changed.disconnect(_update)


## The router's state, the address and the code: this game's (hosting) or
## the local server's (as it last told).
func _state() -> PortForward.State:
	if not _local:
		return Net.port_forward.state
	var info := Net.local_server.info
	if str(info.get("code", "")) != "":
		return PortForward.State.OPEN
	return {"working": PortForward.State.WORKING, "failed": PortForward.State.FAILED}.get(str(info.get("upnp", "off")),
		PortForward.State.OFF)


func _process(_delta: float) -> void:
	if _state() == PortForward.State.WORKING:
		var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		_status.text = Lang.t("Asking your router to open the port") + dots


func _update() -> void:
	var forward := Net.port_forward
	var state := _state()
	var info := Net.local_server.info
	var port: int = int(info.get("port", Net.local_server.port)) if _local else Net.host_port
	var lines := PackedStringArray()
	if _local:
		lines = PackedStringArray(info.get("lan", []))
	else:
		for ip in InviteCode.lan_addresses():
			lines.append("%s:%d" % [ip, port])
	_lan_label.text = "\n".join(lines) if not lines.is_empty() else Lang.t("No network found")
	_lan_label.tooltip_text = Lang.t("Your world is open on port %d") % port \
		+ "\n" + Lang.t("Friends on the same Wi-Fi or a VPN connect to one of these addresses")
	_code_row.visible = state == PortForward.State.OPEN
	_address.visible = state == PortForward.State.OPEN
	_hint.visible = false # (the VPN advice is the error's tooltip)
	_status.visible = state != PortForward.State.OPEN
	_status.tooltip_text = ""
	_open_button.visible = state == PortForward.State.OFF or state == PortForward.State.FAILED
	_open_button.text = Lang.t("Try Again" if state == PortForward.State.FAILED else "Allow Internet Access")
	_status.remove_theme_color_override("font_color")
	match state:
		PortForward.State.OFF:
			_status.text = Lang.t("Internet access is off")
		PortForward.State.WORKING:
			_process(0.0)
		PortForward.State.OPEN:
			_code.text = str(info.get("code", "")) if _local else Net.invite_code()
			_address.text = str(info.get("internet", "")) if _local else Net.internet_address()
			_code.tooltip_text = Lang.t("Friends join with this code (Direct Connect or Add Server):") \
				+ "\n" + Lang.t("Internet address: %s") % _address.text \
				+ "\n" + Lang.t("Only share the code with people you trust")
		PortForward.State.FAILED:
			_status.text = Lang.t(str(info.get("upnp_error", "")) if _local else forward.error)
			_status.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
			_status.tooltip_text = Lang.t(VPN_HINT)


## A centered, wrapping line as wide as the wide buttons (not translated by
## itself: the texts are built with Lang.t, addresses stay as they are).
func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON * 1.5, 0)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_PASS # (for the tooltips)
	return label


func _caption(text: String) -> Label:
	var label := _label(Lang.t(text), UiTheme.TITLE_COLOR)
	return label


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4 * P)
	return gap
