class_name Game
extends Node3D
## The game scene's controller: shows the loading screen while the area
## around the player is built, saves the world (every AUTOSAVE_SECONDS, when
## quitting to the title and when the window closes) and goes back to the
## title screen.

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
		# title, like the game does on its first start.
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	add_to_group("game")
	get_tree().auto_accept_quit = false # save first (NOTIFICATION_WM_CLOSE_REQUEST)
	var loading := LoadingScreen.new()
	loading.world = world
	add_child(loading)


func _exit_tree() -> void:
	if is_inside_tree():
		get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		_autosave_timer = 0.0
		save_game()


func is_saved() -> bool:
	return world != null and world.save != null


## Writes the changed columns and the world / player state.
func save_game() -> void:
	if not is_saved():
		return
	var save := world.save
	world.save_columns()
	save.game_mode = player.game_mode
	save.state = {"world": world.save_state(), "player": player.save_state()}
	save.last_played = int(Time.get_unix_time_from_system())
	save.write_level()


func quit_to_title() -> void:
	save_game()
	get_tree().paused = false
	GameInput.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	WorldSave.current = null
	get_tree().change_scene_to_file(TITLE_SCENE)
