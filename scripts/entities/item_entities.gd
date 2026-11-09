class_name ItemEntities
extends Node3D
## Dropped items like the classic game: what breaking a block gives, what
## the player throws (Q) or loses on death.
## - Blocks are drawn as small spinning cubes, items as flat pictures
##   facing the camera; bigger stacks show 2..4 copies. They bob up and
##   down and take the light where they lie.
## - Physics per game tick: gravity 0.04, drag 0.98, friction on the
##   ground, they float up in water and are pushed out of blocks.
## - The player picks them up when close (after a short delay: 10 ticks
##   for drops, 40 for thrown items); they fly to the player. Equal items
##   lying together merge into one stack. After 5 minutes they disappear.

const GRAVITY := 0.04
const DRAG := 0.98
const HALF := 0.125           # half size of the item's box
const PICKUP_DELAY := 10
const THROW_PICKUP_DELAY := 40
const LIFETIME := 6000        # ticks (5 minutes)
const PICKUP_TICKS := 3       # flying to the player
const MERGE_DISTANCE := 0.5
const BLOCK_SCALE := 0.25
const ITEM_SIZE := 0.5

var world: VoxelWorld
var player: Player

var _items: Array[Dictionary] = [] # {id, count, damage, pos, prev, vel, age, delay, node, ground, picked}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	TickLoop.add_listener(_tick, TickLoop.Phase.ENTITIES)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)


func count() -> int:
	return _items.size()


## Drops an item stack at `position` (its middle) with `velocity`.
func spawn(id: int, item_count: int, position: Vector3, velocity: Vector3 = Vector3.ZERO,
		pickup_delay: int = PICKUP_DELAY, damage: int = 0) -> void:
	if id == Blocks.AIR or item_count <= 0:
		return
	var item := {
		"id": id, "count": item_count, "damage": damage, "pos": position, "prev": position,
		"vel": velocity, "age": 0, "delay": pickup_delay, "ground": false, "picked": -1,
		"spin": _rng.randf() * TAU,
	}
	item.node = _make_node(item)
	_items.append(item)


## Drops what breaking a block gives, from the block's cell, like the classic
## game: a random spot inside the block and a small random push.
func drop_from_block(pos: Vector3i, id: int, item_count: int, damage: int = 0) -> void:
	var position := Vector3(pos) + Vector3(_rng.randf_range(0.15, 0.85), _rng.randf_range(0.15, 0.85), _rng.randf_range(0.15, 0.85))
	var velocity := Vector3(_rng.randf_range(-0.1, 0.1), 0.2, _rng.randf_range(-0.1, 0.1))
	spawn(id, item_count, position, velocity, PICKUP_DELAY, damage)


## Throws an item from the player's eyes along the look direction (Q).
func throw_from(eye: Vector3, look: Vector3, id: int, item_count: int, damage: int = 0) -> void:
	var velocity := look * 0.3 + Vector3(_rng.randf_range(-0.02, 0.02), 0.1, _rng.randf_range(-0.02, 0.02))
	spawn(id, item_count, eye - Vector3(0, 0.3, 0), velocity, THROW_PICKUP_DELAY, damage)


## Scatters items around a point (the player's death, a broken chest).
func scatter(position: Vector3, id: int, item_count: int, damage: int = 0) -> void:
	var angle := _rng.randf() * TAU
	var speed := _rng.randf() * 0.5
	var velocity := Vector3(-sin(angle) * speed, 0.2, cos(angle) * speed) * 0.4
	spawn(id, item_count, position, velocity, THROW_PICKUP_DELAY, damage)


func clear() -> void:
	for item in _items:
		(item.node as Node).queue_free()
	_items.clear()


## For the save: [[id, count, damage, position, age], ...].
func save_state() -> Array:
	var result := []
	for item in _items:
		if item.picked < 0:
			result.append([item.id, item.count, item.damage, item.pos, item.age])
	return result


func load_state(saved: Array) -> void:
	for entry: Array in saved:
		if entry.size() >= 5 and Items.exists(entry[0]):
			spawn(entry[0], entry[1], entry[3], Vector3.ZERO, 0, entry[2])
			_items.back().age = entry[4]


