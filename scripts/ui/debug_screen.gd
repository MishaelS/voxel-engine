class_name DebugScreen
extends Control
## Debug screen in the style of the classic game's F3 screen: game info in
## the left column, system info and the targeted block in the right one,
## each line on a translucent gray background. F3 shows/hides it (saved as
## the "debug_screen" setting).

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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_fill(_left, _left_lines(), HORIZONTAL_ALIGNMENT_LEFT)
	_fill(_right, _right_lines(), HORIZONTAL_ALIGNMENT_RIGHT)


# --- Content -------------------------------------------------------------------

func _left_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	lines.append("Voxel Engine %s (Godot %s)" % [version, Engine.get_version_info().string])
	var fps := Engine.get_frames_per_second()
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	lines.append("%d fps (%.2f ms) T: %s%s" % [fps, 1000.0 / maxf(fps, 1.0),
		"unlimited" if Engine.max_fps == 0 else str(Engine.max_fps), " vsync" if vsync else ""])
	var viewport_rid := get_viewport().get_viewport_rid()
	lines.append("Render: CPU %.2f ms, %d draw calls, %d primitives" % [
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	lines.append("Tick %d: %.1f TPS (target %d), %.3f ms/tick%s" % [TickLoop.tick_count,
		TickLoop.measured_tps, int(TickLoop.tick_rate), TickLoop.mspt, " FROZEN" if TickLoop.frozen else ""])

	if world:
		var s := world.stats
		if not s.is_empty():
			var culled := 100.0 * (1.0 - float(s.faces) / maxi(s.faces_naive, 1))
			lines.append("C: %d loaded, %d meshing, last mesh %.1f ms" % [s.chunks, world.mesh_jobs_count(), s.mesh_ms])
			lines.append("Faces: %d of %d (%d%% culled), %d vertices" % [s.faces, s.faces_naive, int(culled), s.vertices])
	lines.append("")

	if camera:
		var pos := camera.global_position
		var block := Vector3i(pos.floor())
		var chunk := VoxelWorld.chunk_coord_of(block)
		var local := block - chunk * ChunkData.SIZE
		lines.append("XYZ: %.3f / %.3f / %.3f" % [pos.x, pos.y, pos.z])
		lines.append("Block: %d %d %d" % [block.x, block.y, block.z])
		lines.append("Chunk: %d %d %d in %d %d %d" % [local.x, local.y, local.z, chunk.x, chunk.y, chunk.z])
		lines.append(_facing_line(-camera.global_basis.z))
	lines.append("")

	if world:
		var clock := world.clock
		lines.append("World: %s, seed %d" % [world.stats.get("generator", "?"), world.world_seed])
		lines.append("Game time: %d, day time: %d%s" % [clock.game_time, int(clock.day_time),
			"" if clock.daylight_cycle else " (stopped)"])
		lines.append("Random tick speed: %d, scheduled ticks: %d" % [world.random_tick_speed, world.scheduled_tick_count()])
	if sun:
		lines.append("Time: %s" % sun.describe())
		var to_sun := sun.sun_direction()
		lines.append("Sun: elevation %.1f°, azimuth %.1f°, declination %.1f°" % [
			rad_to_deg(asin(to_sun.y)), fposmod(rad_to_deg(atan2(to_sun.x, -to_sun.z)), 360.0),
			rad_to_deg(sun.declination_rad()) if sun.analemma_enabled else 0.0])
		lines.append("Light: %s, energy %.2f" % ["sun" if to_sun.y >= 0.0 else "moon", sun.light_energy])
	return lines


func _right_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Renderer: %s, %s" % [RenderingServer.get_current_rendering_driver_name(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")])
	lines.append("Mem: %d MB (peak %d MB)" % [OS.get_static_memory_usage() >> 20, OS.get_static_memory_peak_usage() >> 20])
	lines.append("Video mem: %d MB" % (int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) >> 20))
	lines.append("CPU: %d threads, %s" % [OS.get_processor_count(), OS.get_processor_name()])
	lines.append("")
	var window := get_window()
	lines.append("Display: %dx%d, GUI scale %.1f" % [window.size.x, window.size.y, window.content_scale_factor])
	lines.append(RenderingServer.get_video_adapter_name())
	lines.append("Render scale: %s, AA: %s, shadows: %s" % [
		Settings.get_setting("render_scale").display_value(),
		Settings.get_setting("antialiasing").display_value(),
		Settings.get_setting("shadows").display_value()])

	if interaction and interaction.target.get("hit", false):
		var target: Dictionary = interaction.target
		var pos: Vector3i = target.pos
		var block := Blocks.get_type(target.block)
		lines.append("")
		lines.append("Targeted Block: %d, %d, %d" % [pos.x, pos.y, pos.z])
		lines.append("%s (id %d)" % [block.name, block.id])
		lines.append("layer: %s" % LAYER_NAMES[block.layer])
		lines.append("face: %s, distance: %.2f" % [FACE_NAMES.get(target.normal, "inside"), target.distance])
		var ticks := PackedStringArray()
		if block.random_tick.is_valid():
			ticks.append("random")
		if block.scheduled_tick.is_valid():
			ticks.append("scheduled")
		if block.on_update.is_valid():
			ticks.append("updates")
		lines.append("ticks: %s" % (", ".join(ticks) if not ticks.is_empty() else "none"))
	return lines


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
