class_name DebugScreen
extends Control
## Debug screen in the style of the classic game's F3 screen: game info in
## the left column, system info and the targeted block in the right one,
## each line on a translucent gray background. F3 shows/hides it (saved as
## the "debug_screen" setting).
## The full screen is only in debug builds (the editor, debug exports); a
## release build shows the game and its version, the frame rate, the memory
## used and how much the world takes on disk (the player's coordinates are
## on the map).

const LINE_BACKGROUND := Color(0.31, 0.31, 0.31, 0.56)
const TEXT_COLOR := Color("e0e0e0")
const P := UiTheme.PIXEL
const LAYER_NAMES := ["opaque", "cutout", "translucent"]
const FACE_NAMES := {
	Vector3i.UP: "top", Vector3i.DOWN: "bottom", Vector3i.RIGHT: "east",
	Vector3i.LEFT: "west", Vector3i.BACK: "south", Vector3i.FORWARD: "north",
}

@export var camera: Camera3D
@export var world: VoxelWorld
@export var sun: DayNightCycle
@export var interaction: BlockInteraction

var _left: VBoxContainer
var _right: VBoxContainer
var _box: StyleBoxFlat
var _next_refresh_ms := 0
## The text is rebuilt this often (re-laying out ~40 labels every frame
## costs about 1 ms of CPU).
const REFRESH_MS := 50
## Everything (debug builds) or the short release screen.
## (tools/run.sh --release passes --short-f3 to see the release one.)
static var full := OS.is_debug_build() and not OS.get_cmdline_user_args().has("--short-f3")
## The world's size on disk is measured this often (it walks the folder).
const DISK_REFRESH_MS := 5000
var _disk_bytes := -1
var _next_disk_ms := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Like the classic game, the debug screen stays in English.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme = UiTheme.theme()
	_box = StyleBoxFlat.new()
	_box.bg_color = LINE_BACKGROUND
	_box.content_margin_left = P
	_box.content_margin_right = P
	_box.content_margin_top = 0
	_box.content_margin_bottom = 0

	_left = _column(Control.PRESET_TOP_LEFT, Control.GROW_DIRECTION_END)
	_right = _column(Control.PRESET_TOP_RIGHT, Control.GROW_DIRECTION_BEGIN)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		Settings.set_value("debug_screen", not Settings.get_value("debug_screen"))


