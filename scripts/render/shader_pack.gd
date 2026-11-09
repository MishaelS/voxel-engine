class_name ShaderPack
extends RefCounted
## A shader pack: a lighting style (its base) plus the values of that
## style's options. Two built-in packs exist (ShaderPacks); players can copy
## any pack into their own and change its options in the Shaders menu.
##
## Bases:
## - CLASSIC: lighting like the original game, no real-time sun light or
##   shadows (block_classic_*.gdshader). Fast.
## - DYNAMIC: the engine's real-time sun and moon light with shadows,
##   specular water, optional glow.
## Options are Setting objects, so the menu builds their widgets; adding an
## option is one line in _definitions() plus applying it (BlockMaterials or
## ShaderPackApplier).

enum Base { CLASSIC, DYNAMIC }

const BASE_NAMES := ["classic", "dynamic"]
const BASE_LABELS := ["Classic", "Dynamic Lighting"]

var name := ""
var base: Base = Base.CLASSIC
## Built-in packs can be changed (saved as overrides) but not deleted.
var builtin := false
## File name of a player's pack in ShaderPacks.DIR.
var file := ""
## Option key -> value (missing = the option's default).
var values := {}


static func create(pack_name: String, pack_base: Base, is_builtin: bool = false) -> ShaderPack:
	var pack := ShaderPack.new()
	pack.name = pack_name
	pack.base = pack_base
	pack.builtin = is_builtin
	return pack


## The options of a base (fresh, unbound Setting objects).
static func _definitions(pack_base: Base) -> Array[Setting]:
	var percent := func(v: float) -> String: return "%d%%" % int(v)
	var options: Array[Setting] = []
	if pack_base == Base.CLASSIC:
		options.append(Setting.toggle("face_shading", "Face Shading", true))
		options.append(Setting.range_of("night_brightness", "Night Brightness", 5, 60, 20, 5).format_with(percent))
	else:
		options.append(Setting.choice("shadows", "Shadows", PackedStringArray(["Off", "Low", "High"]), 2))
		options.append(Setting.range_of("sun_strength", "Sun Strength", 50, 200, 100, 10).format_with(percent))
		options.append(Setting.range_of("ambient", "Ambient Light", 0, 200, 75, 10).format_with(percent))
		options.append(Setting.toggle("water_shine", "Water Shine", true))
		options.append(Setting.toggle("glow", "Glow (Bloom)", false))
	options.append(Setting.range_of("saturation", "Saturation", 50, 150, 100, 5).format_with(percent))
	options.append(Setting.range_of("contrast", "Contrast", 80, 130, 100, 5).format_with(percent))
	return options


## The options bound to this pack's values; `on_change` runs after a change.
func settings(on_change: Callable) -> Array[Setting]:
	var options := _definitions(base)
	for setting in options:
		var key := setting.key
		var default: Variant = setting.default_value
		# Capture the key and default only (no reference cycle through `setting`).
		setting.bind(func() -> Variant: return values.get(key, default),
			func(value: Variant) -> void:
				values[key] = value
				on_change.call())
	return options


## Current value of an option (its default if never changed).
func value(key: String) -> Variant:
	if values.has(key):
		return values[key]
	for setting in _definitions(base):
		if setting.key == key:
			return setting.default_value
	return null


func reset() -> void:
	values.clear()


func base_label() -> String:
	return BASE_LABELS[base]


## A player's copy of this pack.
func copy_as(copy_name: String) -> ShaderPack:
	var copy := ShaderPack.create(copy_name, base)
	copy.values = values.duplicate()
	return copy
