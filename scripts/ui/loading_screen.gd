class_name LoadingScreen
extends CanvasLayer
## Shown over the game while the world around the player is prepared.
##
## A floating island turns in the middle of the screen and shows the real
## loading: each of its columns is one world column around the player
## (7 x 7, rounded), as high as that column's real terrain, and it shows
## every stage that column goes through:
## - generated: the column drops into place as bare stone;
## - lit: its top turns to dirt;
## - meshed: grass grows on it (sand at the shore).
## Stages are shown one after another with a small pop, never skipped, so
## the island builds smoothly even when the world loads fast; when every
## column is done a tree grows in the middle. Below: the current stage, a
## progress bar and the percentage. Then the screen fades into the game.

const P := UiTheme.PIXEL
## Radius (columns) that must be ready before playing.
const RADIUS := 3
const FADE_SECONDS := 0.6
const DROP_SECONDS := 0.75
const DROP_HEIGHT := 7.0
## Minimum time a column shows each stage, and between two columns dropping.
const STAGE_SECONDS := 0.22
const DROP_STAGGER := 0.05
const POP_SECONDS := 0.3
const SPIN_DEGREES_PER_SECOND := 12.0
enum Stage { NONE, GENERATED, LIT, MESHED }

var world: VoxelWorld

var _root: Control
var _viewport: SubViewport
var _island: Node3D
## Shown columns: {index (in column_states), node, top (MeshInstance3D),
## height, depth, stage, changed_at, dropped_at}
var _cells: Array[Dictionary] = []
var _tree: Node3D
var _tree_at := -1.0
var _next_drop := 0.0
var _phase: Label
var _percent: Label
var _bar_fill: ColorRect
var _shown := 0.0     # displayed progress, follows the island
const STUCK_SECONDS := 6.0
var _elapsed := 0.0
var _finished_at := -1.0
var _real_done_at := -1.0 # when the world itself was ready
var _meshes := {}
var _ids := {}


## A world is loading (the pause menu waits).
static var active := false


func _exit_tree() -> void:
	active = false


func _ready() -> void:
	active = true
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameInput.lock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for block_name in ["stone", "dirt", "grass_plains", "sand", "oak_log", "oak_leaves"]:
		_ids[block_name] = Blocks.id_of(block_name)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiTheme.theme()
	add_child(_root)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background_material := ShaderMaterial.new()
	background_material.shader = preload("res://shaders/loading_background.gdshader")
	background.material = background_material
	_root.add_child(background)

	_build_island_view()
	_build_texts()


# --- Island ---------------------------------------------------------------------------

func _build_island_view() -> void:
	var view := SubViewportContainer.new()
	view.stretch = true
	view.set_anchors_preset(Control.PRESET_CENTER)
	var view_size := Vector2(420, 330) * P
	view.offset_left = -view_size.x / 2
	view.offset_right = view_size.x / 2
	view.offset_top = -view_size.y / 2 - 18 * P
	view.offset_bottom = view_size.y / 2 - 18 * P
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(view)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	view.add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.85)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	_viewport.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = 34
	camera.look_at_from_position(Vector3(0, 11.0, 25.0), Vector3(0, 0.5, 0), Vector3.UP)
	_viewport.add_child(camera)

	_island = Node3D.new()
	_viewport.add_child(_island)
	# One cell per column within a rounded radius; nearest first.
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var distance := Vector2(dx, dz).length()
			if distance > RADIUS + 0.5:
				continue
			var node := Node3D.new()
			node.position = Vector3(dx, 0, dz)
			node.visible = false
			_island.add_child(node)
			_cells.append({
				"index": (dz + RADIUS) * (RADIUS * 2 + 1) + (dx + RADIUS), "node": node, "top": null,
				"distance": distance, "height": 1, "depth": maxi(1, roundi(4.5 - distance * 0.9 + randf() * 0.8)),
				"stage": Stage.NONE, "changed_at": -10.0, "dropped_at": -10.0,
			})
	_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)


