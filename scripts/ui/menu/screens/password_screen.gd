class_name PasswordScreen
extends MenuScreen
## "Server Password": a server asked for one (Net.password_wanted). The
## password is kept for this game only (Net.join_password) and never sent:
## the server gets a hash of it with a one-time number (Net.password_proof).

var _address := ""
var _on_join := Callable()
var _password: LineEdit
var _join: Button


func _init(address: String, on_join: Callable) -> void:
	title = "Server Password"
	columns = 1
	center_vertically = true
	_address = address
	_on_join = on_join


func build() -> void:
	var why := EditServerScreen.caption("")
	var code := Net.last_code if NetErrors.wants_password(Net.last_code) else NetErrors.PASSWORD_NEEDED
	why.text = "%s (%s)" % [NetErrors.text(code), NetErrors.label(code)]
	why.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_list_item(why)
	_password = EditServerScreen.field("")
	_password.secret = true
	_password.max_length = 128
	_password.text_changed.connect(func(text: String) -> void: _join.disabled = text == "")
	_password.text_submitted.connect(func(_text: String) -> void: _finish())
	add_list_item(_password)
	_join = add_bottom_button("Join Server", _finish)
	add_bottom_button("Cancel", func() -> void: menu.back())
	_join.disabled = true
	_password.grab_focus.call_deferred()


func _finish() -> void:
	if _password.text == "":
		return
	Net.join_password = _password.text
	menu.back()
	_on_join.call(_address)
