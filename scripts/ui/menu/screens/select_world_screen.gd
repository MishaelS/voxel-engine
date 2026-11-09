class_name SelectWorldScreen
extends MenuScreen
## "Select World", like the classic game: the saved worlds (most recently
## played first) with name, folder, last played date and game mode. Click
## selects, double click plays. Buttons: Play Selected World, Create New
## World, Delete (asks first), Cancel.

const ENTRY_WIDTH := 220 * UiTheme.PIXEL
const ENTRY_HEIGHT := 36 * UiTheme.PIXEL
const MODE_NAMES := ["Survival", "Creative"]

## Called with the WorldSave to play.
var on_play := Callable()

var _worlds: Array[WorldSave] = []
var _entries: Array[PanelContainer] = []
var _selected := -1
var _play: Button
var _delete: Button


func _init(play: Callable) -> void:
	title = "Select World"
	columns = 1
	on_play = play


func build() -> void:
	_worlds = WorldSave.list_all()
	for i in _worlds.size():
		var entry := _make_entry(_worlds[i], i)
		_entries.append(entry)
		add_list_item(entry)
	if _worlds.is_empty():
		var empty := Label.new()
		empty.text = "No worlds yet"
		empty.add_theme_color_override("font_color", UiTheme.DISABLED_TEXT_COLOR)
		add_list_item(empty)
	var top := add_bottom_row([
		["Play Selected World", func() -> void: _play_selected()],
		["Create New World", func() -> void: menu.push(CreateWorldScreen.new(on_play))],
	])
	var bottom := add_bottom_row([
		["Delete", func() -> void: _ask_delete()],
		["Cancel", func() -> void: menu.back()],
	])
	_play = top[0]
	_delete = bottom[0]
	_select(0 if not _worlds.is_empty() else -1)


func _make_entry(save: WorldSave, index: int) -> PanelContainer:
	var entry := PanelContainer.new()
	entry.custom_minimum_size = Vector2(ENTRY_WIDTH, ENTRY_HEIGHT)
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(lines)
	var name_label := Label.new()
	name_label.text = save.name
	name_label.add_theme_color_override("font_color", Color.WHITE)
	lines.add_child(name_label)
	var details := Label.new()
	var played := Time.get_datetime_string_from_unix_time(save.last_played + _timezone_seconds(), true)
	details.text = "%s (%s)" % [save.folder, played]
	details.add_theme_color_override("font_color", Color("808080"))
	lines.add_child(details)
	var mode := Label.new()
	mode.text = Lang.t("%s Mode, seed %d") % [Lang.t(MODE_NAMES[clampi(save.game_mode, 0, 1)]), save.world_seed]
	mode.add_theme_color_override("font_color", Color("808080"))
	lines.add_child(mode)
	for label: Label in [name_label, details, mode]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
	entry.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select(index)
			if event.double_click:
				_play_selected())
	return entry


func _select(index: int) -> void:
	_selected = index
	for i in _entries.size():
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.6) if i == index else Color(0, 0, 0, 0)
		box.border_color = Color("808080")
		box.set_border_width_all(UiTheme.PIXEL if i == index else 0)
		box.set_content_margin_all(3 * UiTheme.PIXEL)
		_entries[i].add_theme_stylebox_override("panel", box)
	_play.disabled = index < 0
	_delete.disabled = index < 0


func _play_selected() -> void:
	if _selected >= 0:
		on_play.call(_worlds[_selected])


func _ask_delete() -> void:
	if _selected < 0:
		return
	var save := _worlds[_selected]
	menu.push(ConfirmScreen.new("Are you sure you want to delete this world?",
		Lang.t("'%s' will be lost forever! (A long time!)") % save.name, "Delete", func() -> void:
			save.delete()
			# Rebuild the list.
			menu.back()
			menu.push(SelectWorldScreen.new(on_play))))


static func _timezone_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
