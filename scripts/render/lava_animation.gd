class_name LavaAnimation
extends Node
## Animated lava textures like the classic Beta game (its LavaFX): a small
## heat simulation per texture, 20 steps per second, written into the block
## tile array: hot spots appear at random, spread and cool down; the
## pixel's heat sets its color (dark red .. bright yellow). Flowing lava
## (sides) slides down one pixel every third step.

const STILL_TILE := 237
const FLOW_TILE := 238
const SIZE := 16
const STEP := 1.0 / 20.0

var _still := _Heat.new()
var _flow := _Heat.new()
var _accumulator := 0.0
var _ticks := 0


class _Heat:
	var current := PackedFloat32Array()
	var next := PackedFloat32Array()
	var heat := PackedFloat32Array()
	var speed := PackedFloat32Array()

	func _init() -> void:
		current.resize(SIZE * SIZE)
		next.resize(SIZE * SIZE)
		heat.resize(SIZE * SIZE)
		speed.resize(SIZE * SIZE)

	func step() -> void:
		for y in SIZE:
			for x in SIZE:
				var sum := 0.0
				var wobble_x := int(sin(y * PI * 2.0 / SIZE) * 1.2)
				var wobble_y := int(sin(x * PI * 2.0 / SIZE) * 1.2)
				for nx in range(x - 1, x + 2):
					for ny in range(y - 1, y + 2):
						sum += current[((nx + wobble_x) & 15) + ((ny + wobble_y) & 15) * SIZE]
				next[x + y * SIZE] = sum / 10.0 + (heat[(x & 15) + (y & 15) * SIZE] \
					+ heat[((x + 1) & 15) + (y & 15) * SIZE] + heat[((x + 1) & 15) + ((y + 1) & 15) * SIZE] \
					+ heat[(x & 15) + ((y + 1) & 15) * SIZE]) / 4.0 * 0.8
				var i := x + y * SIZE
				heat[i] = maxf(heat[i] + speed[i] * 0.01, 0.0)
				speed[i] -= 0.06
				if randf() < 0.005:
					speed[i] = 1.5
		var swap := current
		current = next
		next = swap

	func pixels(shift: int) -> PackedByteArray:
		var data := PackedByteArray()
		data.resize(SIZE * SIZE * 4)
		for i in SIZE * SIZE:
			var f := clampf(current[(i - shift * SIZE) & 255] * 2.0, 0.0, 1.0)
			data[i * 4] = int(f * 100.0 + 155.0)
			data[i * 4 + 1] = int(f * f * 255.0)
			data[i * 4 + 2] = int(f * f * f * f * 128.0)
			data[i * 4 + 3] = 255
		return data


## The same simulations in C++ (NativeTextureFx): [still, flowing], or
## empty without the native library (then the GDScript above).
var _native: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if ClassDB.class_exists("NativeTextureFx"):
		for kind: int in [1, 1]:
			var fx: Object = ClassDB.instantiate("NativeTextureFx")
			fx.call("setup", kind, randi())
			_native.append(fx)


func _process(delta: float) -> void:
	if not Settings.get_value("animated_water"):
		return
	_accumulator += delta
	if _accumulator < STEP:
		return
	_accumulator = minf(_accumulator - STEP, STEP)
	_ticks += 1
	var tiles := BlockMaterials.tiles()
	if not _native.is_empty():
		tiles.update_layer(_image(_native[0].call("step", 0)), STILL_TILE)
		tiles.update_layer(_image(_native[1].call("step", _ticks / 3)), FLOW_TILE)
		return
	_still.step()
	_flow.step()
	tiles.update_layer(_image(_still.pixels(0)), STILL_TILE)
	tiles.update_layer(_image(_flow.pixels(_ticks / 3)), FLOW_TILE)


static func _image(data: PackedByteArray) -> Image:
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image
