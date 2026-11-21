class_name FireAnimation
extends Node
## Animated fire like the classic Beta game (its FireFX): a small heat
## simulation 16 x 20 pixels, 20 steps per second, fed with random heat
## at the bottom; heat rises, spreads and fades; the color goes from
## transparent through red and orange to yellow. Two separate fires for
## the two fire tiles. Shown once even with animations off.

const TILES: Array[int] = [31, 47]
const SIZE := 16
const ROWS := 20
const STEP := 1.0 / 20.0

var _fields: Array[PackedFloat32Array] = []
var _next := PackedFloat32Array()
var _accumulator := 0.0
var _native: Array = [] # NativeTextureFx per tile (empty: the GDScript below)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_next.resize(SIZE * ROWS)
	for tile in TILES:
		var field := PackedFloat32Array()
		field.resize(SIZE * ROWS)
		_fields.append(field)
	if ClassDB.class_exists("NativeTextureFx"):
		# The same simulation in C++ (NativeTextureFx), one object a tile.
		for k in TILES.size():
			var fx: Object = ClassDB.instantiate("NativeTextureFx")
			fx.call("setup", 0, randi())
			_native.append(fx)
	# Warm up so the fire is there from the start, then show it once.
	for i in 39:
		_advance(false)
	_advance(true)


func _process(delta: float) -> void:
	if not Settings.get_value("animated_water"):
		return
	_accumulator += delta
	if _accumulator < STEP:
		return
	_accumulator = minf(_accumulator - STEP, STEP)
	_advance(true)


## One step of every fire; `show`: its pixels go to the tile array.
func _advance(show: bool) -> void:
	if not _native.is_empty():
		var tiles := BlockMaterials.tiles()
		for k in _native.size():
			var data: PackedByteArray = _native[k].call("step", 0)
			if show:
				var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
				image.generate_mipmaps()
				tiles.update_layer(image, TILES[k])
		return
	for k in _fields.size():
		_step(k)
	if show:
		_upload()


func _step(k: int) -> void:
	var field := _fields[k]
	for y in ROWS:
		for x in SIZE:
			var count := 18
			var sum := field[x + ((y + 1) % ROWS) * SIZE] * 18.0
			for nx in range(x - 1, x + 2):
				for ny in range(y, y + 2):
					if nx >= 0 and ny >= 0 and nx < SIZE and ny < ROWS:
						sum += field[nx + ny * SIZE]
						count += 1
			var value := sum / (count * 1.06)
			if y >= ROWS - 1:
				# The bottom row: random heat feeds the fire.
				value = randf() * randf() * randf() * 4.0 + randf() * 0.1 + 0.2
			_next[x + y * SIZE] = value
	for i in SIZE * ROWS:
		field[i] = _next[i]


func _upload() -> void:
	var tiles := BlockMaterials.tiles()
	for k in _fields.size():
		var field := _fields[k]
		var data := PackedByteArray()
		data.resize(SIZE * SIZE * 4)
		for i in SIZE * SIZE:
			var f := clampf(field[i] * 1.8, 0.0, 1.0)
			data[i * 4] = int(f * 155.0 + 100.0)
			data[i * 4 + 1] = int(f * f * 255.0)
			data[i * 4 + 2] = int(pow(f, 10.0) * 255.0)
			data[i * 4 + 3] = 0 if f < 0.5 else 255
		var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
		image.generate_mipmaps()
		tiles.update_layer(image, TILES[k])
