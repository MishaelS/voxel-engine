class_name BlockIcons
extends RefCounted
## Isometric inventory icons of blocks, drawn from the texture atlas like
## the classic game: top face, south face on the left (front of furnaces
## and crafting tables) and east face on the right, with face shading,
## biome tints and overlays (grass sides). Icons are made once and cached.

const SIZE := 64 ## Icon image size in pixels.
const TILE := 16 ## Atlas tile size.

## Brightness of the visible faces.
const TOP_SHADE := 1.0
const LEFT_SHADE := 0.8
const RIGHT_SHADE := 0.6

## Face index (BlockType order), shade, origin and the two edge vectors of
## each face in icon pixels: p = origin + u * edge_u + v * edge_v (u, v in 0..1).
const FACES := [
	[0, TOP_SHADE, Vector2(32, 0), Vector2(32, 16), Vector2(-32, 16)],   # +Y: NW corner, east, south
	[4, LEFT_SHADE, Vector2(0, 16), Vector2(32, 16), Vector2(0, 32)],    # +Z (south)
	[2, RIGHT_SHADE, Vector2(32, 32), Vector2(32, -16), Vector2(0, 32)], # +X (east)
]

static var _cache := {}
static var _atlas: Image


static func get_icon(id: int) -> Texture2D:
	if not _cache.has(id):
		_cache[id] = ImageTexture.create_from_image(render(id))
	return _cache[id]


## Drops cached icons (e.g. after replacing the atlas).
static func clear() -> void:
	_cache.clear()
	_atlas = null


static func render(id: int) -> Image:
	if _atlas == null:
		_atlas = (load(Blocks.ATLAS_PATH) as Texture2D).get_image()
		if _atlas.is_compressed():
			_atlas.decompress()
		_atlas.convert(Image.FORMAT_RGBA8)
	var icon := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if id == Blocks.AIR:
		return icon
	var block := Blocks.get_type(id)

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			for face: Array in FACES:
				var uv := _face_uv(point, face[2], face[3], face[4])
				if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
					continue
				var color := _sample(block, face[0], uv)
				color.r *= face[1]
				color.g *= face[1]
				color.b *= face[1]
				icon.set_pixel(x, y, color)
				break
	return icon


## (u, v) of a point inside a parallelogram face; outside 0..1 = not on it.
static func _face_uv(point: Vector2, origin: Vector2, edge_u: Vector2, edge_v: Vector2) -> Vector2:
	var d := point - origin
	var det := edge_u.x * edge_v.y - edge_u.y * edge_v.x
	return Vector2((d.x * edge_v.y - d.y * edge_v.x) / det, (edge_u.x * d.y - edge_u.y * d.x) / det)


static func _sample(block: BlockType, face: int, uv: Vector2) -> Color:
	var base := _tile_pixel(block.tiles[face], uv)
	var overlay_tile := block.overlays[face]
	if overlay_tile >= 0:
		var overlay := _tile_pixel(overlay_tile, uv)
		var tinted := overlay * block.tint
		return Color(base.lerp(tinted, overlay.a), base.a)
	var color := base * block.tint
	color.a = base.a
	return color


static func _tile_pixel(tile: int, uv: Vector2) -> Color:
	var px := (tile % Blocks.ATLAS_TILES_PER_ROW) * TILE + mini(int(uv.x * TILE), TILE - 1)
	var py := (tile / Blocks.ATLAS_TILES_PER_ROW) * TILE + mini(int(uv.y * TILE), TILE - 1)
	return _atlas.get_pixel(px, py)
