class_name Atmosphere
extends Node
## The look of the air, like the classic game:
## - fog: colored like the sky at the horizon (darker at night, tinted
##   orange when looking toward a rising or setting sun), starting at 60%
##   of the render distance and hiding the edge of the loaded world;
## - under water: dense blue fog and a blue screen tint;
## - 3D clouds (Clouds) colored by the time of day;
## - vignette: dark screen corners, stronger in the dark.
## Sky colors are read from the sky material, so fog and clouds always
## match the sky. Daylight (0 night .. 1 day) is shared with other effects
## (the block in hand).

## Fog under water (blocks), like the classic game: you see little.
const WATER_FOG_END := 18.0
const WATER_TINT := Color(0.05, 0.15, 0.45, 0.35)
const WATER_FOG := Color(0.03, 0.08, 0.25)

@export var world_environment: WorldEnvironment
@export var sun: DayNightCycle
@export var player: Player
@export var world: VoxelWorld

## 0 at night .. 1 in full day.
var daylight := 1.0
## True while the eyes are in water.
var underwater := false
## The isometric camera is in use / an isometric screenshot is being
## rendered: fog and clouds follow the Isometric Camera settings.
var isometric := false
## Light levels sky light loses now (Classic pack at night), for the block
## in hand.
var sky_darkness := 0.0
var snapshot := false

var _clouds: Clouds
var _overlay: ColorRect
var _sky: ShaderMaterial


func _ready() -> void:
	add_to_group("atmosphere")
	if world_environment and world_environment.environment.sky:
		_sky = world_environment.environment.sky.sky_material as ShaderMaterial
	var environment := world_environment.environment
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.0
	environment.fog_aerial_perspective = 0.0 # our own fog color (cheaper)
	environment.fog_sky_affect = 0.0

	add_child(WaterAnimation.new())
	_clouds = Clouds.new()
	_clouds.name = "Clouds"
	_clouds.camera = player.camera if player else null
	_clouds.world = world
	add_child(_clouds)

	var layer := CanvasLayer.new()
	layer.layer = 0 # above the 3D view, below the HUD (layer 1)
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_material := ShaderMaterial.new()
	overlay_material.shader = preload("res://shaders/screen_overlay.gdshader")
	_overlay.material = overlay_material
	layer.add_child(_overlay)


## Night Brightness option of the Classic pack: 5% = the classic darkness
## (all 11 levels), brighter nights take away fewer levels.
func _night_factor() -> float:
	var pack := ShaderPacks.current
	var brightness: float = pack.value("night_brightness") if pack and pack.base == ShaderPack.Base.CLASSIC else 5.0
	return clampf(1.0 - (brightness - 5.0) / 80.0, 0.3, 1.0)


static func find(tree: SceneTree) -> Atmosphere:
	return tree.get_first_node_in_group("atmosphere") as Atmosphere


func _process(_delta: float) -> void:
	if player and player.camera and _clouds.camera == null:
		_clouds.camera = player.camera
	var to_sun := sun.sun_direction() if sun else Vector3.UP
	daylight = sun.sky_brightness() if sun else 1.0
	# Classic lighting: sky light loses up to 11 levels at night (the classic
	# game's way); Dynamic Lighting has real moonlight instead.
	var classic := ShaderPacks.current != null and ShaderPacks.current.base == ShaderPack.Base.CLASSIC
	sky_darkness = sun.sky_darkness() * _night_factor() if sun and classic else 0.0
	BlockMaterials.set_parameter("sky_darkness", sky_darkness)
	var eye := player.eye_position() if player else Vector3.ZERO
	underwater = world != null and Blocks.liquid_table[world.get_block(Vector3i(eye.floor()))] == 1
	_update_fog(to_sun)
	_update_clouds(to_sun)
	_update_overlay(eye)
	if _sky:
		_sky.set_shader_parameter("show_stars", Settings.get_value("stars"))
		_sky.set_shader_parameter("show_sun_moon", Settings.get_value("sun_moon"))
		_sky.set_shader_parameter("star_twinkle", Settings.get_value("star_twinkle"))


