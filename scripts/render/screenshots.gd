class_name Screenshots
extends Node
## Screenshots and the isometric camera, like the old game:
## - F2: a screenshot of the screen (with the GUI unless it is hidden);
## - F1: hide / show the GUI;
## - F6: the isometric camera (IsometricCamera), Z / X turn it, the wheel
##   zooms; the crosshair and the block in hand are hidden;
## - F7: an isometric picture of the whole loaded area at high resolution
##   (Screenshot Size), rendered off-screen without GUI, fog or clouds.
## Pictures go to user://screenshots/ and the chat says where.

const FOLDER := "user://screenshots"
const RENDER_SIZES: Array[int] = [2048, 4096, 8192]

@export var player: Player
@export var world: VoxelWorld
@export var ui: CanvasLayer
@export var chat: Chat

var isometric := false

var _camera: IsometricCamera
var _rendering := false


func _ready() -> void:
	_camera = IsometricCamera.new()
	_camera.target = player
	add_child(_camera)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		take_screenshot()
	elif event.is_action_pressed("hide_gui"):
		ui.visible = not ui.visible
	elif event.is_action_pressed("isometric_view") and not GameInput.is_blocked():
		set_isometric(not isometric)
	elif event.is_action_pressed("isometric_screenshot") and not GameInput.is_blocked():
		render_isometric()
	elif isometric and not GameInput.is_blocked():
		if event.is_action_pressed("isometric_rotate_left"):
			_camera.rotate_view(-1)
		elif event.is_action_pressed("isometric_rotate_right"):
			_camera.rotate_view(1)
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.zoom(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


func set_isometric(enabled: bool) -> void:
	isometric = enabled
	if enabled:
		_camera.current = true
	elif player and player.camera:
		player.camera.current = true
	if player and player.held_item:
		player.held_item.hidden = enabled
	var crosshair := ui.get_node_or_null("Crosshair") as CanvasItem
	if crosshair:
		crosshair.visible = not enabled
	var atmosphere := Atmosphere.find(get_tree())
	if atmosphere:
		atmosphere.isometric = enabled


## Saves what is on the screen now.
func take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	_save(get_viewport().get_texture().get_image(), "")


## Renders the loaded area from the isometric angle into a big picture.
func render_isometric() -> void:
	if _rendering or world == null or player == null:
		return
	_rendering = true
	_say(Lang.t("Rendering isometric screenshot..."))
	var angle_index: int = Settings.get_value("iso_angle")
	var pitch := deg_to_rad(IsometricCamera.ANGLES[angle_index])
	var side := (world.render_distance * 2 + 1) * ChunkData.SIZE
	# The loaded square seen diagonally: its width, and its height on screen
	# (ground plus the height of the world).
	var width := side * sqrt(2.0)
	var height := width * sin(pitch) + WorldGenerator.HEIGHT * cos(pitch)
	var longest := RENDER_SIZES[Settings.get_value("iso_render_size")]
	var pixels := Vector2i(longest, roundi(longest * height / width)) if width >= height \
		else Vector2i(roundi(longest * width / height), longest)

	var viewport := SubViewport.new()
	viewport.world_3d = get_viewport().world_3d
	viewport.size = pixels
	viewport.transparent_bg = Settings.get_value("iso_background") == 1
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = height
	camera.near = 1.0
	camera.far = 4000.0
	camera.basis = IsometricCamera.view_basis(Settings.get_value("iso_facing"), angle_index)
	var center := Vector3(player.global_position.x, WorldGenerator.HEIGHT * 0.5, player.global_position.z)
	camera.position = center + camera.basis.z * 1500.0
	viewport.add_child(camera)
	var atmosphere := Atmosphere.find(get_tree())
	if atmosphere:
		atmosphere.snapshot = true
	player.held_item.hidden = true
	world.culling_enabled = false # the cut sides must be solid
	world.set_open_edges(true)
	var waited := 0.0
	while world.edges_pending() > 0 and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# One frame for Atmosphere and the culling to apply the changes (no fog:
	# the camera is far away, everything would be in it).
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if atmosphere:
		atmosphere.snapshot = false
	player.held_item.hidden = isometric
	world.culling_enabled = true
	world.set_open_edges(false)
	viewport.queue_free()
	_save(image, "isometric_")
	_rendering = false


func _save(image: Image, prefix: String) -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var stamp := Time.get_datetime_string_from_system().replace(":", ".").replace("T", "_")
	var file := "%s%s.png" % [prefix, stamp]
	var path := FOLDER.path_join(file)
	var n := 2
	while FileAccess.file_exists(path):
		path = FOLDER.path_join("%s%s_%d.png" % [prefix, stamp, n])
		n += 1
	if image.save_png(path) == OK:
		_say(Lang.t("Saved screenshot as %s (%dx%d)") % [path.get_file(), image.get_width(), image.get_height()])
		print("Screenshot: ", ProjectSettings.globalize_path(path))
	else:
		_say(Lang.t("Couldn't save the screenshot"))


func _say(text: String) -> void:
	if chat:
		chat.add_message(text, CommandSource.MessageKind.INFO)