func _process(_delta: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_msec()
	if now < _next_refresh_ms:
		return
	_next_refresh_ms = now + REFRESH_MS
	_fill(_left, _left_lines(), HORIZONTAL_ALIGNMENT_LEFT)
	_fill(_right, _right_lines(), HORIZONTAL_ALIGNMENT_RIGHT)


# --- Content -------------------------------------------------------------------

func _left_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	lines.append("%s %s (Godot %s)" % [ProjectSettings.get_setting("application/config/name"), version,
		Engine.get_version_info().string])
	var fps := Engine.get_frames_per_second()
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	lines.append("%d fps (%.2f ms) T: %s%s" % [fps, 1000.0 / maxf(fps, 1.0),
		"unlimited" if Engine.max_fps == 0 else str(Engine.max_fps), " vsync" if vsync else ""])
	if not full:
		lines.append("Release build" + (", world: %s" % WorldSave.current.name if WorldSave.current else ""))
		return lines
	var viewport_rid := get_viewport().get_viewport_rid()
	lines.append("Render: CPU %.2f ms, %d draw calls, %d primitives" % [
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	lines.append("Tick %d: %.1f TPS (target %d), %.3f ms/tick%s" % [TickLoop.tick_count,
		TickLoop.measured_tps, int(TickLoop.tick_rate), TickLoop.mspt, " FROZEN" if TickLoop.frozen else ""])

	if world:
		var s := world.get_stats()
		if not s.is_empty():
			lines.append("C: %d/%d visible, %d columns, D: %d, pending %d" % [s.visible_chunks, s.chunks, s.columns, world.render_distance, s.pending])
			lines.append("Jobs: %d generating (last %.1f ms), %d lighting, %d meshing (last %.1f ms)" % [
				world.generation_jobs_count(), s.generation_ms, world.light_jobs_count(), world.mesh_jobs_count(), s.mesh_ms])
			lines.append("Faces: %d, vertices: %d" % [s.faces, s.vertices])
			lines.append("Cave culling: %d chunks hidden" % world.culled_chunks)
			# Where the main thread's time goes (ms), to track down stutters.
			var f := world.frame_times
			var t := world.tick_times
			var e := world.entities.tick_times if world.entities else {}
			var entity_us := 0
			for kind: String in e:
				entity_us += int(e[kind])
			lines.append("Frame ms: stream %.1f gen %.1f light %.1f mesh %.1f cull %.1f" % [f.get("stream", 0) / 1000.0,
				f.get("generation", 0) / 1000.0, f.get("light", 0) / 1000.0, f.get("mesh", 0) / 1000.0, f.get("cull", 0) / 1000.0])
			lines.append("Tick ms: random %.1f display %.1f scheduled %.1f entities %.1f" % [t.get("random", 0) / 1000.0,
				t.get("display", 0) / 1000.0, t.get("scheduled", 0) / 1000.0, entity_us / 1000.0])
	lines.append("")

	if camera:
		# Like the classic game: the player's feet, not the eyes.
		var player := camera.get_parent() as Player
		var pos := player.global_position if player else camera.global_position
		var block := Vector3i(pos.floor())
		var chunk := VoxelWorld.chunk_coord_of(block)
		var local := block - chunk * ChunkData.SIZE
		lines.append("XYZ: %.3f / %.3f / %.3f" % [pos.x, pos.y, pos.z])
		lines.append("Block: %d %d %d" % [block.x, block.y, block.z])
		lines.append("Chunk: %d %d %d in %d %d %d" % [local.x, local.y, local.z, chunk.x, chunk.y, chunk.z])
		lines.append(_facing_line(-camera.global_basis.z))
		if player:
			var states := PackedStringArray()
			for state: Array in [[player.on_ground, "on ground"], [player.flying, "flying"],
					[player.sneaking, "sneaking"], [player.in_water, "in water"]]:
				if state[0]:
					states.append(state[1])
			var v := player.velocity * 20.0
			lines.append("Player: %s mode, %.2f m/s%s" % [Player.GameMode.keys()[player.game_mode].capitalize(),
				Vector2(v.x, v.z).length(), (", " + ", ".join(states)) if not states.is_empty() else ""])
			lines.append("Health: %d/%d" % [player.health, Player.MAX_HEALTH])
		if world:
			lines.append("Biome: %s" % world.biome_at(block.x, block.z))
			lines.append("Sky light: %d, block light: %d" % [world.get_light(block), world.get_block_light(block)])
	lines.append("")

	if world:
		var clock := world.clock
		lines.append("World: %s, seed %d" % [VoxelWorld.Generator.keys()[world.generator], world.world_seed])
		lines.append("Game time: %d, day time: %d%s" % [clock.game_time, int(clock.day_time),
			"" if clock.daylight_cycle else " (stopped)"])
		lines.append("Random tick speed: %d, scheduled ticks: %d" % [world.random_tick_speed, world.scheduled_tick_count()])
		lines.append("Entities: %d falling blocks" % world.falling_blocks.count())
	if sun:
		lines.append("Time: %s" % sun.describe())
		var to_sun := sun.sun_direction()
		lines.append("Sun: celestial angle %.3f, elevation %.1f°, sky light -%.1f" % [
			sun.celestial_angle(), rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0))), sun.sky_darkness()])
		lines.append("Light: %s, energy %.2f" % ["sun" if to_sun.y >= 0.0 else "moon", sun.light_energy])
	return lines