# --- Simulation --------------------------------------------------------------------

func _tick(tick_index: int) -> void:
	var i := 0
	while i < _items.size():
		var item := _items[i]
		item.prev = item.pos
		item.age += 1
		if item.picked >= 0:
			item.picked += 1
			if item.picked >= PICKUP_TICKS:
				(item.node as Node).queue_free()
				_items.remove_at(i)
				continue
		elif item.age >= LIFETIME or (item.pos as Vector3).y < Player.VOID_Y:
			(item.node as Node).queue_free()
			_items.remove_at(i)
			continue
		elif world and _in_lava(item.pos):
			# Items burn up in lava.
			world.particles.smoke(item.pos, 4)
			(item.node as Node).queue_free()
			_items.remove_at(i)
			continue
		else:
			_physics(item)
			item.delay = maxi(item.delay - 1, 0)
			_try_pickup(item)
		i += 1
	if tick_index % 10 == 0:
		_merge()


func _physics(item: Dictionary) -> void:
	if world == null or not world.is_inside(Vector3i((item.pos as Vector3).floor())):
		return # the ground is not loaded: wait
	var velocity: Vector3 = item.vel
	var position: Vector3 = item.pos
	if _box_blocked(position):
		# Inside a block: pushed out upward.
		position.y += 0.1
		velocity = Vector3.ZERO
	elif _in_water(position):
		velocity.y = velocity.y * 0.8 + 0.01 # floats up slowly
		velocity.x *= 0.9
		velocity.z *= 0.9
		# Carried along by the current, like the classic game.
		var flow := LiquidBehavior.flow_vector(world, Vector3i(position.floor()))
		if flow.length_squared() > 1e-6:
			velocity += flow.normalized() * 0.014
	else:
		velocity.y -= GRAVITY
	var on_ground := false
	for axis in [1, 0, 2]:
		var next := position
		next[axis] += velocity[axis]
		if _box_blocked(next):
			if axis == 1 and velocity.y < 0.0:
				on_ground = true
				# Rest on the block's top (beds are lower).
				var cell := Vector3i(floori(position.x), floori(next.y - HALF), floori(position.z))
				var top := cell.y + Blocks.height_table[world.get_block(cell)]
				if top <= position.y - HALF + 1e-3:
					position.y = top + HALF
			velocity[axis] = 0.0
		else:
			position = next
	velocity *= DRAG
	if on_ground:
		velocity.x *= 0.6
		velocity.z *= 0.6
		velocity.y *= -0.5
	item.vel = velocity
	item.pos = position
	item.ground = on_ground


func _box_blocked(center: Vector3) -> bool:
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1),
			Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1)]:
		var point: Vector3 = center + corner * (HALF - 0.001)
		var cell := Vector3i(point.floor())
		var id := world.get_block(cell)
		if Blocks.collides_table[id] == 1 and point.y - cell.y < Blocks.height_table[id]:
			return true
	return false


func _in_water(center: Vector3) -> bool:
	var id := world.get_block(Vector3i(center.floor()))
	return Blocks.liquid_table[id] == 1 and Blocks.family_of(id) == "water"


func _in_lava(center: Vector3) -> bool:
	var id := world.get_block(Vector3i(center.floor()))
	return Blocks.liquid_table[id] == 1 and Blocks.family_of(id) == "lava"


func _try_pickup(item: Dictionary) -> void:
	if player == null or player.dead or item.delay > 0:
		return
	var feet := player.global_position
	var position: Vector3 = item.pos
	# The player's box grown by 1 block sideways (like the classic game).
	if absf(position.x - feet.x) > Player.HALF_WIDTH + 1.0 + HALF \
			or absf(position.z - feet.z) > Player.HALF_WIDTH + 1.0 + HALF \
			or position.y + HALF < feet.y - 0.5 or position.y - HALF > feet.y + Player.HEIGHT + 0.5:
		return
	var room := player.inventory.room_for(item.id, item.damage)
	if room <= 0:
		return
	var taken := mini(room, item.count)
	player.inventory.add(item.id, taken, item.damage)
	item.count -= taken
	if item.count <= 0:
		item.picked = 0 # fly to the player, then disappear
	else:
		_update_copies(item)


