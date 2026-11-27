class_name Redstone
extends RefCounted
## Redstone power like Beta 1.7.3 (World.isBlockGettingPowered and friends):
## - a power source "weakly" powers a neighbor (the neighbor reacts: a door,
##   a lamp-like thing, wire) and may "strongly" power one, which makes that
##   block powered as a whole: everything next to a strongly powered solid
##   block gets power from it (a torch powers the block above it, a lever the
##   block it hangs on, a repeater the block in front, wire the block under
##   it and the block it points into);
## - a block is "getting power" (block_powered) when a neighbor strongly
##   powers it; something is "indirectly powered" (indirectly_powered) when a
##   neighbor provides power toward it - a source weakly, or a solid block
##   that is getting power;
## - redstone wire carries 15 levels, one less per block, up and down a
##   block like the game's, and doesn't power other wire through blocks;
##   its level is in the block's state (REDSTONE: power * 81 + shape).
## Changes spread through a queue (no deep recursion); after a component
## changes, its neighbors and their neighbors are told (notify_around), like
## the game.
## The components (torches, repeaters, levers, buttons, pressure plates) are
## in RedstoneComponents, pistons in PistonBehavior, dispensers in
## DispenserBehavior; doors, trapdoors, TNT and note blocks react through
## consumer_update().

const DIRS: Array[Vector3i] = [Vector3i.DOWN, Vector3i.UP, Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const HORIZONTAL: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]
const SHAPES := 81 ## 3 states (none, side, up) for each of the 4 sides

## While wire works out its own level it ignores power from other wire.
static var wires_provide_power := true
static var _queue: Array[Vector3i] = []
static var _queued := {}
static var _busy := false
## The handlers doors, trapdoors, TNT and note blocks had before redstone
## (family -> Callable), called first by consumer_update().
static var inner_updates := {}


# --- Kinds of blocks ----------------------------------------------------------------

## A full solid block (the game's "normal cube"): conducts power.
static func is_solid(id: int) -> bool:
	return id != Blocks.AIR and Blocks.is_opaque_table[id] == 1 and Blocks.collides_table[id] == 1 \
		and Blocks.shape_table[id] == BlockType.Shape.CUBE


static func is_wire(id: int) -> bool:
	return Blocks.family_of(id) == "redstone_wire"


static func wire_power(id: int) -> int:
	return Blocks.family_ids("redstone_wire").find(id) / SHAPES if is_wire(id) else 0


static func wire_id(power: int, shape: int) -> int:
	return Blocks.family_ids("redstone_wire")[power * SHAPES + shape]


## Wire connects to it from `direction` (wire, torches, levers, buttons,
## plates, and repeaters along their line).
static func connects(id: int, direction: Vector3i) -> bool:
	var family := Blocks.family_of(id)
	if family == "redstone_wire" or family in RedstoneComponents.SOURCES:
		return true
	if family == "repeater":
		var out := RedstoneComponents.repeater_out(id)
		return direction == out or direction == -out
	return false


# --- Power --------------------------------------------------------------------------

## Whether the block at pos weakly powers its neighbor at pos + toward.
static func weak(world: VoxelWorld, pos: Vector3i, toward: Vector3i) -> bool:
	var id := world.get_block(pos)
	if id == Blocks.AIR:
		return false
	if is_wire(id):
		return wires_provide_power and wire_power(id) > 0 and wire_points(world, pos, toward)
	return RedstoneComponents.weak(world, pos, id, toward)


## Whether the block at pos strongly powers the block at pos + toward.
static func strong(world: VoxelWorld, pos: Vector3i, toward: Vector3i) -> bool:
	var id := world.get_block(pos)
	if id == Blocks.AIR:
		return false
	if is_wire(id):
		return weak(world, pos, toward)
	return RedstoneComponents.strong(world, pos, id, toward)


## A block getting power: a neighbor strongly powers it.
static func block_powered(world: VoxelWorld, pos: Vector3i) -> bool:
	for d in DIRS:
		if strong(world, pos + d, -d):
			return true
	return false


## The block at pos gives power toward pos + toward (a source weakly, or a
## solid block that is getting power).
static func provides(world: VoxelWorld, pos: Vector3i, toward: Vector3i) -> bool:
	if is_solid(world.get_block(pos)):
		return block_powered(world, pos)
	return weak(world, pos, toward)


## Something at pos gets power from any side.
static func indirectly_powered(world: VoxelWorld, pos: Vector3i, except: Vector3i = Vector3i.ZERO) -> bool:
	for d in DIRS:
		if d != except and provides(world, pos + d, -d):
			return true
	return false


# --- Wire ---------------------------------------------------------------------------

## How the wire at pos meets side `direction`: 0 not, 1 along the ground (or
## down a block), 2 up the side of the block there.
static func wire_side(world: VoxelWorld, pos: Vector3i, direction: Vector3i) -> int:
	var side := pos + direction
	var side_id := world.get_block(side)
	if connects(side_id, direction):
		return 1
	if is_solid(side_id):
		if not is_solid(world.get_block(pos + Vector3i.UP)) and is_wire(world.get_block(side + Vector3i.UP)):
			return 2
	elif is_wire(world.get_block(side + Vector3i.DOWN)):
		return 1
	return 0


## The wire's shape (base 3 digits per side, HORIZONTAL order).
static func wire_shape(world: VoxelWorld, pos: Vector3i) -> int:
	var shape := 0
	var digit := 1
	for d in HORIZONTAL:
		shape += wire_side(world, pos, d) * digit
		digit *= 3
	return shape


