class_name WaterAnimation
extends Node
## Animated water textures like the classic Beta game: not a sequence of
## frames but a small simulation per texture, 20 steps per second, written
## into the block tile array:
## - still water (tops): ripples spread sideways, random drops add energy;
## - flowing water (sides): ripples spread along the flow and the whole
##   pattern slides down one pixel per step.
## Each texture pixel keeps an energy value; brighter, greener and more
## opaque where the energy is high (the classic water colors).

const STILL_TILE := 205
const FLOW_TILE := 206
const SIZE := 16
const STEP := 1.0 / 20.0

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
			energy *= energy
			data[i * 4] = int(32 + energy * 32)
			data[i * 4 + 1] = int(50 + energy * 64)
			data[i * 4 + 2] = 255
			data[i * 4 + 3] = int(146 + energy * 50)
		return data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not Settings.get_value("animated_water"):
		return
	_accumulator += delta
	if _accumulator < STEP:
		return
	_accumulator = minf(_accumulator - STEP, STEP)
	_ticks += 1
	_still.step()
	_flow.step()
	var tiles := BlockMaterials.tiles()
	tiles.update_layer(_image(_still.pixels(0)), STILL_TILE)
	tiles.update_layer(_image(_flow.pixels(_ticks)), FLOW_TILE)


static func _image(data: PackedByteArray) -> Image:
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image