## Blocks of a column for its stage: the top (stone, dirt, then grass or
## sand), stone under it and a tapering stone underside.
func _build_column(cell: Dictionary) -> void:
	var node: Node3D = cell.node
	for child in node.get_children():
		child.queue_free()
	var height: int = cell.height
	var top_id: int = _ids.stone
	match cell.stage:
		Stage.LIT:
			top_id = _ids.dirt
		Stage.MESHED:
			top_id = _ids.sand if height <= 1 else _ids.grass_plains
	cell.top = _add_block(node, top_id, Vector3(0, height - 1, 0))
	for y in range(height - 2, -cell.depth - 1, -1):
		var filler: int = _ids.dirt if cell.stage >= Stage.LIT and y >= height - 3 else _ids.stone
		_add_block(node, filler, Vector3(0, y, 0))


func _add_block(parent: Node3D, id: int, position: Vector3) -> MeshInstance3D:
	if not _meshes.has(id):
		_meshes[id] = ChunkMesher.block_mesh(id)
	var block := MeshInstance3D.new()
	block.mesh = _meshes[id]
	block.position = position - Vector3(0.5, 0, 0.5)
	parent.add_child(block)
	return block


# --- Texts and bar --------------------------------------------------------------------

func _build_texts() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -120 * P
	box.offset_right = 120 * P
	box.offset_top = -78 * P
	box.offset_bottom = -30 * P
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 5 * P)
	_root.add_child(box)

	var title := Label.new()
	title.text = WorldSave.current.name if WorldSave.current else "Loading World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)
	_phase = Label.new()
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_color_override("font_color", Color("a0a0a0"))
	box.add_child(_phase)

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(182, 5) * P
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.55)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("6fcf4f")
	_bar_fill.position = Vector2(P, P)
	_bar_fill.size = Vector2(0, 3 * P)
	bar.add_child(_bar_fill)
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.25)
	shine.size = Vector2(0, P)
	shine.name = "Shine"
	_bar_fill.add_child(shine)

	_percent = Label.new()
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.add_theme_color_override("font_color", Color("e0e0e0"))
	box.add_child(_percent)


# --- Progress -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	var radius := mini(RADIUS, world.render_distance) if world else RADIUS
	var states := world.column_states(RADIUS) if world else []
	var counts := world.loading_progress(radius) if world else {}
	if world and world.loading_radius != radius:
		world.loading_radius = radius
	_advance_cells(states)
	_update_island(delta)

	# The bar follows what the island shows (each column: 3 stages + tree).
	var steps := 0
	for cell in _cells:
		steps += cell.stage
	var target := float(steps + (1 if _tree_at >= 0.0 else 0)) / (_cells.size() * 3 + 1)
	_shown = move_toward(_shown, target, delta * 1.2)
	var total: int = maxi(counts.get("total", 1), 1)
	_update_texts(counts, total)

	var real_done: bool = counts.get("meshed", total) >= total
	if real_done and _real_done_at < 0.0:
		_real_done_at = _elapsed
	elif not real_done:
		_real_done_at = -1.0
	# Safety net: the world is ready but the island got stuck - finish anyway.
	if _finished_at < 0.0 and _real_done_at >= 0.0 and _elapsed - _real_done_at > STUCK_SECONDS:
		_finished_at = _elapsed
	if _finished_at < 0.0 and real_done and _tree_at >= 0.0 and _elapsed - _tree_at > DROP_SECONDS \
			and _shown >= 0.999:
		_finished_at = _elapsed
	if _finished_at >= 0.0:
		var fade := clampf((_elapsed - _finished_at - 0.35) / FADE_SECONDS, 0.0, 1.0)
		_root.modulate.a = 1.0 - fade
		if fade >= 1.0:
			_finish()


