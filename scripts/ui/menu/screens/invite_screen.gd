class_name InviteScreen
extends MenuScreen
## "Invite Friends" (the pause menu while hosting, and after Open to LAN):
## how others can join this world. Over the internet: the invite code with
## Copy (while the router's ports are open), or why they couldn't be opened
## and what to do instead (a VPN that makes one network of the computers).
## On the same network (or the VPN): this computer's LAN addresses.

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


func _init() -> void:
	title = "Invite Friends"
	columns = 1
	center_vertically = true


func build() -> void:
	add_list_item(_label(Lang.t("Your world is open on port %d") % Net.host_port, GRAY))
	add_list_item(_gap())
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
		DisplayServer.clipboard_set(Net.invite_code())
		_status.text = Lang.t("Copied! Send the code to your friend"))
	copy.custom_minimum_size = Vector2(90 * P, UiTheme.BUTTON_HEIGHT)
	_code_row.add_child(copy)
	add_list_item(_code_row)
	_address = _label("", GRAY)
	add_list_item(_address)
	_hint = _label("", GRAY)
	add_list_item(_hint)
	_open_button = _make_button("", func() -> void: Net.allow_internet())
	_open_button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	var centered := CenterContainer.new()
	centered.add_child(_open_button)
	add_list_item(centered)
	_warning = _label(Lang.t("Only share the code with people you trust"), UiTheme.WARNING_COLOR)
	add_list_item(_warning)
	add_list_item(_gap())
	add_list_item(_caption("On Your Network"))
	var lan := InviteCode.lan_addresses()
	var lines := PackedStringArray()
	for ip in lan:
		lines.append("%s:%d" % [ip, Net.host_port])
	add_list_item(_label("\n".join(lines) if not lines.is_empty() else Lang.t("No network found"), Color.WHITE))
	add_done_button()
	Net.port_forward.changed.connect(_update)
	_update()


func _exit_tree() -> void:
	if Net.port_forward.changed.is_connected(_update):
		Net.port_forward.changed.disconnect(_update)


func _process(_delta: float) -> void:
	if Net.port_forward.state == PortForward.State.WORKING:
		var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		_status.text = Lang.t("Asking your router to open the port") + dots


func _update() -> void:
	var forward := Net.port_forward
	var state := forward.state
	_code_row.visible = state == PortForward.State.OPEN
	_address.visible = state == PortForward.State.OPEN
	_hint.visible = state == PortForward.State.FAILED
	_warning.visible = state == PortForward.State.OPEN or state == PortForward.State.WORKING
	_open_button.visible = state == PortForward.State.OFF or state == PortForward.State.FAILED
	_open_button.text = Lang.t("Try Again" if state == PortForward.State.FAILED else "Allow Internet Access")
	_status.remove_theme_color_override("font_color")
	match state:
		PortForward.State.OFF:
			_status.text = Lang.t("Internet access is off")
		PortForward.State.WORKING:
			_process(0.0)
		PortForward.State.OPEN:
			_status.text = Lang.t("Friends join with this code (Direct Connect or Add Server):")
			_code.text = Net.invite_code()
			_address.text = Lang.t("Internet address: %s") % ("%s:%d" % [forward.external_ip, forward.port])
		PortForward.State.FAILED:
			_status.text = Lang.t(forward.error)
			_status.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
			_hint.text = Lang.t(VPN_HINT)


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
	return label


func _caption(text: String) -> Label:
	var label := _label(Lang.t(text), UiTheme.TITLE_COLOR)
	return label


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4 * P)
	return gap
