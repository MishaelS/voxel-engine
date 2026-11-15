class_name BlockModel
extends RefCounted
## Blocks drawn as a set of boxes (BlockType.Shape.MODEL), like the game's
## block models: chests, and later stairs, slabs, fences, torches, doors,
## ladders, rails... A model is registered once per facing and the mesher
## draws its quads (lit by the light in the block's cell, shaded by side).
##
## A box is {"from": Vector3, "to": Vector3 (pixels, 0..16), "faces":
## {face: {...}}} with faces in BlockType order (+Y, -Y, +X, -X, +Z, -Z).
## A face is {"layer": tile array layer, optionally "uv": Rect2 (pixels in
## the tile; by default the box's own extent, like the game), "flip_v": the
## texture upside down, "mirror_u": mirrored left-right, "uv_turn": turned that many quarter turns}. Faces left out
## are not drawn (hidden ones, like the inside of a chest's seam).
## A box may be tilted: "rotation": {"axis": "x" or "z", "angle": degrees,
## "origin": Vector3 (pixels)} (the wall torch leans 22.5 degrees).
## Textures are seen from outside, left to right and top to bottom.

const UP := 0
const DOWN := 1
const EAST := 2
const WEST := 3
const SOUTH := 4
const NORTH := 5

## Turn of each facing (0 south, 1 west, 2 north, 3 east) around the block's
## vertical middle; models are written facing south (+Z).
const FACING_TURNS: Array[float] = [0.0, -90.0, 180.0, 90.0]

static var _models: Array = [] # index -> Array of quads


## Registers a model (its boxes turned for `facing`) and returns its index.
## `uvlock`, like the game's block states: the texture is not turned with
## the model but laid by where each face ends up in the block (stairs: the
## planks run the same way whichever way they face, as if cut from a block).
static func register(boxes: Array, facing: int = 0, uvlock: bool = false) -> int:
	_models.append(_build(boxes, FACING_TURNS[facing], uvlock))
	return _models.size() - 1


## Registers a model turned by any angle (degrees, like facing turns:
## floor signs come in 16 directions).
static func register_turned(boxes: Array, degrees: float) -> int:
	_models.append(_build(boxes, degrees))
	return _models.size() - 1


## The quads of a model: [corners (4, clockwise from the top left seen from
## outside, in blocks), normal, uvs (4, 0..1 inside the layer), layer].
static func quads(index: int) -> Array:
	return _models[index]


## The quads of boxes without registering a model (meshes drawn outside the
## chunks: ChestModel.lid_meshes).
## `degrees`: turned like register_turned.
static func quads_of(boxes: Array, degrees: float = 0.0) -> Array:
	return _build(boxes, degrees)


static func _build(boxes: Array, degrees: float, uvlock: bool = false) -> Array:
	var rotation := Basis(Vector3.UP, deg_to_rad(degrees))
	var middle := Vector3(0.5, 0.0, 0.5)
	var result := []
	for box: Dictionary in boxes:
		var from: Vector3 = box.from / 16.0
		var to: Vector3 = box.to / 16.0
		var faces: Dictionary = box.faces
		var tilt := Basis.IDENTITY
		var pivot := Vector3.ZERO
		if box.has("rotation"):
			var turn: Dictionary = box.rotation
			tilt = Basis(Vector3.RIGHT if turn.axis == "x" else Vector3.BACK, deg_to_rad(turn.angle))
			pivot = turn.origin / 16.0
		for face: int in faces:
			var spec: Dictionary = faces[face]
			var rect: Rect2 = spec.get("uv", _auto_uv(face, box.from, box.to))
			var uvs := PackedVector2Array()
			for c in 4:
				var corner_uv := Vector2(ChunkMesher.CORNER_UVS[(c + int(spec.get("uv_turn", 0))) % 4])
				if spec.get("mirror_u", false):
					corner_uv.x = 1.0 - corner_uv.x
				if spec.get("flip_v", false):
					corner_uv.y = 1.0 - corner_uv.y
				uvs.append((rect.position + corner_uv * rect.size) / 16.0)
			var corners := PackedVector3Array()
			for corner: Vector3 in ChunkMesher.FACE_CORNERS[face]:
				var point := Vector3(lerpf(from.x, to.x, corner.x), lerpf(from.y, to.y, corner.y), lerpf(from.z, to.z, corner.z))
				point = tilt * (point - pivot) + pivot
				corners.append(rotation * (point - middle) + middle)
			var normal := rotation * (tilt * ChunkMesher.FACE_NORMALS[face])
			if uvlock and not box.has("rotation") and not spec.has("uv") and not spec.has("uv_turn") \
					and not spec.get("mirror_u", false) and not spec.get("flip_v", false):
				uvs = PackedVector2Array()
				for point: Vector3 in corners:
					uvs.append(_locked_uv(point, normal))
			result.append([corners, normal, uvs, int(spec.layer)])
	return result


## Where in the texture (0..1) a point of a face pointing `normal` falls,
## the same projection as _auto_uv but from the turned model's own place.
static func _locked_uv(point: Vector3, normal: Vector3) -> Vector2:
	if normal.y > 0.5:
		return Vector2(point.x, point.z)
	if normal.y < -0.5:
		return Vector2(point.x, 1.0 - point.z)
	if normal.z > 0.5:
		return Vector2(point.x, 1.0 - point.y)
	if normal.z < -0.5:
		return Vector2(1.0 - point.x, 1.0 - point.y)
	if normal.x > 0.5:
		return Vector2(1.0 - point.z, 1.0 - point.y)
	return Vector2(point.z, 1.0 - point.y)


## The texture part a face shows by default (pixels): the box's own extent
## on that face, seen from outside, like the game's block models.
static func _auto_uv(face: int, from: Vector3, to: Vector3) -> Rect2:
	match face:
		UP:
			return Rect2(from.x, from.z, to.x - from.x, to.z - from.z)
		DOWN:
			return Rect2(from.x, 16.0 - to.z, to.x - from.x, to.z - from.z)
		SOUTH:
			return Rect2(from.x, 16.0 - to.y, to.x - from.x, to.y - from.y)
		NORTH:
			return Rect2(16.0 - to.x, 16.0 - to.y, to.x - from.x, to.y - from.y)
		EAST:
			return Rect2(16.0 - to.z, 16.0 - to.y, to.z - from.z, to.y - from.y)
		_: # WEST
			return Rect2(from.z, 16.0 - to.y, to.z - from.z, to.y - from.y)