## Moves each column one stage toward its real stage at a time, so every
## stage is seen; new columns drop in one after another, nearest first.
func _advance_cells(states: Array) -> void:
	var all_done := true
	for cell in _cells:
		var real: Array = states[cell.index] if cell.index < states.size() else [Stage.MESHED, WorldGenerator.SEA_LEVEL]
		if cell.stage == Stage.NONE:
			if real[0] > Stage.NONE and _elapsed >= _next_drop:
				_next_drop = _elapsed + DROP_STAGGER
				cell.height = clampi(1 + roundi((real[1] - (WorldGenerator.SEA_LEVEL - 3)) / 3.0), 1, 6)
				cell.stage = Stage.GENERATED
				cell.changed_at = _elapsed
				cell.dropped_at = _elapsed
				_build_column(cell)
				(cell.node as Node3D).visible = true
		elif cell.stage < real[0] and _elapsed - cell.changed_at >= STAGE_SECONDS \
				and _elapsed - cell.dropped_at >= DROP_SECONDS * 0.6:
			cell.stage += 1
			cell.changed_at = _elapsed
			_build_column(cell)
		if cell.stage < Stage.MESHED:
			all_done = false
	if all_done and _tree_at < 0.0:
		_grow_tree()


func _grow_tree() -> void:
	_tree_at = _elapsed
	var center: Dictionary = _cells[0]
	var base: int = center.height
	_tree = Node3D.new()
	for i in 3:
		_add_block(_tree, _ids.oak_log, Vector3(0, base + i, 0))
	for x in range(-1, 2):
		for z in range(-1, 2):
			for y in range(base + 2, base + 4):
				if (x == 0 and z == 0 and y < base + 3) or (y == base + 3 and absi(x) + absi(z) == 2):
					continue
				_add_block(_tree, _ids.oak_leaves, Vector3(x, y, z))
	_add_block(_tree, _ids.oak_leaves, Vector3(0, base + 4, 0))
	(center.node as Node3D).add_child(_tree)


func _update_texts(counts: Dictionary, total: int) -> void:
	var dots := ".".repeat(int(_elapsed * 3.0) % 4)
	if _finished_at >= 0.0:
		_phase.text = Lang.t("Ready!")
	elif counts.get("generated", total) < total:
		_phase.text = Lang.t("Generating terrain") + dots
	elif counts.get("lit", total) < total:
		_phase.text = Lang.t("Lighting the world") + dots
	else:
		_phase.text = Lang.t("Building terrain") + dots
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_bar_fill.size.x = 180 * P * _shown
	(_bar_fill.get_node("Shine") as ColorRect).size.x = _bar_fill.size.x


func _update_island(delta: float) -> void:
	_island.rotate_y(deg_to_rad(SPIN_DEGREES_PER_SECOND) * delta)
	_island.position.y = sin(_elapsed * 1.1) * 0.2
	for cell in _cells:
		if cell.stage == Stage.NONE:
			continue
		var node: Node3D = cell.node
		# Drop in with a soft bounce, fading in.
		var t := clampf((_elapsed - cell.dropped_at) / DROP_SECONDS, 0.0, 1.0)
		node.position.y = (1.0 - _ease_out_back(t)) * DROP_HEIGHT
		var fade := 1.0 - clampf(t / 0.5, 0.0, 1.0)
		for child in node.get_children():
			if child is MeshInstance3D:
				child.transparency = fade
		# A small pop of the top block when the stage changes.
		var top: MeshInstance3D = cell.top
		if top and is_instance_valid(top):
			var p := clampf((_elapsed - cell.changed_at) / POP_SECONDS, 0.0, 1.0)
			var pop := 1.0 + sin(p * PI) * 0.22 * (1.0 if cell.changed_at > cell.dropped_at else 0.0)
			top.scale = Vector3.ONE * pop
			top.position = Vector3(-0.5 * pop, cell.height - 1 - (pop - 1.0) * 0.5, -0.5 * pop)
	if _tree:
		var t := clampf((_elapsed - _tree_at) / DROP_SECONDS, 0.0, 1.0)
		_tree.scale = Vector3.ONE * maxf(_ease_out_back(t), 0.01)


static func _ease_out_back(t: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * pow(t - 1.0, 3.0) + C1 * pow(t - 1.0, 2.0)


func _finish() -> void:
	if world:
		world.loading_radius = -1
	GameInput.unlock()
	active = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
