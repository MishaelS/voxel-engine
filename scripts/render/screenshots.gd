class_name Screenshots
extends Node
## Screenshots and the World Diorama:
## - F2: a screenshot of the screen (with the GUI unless it is hidden);
## - F1: hide / show the HUD like the classic game (crosshair, hotbar,
##   health, chat, debug screen, the hand); windows and menus still show;
## - F6: the World Diorama: the area around the player (Area chunks) cut
##   out of the world and seen from far away with an orthographic camera
##   (IsometricCamera) on a light sky, its controls on the screen
##   (IsometricPanel): drag to move, right-drag to turn, wheel to zoom;
## - F7: a picture of the diorama at high resolution (Screenshot Size),
##   rendered off-screen without the GUI.
## Pictures go to user://screenshots/ and the chat says where.

## A picture was saved (its path, or "" when it failed).
signal saved(path: String)

const FOLDER := "user://screenshots"
const RENDER_SIZES: Array[int] = [2048, 4096, 8192]
## The diorama's sky: top and bottom by day and by night.
const SKY_DAY: Array[Color] = [Color(0.49, 0.68, 0.94), Color(0.83, 0.91, 1.0)]
const SKY_NIGHT: Array[Color] = [Color(0.03, 0.04, 0.1), Color(0.11, 0.14, 0.25)]

@export var player: Player
@export var world: VoxelWorld
@export var ui: CanvasLayer
@export var chat: Chat

## The World Diorama is open.
var isometric := false
## F1: the HUD is hidden.
var hud_hidden := false
## The same for HUD parts that show themselves (StatusBars).
static var hud_off := false

const HUD_NODES := ["Crosshair", "Hotbar", "StatusBars", "DebugScreen"]

var _camera: IsometricCamera
var _panel: IsometricPanel
var _rendering := false
## The diorama's sky behind the world (a background canvas layer).
var _sky_layer: CanvasLayer
var _sky_gradient: Gradient
var _saved_background := -1
## Entities and players the diorama hid (shown again when it closes).
var _hidden: Array[Node3D] = []


func _ready() -> void:
	hud_off = false
	_camera = IsometricCamera.new()
	_camera.target = player
	add_child(_camera)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		take_screenshot()
	elif event.is_action_pressed("hide_gui"):
		hud_hidden = not hud_hidden
		_apply_hud()
	elif event.is_action_pressed("isometric_view") and not GameInput.is_blocked():
		set_isometric(not isometric)
	elif event.is_action_pressed("isometric_screenshot") and not GameInput.is_blocked():
		render_isometric()
	elif isometric and not GameInput.is_blocked():
		if event.is_action_pressed("isometric_rotate_left"):
			_camera.rotate_view(-90)
		elif event.is_action_pressed("isometric_rotate_right"):
			_camera.rotate_view(90)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


## Opens or closes the World Diorama.
func set_isometric(enabled: bool) -> void:
	if enabled == isometric:
		return
	isometric = enabled
	if enabled:
		_camera.pan = Vector3.ZERO
		_camera.current = true
	elif player and player.camera:
		player.camera.current = true
	var atmosphere := Atmosphere.find(get_tree())
	if atmosphere:
		atmosphere.isometric = enabled
	# The area cut out of the world: solid walls on its sides, nothing beyond.
	if world:
		world.set_edge_radius(int(Settings.get_value("iso_area")))
		if not _rendering:
			world.culling_enabled = not enabled
			world.set_open_edges(enabled)
		if not enabled:
			world.edge_radius = -1
			if world.far_terrain:
				world.far_terrain.visible = true
	_set_sky(enabled)
	if not enabled:
		DayNightCycle.shown_time = -1.0
		for node: Node3D in _hidden:
			if is_instance_valid(node):
				node.visible = true
		_hidden.clear()
	# The controls, with the mouse free to use them.
	if enabled and _panel == null:
		_panel = IsometricPanel.new()
		_panel.screenshots = self
		_panel.camera = _camera
		ui.add_child(_panel)
		# Under the chat, the inventory and the menus.
		var first_window := ui.get_node_or_null("Chat")
		if first_window:
			ui.move_child(_panel, first_window.get_index())
	elif not enabled and _panel:
		_panel.queue_free()
		_panel = null
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not GameInput.is_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_hud()


