class_name FallingBlocks
extends Node3D
## Falling block entities (sand, gravel), like the classic game, but
## lighter: no node or object per entity.
##
## - Simulation runs in game ticks (TickLoop, Phase.ENTITIES) on packed
##   arrays: position, previous position, vertical speed, block id.
##   Physics per tick as in the classic game: speed -= GRAVITY, move,
##   speed *= DRAG (terminal speed ~2 blocks per tick).
## - Landing checks only the cells the block passed through this tick, so
##   fast blocks never fall through the floor. A landed block becomes a
##   normal block again (in the first free cell, so blocks landing in the
##   same column in the same tick stack up).
## - Rendering: one MultiMeshInstance3D per block type with the same mesh
##   and materials as chunk blocks; instance positions are interpolated
##   between the last two ticks with TickLoop.alpha, so motion is smooth at
##   any frame rate.

const GRAVITY := 0.04
const DRAG := 0.98
## Removed when falling this far below the lowest loaded block.
const VOID_DEPTH := 64.0

## The world the blocks fall in (set by VoxelWorld).
var world: VoxelWorld

var _positions := PackedVector3Array()      # min corner of the block
var _previous := PackedVector3Array()       # position at the previous tick
var _speeds := PackedFloat32Array()         # vertical speed, blocks per tick
var _ids := PackedInt32Array()

var _renderers := {}   # block id -> MultiMeshInstance3D
static var _meshes := {} # block id -> Mesh (shared, built once)
var _water := -1


func _ready() -> void:
	_water = Blocks.id_of("water")
	TickLoop.add_listener(_tick, TickLoop.Phase.ENTITIES)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)
	_meshes.clear() # shared cache; rebuilt on demand


func count() -> int:
	return _ids.size()


## Starts a falling block whose lower corner is at `cell`.
func spawn(cell: Vector3i, block_id: int) -> void:
	var position := Vector3(cell)
	_positions.append(position)
	_previous.append(position)
	_speeds.append(0.0)
	_ids.append(block_id)


func clear() -> void:
	_positions.clear()
	_previous.clear()
	_speeds.clear()
	_ids.clear()
	_update_renderers(0.0)


# --- Simulation ------------------------------------------------------------------

func _tick(_tick_index: int) -> void:
	var i := 0
	while i < _ids.size():
		_previous[i] = _positions[i]
		var speed := (_speeds[i] - GRAVITY)
		var position := _positions[i]
		var target_y := position.y + speed
		var landing: Variant = _find_landing(position, target_y)
		if landing != null:
			_land(i, landing)
			continue # entity i was replaced by the last one
		position.y = target_y
		_positions[i] = position
		_speeds[i] = speed * DRAG
		if position.y < -VOID_DEPTH:
			_remove(i)
			continue
		i += 1


## The cell to land in if the block hits ground while moving from
## position.y down to target_y, or null.
func _find_landing(position: Vector3, target_y: float) -> Variant:
	var x := floori(position.x + 0.5)
	var z := floori(position.z + 0.5)
	# Cells under the block bottom that it enters during this tick.
	var from_cell := floori(position.y) - 1
	var to_cell := floori(target_y)
	for cell_y in range(from_cell, to_cell - 1, -1):
		var below := Vector3i(x, cell_y, z)
		if world.is_inside(below) and _is_solid(world.get_block(below)):
			return below + Vector3i.UP
	return null


## Max cells to look up for a free spot when the landing cell is taken
## (two blocks landing in the same column in the same tick).
const MAX_STACK_SEARCH := 4


func _land(index: int, cell: Vector3i) -> void:
	for i in MAX_STACK_SEARCH:
		if world.is_inside(cell) and not _is_solid(world.get_block(cell)):
			world.set_block(cell, _ids[index])
			break
		cell += Vector3i.UP
	_remove(index)


func _is_solid(block_id: int) -> bool:
	return block_id != Blocks.AIR and block_id != _water


## Swap-remove: O(1), order does not matter.
func _remove(index: int) -> void:
	var last := _ids.size() - 1
	_positions[index] = _positions[last]
	_previous[index] = _previous[last]
	_speeds[index] = _speeds[last]
	_ids[index] = _ids[last]
	_positions.resize(last)
	_previous.resize(last)
	_speeds.resize(last)
	_ids.resize(last)


# --- Rendering -------------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_renderers(TickLoop.alpha)


func _update_renderers(alpha: float) -> void:
	# Count instances per block type.
	var counts := {}
	for id in _ids:
		counts[id] = counts.get(id, 0) + 1
	for id: int in _renderers.keys():
		if not counts.has(id):
			(_renderers[id] as MultiMeshInstance3D).multimesh.instance_count = 0
	var next_index := {}
	for id: int in counts:
		var multimesh := _renderer(id).multimesh
		if multimesh.instance_count != counts[id]:
			multimesh.instance_count = counts[id]
		next_index[id] = 0
	for i in _ids.size():
		var id := _ids[i]
		var position := _previous[i].lerp(_positions[i], alpha)
		_renderers[id].multimesh.set_instance_transform(next_index[id], Transform3D(Basis.IDENTITY, position))
		next_index[id] += 1


func _renderer(block_id: int) -> MultiMeshInstance3D:
	if not _renderers.has(block_id):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = block_mesh(block_id)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)
		_renderers[block_id] = instance
	return _renderers[block_id]


## Mesh of a single block, built by ChunkMesher so it looks exactly like
## the block in the world (textures, tint, materials). Cached per type.
static func block_mesh(block_id: int) -> Mesh:
	if not _meshes.has(block_id):
		var data := ChunkData.new()
		data.set_block(0, 0, 0, block_id)
		var mesh := ArrayMesh.new()
		var surfaces := ChunkMesher.build(data)
		for layer: int in surfaces:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[layer])
			mesh.surface_set_material(mesh.get_surface_count() - 1, BlockMaterials.get_material(layer))
		_meshes[block_id] = mesh
	return _meshes[block_id]
