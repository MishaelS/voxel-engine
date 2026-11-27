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
## Inside lava: thick glowing fog, like the classic game.
const LAVA_FOG := Color(0.6, 0.1, 0.0)
const LAVA_FOG_END := 2.0
const LAVA_TINT := Color(0.9, 0.25, 0.0, 0.55)
## The day's haze, like the Better than Adventure mod's: the fog begins
## much nearer than Fog Distance says (this part of it) and thickens slowly
## at first (the curve), so the far land fades softly into the sky's color
## instead of a clear line near the world's edge.
const HAZE_START := 0.3
const HAZE_CURVE := 1.6

@export var world_environment: WorldEnvironment
@export var sun: DayNightCycle
@export var player: Player
@export var world: VoxelWorld

## 0 at night .. 1 in full day.
var daylight := 1.0
## True while the eyes are in water.
var underwater := false
var in_lava := false
## The World Diorama is open / its screenshot is being rendered: fog and
## clouds follow the diorama's settings.
var isometric := false
## Light levels sky light loses now (Classic pack at night), for the block
## in hand.
var sky_darkness := 0.0
## A lightning flash (0..1), set by LightningBolt, fading by itself.
var lightning_flash := 0.0
var snapshot := false

var _clouds: Clouds
var _overlay: ColorRect
var _water_picture := false # (a texture pack's misc/water.png)
var _sky: ShaderMaterial


func _ready() -> void:
	add_to_group("atmosphere")
	if world_environment and world_environment.environment.sky:
		_sky = world_environment.environment.sky.sky_material as ShaderMaterial
	var environment := world_environment.environment
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.0
	environment.fog_density = 1.0 # (depth fog: its full strength at the end)
	environment.fog_aerial_perspective = 0.0 # our own fog color (cheaper)
	environment.fog_sky_affect = 0.0

	add_child(WaterAnimation.new())
	add_child(LavaAnimation.new())
	add_child(FireAnimation.new())
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
	# A texture pack's vignette and under-water picture, like Beta's.
	var vignette_image := TexturePacks.pack_image("misc/vignette.png")
	if vignette_image:
		overlay_material.set_shader_parameter("use_vignette_map", true)
		overlay_material.set_shader_parameter("vignette_map", ImageTexture.create_from_image(vignette_image))
	var water_image := TexturePacks.pack_image("misc/water.png")
	if water_image:
		overlay_material.set_shader_parameter("water_map", ImageTexture.create_from_image(water_image))
		_water_picture = true


## Night Brightness option of the Classic pack: 5% = the classic darkness
## (all 11 levels), brighter nights take away fewer levels.
func _night_factor() -> float:
	var pack := ShaderPacks.current
	var brightness: float = pack.value("night_brightness") if pack and pack.base == ShaderPack.Base.CLASSIC else 5.0
	return clampf(1.0 - (brightness - 5.0) / 80.0, 0.3, 1.0)


static func find(tree: SceneTree) -> Atmosphere:
	return tree.get_first_node_in_group("atmosphere") as Atmosphere


func _process(delta: float) -> void:
	lightning_flash = maxf(lightning_flash - delta * 4.0, 0.0)
	if player and player.camera and _clouds.camera == null:
		_clouds.camera = player.camera
	var to_sun := sun.sun_direction() if sun else Vector3.UP
	daylight = sun.sky_brightness() if sun else 1.0
	# Classic lighting: sky light loses up to 11 levels at night (the classic
	# game's way); Dynamic Lighting has real moonlight instead.
	var classic := ShaderPacks.current != null and ShaderPacks.current.base == ShaderPack.Base.CLASSIC
	sky_darkness = sun.sky_darkness() * _night_factor() if sun and classic else 0.0
	sky_darkness *= 1.0 - lightning_flash # a lightning flash lights the world up
	BlockMaterials.set_parameter("sky_darkness", sky_darkness)
	var eye := player.eye_position() if player else Vector3.ZERO
	var eye_block := world.get_block(Vector3i(eye.floor())) if world else Blocks.AIR
	in_lava = Blocks.liquid_table[eye_block] == 1 and Blocks.family_of(eye_block) == "lava"
	underwater = Blocks.liquid_table[eye_block] == 1 and not in_lava
	_update_fog(to_sun)
	_update_clouds(to_sun)
	_update_overlay(eye)
	if _sky:
		var weather := world.weather if world else null
		_sky.set_shader_parameter("rain", weather.rain_strength if weather else 0.0)
		_sky.set_shader_parameter("thunder", weather.thunder_strength if weather else 0.0)
		_sky.set_shader_parameter("flash", lightning_flash)
		_sky.set_shader_parameter("show_stars", Settings.get_value("stars"))
		_sky.set_shader_parameter("show_sun_moon", Settings.get_value("sun_moon"))
		_sky.set_shader_parameter("star_twinkle", Settings.get_value("star_twinkle"))


