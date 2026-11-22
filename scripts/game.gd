class_name Game
extends Node3D
## The game scene's controller: shows the loading screen while the area
## around the player is built, saves the world (every AUTOSAVE_SECONDS, when
## quitting to the title and when the window closes) and goes back to the
## title screen.
##
## A dedicated server (DedicatedServer) runs scenes/server.tscn: the same
## Game with only the world (no player, no UI); it saves every
## Net.autosave_seconds and keeps the players of the network game.

const TITLE_SCENE := "res://scenes/title.tscn"
## The classic game saves every 45 s; the save only writes changed columns.
const AUTOSAVE_SECONDS := 45.0

@export var world: VoxelWorld
@export var player: Player

var _autosave_timer := 0.0


static func find(tree: SceneTree) -> Game:
	return tree.get_first_node_in_group("game") as Game


func _ready() -> void:
	if WorldSave.current == null:
		# Started directly (not from the title screen): always begin at the
		# title, like the game does on its first start (a dedicated server
		# starts its own scene).
		if not Net.dedicated:
			get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	if Net.dedicated and player != null:
		return # (the game's scene before the server's: never played)
	add_to_group("game")
	if Net.dedicated:
		Settings.forced["difficulty"] = Net.server_difficulty # (server.properties)
		return # no screens: the server's world only
	Settings.forced.clear()
	if WorldSave.current.hardcore:
		Settings.forced["difficulty"] = 3 # Hard, and it stays
	Stats.add("saves_loaded")
	get_tree().auto_accept_quit = false # save first (NOTIFICATION_WM_CLOSE_REQUEST)
	_add_sleep_screen()
	_add_touch_controls()
	var loading := LoadingScreen.new()
	loading.world = world
	add_child(loading)
	loading.tree_exited.connect(_first_icon)


## A new world's picture for Select World (WorldIcon), a few seconds after
## it first shows.
const ICON_DELAY := 3.0


func _first_icon() -> void:
	if not is_inside_tree() or WorldIcon.has_icon(WorldSave.current):
		return
	await get_tree().create_timer(ICON_DELAY).timeout
	if is_inside_tree() and is_saved() and not WorldIcon.has_icon(world.save):
		await _take_icon()


## Takes the world's picture (WorldIcon) without the HUD, menus or hand.
func _take_icon() -> void:
	if not is_saved():
		return
	await WorldIcon.capture(get_tree(), world.save, player.held_item if player else null)


## The in-bed screen goes into the UI layer over the HUD (hotbar, health)
## and under the death screen, the chat and the menus.
func _add_sleep_screen() -> void:
	var ui := get_node_or_null("UI")
	if ui == null or player == null:
		return
	var sleep_screen := SleepScreen.new()
	sleep_screen.name = "SleepScreen"
	sleep_screen.player = player
	sleep_screen.chat = ui.get_node_or_null("Chat") as Chat
	sleep_screen.menu = ui.get_node_or_null("Menu") as Menu
	var below := ui.get_node_or_null("DeathScreen")
	ui.add_child(sleep_screen)
	if below:
		ui.move_child(sleep_screen, below.get_index())


## The Phone control mode's stick and buttons (TouchControls): over the
## HUD, under the screens and windows. Shown only in that mode.
func _add_touch_controls() -> void:
	var ui := get_node_or_null("UI")
	if ui == null or player == null:
		return
	var controls := TouchControls.new()
	controls.name = "TouchControls"
	controls.player = player
	controls.hotbar = ui.get_node_or_null("Hotbar") as Hotbar
	controls.interaction = get_node_or_null("BlockInteraction") as BlockInteraction
	controls.screenshots = get_node_or_null("Screenshots")
	var below := ui.get_node_or_null("DeathScreen")
	ui.add_child(controls)
	if below:
		ui.move_child(controls, below.get_index())


func _exit_tree() -> void:
	Settings.forced.clear()
	if is_inside_tree():
		get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


func _process(delta: float) -> void:
	if not is_in_group("game"):
		return
	_autosave_timer += delta
	if _autosave_timer >= (Net.autosave_seconds if Net.dedicated else AUTOSAVE_SECONDS):
		_autosave_timer = 0.0
		save_game(true)


func is_saved() -> bool:
	return world != null and world.save != null and not world.save.remote


## Writes the changed columns and the world / player state.
## `in_background`: the autosave (the columns are written on worker
## threads, VoxelWorld.save_columns); leaving the world writes them here.
func save_game(in_background: bool = false) -> void:
	if not is_saved():
		return
	var save := world.save
	world.save_columns(in_background)
	# The network game's other players (by tag): kept even when not hosting now.
	var others: Dictionary = Net.saved_players if Net.is_host() else save.state.get("net_players", {})
	var own: Dictionary = save.state.get("player", {}) # (a server keeps the single player's)
	if player:
		save.game_mode = player.game_mode
		own = player.save_state()
	save.state = {"world": world.save_state()}
	if not own.is_empty():
		save.state["player"] = own
	if not others.is_empty():
		save.state["net_players"] = others
	save.last_played = int(Time.get_unix_time_from_system())
	save.write_level()


var _quitting := false


func quit_to_title() -> void:
	if _quitting:
		return
	_quitting = true
	# The world's picture as the player leaves it (WorldIcon).
	await _take_icon()
	Stats.add("leave_game")
	save_game()
	Net.leave() # stops hosting / leaves the host's game
	get_tree().paused = false
	GameInput.reset()
	GameInput.capture(false)
	WorldSave.current = null
	get_tree().change_scene_to_file(TITLE_SCENE)
