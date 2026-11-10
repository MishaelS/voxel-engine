class_name ChestModel
extends RefCounted
## The chest model like the modern game (its chest block entity): a base
## 14 x 10 x 14 pixels, a lid 14 x 4 x 14 on top and a latch 2 x 4 x 1 on
## the front; a large chest is two halves 15 pixels wide each with a 1 pixel
## latch at the seam. Textures come from assets/textures/chest-atlas.png,
## laid out like the game's chest textures (64 x 64 cells, box textures with
## the faces unfolded: two squares, then the side strip).
##
## Every face's pixels become an extra layer of the block tile array (after
## the 256 atlas tiles; edges extended so distant mipmaps don't bleed), and
## the chest is a block model (BlockModel) using those layers, registered
## for each part and facing (model_index()).
##
## Face orientation in the textures (the game's): side faces are upside
## down (their bottom row is the face's top), seen from outside left to
## right; the up and down squares run along -X.

const ATLAS_PATH := "res://assets/textures/chest-atlas.png"
## First tile array layer of the chest faces (after the 16 x 16 atlas tiles).
const FIRST_LAYER := 256

enum Part { SINGLE, LEFT, RIGHT }
## Atlas cells (column, row) of the wooden chest and its two halves. LEFT is
## the half on the left when looking at the front (its seam on +X).
const CELLS := {Part.SINGLE: Vector2i(4, 0), Part.LEFT: Vector2i(4, 1), Part.RIGHT: Vector2i(4, 2)}

## Faces in BlockType order: +Y, -Y, +X, -X, +Z, -Z.
const UP := 0
const DOWN := 1
const EAST := 2
const WEST := 3
const SOUTH := 4
const NORTH := 5

## Per part: the boxes, each [from, to (pixels), texture origin (u, v),
## texture size (w, h, d), the rows of the side strip to use (from the
## top of the box's strip), faces left out].
static var _boxes := {
	Part.SINGLE: [
		[Vector3(1, 0, 1), Vector3(15, 10, 15), Vector2i(0, 19), Vector3i(14, 10, 14), 0, []],
		[Vector3(1, 10, 1), Vector3(15, 14, 15), Vector2i(0, 0), Vector3i(14, 5, 14), 1, [DOWN]],
		[Vector3(7, 7, 15), Vector3(9, 11, 16), Vector2i(0, 0), Vector3i(2, 4, 1), 0, [NORTH]],
	],
	Part.LEFT: [
		[Vector3(1, 0, 1), Vector3(16, 10, 15), Vector2i(0, 19), Vector3i(15, 10, 14), 0, [EAST]],
		[Vector3(1, 10, 1), Vector3(16, 14, 15), Vector2i(0, 0), Vector3i(15, 5, 14), 1, [DOWN, EAST]],
		[Vector3(15, 7, 15), Vector3(16, 11, 16), Vector2i(0, 0), Vector3i(1, 4, 1), 0, [NORTH, EAST]],
	],
	Part.RIGHT: [
		[Vector3(0, 0, 1), Vector3(15, 10, 15), Vector2i(0, 19), Vector3i(15, 10, 14), 0, [WEST]],
		[Vector3(0, 10, 1), Vector3(15, 14, 15), Vector2i(0, 0), Vector3i(15, 5, 14), 1, [DOWN, WEST]],
		[Vector3(0, 7, 15), Vector3(1, 11, 16), Vector2i(0, 0), Vector3i(1, 4, 1), 0, [NORTH, WEST]],
	],
}

## Faces and their texture rectangles, filled by _layout().
static var _faces: Array = []        # [part][box] -> {face: [layer, Rect2i]}
static var _rects: Array[Rect2i] = [] # layer - FIRST_LAYER -> rect in the atlas
static var _models := {}              # part * 4 + facing -> BlockModel index
static var _ready := _layout()


## The block model of a chest part facing `facing` (0 south .. 3 east).
static func model_index(part: int, facing: int) -> int:
	var key := part * 4 + facing
	if not _models.has(key):
		_models[key] = BlockModel.register(_model_boxes(part), facing)
	return _models[key]


## The chest's boxes as BlockModel boxes: each face shows its own layer,
## side faces upside down and the squares mirrored, like the game.
static func _model_boxes(part: int) -> Array:
	var result := []
	var boxes: Array = _boxes[part]
	for b in boxes.size():
		var faces := {}
		var part_faces: Dictionary = _faces[part][b]
		for face: int in part_faces:
			var rect: Rect2i = part_faces[face][1]
			faces[face] = {"layer": part_faces[face][0], "uv": Rect2(Vector2.ZERO, Vector2(rect.size)),
				"flip_v": face != UP and face != DOWN, "mirror_u": face == UP or face == DOWN}
		result.append({"from": boxes[b][0], "to": boxes[b][1], "faces": faces})
	return result


## The tile layers of the chest faces, as 16 x 16 images (for the tile array).
static func tile_images() -> Array[Image]:
	var atlas: Image = TexturePacks.load_texture(ATLAS_PATH).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var images: Array[Image] = []
	for rect in _rects:
		var tile := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				# Outside the face: its nearest edge pixel (no mipmap bleeding).
				var source := rect.position + Vector2i(mini(x, rect.size.x - 1), mini(y, rect.size.y - 1))
				tile.set_pixelv(Vector2i(x, y), atlas.get_pixelv(source))
		tile.generate_mipmaps()
		images.append(tile)
	return images


## A tile showing the chest's planks (particles, the block's own tiles).
static func particle_layer() -> int:
	return FIRST_LAYER + 1 # the single chest base's -Y face (its bottom)


static func layer_count() -> int:
	return _rects.size()


static func _layout() -> bool:
	for part in [Part.SINGLE, Part.LEFT, Part.RIGHT]:
		var cell: Vector2i = CELLS[part] * 64
		var part_faces := []
		for box: Array in _boxes[part]:
			var origin: Vector2i = cell + box[2]
			var size: Vector3i = box[3]
			var w := size.x
			var h := size.y
			var d := size.z
			var skip: int = box[4]
			var faces := {}
			var rects := {
				DOWN: Rect2i(origin + Vector2i(d, 0), Vector2i(w, d)),
				UP: Rect2i(origin + Vector2i(d + w, 0), Vector2i(w, d)),
				EAST: Rect2i(origin + Vector2i(0, d + skip), Vector2i(d, h - skip)),
				NORTH: Rect2i(origin + Vector2i(d, d + skip), Vector2i(w, h - skip)),
				WEST: Rect2i(origin + Vector2i(d + w, d + skip), Vector2i(d, h - skip)),
				SOUTH: Rect2i(origin + Vector2i(d + w + d, d + skip), Vector2i(w, h - skip)),
			}
			for face: int in rects:
				if (box[5] as Array).has(face):
					continue
				faces[face] = [FIRST_LAYER + _rects.size(), rects[face]]
				_rects.append(rects[face])
			part_faces.append(faces)
		_faces.append(part_faces)
	return true