## Sky color at the horizon in the view direction (the sky shader's own
## gradient and sunset glow).
func horizon_color(to_sun: Vector3, view: Vector3) -> Color:
	var horizon := _sky_color("night_horizon", Color(0.03, 0.04, 0.09)).lerp(
		_sky_color("day_horizon", Color(0.75, 0.85, 1.0)), daylight)
	# Toward the sun at dawn and dusk the fog takes the dawn's color, like
	# Beta 1.7.3's (EntityRenderer.updateFogColor, by how much the view
	# faces the sun times the dawn's strength; the sky shader's fan).
	var dawn := dawn_color(to_sun.y)
	var flat_view := Vector2(view.x, view.z)
	var flat_sun := Vector2(to_sun.x, to_sun.z)
	if dawn.a > 0.0 and flat_view.length() > 1e-4 and flat_sun.length() > 1e-4:
		var toward_sun := maxf(flat_view.normalized().dot(flat_sun.normalized()), 0.0)
		horizon = horizon.lerp(Color(dawn.r, dawn.g, dawn.b), toward_sun * dawn.a)
	return _weathered(horizon)


## Beta 1.7.3's WorldProvider.calcSunriseSunsetColors by the sun's height
## (-1..1): the dawn's color and, in alpha, its strength (0: none).
static func dawn_color(sun_height: float) -> Color:
	if absf(sun_height) > 0.4:
		return Color(0, 0, 0, 0)
	var f5 := sun_height / 0.4 * 0.5 + 0.5
	var f6 := 1.0 - (1.0 - sin(f5 * PI)) * 0.99
	return Color(f5 * 0.3 + 0.7, f5 * f5 * 0.7 + 0.2, 0.2, f6 * f6)


## Colors grayed by rain and storms, like the game's sky and fog.
func _weathered(color: Color) -> Color:
	var weather := world.weather if world else null
	if weather == null:
		return color
	var gray := color.r * 0.3 + color.g * 0.59 + color.b * 0.11
	color = color.lerp(Color(gray * 0.6, gray * 0.6, gray * 0.6), weather.rain_strength * 0.75)
	color = color.lerp(Color(gray * 0.2, gray * 0.2, gray * 0.2), weather.thunder_strength * 0.75)
	return color


