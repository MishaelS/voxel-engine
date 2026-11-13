class_name PauseScreen
extends MenuScreen
## Esc menu while playing, laid out like the game's (1.7): Back to Game;
## Achievements and Statistics side by side; a gap, then Options... and
## Open to LAN side by side; Save and Quit to Title. The buttons start a
## quarter of the screen down, like the game's (not in the middle).

const P := UiTheme.PIXEL
## Half of a row: two of them and the gap are a wide button.
const HALF := (UiTheme.WIDE_BUTTON - COLUMN_GAP) / 2

var _top_spacer: Control


func _init() -> void:
	title = "Game Menu"
	columns = 1


func build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", ROW_GAP)
	add_list_item(column)
	_top_spacer = Control.new()
	column.add_child(_top_spacer)
	column.add_child(_wide("Back to Game", func() -> void: menu.close()))
	column.add_child(_row([
		_half("Achievements", func() -> void: menu.push(AchievementsScreen.new())),
		_half("Statistics", func() -> void: menu.push(StatsScreen.new())),
	]))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20 * P) # (the game's 48 pixels between the rows)
	column.add_child(gap)
	var game := Game.find(menu.get_tree())
	var lan := _half("Open to LAN", func() -> void: menu.push(OpenToLanScreen.new()))
	# Like the classic game's "Open to LAN": others can join this world.
	lan.disabled = not (game and game.is_saved() and not Net.is_online())
	column.add_child(_row([_half("Options...", func() -> void: menu.push(OptionsScreen.new())), lan]))
	if game:
		column.add_child(_wide("Save and Quit to Title" if game.is_saved() else "Quit to Title",
			func() -> void: game.quit_to_title()))
	resized.connect(_place)
	_place.call_deferred()


## The buttons a quarter of the screen down (from the top of the window).
func _place() -> void:
	if _top_spacer == null or list_area == null:
		return
	var below_title := list_area.get_global_rect().position.y - get_global_rect().position.y
	_top_spacer.custom_minimum_size.y = maxf(size.y / 4.0 + 8 * P - below_title, 0.0)


func _wide(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	return button


func _half(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size = Vector2(HALF, UiTheme.BUTTON_HEIGHT)
	return button


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COLUMN_GAP)
	for button: Button in buttons:
		row.add_child(button)
	return row