## Whether wire powers the block toward `direction`: down always; sideways
## when it runs straight into it (or connects nowhere), like the game.
static func wire_points(world: VoxelWorld, pos: Vector3i, direction: Vector3i) -> bool:
	if direction == Vector3i.DOWN:
		return true
	if direction == Vector3i.UP:
		return false
	var sides := {}
	for d in HORIZONTAL:
		sides[d] = wire_side(world, pos, d) != 0
	if not sides.values().has(true):
		return true
	var across := Vector3i(direction.z, 0, direction.x)
	return sides[-direction] and not sides[across] and not sides[-across]


## Block update of a wire: works out its shape and level again.
static func on_wire_update(world: VoxelWorld, pos: Vector3i) -> void:
	if not is_wire(world.get_block(pos)):
		return
	if not is_solid(world.get_block(pos + Vector3i.DOWN)) and Blocks.get_type(world.get_block(pos + Vector3i.DOWN)).name != "glowstone":
		world.destroy_block(pos, true, true, false)
		return
	_enqueue(pos)
	if _busy:
		return
	_busy = true
	var steps := 0
	while not _queue.is_empty() and steps < 20000:
		steps += 1
		var at: Vector3i = _queue.pop_front()
		_queued.erase(at)
		_recalculate(world, at)
	_queue.clear()
	_queued.clear()
	_busy = false


static func _enqueue(pos: Vector3i) -> void:
	if not _queued.has(pos):
		_queued[pos] = true
		_queue.append(pos)


static func _recalculate(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_wire(id):
		return
	var old_power := wire_power(id)
	wires_provide_power = false
	var powered := indirectly_powered(world, pos)
	wires_provide_power = true
	var power := 0
	if powered:
		power = 15
	else:
		var best := 0
		var above_solid := is_solid(world.get_block(pos + Vector3i.UP))
		for d in HORIZONTAL:
			var side := pos + d
			best = maxi(best, wire_power(world.get_block(side)))
			if is_solid(world.get_block(side)):
				if not above_solid:
					best = maxi(best, wire_power(world.get_block(side + Vector3i.UP)))
			else:
				best = maxi(best, wire_power(world.get_block(side + Vector3i.DOWN)))
		power = maxi(best - 1, 0)
	var wanted := wire_id(power, wire_shape(world, pos))
	if wanted == id:
		return
	world.set_block(pos, wanted, false)
	if power == old_power:
		return # only the shape changed
	# The wire around (also a block up and down) follows; everything else
	# near hears about it.
	for d in DIRS:
		for at: Vector3i in [pos + d, pos + d + Vector3i.UP, pos + d + Vector3i.DOWN]:
			if is_wire(world.get_block(at)):
				_enqueue(at)
	notify_around(world, pos, true)


## Tells the neighbors of pos and their neighbors that something changed
## (wire only through the queue when `skip_wire`).
static func notify_around(world: VoxelWorld, pos: Vector3i, skip_wire: bool = false) -> void:
	var told := {}
	for d in DIRS:
		for at: Vector3i in [pos + d] + DIRS.map(func(e: Vector3i) -> Vector3i: return pos + d + e):
			if told.has(at) or at == pos:
				continue
			told[at] = true
			var id := world.get_block(at)
			if is_wire(id):
				if skip_wire or _busy:
					_enqueue(at)
					continue
			world._update_block(at)


# --- Things that react to power -------------------------------------------------------

## Whether `powered` changed at pos since last asked: +1 now powered, -1 not
## any more, 0 the same (the first time: 0).
static func edge(world: VoxelWorld, pos: Vector3i, powered: bool) -> int:
	var before: Variant = world.redstone_power.get(pos)
	world.redstone_power[pos] = powered
	if before == null or before == powered:
		return 0
	return 1 if powered else -1


## Block update of a door, trapdoor, TNT or note block: their own handling,
## then power: doors and trapdoors open while powered, TNT is lit, a note
## block plays when power arrives.
static func consumer_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var family := Blocks.family_of(id)
	var inner: Callable = inner_updates.get(family, Callable())
	if inner.is_valid():
		inner.call(world, pos)
		id = world.get_block(pos)
		if Blocks.family_of(id) != family:
			return
	var name := Blocks.get_type(id).name
	if name == "tnt":
		if indirectly_powered(world, pos):
			PrimedTnt.light(world, pos)
		return
	if family == "note_block":
		if edge(world, pos, indirectly_powered(world, pos)) > 0:
			MusicBehavior.play_note(world, pos)
		return
	if DoorBehavior.is_door(id):
		var info := DoorBehavior.parts(id)
		var lower: Vector3i = pos if info[1] == "lower" else pos + Vector3i.DOWN
		var powered := indirectly_powered(world, lower) or indirectly_powered(world, lower + Vector3i.UP)
		if edge(world, lower, powered) != 0 and DoorBehavior.parts(world.get_block(lower))[2] != powered:
			DoorBehavior.toggle(world, lower)
		return
	if family == "fence_gate" or family == "fence_gate_open":
		var gate_powered := indirectly_powered(world, pos)
		if edge(world, pos, gate_powered) != 0 and (family == "fence_gate_open") != gate_powered:
			FenceBehavior.toggle_gate(world, pos)
		return
	if TrapdoorBehavior.is_trapdoor(family):
		var powered := indirectly_powered(world, pos)
		if edge(world, pos, powered) != 0 and TrapdoorBehavior.is_open(family) != powered:
			world.set_block(pos, TrapdoorBehavior.with_open(id, powered), false)
			Sounds.play("door/" + ("open" if powered else "close"), Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, randf() * 0.1 + 0.9)
