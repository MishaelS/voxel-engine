class_name Minecart
extends Entity
## Minecarts like Beta 1.7.3 (EntityMinecart):
## - on rails the cart follows the rail's line, turning onto the next rail
##   it rolls into; slopes speed it up downhill (0.0078 a tick); powered rails
##   push it on (0.06 a tick, or off a wall from standing), unpowered ones
##   brake; at most 0.4 blocks a tick; it slows by 0.96 a tick empty, 0.997
##   with a rider;
## - off rails it rolls and stops like any box;
## - the player walking into it pushes it; right-click gets in (or opens the
##   chest of a chest minecart, or feeds coal to a furnace minecart, which
##   then drives itself for 3600 ticks a piece the way the player faced);
##   while riding, walking forward gets a standing cart going;
## - hits break it after a few; it drops itself (and the chest's items).
## Kinds: "minecart", "chest_minecart", "furnace_minecart".

const MAX_SPEED := 0.4
const SLOPE := 0.0078125
const BOOST := 0.06
const FUEL_PER_COAL := 3600

var kind := "minecart"
var inventory: Inventory
var fuel := 0
var push := Vector2.ZERO # furnace cart: the way it drives

var _model := {}
var _cargo: MeshInstance3D
var _wear := 0.0
var _yaw := 0.0
var _rider_forward := 0.0
var _rider_look := Vector3.ZERO


static func create(type: String) -> Minecart:
	var cart := Minecart.new()
	cart.kind = type
	if type == "chest_minecart":
		cart.inventory = Inventory.new(VoxelWorld.CHEST_SIZE)
	return cart


func type_name() -> String:
	return kind


func _ready() -> void:
	half_width = 0.49
	height = 0.7
	max_health = 1000
	health = max_health
	_model = MobModels.build("minecart")
	add_child(_model.root)
	if kind != "minecart":
		# The chest or furnace riding in it.
		_cargo = MeshInstance3D.new()
		_cargo.mesh = FallingBlocks.block_mesh(Blocks.variant("chest" if kind == "chest_minecart" else "furnace"))
		_cargo.scale = Vector3.ONE * 0.75
		_cargo.position = Vector3(-0.375, 0.2, -0.375)
		_cargo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cargo)


func seat_height() -> float:
	return 0.3 # inside, on its floor


## The player riding it steers like the game: forward gets a standing cart
## going (called by Player each tick).
func steer(forward: float, look: Vector3) -> void:
	_rider_forward = forward
	_rider_look = look


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	if _wear > 0.0:
		_wear = maxf(_wear - 1.0, 0.0)
	var rail := _rail_cell(Vector3(_x, _y, _z))
	if rail.y != -1000:
		_on_rail(rail)
	else:
		_off_rail()
	_push_player()
	if kind == "minecart":
		take_creature(Vector2(velocity.x, velocity.z).length_squared() > 0.0004)
	if fuel > 0:
		fuel -= 1
		if randi_range(0, 3) == 0:
			world.particles.smoke(feet() + Vector3(0, 0.9, 0), 1)
	if _y < Player.VOID_Y:
		removed = true


## The rail the cart is on (at its feet, or just below them).
func _rail_cell(at: Vector3) -> Vector3i:
	var cell := Vector3i(at.floor())
	for dy in [0, -1]:
		if RailBehavior.is_rail(world.get_block(cell + Vector3i(0, dy, 0))):
			return cell + Vector3i(0, dy, 0)
	return Vector3i(0, -1000, 0)


