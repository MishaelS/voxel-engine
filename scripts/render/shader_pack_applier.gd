class_name ShaderPackApplier
extends Node
## Applies the scene side of the selected shader pack (ShaderPacks): the
## sun and moon light and shadows, ambient light, glow and color
## adjustments. Block shaders are switched by BlockMaterials.
## Classic: no sun light or shadows at all (blocks are unshaded), which is
## also the fastest. Dynamic Lighting: shadows Off / Low (2 cascades, 48
## blocks) / High (4 cascades, 64 blocks), sun and ambient strength, glow.

const SHADOW_ATLAS_SIZES: Array[int] = [0, 2048, 4096]

@export var sun: DayNightCycle
@export var world_environment: WorldEnvironment

var _sun_energy := 1.2
var _moon_energy := 0.25


func _ready() -> void:
	if sun:
		_sun_energy = sun.sun_energy
		_moon_energy = sun.moon_energy
	ShaderPacks.changed.connect(_apply)
	_apply()


func _apply() -> void:
	var pack := ShaderPacks.current
	if pack == null:
		return
	var dynamic := pack.base == ShaderPack.Base.DYNAMIC
	var environment := world_environment.environment if world_environment else null
	if sun:
		# Classic blocks are unshaded: the light would only cost time.
		sun.visible = dynamic
		var shadows: int = pack.value("shadows") if dynamic else 0
		sun.shadow_enabled = shadows > 0
		if shadows > 0:
			RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZES[shadows], true)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadows == 1 \
				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 48.0 if shadows == 1 else 64.0
		var strength: float = pack.value("sun_strength") / 100.0 if dynamic else 1.0
		sun.sun_energy = _sun_energy * strength
		sun.moon_energy = _moon_energy * strength
	if environment:
		environment.ambient_light_energy = pack.value("ambient") / 100.0 if dynamic else 1.0
		environment.glow_enabled = dynamic and pack.value("glow")
		var saturation: float = pack.value("saturation") / 100.0
		var contrast: float = pack.value("contrast") / 100.0
		environment.adjustment_enabled = not is_equal_approx(saturation, 1.0) or not is_equal_approx(contrast, 1.0)
		environment.adjustment_saturation = saturation
		environment.adjustment_contrast = contrast
