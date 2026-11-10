class_name Maps
extends RefCounted
## Maps like the classic game (Beta 1.7.3): a map item draws the land around
## the place it was first held, 128 x 128 pixels, one pixel per 8 x 8
## blocks (1024 blocks across). While the player holds it, the pixels within
## 128 blocks of them fill in, a stripe per tick: the color of the top block
## (grass, sand, water, leaves, stone, wood...), lighter where the ground
## rises to the north and darker where it falls, water darker the deeper.
## Maps live in the world save (VoxelWorld.maps); the map item's damage
## value is its number (0 = not drawn yet: it gets a number when held).

const SIZE := 128
const SCALE := 8 ## blocks per pixel
const RADIUS := 16 ## pixels around the player filled in
## Map colors (like the game's MapColor), index 0 = not explored.
const COLORS: Array[Color] = [
	Color(0, 0, 0, 0),
	Color8(127, 178, 56), # grass
	Color8(247, 233, 163), # sand
	Color8(167, 167, 167), # wool
	Color8(255, 0, 0), # lava, fire
	Color8(160, 160, 255), # ice
	Color8(167, 167, 167), # iron
	Color8(0, 124, 0), # leaves, plants
	Color8(255, 255, 255), # snow
	Color8(164, 168, 184), # clay
	Color8(183, 106, 47), # dirt
	Color8(112, 112, 112), # stone
	Color8(64, 64, 255), # water
	Color8(104, 83, 50), # wood
]
const SHADES: Array[float] = [180.0 / 255.0, 220.0 / 255.0, 1.0]


## A new map centered on `point`; returns its number.
static func create(world: VoxelWorld, point: Vector3) -> int:
	world.next_map_id += 1
	var colors := PackedByteArray()
	colors.resize(SIZE * SIZE)
	world.maps[world.next_map_id] = {"x": floori(point.x), "z": floori(point.z), "colors": colors}
	return world.next_map_id


## Fills in one stripe of pixels near `point` (call once per tick while
## held). Returns true if a pixel changed.
static func update(world: VoxelWorld, number: int, point: Vector3, tick: int) -> bool:
	var map: Dictionary = world.maps.get(number, {})
	if map.is_empty():
		return false
	var colors: PackedByteArray = map.colors
	var center_x: int = map.x
	var center_z: int = map.z
	var px := floori((point.x - center_x) / SCALE) + SIZE / 2
	var pz := floori((point.z - center_z) / SCALE) + SIZE / 2
	var column := px + (tick % (RADIUS * 2 + 1)) - RADIUS
	if column < 0 or column >= SIZE:
		return false
	var changed := false
	var previous := -1
	for row in range(pz - RADIUS - 1, pz + RADIUS + 1):
		var dx := column - px
		var dz := row - pz
		var x := center_x + (column - SIZE / 2) * SCALE + SCALE / 2
		var z := center_z + (row - SIZE / 2) * SCALE + SCALE / 2
		var sample := _sample(world, x, z)
		if sample.is_empty():
			previous = -1
			continue
		var height: int = sample[1]
		if row >= 0 and row < SIZE and dx * dx + dz * dz <= RADIUS * RADIUS and previous >= 0:
			var shade := 1
			if sample[0] == 12: # water: darker the deeper
				var depth: int = sample[2]
				shade = 2 if depth < 2 else (1 if depth < 6 else 0)
			elif height > previous:
				shade = 2
			elif height < previous:
				shade = 0
			var value: int = sample[0] * 4 + shade
			if colors[column + row * SIZE] != value:
				colors[column + row * SIZE] = value
				changed = true
		previous = height
	map.colors = colors
	return changed


## [color index, height, water depth] of the top block of a column, or []
## where the ground isn't loaded.
static func _sample(world: VoxelWorld, x: int, z: int) -> Array:
	if not world.is_inside(Vector3i(x, 0, z)):
		return []
	for y in range(WorldGenerator.HEIGHT - 1, -1, -1):
		var id := world.get_block(Vector3i(x, y, z))
		if id == Blocks.AIR:
			continue
		var color := color_of(id)
		if color == 12:
			var depth := 1
			while y - depth > 0 and Blocks.liquid_table[world.get_block(Vector3i(x, y - depth, z))] == 1:
				depth += 1
			return [color, y, depth]
		return [color, y, 0]
	return [11, 0, 0]


## The map color index of a block.
static func color_of(id: int) -> int:
	var block := Blocks.get_type(id)
	var name := block.name
	if block.liquid:
		return 12 if Blocks.family_of(id) == "water" else 4
	if name.begins_with("grass"):
		return 1
	if name in ["sand", "sandstone", "gravel"] or name.begins_with("sandstone"):
		return 2
	if name.ends_with("_wool") or name.begins_with("bed"):
		return 3
	if name.begins_with("fire"):
		return 4
	if name == "ice":
		return 5
	if name.ends_with("_leaves") or block.shape == BlockType.Shape.CROSS or name == "cactus":
		return 7
	if name.begins_with("snow"):
		return 8
	if name == "clay":
		return 9
	if name == "dirt" or name.begins_with("farmland"):
		return 10
	if name.contains("_log") or name.contains("planks") or name.contains("oak") or name.contains("birch") \
			or name.contains("spruce") or name.contains("wooden") or name.begins_with("chest") \
			or name in ["crafting_table", "bookshelf", "fence", "ladder", "jukebox", "note_block"]:
		return 13
	if name.contains("iron") or name.contains("gold") or name.contains("diamond") or name.contains("lapis"):
		return 6
	return 11


## The map's picture (128 x 128, unexplored pixels transparent).
static func image_of(world: VoxelWorld, number: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var map: Dictionary = world.maps.get(number, {})
	if map.is_empty():
		return image
	var colors: PackedByteArray = map.colors
	for i in colors.size():
		var value := colors[i]
		if value == 0:
			continue
		var color := COLORS[value / 4]
		var shade := SHADES[value % 4] if value % 4 < 3 else 1.0
		image.set_pixel(i % SIZE, i / SIZE, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
	return image