func _on_rail(cell: Vector3i) -> void:
	var id := world.get_block(cell)
	var shape := RailBehavior.shape_of(id)
	var family := Blocks.family_of(id)
	var powered := family == "powered_rail" and RailBehavior.is_on(id)
	var braking := family == "powered_rail" and not powered
	var rise := RailBehavior.rising(shape)
	if rise != Vector3i.ZERO:
		velocity.x -= rise.x * SLOPE
		velocity.z -= rise.z * SLOPE
	var ends: Array = RailBehavior.ENDS[shape]
	var a: Vector3i = ends[0]
	var b: Vector3i = ends[1]
	var line := Vector2(b.x - a.x, b.z - a.z)
	var length := line.length()
	var motion := Vector2(velocity.x, velocity.z)
	if motion.dot(line) < 0.0:
		line = -line
	var speed := motion.length()
	motion = line / length * speed
	# A rider walking forward gets a standing cart going.
	if _rider_forward > 0.0 and speed < 0.01:
		motion += Vector2(_rider_look.x, _rider_look.z).normalized() * 0.1 * _rider_forward
	# Furnace carts drive themselves.
	if kind == "furnace_minecart" and fuel > 0 and push.length_squared() > 1e-4:
		var along := push.normalized()
		if along.dot(line) < 0.0:
			along = -line.normalized()
		else:
			along = line.normalized()
		motion = motion * 0.8 + along * 0.04
		push = along
	if braking:
		if motion.length() < 0.03:
			motion = Vector2.ZERO
		else:
			motion *= 0.5
	# Onto the rail's line.
	var start := Vector2(cell.x + 0.5 + a.x * 0.5, cell.z + 0.5 + a.z * 0.5)
	var finish := Vector2(cell.x + 0.5 + b.x * 0.5, cell.z + 0.5 + b.z * 0.5)
	var span := finish - start
	var here := Vector2(_x, _z)
	var t := clampf((here - start).dot(span) / span.length_squared(), 0.0, 1.0)
	here = start + span * t
	var step := motion
	step.x = clampf(step.x, -MAX_SPEED, MAX_SPEED)
	step.y = clampf(step.y, -MAX_SPEED, MAX_SPEED)
	var old_cell := Vector2i(floori(here.x), floori(here.y))
	here += step
	_x = here.x
	_z = here.y
	_y = _rail_height(cell, Vector3(_x, 0, _z))
	var new_cell := Vector2i(floori(_x), floori(_z))
	if new_cell != old_cell:
		# Into the next block: along the way it went (the rail there turns it).
		var moved := Vector2(new_cell - old_cell)
		motion = moved.normalized() * motion.length()
		var next := _rail_cell(Vector3(_x, _y + 0.5, _z))
		if next.y == -1000:
			next = _rail_cell(Vector3(_x, _y + 1.0, _z))
		if next.y != -1000:
			_y = _rail_height(next, Vector3(_x, 0, _z))
	if powered:
		var now := motion.length()
		if now > 0.01:
			motion += motion / now * BOOST
		elif shape == 1:
			if Redstone.is_solid(world.get_block(cell + Vector3i(-1, 0, 0))):
				motion.x = 0.02
			elif Redstone.is_solid(world.get_block(cell + Vector3i(1, 0, 0))):
				motion.x = -0.02
		elif shape == 0:
			if Redstone.is_solid(world.get_block(cell + Vector3i(0, 0, -1))):
				motion.y = 0.02
			elif Redstone.is_solid(world.get_block(cell + Vector3i(0, 0, 1))):
				motion.y = -0.02
	motion *= 0.997 if _ridden() else 0.96
	if motion.length() > MAX_SPEED:
		motion = motion.normalized() * MAX_SPEED
	velocity = Vector3(motion.x, 0.0, motion.y)
	on_ground = true
	if Blocks.family_of(world.get_block(Vector3i(floori(_x), floori(_y + 0.1), floori(_z)))) == "detector_rail":
		RailBehavior.cart_on(world, Vector3i(floori(_x), floori(_y + 0.1), floori(_z)))
	if Blocks.family_of(world.get_block(cell)) == "detector_rail":
		RailBehavior.cart_on(world, cell)
	if motion.length_squared() > 1e-6:
		_yaw = atan2(motion.x, motion.y)


## The height of the rail's top at a point (slopes rise across their block).
func _rail_height(cell: Vector3i, at: Vector3) -> float:
	var shape := RailBehavior.shape_of(world.get_block(cell))
	var rise := RailBehavior.rising(shape)
	if rise == Vector3i.ZERO:
		return float(cell.y)
	var local := Vector2(at.x - cell.x, at.z - cell.z)
	var progress := 0.0
	match rise:
		Vector3i(1, 0, 0):
			progress = local.x
		Vector3i(-1, 0, 0):
			progress = 1.0 - local.x
		Vector3i(0, 0, 1):
			progress = local.y
		_:
			progress = 1.0 - local.y
	return cell.y + clampf(progress, 0.0, 1.0)


