class_name EditServerScreen
extends MenuScreen
## "Edit Server Info" (adding or editing a server in the server list), like
## the classic game's: the server's name and address (or an invite code:
## the address it stands for is shown under it), Done and Cancel.
## Done is off until both are filled in.

## Called with the name and the address on Done.
var _on_done := Callable()
var _start_name := ""
var _start_address := ""
var _name: LineEdit
var _address: LineEdit
var _hint: Label
var _done: Button


func _init(server_name: String, address: String, on_done: Callable) -> void:
	title = "Edit Server Info"
	columns = 1
	center_vertically = true
	_start_name = server_name
	_start_address = address
	_on_done = on_done


func build() -> void:
	add_list_item(caption("Server Name"))
	_name = field(_start_name)
	add_list_item(_name)
	add_list_item(caption("Server Address or Invite Code"))
	_address = field(_start_address)
	_address.text_submitted.connect(func(_text: String) -> void: _finish())
	add_list_item(_address)
	_hint = code_hint()
	add_list_item(_hint)
	_done = add_bottom_button("Done", _finish)
	add_bottom_button("Cancel", func() -> void: menu.back())
	for edit: LineEdit in [_name, _address]:
		edit.text_changed.connect(func(_text: String) -> void: _update())
	_update()
	_name.grab_focus.call_deferred()


func _update() -> void:
	show_code_hint(_hint, _address.text)
	_done.disabled = _name.text.strip_edges() == "" or _address.text.strip_edges() == ""


func _finish() -> void:
	if _done.disabled:
		return
	menu.back()
	_on_done.call(_name.text.strip_edges(), _address.text.strip_edges())


## A gray caption over a field.
static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = Lang.t(text)
	label.add_theme_color_override("font_color", Color("a0a0a0"))
	return label


## The line under an address field: what an invite code stands for.
static func code_hint() -> Label:
	var label := caption("")
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


## "Invite code for 1.2.3.4:25565", "This invite code has a typo" or nothing.
static func show_code_hint(label: Label, text: String) -> void:
	var address := InviteCode.decode(text)
	if address != "":
		label.text = Lang.t("Invite code for %s") % address
		label.add_theme_color_override("font_color", Color("55ff55"))
	elif InviteCode.looks_like_code(text):
		label.text = Lang.t("This invite code has a typo")
		label.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
	else:
		label.text = " " # (keeps its height)


## A text field as wide as the wide buttons.
static func field(text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.max_length = 64
	edit.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	return edit