## Equal stacks lying close together become one.
func _merge() -> void:
	for a in _items.size():
		var first := _items[a]
		if first.picked >= 0 or first.count <= 0:
			continue
		for b in range(a + 1, _items.size()):
			var second := _items[b]
			if second.picked >= 0 or second.count <= 0 or second.id != first.id or second.damage != first.damage:
				continue
			if (first.pos as Vector3).distance_squared_to(second.pos) > MERGE_DISTANCE * MERGE_DISTANCE:
				continue
			var stack := Items.max_stack(first.id)
			if first.count + second.count > stack:
				continue
			first.count += second.count
			first.delay = maxi(first.delay, second.delay)
			first.age = mini(first.age, second.age)
			second.count = 0
			second.age = LIFETIME # removed on the next tick
			_update_copies(first)


# --- Drawing ------------------------------------------------------------------------

func _make_node(item: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	item.node = node
	_update_copies(item)
	node.position = item.pos
	return node


## 1 copy, 2 for more than 1, 3 for more than 5, 4 for more than 20.
func _update_copies(item: Dictionary) -> void:
	var node: Node3D = item.node
	var wanted := 1 + int(item.count > 1) + int(item.count > 5) + int(item.count > 20)
	if node.get_child_count() == wanted:
		return
	for child in node.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item.spin)
	for copy in wanted:
		var offset := Vector3.ZERO if copy == 0 else Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
		if Items.is_block(item.id):
			var mesh := MeshInstance3D.new()
			mesh.mesh = FallingBlocks.block_mesh(item.id)
			mesh.scale = Vector3.ONE * BLOCK_SCALE
			mesh.position = offset - Vector3.ONE * BLOCK_SCALE * 0.5
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var pivot := Node3D.new()
			pivot.add_child(mesh)
			node.add_child(pivot)
		else:
			var sprite := Sprite3D.new()
			sprite.texture = Items.icon(item.id)
			sprite.pixel_size = ITEM_SIZE / 16.0
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sprite.shaded = false
			sprite.position = offset + Vector3(0, ITEM_SIZE * 0.5 - HALF, 0)
			node.add_child(sprite)


func _process(_delta: float) -> void:
	var alpha := TickLoop.alpha
	var time := Time.get_ticks_msec() / 1000.0
	var atmosphere := Atmosphere.find(get_tree())
	for item in _items:
		var node: Node3D = item.node
		var position: Vector3 = (item.prev as Vector3).lerp(item.pos, alpha)
		if item.picked >= 0 and player:
			# Flying into the player.
			var t := clampf((item.picked + alpha) / PICKUP_TICKS, 0.0, 1.0)
			position = position.lerp(player.global_position + Vector3(0, 0.8, 0), t)
		var age := float(item.age) + alpha
		var bob := sin(age / 10.0 + item.spin) * 0.1 + 0.1
		node.position = position + Vector3(0, bob, 0)
		var spin: float = age / 20.0 + item.spin
		var brightness := _brightness(position, atmosphere)
		for child in node.get_children():
			if child is Sprite3D:
				(child as Sprite3D).modulate = Color(brightness, brightness, brightness)
			else:
				(child as Node3D).rotation.y = spin


func _brightness(point: Vector3, atmosphere: Atmosphere) -> float:
	var light := world.get_light(Vector3i(point.floor())) if world else SkyLight.MAX
	if atmosphere == null:
		return ChunkMesher.LIGHT_BRIGHTNESS[light]
	var level := clampi(roundi(light - atmosphere.sky_darkness), 0, SkyLight.MAX)
	var brightness := ChunkMesher.LIGHT_BRIGHTNESS[level]
	if atmosphere.sky_darkness <= 0.0:
		brightness *= 0.25 + 0.75 * atmosphere.daylight
	return brightness
