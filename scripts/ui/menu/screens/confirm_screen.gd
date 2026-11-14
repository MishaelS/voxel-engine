class_name ConfirmScreen
extends MenuScreen
## A question with a confirm and a cancel button (e.g. deleting a world).
## The second button can do something too (`on_other`: "Keep Running").

var _message := ""
var _confirm_text := ""
var _on_confirm := Callable()
var _other_text := "Cancel"
var _on_other := Callable()


func _init(question: String, message: String, confirm_text: String, on_confirm: Callable,
		other_text: String = "Cancel", on_other: Callable = Callable()) -> void:
	title = question
	_message = message
	_confirm_text = confirm_text
	_on_confirm = on_confirm
	_other_text = other_text
	_on_other = on_other
	columns = 1
	center_vertically = true


func build() -> void:
	var label := Label.new()
	label.text = _message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_list_item(label)
	add_bottom_row([
		[_confirm_text, func() -> void:
			menu.back()
			_on_confirm.call()],
		[_other_text, func() -> void:
			menu.back()
			if _on_other.is_valid():
				_on_other.call()],
	])