## Sky color at the horizon in the view direction (the sky shader's own
## gradient and sunset glow).
func horizon_color(to_sun: Vector3, view: Vector3) -> Color:
	var horizon := _sky_color("night_horizon", Color(0.03, 0.04, 0.09)).lerp(
		_sky_color("day_horizon", Color(0.75, 0.85, 1.0)), daylight)
	var low_sun := 1.0 - smoothstep(0.0, 0.4, absf(to_sun.y + 0.05))
	var toward_sun := 0.0
	var flat_view := Vector2(view.x, view.z)
	var flat_sun := Vector2(to_sun.x, to_sun.z)
	if flat_view.length() > 1e-4 and flat_sun.length() > 1e-4:
		toward_sun = maxf(flat_view.normalized().dot(flat_sun.normalized()), 0.0)
	return horizon.lerp(_sky_color("sunset_color", Color(1.0, 0.42, 0.12)), low_sun * toward_sun * toward_sun * 0.6)


func _update_fog(to_sun: Vector3) -> void:
	var environment := world_environment.environment
	# Under water the fog covers the sky too: everything far is deep water.
	environment.fog_sky_affect = 1.0 if underwater else 0.0
	if underwater:
		environment.fog_enabled = true
		environment.fog_light_color = WATER_FOG * (0.2 + 0.8 * daylight)
		environment.fog_depth_begin = 0.0
		environment.fog_depth_end = WATER_FOG_END
		return
	var distance := float(Settings.get_value("render_distance")) * ChunkData.SIZE
	environment.fog_enabled = Settings.get_value("fog")
	if isometric or snapshot:
		environment.fog_enabled = Settings.get_value("iso_fog") and not snapshot
	var view := -player.camera.global_basis.z if player and player.camera else Vector3.FORWARD
	environment.fog_light_color = horizon_color(to_sun, view)
	environment.fog_depth_begin = distance * Settings.get_value("fog_distance") / 100.0
	environment.fog_depth_end = distance


func _update_clouds(to_sun: Vector3) -> void:
	var clouds: int = Settings.get_value("clouds") # OFF, Fast, Fancy
	_clouds.visible = clouds > 0
	if isometric or snapshot:
		_clouds.visible = _clouds.visible and Settings.get_value("iso_clouds") and not snapshot
	if not _clouds.visible:
		return
	_clouds.set_fancy(clouds == 2)
	# White by day, dark at night, warm at sunrise / sunset.
	var color := Color(0.12, 0.13, 0.18).lerp(Color.WHITE, daylight)
	var low_sun := 1.0 - smoothstep(0.0, 0.35, absf(to_sun.y))
	color = color.lerp(color * Color(1.0, 0.75, 0.6), low_sun * 0.6)
	_clouds.set_color(color)


func _update_overlay(eye: Vector3) -> void:
	var material := _overlay.material as ShaderMaterial
	var strength := 0.0
	if Settings.get_value("vignette"):
		# The classic vignette follows the light at the eyes.
		var light := float(world.get_light(Vector3i(eye.floor()))) / SkyLight.MAX if world else 1.0
		strength = lerpf(0.55, 0.22, light * (0.3 + 0.7 * daylight))
	material.set_shader_parameter("vignette", strength)
	var tint := WATER_TINT if underwater else Color(0, 0, 0, 0)
	tint.r *= 0.3 + 0.7 * daylight
	tint.g *= 0.3 + 0.7 * daylight
	tint.b *= 0.3 + 0.7 * daylight
	material.set_shader_parameter("tint", tint)
	_overlay.visible = strength > 0.0 or underwater


func _sky_color(parameter: String, fallback: Color) -> Color:
	if _sky == null:
		return fallback
	var value: Variant = _sky.get_shader_parameter(parameter)
	if value is Color:
		return value
	if value is Vector3:
		return Color(value.x, value.y, value.z)
	return fallback
