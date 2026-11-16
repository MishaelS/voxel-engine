class_name RenameWorldScreen
extends MenuScreen
## "Rename World", like Beta 1.7.3's GuiRenameWorld: the world's name in a
## field (selected, ready to type over), "Rename" (not while the field is
## empty) and "Cancel". Only the name changes (WorldSave.rename), its folder
## stays.

const GRAY := Color("a0a0a0")
const FIELD_WIDTH := UiTheme.HALF_BUTTON * 2 + COLUMN_GAP

var _save: WorldSave
## Called with the new name once it is saved.
var _on_renamed := Callable()
var _name: LineEdit
var _rename: Button


func _init(save: WorldSave, on_renamed: Callable) -> void:
	title = "Rename World"
	columns = 1
	_save = save
	_on_renamed = on_renamed


func build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2 * UiTheme.PIXEL)
	add_list_item(column)
	var label := Label.new()
	label.text = Lang.t("Enter Name")
	label.add_theme_color_override("font_color", GRAY)
	column.add_child(label)
	_name = LineEdit.new()
	_name.text = _save.name
	_name.max_length = 32
	_name.custom_minimum_size = Vector2(FIELD_WIDTH, UiTheme.BUTTON_HEIGHT)
	_name.text_changed.connect(func(_text: String) -> void: _update())
	_name.text_submitted.connect(func(_text: String) -> void: _apply())
	column.add_child(_name)
	_rename = add_bottom_row([["Rename", func() -> void: _apply()], ["Cancel", func() -> void: menu.back()]])[0]
	_update()
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func _update() -> void:
	_rename.disabled = _name.text.strip_edges().is_empty()


func _apply() -> void:
	var new_name := _name.text.strip_edges()
	if new_name.is_empty():
		return
	_save.rename(new_name)
	_on_renamed.call(new_name)
	menu.back()