func _off_rail() -> void:
	var motion := Vector2(velocity.x, velocity.z)
	if motion.length() > MAX_SPEED:
		motion = motion.normalized() * MAX_SPEED
	velocity.x = motion.x
	velocity.z = motion.y
	if in_water:
		velocity *= 0.8
	move(velocity)
	velocity.y -= 0.04
	velocity *= Vector3(0.5, 0.95, 0.5) if on_ground else Vector3(0.95, 0.95, 0.95)


func _ridden() -> bool:
	var player := world.player as Player
	return player != null and player.vehicle == self


## The player walking into the cart pushes it away.
func _push_player() -> void:
	var player := world.player as Player
	if player == null or player.dead or player.vehicle == self:
		return
	var away := Vector2(_x - player.global_position.x, _z - player.global_position.z)
	var gap := away.length()
	if gap > 0.8 or absf(player.global_position.y - _y) > 1.0 or gap < 1e-3:
		return
	var push_by := away / gap * (0.8 - gap) * 0.1
	velocity.x += push_by.x
	velocity.z += push_by.y


## Right-click: get in, open the chest, or feed coal to the furnace.
func interact(player: Player, item_id: int) -> bool:
	match kind:
		"chest_minecart":
			player.open_container({"type": "chest", "inventory": inventory})
			return true
		"furnace_minecart":
			var name := Items.name_of(item_id) if item_id != Blocks.AIR else ""
			if name == "coal" or name == "charcoal":
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				fuel += FUEL_PER_COAL
				push = Vector2(_x - player.global_position.x, _z - player.global_position.z)
				return true
			return false
	if player.vehicle == null and seat_free():
		player.mount(self)
		return true
	return false


## Hits wear it down; enough of them break it (it drops itself).
func damage(amount: int, from: Variant = null) -> bool:
	if removed:
		return false
	_wear += amount * 10.0
	hurt_ticks = 10
	if from is Vector3:
		var away := Vector2(_x - (from as Vector3).x, _z - (from as Vector3).z).normalized() * 0.1
		velocity.x += away.x
		velocity.z += away.y
	var player := world.player as Player
	if _wear > 40.0 or (player and player.is_creative()):
		_break()
	return true


func _break() -> void:
	removed = true
	if rider and is_instance_valid(rider):
		rider.vehicle = null
	var player := world.player as Player
	if player and player.vehicle == self:
		player.vehicle = null
	if player and player.is_creative():
		return
	world.items.spawn(Items.id_of("minecart"), 1, center(), Vector3(0, 0.2, 0))
	match kind:
		"chest_minecart":
			world.items.spawn(Blocks.variant("chest"), 1, center(), Vector3(0, 0.2, 0))
			for slot in inventory.size():
				if inventory.count_at(slot) > 0:
					world.items.scatter(center(), inventory.id_at(slot), inventory.count_at(slot), inventory.damage_at(slot))
		"furnace_minecart":
			world.items.spawn(Blocks.variant("furnace"), 1, center(), Vector3(0, 0.2, 0))


func _process(delta: float) -> void:
	super(delta)
	if _model.is_empty():
		return
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * 12.0, 1.0))
	# Tilted on slopes.
	var rise := _y - _prev.y
	var run := Vector2(_x - _prev.x, _z - _prev.z).length()
	var pitch := atan2(rise, run) if run > 1e-4 else 0.0
	_model.root.rotation.x = lerp_angle(_model.root.rotation.x, -pitch, minf(delta * 10.0, 1.0))
	var light := world.brightness_at(center()) if world else 1.0
	if _cargo:
		_cargo.set_instance_shader_parameter("entity_light", light) # the chest / furnace inside
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", light)
		mesh.set_instance_shader_parameter("hurt", 1.0 if hurt_ticks > 0 else 0.0)
	hurt_ticks = maxi(hurt_ticks - 1, 0) if Engine.get_process_frames() % 3 == 0 else hurt_ticks


func save_state() -> Dictionary:
	var state := super()
	state["fuel"] = fuel
	state["push"] = push
	if inventory:
		state["inventory"] = inventory.save_state()
	return state


func load_state(saved: Dictionary) -> void:
	super(saved)
	fuel = saved.get("fuel", 0)
	push = saved.get("push", Vector2.ZERO)
	if inventory and saved.has("inventory"):
		inventory.load_state(saved.inventory)