func _right_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if not full:
		lines.append("Mem: %d MB (peak %d MB)" % [OS.get_static_memory_usage() >> 20, OS.get_static_memory_peak_usage() >> 20])
		lines.append("Video mem: %d MB" % (int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) >> 20))
		var bytes := _world_disk_bytes()
		if bytes >= 0:
			lines.append("World on disk: %.1f MB" % (bytes / 1048576.0))
		return lines
	lines.append("Renderer: %s, %s" % [RenderingServer.get_current_rendering_driver_name(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")])
	lines.append("Mem: %d MB (peak %d MB)" % [OS.get_static_memory_usage() >> 20, OS.get_static_memory_peak_usage() >> 20])
	lines.append("Video mem: %d MB" % (int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) >> 20))
	lines.append("CPU: %d threads, %s" % [OS.get_processor_count(), OS.get_processor_name()])
	lines.append("")
	var window := get_window()
	lines.append("Display: %dx%d, GUI scale %.1f" % [window.size.x, window.size.y, window.content_scale_factor])
	lines.append(RenderingServer.get_video_adapter_name())
	lines.append("Render scale: %s, AA: %s" % [
		Settings.get_setting("render_scale").display_value(),
		Settings.get_setting("antialiasing").display_value()])
	var pack := ShaderPacks.current
	lines.append("Shaders: %s (%s)" % [pack.name, pack.base_label()] if pack else "Shaders: none")

	if interaction and interaction.target.get("hit", false):
		var target: Dictionary = interaction.target
		var pos: Vector3i = target.pos
		var block := Blocks.get_type(target.block)
		lines.append("")
		lines.append("Targeted Block: %d, %d, %d" % [pos.x, pos.y, pos.z])
		lines.append("%s (id %d)" % [block.name, block.id])
		lines.append("layer: %s" % LAYER_NAMES[block.layer])
		lines.append("face: %s, distance: %.2f" % [FACE_NAMES.get(target.normal, "inside"), target.distance])
		if world:
			lines.append("light at face: %d" % world.get_light(pos + target.normal))
		var ticks := PackedStringArray()
		if block.random_tick.is_valid():
			ticks.append("random")
		if block.scheduled_tick.is_valid():
			ticks.append("scheduled")
		if block.on_update.is_valid():
			ticks.append("updates")
		lines.append("ticks: %s" % (", ".join(ticks) if not ticks.is_empty() else "none"))
	return lines


## How much the current world's folder takes (bytes), measured now and
## then; -1 without a saved world.
func _world_disk_bytes() -> int:
	var save := WorldSave.current
	if save == null:
		return -1
	var now := Time.get_ticks_msec()
	if now >= _next_disk_ms:
		_next_disk_ms = now + DISK_REFRESH_MS
		_disk_bytes = _folder_bytes(save.path(""))
	return _disk_bytes


static func _folder_bytes(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	for file in dir.get_files():
		var f := FileAccess.open(path.path_join(file), FileAccess.READ)
		if f:
			total += f.get_length()
	for sub_dir in dir.get_directories():
		total += _folder_bytes(path.path_join(sub_dir))
	return total


## Like the classic game: compass direction, axis and yaw / pitch, where
## yaw 0 = south (+Z), 90 = west, pitch > 0 = looking down.
static func _facing_line(forward: Vector3) -> String:
	var direction := "south"
	var towards := "positive Z"
	if absf(forward.x) > absf(forward.z):
		direction = "east" if forward.x > 0.0 else "west"
		towards = "positive X" if forward.x > 0.0 else "negative X"
	elif forward.z < 0.0:
		direction = "north"
		towards = "negative Z"
	var yaw := rad_to_deg(atan2(-forward.x, forward.z))
	var pitch := rad_to_deg(-asin(clampf(forward.y, -1.0, 1.0)))
	return "Facing: %s (Towards %s) (%.1f / %.1f)" % [direction, towards, yaw, pitch]


# --- Layout ----------------------------------------------------------------------

func _column(preset: Control.LayoutPreset, grow: Control.GrowDirection) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(preset)
	column.offset_left = P if preset == Control.PRESET_TOP_LEFT else -P
	column.offset_right = column.offset_left
	column.offset_top = P
	column.grow_horizontal = grow
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	return column


## Shows the lines, reusing labels; empty lines are gaps without background.
func _fill(column: VBoxContainer, lines: PackedStringArray, align: HorizontalAlignment) -> void:
	while column.get_child_count() < lines.size():
		var label := Label.new()
		label.add_theme_color_override("font_color", TEXT_COLOR)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if align == HORIZONTAL_ALIGNMENT_LEFT else Control.SIZE_SHRINK_END
		column.add_child(label)
	for i in column.get_child_count():
		var label := column.get_child(i) as Label
		label.visible = i < lines.size()
		if not label.visible:
			continue
		label.text = lines[i] if lines[i] != "" else " "
		label.add_theme_stylebox_override("normal", _box if lines[i] != "" else StyleBoxEmpty.new())