func _update_fog(to_sun: Vector3) -> void:
	var environment := world_environment.environment
	# Under water the fog covers the sky too: everything far is deep water.
	var from_far := isometric or snapshot # the isometric camera is far away: no water / lava fog
	environment.fog_sky_affect = 1.0 if (underwater or in_lava) and not from_far else 0.0
	if in_lava and not from_far:
		environment.fog_enabled = true
		environment.fog_light_color = LAVA_FOG
		environment.fog_depth_begin = 0.0
		environment.fog_depth_end = LAVA_FOG_END
		environment.fog_depth_curve = 1.0
		return
	if underwater and not from_far:
		environment.fog_enabled = true
		environment.fog_light_color = WATER_FOG * (0.2 + 0.8 * daylight)
		environment.fog_depth_begin = 0.0
		environment.fog_depth_end = WATER_FOG_END
		environment.fog_depth_curve = 1.0
		return
	# The fog ends at the far terrain's edge when it is on (FarTerrain).
	var distance := float(maxi(int(Settings.get_value("render_distance")), FarTerrain.radius_setting())) * ChunkData.SIZE
	environment.fog_enabled = Settings.get_value("fog")
	var view := -player.camera.global_basis.z if player and player.camera else Vector3.FORWARD
	environment.fog_light_color = horizon_color(to_sun, view)
	environment.fog_depth_begin = distance * Settings.get_value("fog_distance") / 100.0 * HAZE_START
	environment.fog_depth_end = distance
	environment.fog_depth_curve = HAZE_CURVE
	if from_far:
		environment.fog_depth_curve = 1.0
		# Measured from the diorama's camera, DISTANCE blocks from the area's
		# middle: Fog thickens from the far side of the area toward the near.
		var amount: float = Settings.get_value("iso_fog_amount") / 100.0
		var area := mini(int(Settings.get_value("iso_area")), world.render_distance if world else 8)
		var extent := (area + 0.5) * ChunkData.SIZE * sqrt(2.0)
		environment.fog_enabled = amount > 0.0
		environment.fog_depth_begin = IsometricCamera.DISTANCE + extent * (1.0 - 1.8 * amount)
		environment.fog_depth_end = environment.fog_depth_begin + extent * (2.4 - 1.6 * amount)
		return
	_void_fog(environment)


## The void fog like the game's (since Beta 1.8), heavier: near the bedrock
## the fog turns black (below y 32) and, where no sky light reaches, closes
## in - about 25 blocks at y 20, 9 at y 12, 7 at the bottom - like a weight
## of rock overhead. In every game mode (Beta 1.8's: survival only).
func _void_fog(environment: Environment) -> void:
	if world == null or player == null:
		return
	var eye := player.eye_position()
	var shade := eye.y / 32.0
	if shade < 1.0:
		shade = maxf(shade, 0.0)
		environment.fog_light_color *= shade * shade
	var sky := float(world.get_light(Vector3i(eye.floor())))
	var near := sky / 16.0 + eye.y / 40.0
	if near >= 1.0:
		return
	near = maxf(near, 0.0)
	near *= near
	var end := maxf(100.0 * near, 7.0)
	if not environment.fog_enabled or end < environment.fog_depth_end:
		environment.fog_enabled = true
		environment.fog_depth_end = end
		environment.fog_depth_begin = end * 0.4
		environment.fog_depth_curve = 1.0 # (thick at once, not the day's haze)


func _update_clouds(to_sun: Vector3) -> void:
	var clouds: int = Settings.get_value("clouds") # OFF, Fast, Fancy
	_clouds.visible = clouds > 0
	if isometric or snapshot:
		_clouds.visible = _clouds.visible and Settings.get_value("iso_clouds")
	if not _clouds.visible:
		return
	_clouds.set_fancy(clouds == 2)
	# White by day, dark at night, warm at sunrise / sunset.
	var color := Color(0.12, 0.13, 0.18).lerp(Color.WHITE, daylight)
	var low_sun := 1.0 - smoothstep(0.0, 0.35, absf(to_sun.y))
	color = color.lerp(color * Color(1.0, 0.75, 0.6), low_sun * 0.6)
	_clouds.set_color(_weathered(color))


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
	if in_lava:
		tint = LAVA_TINT # glows: no night darkening
	material.set_shader_parameter("tint", tint)
	if _water_picture:
		var brightness := 0.3 + 0.7 * daylight
		material.set_shader_parameter("water_overlay", brightness if underwater and not in_lava else 0.0)
		if player and player.camera:
			var turn := player.camera.global_rotation
			material.set_shader_parameter("water_offset", Vector2(-turn.y / TAU * 4.0, turn.x / TAU * 4.0))
	_overlay.visible = strength > 0.0 or underwater or in_lava


func _sky_color(parameter: String, fallback: Color) -> Color:
	if _sky == null:
		return fallback
	var value: Variant = _sky.get_shader_parameter(parameter)
	if value is Color:
		return value
	if value is Vector3:
		return Color(value.x, value.y, value.z)
	return fallback
