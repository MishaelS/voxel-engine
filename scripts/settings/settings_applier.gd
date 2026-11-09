class_name SettingsApplier
extends Node
## Applies the settings that need nodes of the game scene (environment,
## world, HUD), now and whenever they change. FOV, fog,
## clouds and the vignette are read every frame by Player and Atmosphere;
## lighting and shadows come from the shader pack (ShaderPackApplier).

@export var world_environment: WorldEnvironment
@export var world: VoxelWorld
@export var hud: CanvasItem ## The debug screen.

func _ready() -> void:
	Settings.changed.connect(_apply)
	for key in ["render_distance", "smooth_lighting", "ambient_occlusion", "graphics", "brightness", "debug_screen"]:
		_apply(key, Settings.get_value(key))


func _apply(key: String, value: Variant) -> void:
	match key:
		"smooth_lighting":
			if ChunkMesher.smooth_lighting != value:
				ChunkMesher.smooth_lighting = value
				if world:
					world.remesh_all()
		"ambient_occlusion":
			# Applied by the block shaders: no re-meshing needed.
			BlockMaterials.set_parameter("ao_strength", value / 100.0)
		"graphics":
			# Fast: opaque leaves like the classic game (fewer faces, no cutout).
			if Blocks.set_fast_graphics(value == 0) and world:
				world.remesh_all()
		"render_distance":
			if world:
				world.set_render_distance(int(value))
		"brightness":
			if world_environment:
				world_environment.environment.tonemap_exposure = lerpf(0.75, 1.35, value / 100.0)
		"debug_screen":
			if hud:
				hud.visible = value
