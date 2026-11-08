class_name SettingsApplier
extends Node
## Applies the settings that need nodes of the game scene (camera, sun,
## environment, world, HUD), now and whenever they change.

const SHADOW_ATLAS_SIZES: Array[int] = [0, 2048, 4096]

@export var camera: Camera3D
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var world: VoxelWorld
@export var hud: CanvasItem ## The debug screen.

var _cloud_opacity := 0.85


func _ready() -> void:
	var sky_material := _sky_material()
	if sky_material and sky_material.get_shader_parameter("cloud_opacity") != null:
		_cloud_opacity = sky_material.get_shader_parameter("cloud_opacity")
	Settings.changed.connect(_apply)
	for key in ["fov", "shadows", "smooth_lighting", "clouds", "fog", "brightness", "debug_screen"]:
		_apply(key, Settings.get_value(key))


func _apply(key: String, value: Variant) -> void:
	match key:
		"fov":
			if camera:
				camera.fov = value
		"shadows":
			if sun:
				sun.shadow_enabled = value > 0
				if value > 0:
					RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZES[value], true)
		"smooth_lighting":
			if ChunkMesher.ao_enabled != value:
				ChunkMesher.ao_enabled = value
				if world:
					world.remesh_all()
		"clouds":
			var sky_material := _sky_material()
			if sky_material:
				sky_material.set_shader_parameter("cloud_opacity", _cloud_opacity if value else 0.0)
		"fog":
			if world_environment:
				world_environment.environment.fog_enabled = value
		"brightness":
			if world_environment:
				world_environment.environment.tonemap_exposure = lerpf(0.75, 1.35, value / 100.0)
		"debug_screen":
			if hud:
				hud.visible = value


func _sky_material() -> ShaderMaterial:
	if world_environment and world_environment.environment.sky:
		return world_environment.environment.sky.sky_material as ShaderMaterial
	return null