## A diorama picture is being rendered.
func is_rendering() -> bool:
	return _rendering


## Brings the view back over the player.
func center_camera() -> void:
	_camera.pan = Vector3.ZERO


func rotate_view(degrees: float) -> void:
	_camera.rotate_view(degrees)


## The light sky behind the diorama: the environment's background becomes
## a canvas layer under everything else.
func _set_sky(enabled: bool) -> void:
	var environment := get_viewport().find_world_3d().environment
	if enabled:
		if _sky_layer == null:
			_sky_layer = CanvasLayer.new()
			_sky_layer.layer = -100
			_sky_gradient = Gradient.new()
			var texture := GradientTexture2D.new()
			texture.gradient = _sky_gradient
			texture.fill_from = Vector2(0, 0)
			texture.fill_to = Vector2(0, 1)
			texture.width = 4
			texture.height = 128
			var rect := TextureRect.new()
			rect.texture = texture
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_sky_layer.add_child(rect)
			add_child(_sky_layer)
		_sky_layer.visible = true
		_update_sky()
		if environment and _saved_background < 0:
			_saved_background = environment.background_mode
			environment.background_mode = Environment.BG_CANVAS
			environment.background_canvas_max_layer = -50
	else:
		if _sky_layer:
			_sky_layer.visible = false
		if environment and _saved_background >= 0:
			environment.background_mode = _saved_background as Environment.BGMode
			_saved_background = -1


## The sky's colors now (darker at night, like the world's light).
func sky_colors() -> Array[Color]:
	var atmosphere := Atmosphere.find(get_tree())
	var daylight := atmosphere.daylight if atmosphere else 1.0
	return [SKY_NIGHT[0].lerp(SKY_DAY[0], daylight), SKY_NIGHT[1].lerp(SKY_DAY[1], daylight)]


func _update_sky() -> void:
	if _sky_gradient == null:
		return
	var colors := sky_colors()
	if not _sky_gradient.get_color(0).is_equal_approx(colors[0]) or not _sky_gradient.get_color(1).is_equal_approx(colors[1]):
		_sky_gradient.colors = PackedColorArray(colors)


## Shows or hides the HUD (F1, and what the diorama hides). The debug
## screen comes back only if it is on.
func _apply_hud() -> void:
	hud_off = hud_hidden or isometric
	for name: String in HUD_NODES:
		var node := ui.get_node_or_null(name) as CanvasItem
		if node == null:
			continue
		var shown := not hud_hidden and not isometric
		node.visible = shown
	if player and player.held_item:
		player.held_item.hidden = isometric or hud_hidden


func _process(_delta: float) -> void:
	# With the HUD hidden, the chat shows only while it is open.
	if hud_hidden and chat:
		chat.visible = chat.is_open()
	elif chat and not chat.visible:
		chat.visible = true
	if isometric:
		_update_diorama()


## The diorama's settings that apply every frame: area, time, who shows.
func _update_diorama() -> void:
	_update_sky()
	var hour: float = Settings.get_value("iso_time")
	# (hour 6 is tick 0, the classic sunrise)
	DayNightCycle.shown_time = -1.0 if hour < 0.0 else fposmod((hour - 6.0) * 1000.0, WorldClock.TICKS_PER_DAY)
	if world == null or player == null:
		return
	world.set_edge_radius(int(Settings.get_value("iso_area")))
	if world.far_terrain:
		world.far_terrain.visible = false
	# Only what stands in the area (and the kinds that are on) shows.
	var half := (mini(int(Settings.get_value("iso_area")), world.render_distance) + 0.5) * ChunkData.SIZE
	var middle := (Vector2(floorf(player.global_position.x / ChunkData.SIZE), floorf(player.global_position.z / ChunkData.SIZE)) + Vector2(0.5, 0.5)) * ChunkData.SIZE
	var players: bool = Settings.get_value("iso_players")
	var mobs: bool = Settings.get_value("iso_mobs")
	var shown := func(node: Node3D, kind_on: bool) -> void:
		var at := node.global_position
		var inside := absf(at.x - middle.x) <= half and absf(at.z - middle.y) <= half
		node.visible = kind_on and inside
		if not node.visible and not _hidden.has(node):
			_hidden.append(node)
	if world.entities:
		for entity: Entity in world.entities.all():
			shown.call(entity, mobs or not (entity is Mob))
	for avatar: Variant in Net.avatars.values():
		if is_instance_valid(avatar):
			shown.call(avatar as Node3D, players)
	# The player itself (its body shows only in third person otherwise).
	if player.body:
		player.body.visible = players and not player.dead


