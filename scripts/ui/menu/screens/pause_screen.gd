class_name PauseScreen
extends MenuScreen
## Esc menu while playing. Minimal for now: only Options.


func _init() -> void:
	title = "Game Menu"
	columns = 1
	center_vertically = true


func build() -> void:
	add_list_wide_button("Options...", func() -> void: menu.push(OptionsScreen.new()))
