class_name Blocks
extends RefCounted
## Block type registry. A block is stored as a single byte (its id).
## Colors are temporary: they will be replaced by a texture array later.

const AIR := 0
const STONE := 1
const DIRT := 2
const GRASS := 3

const COLORS: Array[Color] = [
	Color(0, 0, 0, 0),         # AIR (never rendered)
	Color(0.50, 0.50, 0.52),   # STONE
	Color(0.45, 0.32, 0.20),   # DIRT
	Color(0.36, 0.62, 0.25),   # GRASS
]


## True if the block fully hides the faces of its neighbors.
## Every non-air block is opaque for now; glass/water will change this.
static func is_opaque(id: int) -> bool:
	return id != AIR
