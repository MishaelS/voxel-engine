class_name DirectConnectScreen
extends MenuScreen
## "Direct Connect", like the classic game's: a server address to join
## without adding it to the list (starts with the last one joined), or an
## invite code from a friend hosting over the internet.

## Called with the address on "Join Server".
var _on_join := Callable()
var _address: LineEdit
var _hint: Label
var _join: Button


func _init(on_join: Callable) -> void:
	title = "Direct Connect"
	columns = 1
	center_vertically = true
	_on_join = on_join


func build() -> void:
	add_list_item(EditServerScreen.caption("Server Address or Invite Code"))
	_address = EditServerScreen.field(Net.last_address)
	_address.text_changed.connect(func(text: String) -> void:
		_join.disabled = text.strip_edges() == ""
		EditServerScreen.show_code_hint(_hint, text))
	_address.text_submitted.connect(func(_text: String) -> void: _finish())
	add_list_item(_address)
	_hint = EditServerScreen.code_hint()
	EditServerScreen.show_code_hint(_hint, _address.text)
	add_list_item(_hint)
	_join = add_bottom_button("Join Server", _finish)
	add_bottom_button("Cancel", func() -> void: menu.back())
	_join.disabled = _address.text.strip_edges() == ""
	_address.grab_focus.call_deferred()


func _finish() -> void:
	var address := _address.text.strip_edges()
	if address == "":
		return
	menu.back()
	_on_join.call(address)