## Saves what is on the screen now.
func take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	_save(get_viewport().get_texture().get_image(), "")


## Renders the diorama (the Area around the player, from the view's
## rotation and tilt) into a big picture.
func render_isometric() -> void:
	if _rendering or world == null or player == null:
		return
	_rendering = true
	_say(Lang.t("Rendering diorama screenshot..."))
	var basis := IsometricCamera.settings_basis()
	var radius := mini(int(Settings.get_value("iso_area")), world.render_distance)
	var was_open := isometric
	if not was_open:
		world.set_edge_radius(radius)
	world.culling_enabled = false # the cut sides must be solid
	world.set_open_edges(true)
	var waited := 0.0
	while world.edges_pending() > 0 and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# The area's box (ground to its highest block) as the camera sees it.
	var side := (radius * 2 + 1) * ChunkData.SIZE
	var heights := world.edge_height_range()
	var corner := Vector3(floorf(player.global_position.x / ChunkData.SIZE) - radius, 0,
		floorf(player.global_position.z / ChunkData.SIZE) - radius) * ChunkData.SIZE
	var low := Vector2(INF, INF)
	var high := -low
	for x: int in 2:
		for y: int in 2:
			for z: int in 2:
				var point := corner + Vector3(x * side, heights[y], z * side)
				var seen := Vector2(basis.x.dot(point), basis.y.dot(point))
				low = low.min(seen)
				high = high.max(seen)
	var extent := (high - low) * 1.04 # (a little room around it)
	var longest := RENDER_SIZES[Settings.get_value("iso_render_size")]
	var pixels := Vector2i(longest, roundi(longest * extent.y / extent.x)) if extent.x >= extent.y \
		else Vector2i(roundi(longest * extent.x / extent.y), longest)

	var viewport := SubViewport.new()
	viewport.world_3d = get_viewport().world_3d
	viewport.size = pixels
	viewport.transparent_bg = true # (the sky is drawn under it after)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = extent.y
	camera.near = 1.0
	camera.far = 4000.0
	camera.basis = basis
	var middle := (low + high) * 0.5
	var depth := basis.z.dot(corner + Vector3(side, heights.y, side) * 0.5)
	camera.position = basis.x * middle.x + basis.y * middle.y + basis.z * (depth + IsometricCamera.DISTANCE)
	viewport.add_child(camera)
	var atmosphere := Atmosphere.find(get_tree())
	if atmosphere:
		atmosphere.snapshot = true
	player.held_item.hidden = true
	# One frame for Atmosphere and the culling to apply the changes.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if atmosphere:
		atmosphere.snapshot = false
	player.held_item.hidden = isometric or hud_hidden
	if not isometric:
		world.culling_enabled = true
		world.set_open_edges(false)
		world.edge_radius = -1
	viewport.queue_free()
	if Settings.get_value("iso_background") == 0:
		image = _on_sky(image)
	_rendering = false
	_save(image, "diorama_")


## The picture over the diorama's sky.
func _on_sky(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var colors := sky_colors()
	var sky := Image.create(1, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		sky.set_pixel(0, y, colors[0].lerp(colors[1], y / 255.0))
	sky.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_BILINEAR)
	sky.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return sky


## Opens the screenshots folder in the system's file manager.
func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	OS.shell_open(ProjectSettings.globalize_path(FOLDER))


## Saves a picture (and tells `saved`).
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
		saved.emit(path)
		return
	_say(Lang.t("Couldn't save the screenshot"))
	saved.emit("")


## A note in the chat (the diorama shows its own instead).
func _say(text: String) -> void:
	if chat and not isometric:
		chat.add_message(text, CommandSource.MessageKind.INFO)
