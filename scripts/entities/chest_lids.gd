class_name ChestLids
extends Node3D
## Chest lids opening and closing like the modern game's (ChestBlockEntity)
## on Beta's full-cube chests: while anyone has a chest open its lid swings
## back about the back top edge, eased, to 90 degrees in 0.5 s, and swings
## shut the same way when the last one closes it; the opening sound plays
## as it starts to open, the closing one as it shuts. A large chest's
## halves open together as one lid.
##
## While its lid moves the chest is drawn here (ChestModel.lid_meshes: the
## chunk mesher's own cube of it, cut in two, so it looks just like the
## block) and the chunk meshes leave it out (VoxelWorld.hide_chest); the
## block itself never changes, so a world saved with a chest open has it
## closed.
##
## Who has a chest open: this player's windows (hold), the host's clients
## (Net.viewed_chests) and, on a client, what the host says is open
## (set_remote: Net sends it).

const OPEN_SECONDS := 0.5
const OPEN_ANGLE := PI / 2.0
## A shut chest's model stays this long after the block is drawn again,
## until the chunk's new mesh is up (built in the background).
const KEEP_SECONDS := 0.15

var world: VoxelWorld
var _held := {}   # Vector3i -> number of this player's windows holding it open
var _remote := {} # Vector3i -> true: open on the host (a network client)
var _lids := {}   # Vector3i -> Lid
var _screen: InventoryScreen # the window holding chests open


class Lid:
	var id := -1
	var node: Node3D
	var base: MeshInstance3D
	var hinge: Node3D
	var axis: Vector3
	var top: MeshInstance3D
	## 0 shut .. 1 open, 0.1 a tick like the game's.
	var openness := 0.0
	var open := false


## This player's window on `cells` (a chest, or a large chest's halves)
## holds their lids open until `screen` closes.
func hold(cells: Array, screen: InventoryScreen) -> void:
	for cell: Vector3i in cells:
		_held[cell] = int(_held.get(cell, 0)) + 1
	screen.chest_lid = true
	_screen = screen
	screen.closed.connect(_release.bind(cells), CONNECT_ONE_SHOT)


func _release(cells: Array) -> void:
	for cell: Vector3i in cells:
		var count := int(_held.get(cell, 0)) - 1
		if count > 0:
			_held[cell] = count
		else:
			_held.erase(cell)


## Client: the chests open on the host (Net).
func set_remote(cells: Array) -> void:
	_remote.clear()
	for cell: Vector3i in cells:
		_remote[cell] = true


## The chests open now (both halves of a large one), for the host to send.
func open_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	cells.assign(_wanted().keys())
	cells.sort()
	return cells


func clear() -> void:
	for lid: Lid in _lids.values():
		lid.node.queue_free()
	_lids.clear()
	_held.clear()
	_remote.clear()


func _wanted() -> Dictionary:
	var cells := {}
	for source: Variant in [_held.keys(), _remote.keys(), Net.viewed_chests()]:
		for cell: Vector3i in source:
			if ChestBehavior.is_chest(world.get_block(cell)):
				cells[cell] = true
				var other: Variant = ChestBehavior.partner(world, cell)
				if other != null:
					cells[other] = true
	return cells


func _process(delta: float) -> void:
	if _lids.is_empty() and _held.is_empty() and _remote.is_empty() and Net.viewed_chests().is_empty():
		return
	var wanted := _wanted()
	for cell: Vector3i in wanted:
		if not _lids.has(cell):
			_lids[cell] = _start(cell)
	for cell: Vector3i in _lids.keys():
		var lid: Lid = _lids[cell]
		var id := world.get_block(cell)
		if not ChestBehavior.is_chest(id):
			# Broken (or blown up) while open: gone with the block, and this
			# player's window on it shuts (its items dropped).
			if _held.has(cell) and is_instance_valid(_screen) and _screen.is_open():
				_screen.close()
			lid.node.queue_free()
			_lids.erase(cell)
			world.hide_chest(cell, false)
			continue
		if id != lid.id:
			_build(lid, cell, id) # became half of a large chest, or single again
		var open := wanted.has(cell)
		if open and not lid.open:
			_sound(cell, id, "chest/open")
		lid.open = open
		lid.openness = move_toward(lid.openness, 1.0 if open else 0.0, delta / OPEN_SECONDS)
		var eased := 1.0 - pow(1.0 - lid.openness, 3.0)
		lid.hinge.basis = Basis(lid.axis, eased * OPEN_ANGLE)
		if not open and lid.openness <= 0.0:
			_sound(cell, id, "chest/close")
			_lids.erase(cell)
			world.hide_chest(cell, false)
			var node := lid.node
			get_tree().create_timer(KEEP_SECONDS).timeout.connect(func() -> void:
				if is_instance_valid(node):
					node.queue_free())


func _start(cell: Vector3i) -> Lid:
	var lid := Lid.new()
	lid.node = Node3D.new()
	lid.base = MeshInstance3D.new()
	lid.hinge = Node3D.new()
	lid.top = MeshInstance3D.new()
	lid.node.add_child(lid.base)
	lid.node.add_child(lid.hinge)
	lid.hinge.add_child(lid.top)
	add_child(lid.node)
	lid.node.position = Vector3(cell)
	_build(lid, cell, world.get_block(cell))
	world.hide_chest(cell, true)
	return lid


func _build(lid: Lid, cell: Vector3i, id: int) -> void:
	lid.id = id
	var meshes := ChestModel.lid_meshes(world, cell, id)
	lid.base.mesh = meshes[0]
	lid.top.mesh = meshes[1]
	var hinge := ChestModel.hinge_of(id)
	lid.hinge.position = hinge[0]
	lid.top.position = -hinge[0]
	lid.axis = hinge[1]


## A chest's sound, once for a large chest (by its left half, from the
## middle of the two).
func _sound(cell: Vector3i, id: int, sound: String) -> void:
	var at := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var other: Variant = ChestBehavior.partner(world, cell)
	if other != null:
		if Blocks.chest_part_table[id] == ChestModel.Part.RIGHT:
			return
		at = (at + Vector3(other as Vector3i) + Vector3(0.5, 0.5, 0.5)) / 2.0
	Sounds.play(sound, at, 0.5, randf() * 0.1 + 0.9)
