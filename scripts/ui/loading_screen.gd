class_name LoadingScreen
extends CanvasLayer
## Shown over the game while the world around the player is prepared, like
## the classic game's loading screen: the dark dirt background (with the
## title screen's shade, extra/title_blur.png), the current stage ("Generating
## terrain", "Lighting the world", "Building terrain") and a thin progress
## bar - grey with a green fill -
## with the percentage under it. Pixel sparks fly out of the bar's growing
## end (more while it moves fast) and burst out when it is full. Then the
## screen fades into the game.

const P := UiTheme.PIXEL
## Radius (columns) that must be ready before playing.
const RADIUS := 3
const FADE_SECONDS := 0.6
## The bar (GUI pixels) in the classic colors: grey track, green fill.
const BAR_WIDTH := 182
const BAR_HEIGHT := 4
const TRACK_COLOR := Color("808080")
const FILL_COLOR := Color("80ff80")
const SPARK_COLORS: Array[Color] = [Color("80ff80"), Color("c8ffc8"), Color("4fd04f"), Color.WHITE]
## How fast the shown bar may catch up with the real progress (per second).
const CATCH_UP := 0.9
const STUCK_SECONDS := 6.0

var world: VoxelWorld

var _root: Control
var _phase: Label
var _percent: Label
var _fill: ColorRect
var _sparks: CPUParticles2D
var _burst: CPUParticles2D
var _shown := 0.0
var _elapsed := 0.0
var _finished_at := -1.0
var _real_done_at := -1.0

## A world is loading (the pause menu waits).
static var active := false


func _exit_tree() -> void:
	active = false


func _ready() -> void:
	active = true
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameInput.lock()
	GameInput.capture(false)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiTheme.theme()
	add_child(_root)

	var background := TextureRect.new()
	background.texture = UiTheme.background_texture()
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color(0.25, 0.25, 0.25)
	_root.add_child(background)
	# The title screen's shade (extra/title_blur.png): darker toward the bottom.
	var shade := TextureRect.new()
	shade.texture = TexturePacks.load_texture("res://assets/textures/extra/title_blur.png")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_build()


func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -120 * P
	box.offset_right = 120 * P
	box.offset_top = -30 * P
	box.offset_bottom = 30 * P
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6 * P)
	_root.add_child(box)

	_phase = Label.new()
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_phase)

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT) * P
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	var track := ColorRect.new()
	track.color = TRACK_COLOR
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	_fill = ColorRect.new()
	_fill.color = FILL_COLOR
	_fill.size = Vector2(0, BAR_HEIGHT * P)
	bar.add_child(_fill)
	_sparks = _make_sparks(false)
	bar.add_child(_sparks)
	_burst = _make_sparks(true)
	_burst.position = Vector2(BAR_WIDTH * 0.5, BAR_HEIGHT * 0.5) * P
	bar.add_child(_burst)

	_percent = Label.new()
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.add_theme_color_override("font_color", Color("e0e0e0"))
	box.add_child(_percent)


## Square pixel sparks: a steady stream from the bar's end, or (`burst`) one
## big puff along the whole bar when it is full.
func _make_sparks(burst: bool) -> CPUParticles2D:
	var sparks := CPUParticles2D.new()
	sparks.emitting = false
	sparks.one_shot = burst
	sparks.explosiveness = 0.9 if burst else 0.0
	sparks.amount = 90 if burst else 48
	sparks.lifetime = 1.1 if burst else 0.8
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = Vector2(BAR_WIDTH * 0.5, 1.0) * P if burst else Vector2(0.5, BAR_HEIGHT * 0.5) * P
	sparks.direction = Vector2(0.4, -1.0) if not burst else Vector2(0, -1)
	sparks.spread = 70.0 if not burst else 180.0
	sparks.initial_velocity_min = 25.0 * P
	sparks.initial_velocity_max = (70.0 if burst else 55.0) * P
	sparks.gravity = Vector2(0, 90.0 * P)
	sparks.damping_min = 5.0 * P
	sparks.damping_max = 15.0 * P
	# One GUI pixel or a little more: square, sharp like the game's particles.
	sparks.scale_amount_min = 1.0 * P
	sparks.scale_amount_max = 1.6 * P
	var colors := Gradient.new()
	colors.set_color(0, Color(1, 1, 1, 1))
	colors.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = colors
	var palette := Gradient.new()
	palette.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	palette.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	palette.colors = PackedColorArray(SPARK_COLORS)
	sparks.color_initial_ramp = palette
	return sparks


func _process(delta: float) -> void:
	_elapsed += delta
	var radius := mini(RADIUS, world.render_distance) if world else RADIUS
	var counts := world.loading_progress(radius) if world else {}
	if world and world.loading_radius != radius:
		world.loading_radius = radius
	var total: int = maxi(counts.get("total", 1), 1)
	# Each column counts three steps: generated, lit, built.
	var target := float(counts.get("generated", total) + counts.get("lit", total) + counts.get("meshed", total)) / (total * 3)
	var before := _shown
	_shown = move_toward(_shown, target, delta * CATCH_UP)
	_update_bar(delta, _shown - before)
	_update_texts(counts, total)

	var real_done: bool = counts.get("meshed", total) >= total
	if real_done and _real_done_at < 0.0:
		_real_done_at = _elapsed
	elif not real_done:
		_real_done_at = -1.0
	if _finished_at < 0.0 and real_done and (_shown >= 0.999 or _elapsed - _real_done_at > STUCK_SECONDS):
		_finished_at = _elapsed
		_shown = 1.0
		_update_bar(0.0, 0.0)
		_sparks.emitting = false
		_burst.restart()
		_burst.emitting = true
	if _finished_at >= 0.0:
		var fade := clampf((_elapsed - _finished_at - 0.6) / FADE_SECONDS, 0.0, 1.0)
		_root.modulate.a = 1.0 - fade
		if fade >= 1.0:
			_finish()


## The fill and the spark stream at its end, livelier while it grows fast.
func _update_bar(delta: float, grown: float) -> void:
	_fill.size.x = roundf(BAR_WIDTH * _shown) * P
	_sparks.position = Vector2(_fill.size.x, BAR_HEIGHT * 0.5 * P)
	if _finished_at >= 0.0:
		return
	var speed := grown / maxf(delta, 1e-4)
	_sparks.emitting = _shown > 0.0
	_sparks.speed_scale = clampf(0.8 + speed * 3.0, 0.8, 2.0)


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


func _finish() -> void:
	if world:
		world.loading_radius = -1
	GameInput.unlock()
	active = false
	GameInput.capture(true)
	queue_free()
