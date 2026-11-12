class_name PauseScreen
extends MenuScreen
## Esc menu while playing: back to the game, achievements and statistics
## (like the classic game), options, save and quit to the title screen.


func _init() -> void:
	title = "Game Menu"
	columns = 1
	center_vertically = true


func build() -> void:
	add_list_wide_button("Back to Game", func() -> void: menu.close())
	add_list_wide_button("Achievements", func() -> void: menu.push(AchievementsScreen.new()))
	add_list_wide_button("Statistics", func() -> void: menu.push(StatsScreen.new()))
	add_list_wide_button("Options...", func() -> void: menu.push(OptionsScreen.new()))
	var game := Game.find(menu.get_tree())
	if game and game.is_saved() and not Net.is_online():
		# Like the classic game's "Open to LAN": others can join this world.
		add_list_wide_button("Open to LAN", func() -> void:
			var error := Net.host()
			menu.close()
			if menu.chat:
				menu.chat.add_message(Lang.t(error) if error != "" else
					Lang.t("Local game hosted on port %d") % Net.PORT, CommandSource.MessageKind.INFO))
	if game:
		add_list_wide_button("Save and Quit to Title" if game.is_saved() else "Quit to Title",
			func() -> void: game.quit_to_title())
