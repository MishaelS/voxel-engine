class_name WaterAnimation
extends Node
## Animated water textures like the classic Beta game: not a sequence of
## frames but a small simulation per texture, 20 steps per second, written
## into the block tile array:
## - still water (tops): ripples spread sideways, random drops add energy;
## - flowing water (sides): ripples spread along the flow and the whole
##   pattern slides down one pixel per step.
## Each texture pixel keeps an energy value; lighter and more opaque where
## the energy is high. The colors are deeper and calmer than Beta's bright
## blue, like the Better than Adventure mod's water (water_pixel()).

const STILL_TILE := 205
const FLOW_TILE := 206
const SIZE := 16
const STEP := 1.0 / 20.0
## Water's color at no energy and at full energy (sRGB, alpha: opacity).
const CALM := Color8(28, 70, 106, 180)
const RIPPLE := Color8(58, 116, 150, 220)

var _still := _Ripples.new(false)
var _flow := _Ripples.new(true)
var _accumulator := 0.0
var _ticks := 0


## One texture's simulation (the classic four float fields).
class _Ripples:
	var flowing := false
	var current := PackedFloat32Array()
	var next := PackedFloat32Array()
	var heat := PackedFloat32Array()
	var drops := PackedFloat32Array()

	func _init(is_flowing: bool) -> void:
		flowing = is_flowing
		# Packed arrays are values: resize each member itself.
		current.resize(SIZE * SIZE)
		next.resize(SIZE * SIZE)
		heat.resize(SIZE * SIZE)
		drops.resize(SIZE * SIZE)

	func step() -> void:
		for y in SIZE:
			for x in SIZE:
				var sum := 0.0
				if flowing:
					for k in range(y - 2, y + 1): # from above: along the flow
						sum += current[x + (k & 15) * SIZE]
					next[x + y * SIZE] = sum / 3.2 + heat[x + y * SIZE] * 0.8
				else:
					for k in range(x - 1, x + 2): # sideways
						sum += current[(k & 15) + y * SIZE]
					next[x + y * SIZE] = sum / 3.3 + heat[x + y * SIZE] * 0.8
		var decay := 0.3 if flowing else 0.1
		var chance := 0.2 if flowing else 0.05
		for i in SIZE * SIZE:
			heat[i] = maxf(heat[i] + drops[i] * 0.05, 0.0)
			drops[i] -= decay
			if randf() < chance:
				drops[i] = 0.5
		var swap := current
		current = next
		next = swap

	## RGBA bytes; `shift` slides the pattern down (flowing water).
	func pixels(shift: int) -> PackedByteArray:
		var data := PackedByteArray()
		data.resize(SIZE * SIZE * 4)
		for i in SIZE * SIZE:
			var energy := clampf(current[(i - shift * SIZE) & 255], 0.0, 1.0)
			WaterAnimation.water_pixel(data, i, energy * energy)
		return data


## The same simulations in C++ (NativeTextureFx): [still, flowing], or
## empty without the native library (then the GDScript above).
var _native: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if ClassDB.class_exists("NativeTextureFx"):
		for kind: int in [2, 3]:
			var fx: Object = ClassDB.instantiate("NativeTextureFx")
			fx.call("setup", kind, randi())
			_native.append(fx)


## The water was drawn at least once (in our colors even with Animated
## Water off: then it stays still).
var _drawn := false


func _process(delta: float) -> void:
	if not Settings.get_value("animated_water") and _drawn:
		return
	_drawn = true
	_accumulator += delta
	if _accumulator < STEP and _ticks > 0:
		return
	_accumulator = clampf(_accumulator - STEP, 0.0, STEP)
	_ticks += 1
	var tiles := BlockMaterials.tiles()
	if not _native.is_empty():
		tiles.update_layer(_image(_recolored(_native[0].call("step", 0))), STILL_TILE)
		tiles.update_layer(_image(_recolored(_native[1].call("step", _ticks))), FLOW_TILE)
		return
	_still.step()
	_flow.step()
	tiles.update_layer(_image(_still.pixels(0)), STILL_TILE)
	tiles.update_layer(_image(_flow.pixels(_ticks)), FLOW_TILE)


## Writes pixel i of RGBA bytes: water at this energy (0..1, squared).
static func water_pixel(data: PackedByteArray, i: int, energy: float) -> void:
	var color := CALM.lerp(RIPPLE, energy)
	data[i * 4] = color.r8
	data[i * 4 + 1] = color.g8
	data[i * 4 + 2] = color.b8
	data[i * 4 + 3] = color.a8


## The native simulation's pixels (Beta's colors: red 32 + energy * 32) in
## our water colors.
static func _recolored(data: PackedByteArray) -> PackedByteArray:
	for i in SIZE * SIZE:
		water_pixel(data, i, clampf((data[i * 4] - 32) / 32.0, 0.0, 1.0))
	return data


static func _image(data: PackedByteArray) -> Image:
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image
