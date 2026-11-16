class_name BlockInteraction
extends Node3D
## What the player does with blocks and items (with the mouse captured),
## like the classic game:
## - LMB: break the targeted block. Creative: instantly (holding repeats
##   every 5 ticks). Survival: hold it until the block breaks; cracks show
##   the progress and bits chip off. Speed: the right tool's speed (wood 2,
##   stone 4, iron 6, diamond 8, gold 12) / hardness / 30 per tick, or
##   / 100 when the block needs a better tool, which then drops nothing
##   (stone and ores need a pickaxe, iron ore a stone one, diamonds an
##   iron one). Tools wear out. Drops fall out as items.
## - RMB: use the targeted block (crafting table, chest, furnace, bed;
##   not while sneaking), else use the item in hand: place a block (turned
##   like the modern game, see _place_block), place a bed, fill / empty a
##   bucket, or eat (hold for 1.6 s). Holding repeats placing every 4 ticks.
##   RMB on a mob uses it (shear or dye a sheep, milk a cow, tame a wolf);
##   a bow shoots an arrow, a sword's weapons hit (Items.attack_damage).
## - LMB on a creature (closer than the block) hits it: knockback, swords
##   wear by 1, tools by 2. Shears cut leaves and cobwebs, leaves drop.
## - MMB: pick the targeted block (see Hotbar.pick).
## - Q: throw one item from the hand (Ctrl+Q: the whole stack).
## - 1-9 and the mouse wheel choose the hotbar slot.
## The targeted block gets a thin black outline.

const TICK := 1.0 / 20.0
const BREAK_DELAY_TICKS := 5
const PLACE_DELAY_TICKS := 4
## Breaking speed: progress per tick = speed / hardness / 30 (or / 100
## without the right tool).
const HAND_BREAK_FACTOR := 30.0
const WRONG_TOOL_FACTOR := 100.0
## Ticks of eating, like the modern game (32: Beta ate at once).
const EAT_TICKS := 32
## Atlas tiles of the 10 crack stages.
const CRACK_TILE := 240
## Cracks are drawn on a slightly bigger cube to stay above the block.
const CRACK_GROW := 0.004

@export var player: Player
@export var world: VoxelWorld
@export var hotbar: Hotbar

## Current raycast result (see VoxelWorld.raycast), read by the debug screen.
var target := {}
## The creature under the crosshair (closer than `target`), or null.
var target_entity: Entity
## Another player aimed at (a network game), or null.
var target_player: RemotePlayer
## Survival breaking progress of `target` (0..1).
var break_progress := 0.0

var _outline: MeshInstance3D
var _outline_block := -1
var _cracks: MeshInstance3D
var _crack_material: ShaderMaterial
var _breaking_pos := Vector3i(0, -1000, 0)
var _break_delay := 0.0 # ticks
var _drawing := -1.0 # ticks the bow has been drawn, -1 = not drawing
var _eating := -1.0 # ticks eaten, -1 = not eating
## Ticks of a press under which an egg is thrown, not eaten (a tap throws,
## holding eats).
const TAP_TICKS := 4.0
var _place_delay := 0.0 # ticks
var _tick_time := 0.0
var _hit_ticks := 0
var _inventory_screen: InventoryScreen


func _ready() -> void:
	_outline = MeshInstance3D.new()
	_outline.visible = false
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	_cracks = MeshInstance3D.new()
	_cracks.mesh = _make_crack_mesh()
	_cracks.visible = false
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cracks)


func _process(delta: float) -> void:
	target = world.raycast(player.eye_position(), player.look_direction(), player.reach()) if player and world else {}
	target_entity = null
	if player and world and world.entities:
		var reach := player.reach() if not target.get("hit", false) else float(target.distance)
		var found := world.entities.raycast(player.eye_position(), player.look_direction(), reach)
		if not found.is_empty() and not (found[0] as Entity).is_dead():
			target_entity = found[0]
			target = {}
		# Other players (network games): aimed at like creatures.
		target_player = null
		var nearest := reach if found.is_empty() else float(found[1])
		var eye := player.eye_position()
		var to := eye + player.look_direction() * nearest
		for avatar: RemotePlayer in Net.avatars.values():
			if not is_instance_valid(avatar) or avatar.dead:
				continue
			var box := AABB(avatar.global_position - Vector3(0.4, 0, 0.4), Vector3(0.8, 1.9, 0.8))
			var point: Variant = box.intersects_segment(eye, to)
			if point != null and eye.distance_to(point) < nearest:
				nearest = eye.distance_to(point)
				target_player = avatar
				target_entity = null
				target = {}
	var hit: bool = target.get("hit", false)
	_outline.visible = hit and not player.sleeping
	if hit:
		# The outline follows the block's shape: each of its boxes (stairs),
		# or its selection box (slabs, plants, torches, doors).
		_outline.global_position = Vector3(target.pos)
		if target.block != _outline_block:
			_outline_block = target.block
			_outline.mesh = _outline_mesh(target.block)

	var ticks := delta / TICK
	_break_delay = maxf(_break_delay - ticks, 0.0)
	_place_delay = maxf(_place_delay - ticks, 0.0)
	var active := _captured() and not GameInput.is_blocked() and not player.dead and not player.sleeping
	if active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hit:
		_continue_breaking(target.pos, ticks)
	else:
		_stop_breaking()
	var using := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _drawing >= 0.0:
		if Items.name_of(player.held_block()) != "bow" or not active:
			_stop_drawing()
		elif using:
			_drawing += ticks
			player.bow_pull = _drawing
		else:
			_release_bow()
	elif _eating >= 0.0:
		if using:
			_continue_eating(ticks)
		else:
			# Let go too soon: not eaten (an egg tapped is thrown instead).
			var tapped := _eating < TAP_TICKS and THROWN.has(Items.name_of(player.held_block()))
			_stop_eating()
			if tapped:
				_throw_projectile()
	elif using and _place_delay <= 0.0:
		_use()
		_place_delay = PLACE_DELAY_TICKS


func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_blocked():
		return
	for i in Hotbar.SLOT_COUNT:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			hotbar.select(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("drop_item") and not player.dead:
		_throw_held(event is InputEventWithModifiers and (event.ctrl_pressed or event.meta_pressed))
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			hotbar.scroll(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if _captured():
				_break_delay = 0.0 # a fresh click breaks right away in creative
				if target_player and not player.dead and not player.sleeping:
					_attack_player(target_player)
				elif target_entity and not player.dead and not player.sleeping:
					_attack(target_entity)
				elif target.get("hit", false) and Blocks.family_of(target.block) == "note_block":
					MusicBehavior.play_note(world, target.pos)
					Stats.grant("musician")
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if _captured():
				_place_delay = 0.0
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			if _captured() and target.get("hit", false):
				hotbar.pick(target.block)
				get_viewport().set_input_as_handled()


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _throw_held(whole_stack: bool) -> void:
	var slot := player.selected_slot
	var inventory := player.inventory
	if inventory.is_empty_slot(slot):
		return
	var count := inventory.count_at(slot) if whole_stack else 1
	player.throw_items(inventory.id_at(slot), count, inventory.damage_at(slot))
	inventory.take(slot, count)
	player.swing()


# --- Breaking ---------------------------------------------------------------------

func _continue_breaking(pos: Vector3i, ticks: float) -> void:
	if _break_delay > 0.0:
		return
	player.swing(true)
	if player.is_creative():
		world.destroy_block(pos, false)
		_break_delay = BREAK_DELAY_TICKS
		return
	var id := world.get_block(pos)
	var hardness := Blocks.get_type(id).hardness
	if hardness < 0.0:
		_stop_breaking()
		return
	if pos != _breaking_pos:
		RedstoneOre.touch(world, pos)
		id = world.get_block(pos)
		_breaking_pos = pos
		break_progress = 0.0
		_tick_time = 0.0
	var tool := player.held_block()
	var can_harvest := Items.can_harvest(tool, id)
	var factor := HAND_BREAK_FACTOR if can_harvest else WRONG_TOOL_FACTOR
	break_progress += ticks * Items.break_speed(tool, id) / maxf(hardness * factor, 0.001)
	# Bits chip off the face every tick, a hit sound every 4 ticks.
	_tick_time += ticks
	while _tick_time >= 1.0:
		_tick_time -= 1.0
		_hit_ticks += 1
		world.particles.hit_block(pos, target.get("normal", Vector3i.UP), id)
		if _hit_ticks % 4 == 0:
			Sounds.play_block("hit", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if break_progress >= 1.0:
		var sheared := Items.name_of(tool) == "shears" and Blocks.get_type(id).name.ends_with("_leaves")
		if Blocks.get_type(id).name == "tnt":
			PrimedTnt.light(world, pos) # Beta: hitting TNT lights it
		else:
			world.destroy_block(pos, not sheared, can_harvest)
			Stats.add("mine." + Blocks.get_type(id).name)
		if sheared:
			world.items.drop_from_block(pos, Blocks.id_of(Blocks.get_type(id).name), 1)
		if Items.durability(tool) > 0 and (hardness > 0.0 or Items.name_of(tool) == "shears"):
			player.inventory.wear(player.selected_slot, 2 if Items.get_type(tool).tool == "sword" else 1)
		_stop_breaking()
		_break_delay = BREAK_DELAY_TICKS
		return
	_cracks.visible = true
	_cracks.mesh = _crack_mesh_for(world.get_block(pos))
	_cracks.global_position = Vector3(pos)
	_crack_material.set_shader_parameter("stage", CRACK_TILE + mini(int(break_progress * 10.0), 9))


func _stop_breaking() -> void:
	break_progress = 0.0
	_breaking_pos = Vector3i(0, -1000, 0)
	_cracks.visible = false


# --- Using -------------------------------------------------------------------------

## LMB on a creature: hits it with the item in hand, like the classic game.
## A hit on a creature. Like the game since Beta 1.8: hitting while falling
## is a critical hit (half again as hard, white stars); hurt hearts spill
## out, and a sword on the ground sweeps (its arc in front).
func _attack(entity: Entity) -> void:
	player.swing()
	var tool := player.held_block()
	var damage := Items.attack_damage(tool)
	var critical := player.velocity.y < 0.0 and not player.on_ground and not player.flying and not player.in_water
	if critical:
		damage += damage / 2 + (1 if damage % 2 == 1 else 0)
	if entity.puppet:
		# The host's creature (network game): the host hits it.
		Net.send_attack(entity.net_id, damage)
		world.particles.damage(entity.center() + Vector3(0, entity.height * 0.25, 0), damage)
		if critical:
			world.particles.crit(entity.center())
		return
	if not entity.damage(damage, player.global_position):
		return
	var middle := entity.center()
	world.particles.damage(middle + Vector3(0, entity.height * 0.25, 0), damage)
	if critical:
		world.particles.crit(middle)
	elif Items.name_of(tool).ends_with("_sword") and player.on_ground:
		var look := player.look_direction()
		world.particles.sweep(player.eye_position() + Vector3(look.x, 0, look.z).normalized() * 1.2 - Vector3(0, 0.4, 0))
	Stats.add("damage_dealt", damage)
	if entity is Mob and entity.is_dead():
		Stats.killed(entity)
	if entity is Mob:
		(entity as Mob).hurt_by(player)
	var item := Items.get_type(tool)
	if item and Items.durability(tool) > 0 and not player.is_creative():
		player.inventory.wear(player.selected_slot, 1 if item.tool == "sword" else 2)


## Hitting another player (network games): their player gets the damage.
func _attack_player(avatar: RemotePlayer) -> void:
	player.swing()
	var tool := player.held_block()
	var damage := Items.attack_damage(tool)
	var critical := player.velocity.y < 0.0 and not player.on_ground and not player.flying and not player.in_water
	if critical:
		damage += damage / 2 + (1 if damage % 2 == 1 else 0)
	avatar.damage(damage)
	avatar.knockback(player.global_position)
	world.particles.damage(avatar.global_position + Vector3(0, 1.3, 0), damage)
	if critical:
		world.particles.crit(avatar.global_position + Vector3(0, 1.0, 0))


## RMB: the targeted block's own use first (unless sneaking), then the item.
func _use() -> void:
	if target_entity and target_entity.puppet:
		# The host's entity (network game): get into its boat or minecart.
		if target_entity is Boat or (target_entity is Minecart and target_entity.type_name() == "minecart"):
			if player.vehicle == null:
				Net.send_mount(target_entity.net_id)
				player.swing()
		elif target_entity is Minecart and target_entity.type_name() == "chest_minecart":
			Net.open_cart_container(target_entity.net_id)
			player.swing()
		elif target_entity is Mob or (target_entity is Minecart and target_entity.type_name() == "furnace_minecart"):
			Net.send_interact(target_entity.net_id) # the host answers (Net._interacted)
		else:
			player.message.emit(Lang.t("Not in network games yet"))
		return
	if target_entity and target_entity.has_method("interact") and target_entity.call("interact", player, player.held_block()):
		player.swing()
		return
	var hit: bool = target.get("hit", false)
	if hit and not player.sneaking and _use_block(target.pos, target.block):
		player.swing()
		return
	var id := player.held_block()
	var item := Items.get_type(id)
	if item == null:
		if id != Blocks.AIR:
			_place_block(id)
		return
	if THROWN.has(item.name) and not player.can_eat(id):
		_throw_projectile() # snowballs; eggs when not hungry for one
		return
	if item.food > 0:
		if player.can_eat(id):
			# Held down for EAT_TICKS like the modern game (Beta 1.7.3 ate at
			# once): the food at the mouth, crumbs and chewing, then it heals.
			_eating = 0.0
			player.eating = 0.0
		return
	if item.places != "":
		_place_block(Blocks.id_of(item.places)) # sugar cane, seeds, cake
		return
	if item.tool == "hoe":
		if hit and target.normal != Vector3i.DOWN and FarmBehavior.till(world, target.pos):
			player.swing()
			if not player.is_creative():
				player.inventory.wear(player.selected_slot)
		return
	match item.name:
		"bucket":
			_fill_bucket()
		"water_bucket":
			_empty_bucket("water")
		"lava_bucket":
			_empty_bucket("lava")
		"bed":
			_place_bed()
		"flint_and_steel":
			_strike_flint()
		"bow":
			_start_drawing()
		"fishing_rod":
			_fish()
		"minecart", "chest_minecart", "furnace_minecart":
			if hit and RailBehavior.is_rail(target.block):
				var cart := Minecart.create(item.name)
				world.entities.spawn(cart, Vector3(target.pos) + Vector3(0.5, 0.0, 0.5))
				player.swing()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
		"boat":
			if Boat.place(world, player):
				player.swing()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
		"painting":
			if hit and Painting.hang(world, target.pos, target.normal):
				Stats.grant("artist")
				player.swing()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
		"bone_meal":
			if hit and FarmBehavior.bone_meal(world, target.pos):
				player.swing()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
		"wooden_door", "iron_door":
			_place_door(item.name.trim_suffix("_door"))
		"sign":
			_place_sign()


## Blocks a network client has the host use (Net.send_use): levers,
## buttons, repeaters, doors, trapdoors and note blocks.
const SHARED_USE: Array[String] = ["lever", "stone_button", "repeater", "trapdoor", "trapdoor_open", "note_block",
	"fence_gate", "fence_gate_open"]
## Containers a network client opens through the host (Net.open_container).
const CONTAINER_USE: Array[String] = ["chest", "chest_left", "chest_right", "furnace", "furnace_lit", "dispenser", "dungeon_chest"]
## The jukebox's record is the host's (Net.send_jukebox). Cakes and beds a
## client uses itself (the cake's block goes to the host; the night passes
## when everyone sleeps, Player._tick_sleep).
const HOST_ONLY_USE: Array[String] = ["jukebox"]


## The host does what a client's player used (Net._client_use).
static func use_shared(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if RedstoneComponents.use(world, pos, id):
		return
	var family := Blocks.family_of(id)
	if family == "trapdoor" or family == "trapdoor_open":
		var open := family == "trapdoor"
		world.set_block(pos, Blocks.variant("trapdoor_open" if open else "trapdoor", Blocks.facing_table[id]))
		Sounds.play("door/" + ("open" if open else "close"), Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, randf() * 0.1 + 0.9)
	elif FenceBehavior.is_gate(id):
		FenceBehavior.toggle_gate(world, pos)
	elif family == "note_block":
		MusicBehavior.tune(world, pos)
	elif DoorBehavior.is_door(id) and DoorBehavior.parts(id)[0] == "wooden":
		DoorBehavior.toggle(world, pos)


## Crafting table, chest, furnace and bed react to RMB. Returns true if used.
func _use_block(pos: Vector3i, id: int) -> bool:
	if world.remote:
		var shared_family := Blocks.family_of(id)
		if shared_family in SHARED_USE or (DoorBehavior.is_door(id) and DoorBehavior.parts(id)[0] == "wooden"):
			Net.send_use(pos)
			return true
		if shared_family in CONTAINER_USE:
			if not ChestBehavior.blocked(world, pos):
				_open_remote_container(pos, id)
			return true
		if shared_family in HOST_ONLY_USE:
			Net.send_jukebox(pos)
			return true
	if RedstoneComponents.use(world, pos, id):
		return true
	if Blocks.family_of(id) == "dispenser":
		_screen().open_container(world.block_entity(pos))
		return true
	if Blocks.get_type(id).name == "redstone_ore":
		RedstoneOre.touch(world, pos)
		return false
	if ChestBehavior.blocked(world, pos):
		return true # (the click is used up, like Beta's)
	if Blocks.family_of(id) == "dungeon_chest":
		DungeonBehavior.open_chest(world, pos)
		Stats.grant("treasure")
		id = world.get_block(pos)
	var family := Blocks.family_of(id)
	match family:
		"crafting_table":
			_screen().open_crafting_table()
		"jukebox":
			return MusicBehavior.use_jukebox(world, pos, player, player.held_block())
		"note_block":
			MusicBehavior.tune(world, pos)
			Stats.grant("musician")
		"chest", "chest_left", "chest_right":
			var other: Variant = ChestBehavior.partner(world, pos)
			if other == null:
				_screen().open_container(world.block_entity(pos))
			elif Blocks.chest_part_table[id] == ChestModel.Part.LEFT:
				_screen().open_large_chest(world.block_entity(pos), world.block_entity(other))
			else:
				_screen().open_large_chest(world.block_entity(other), world.block_entity(pos))
			if _screen().is_open():
				Sounds.play("chest/open", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, randf() * 0.1 + 0.9)
		"furnace", "furnace_lit":
			_screen().open_container(world.block_entity(pos))
		"fence_gate", "fence_gate_open":
			# (swings away from the player: the facing they look at)
			var look := player.look_direction()
			var looking := (0 if look.z > 0.0 else 2) if absf(look.z) >= absf(look.x) else (3 if look.x > 0.0 else 1)
			FenceBehavior.toggle_gate(world, pos, looking)
		"trapdoor", "trapdoor_open":
			var open := family == "trapdoor"
			world.set_block(pos, Blocks.variant("trapdoor_open" if open else "trapdoor", Blocks.facing_table[id]))
			Sounds.play("door/" + ("open" if open else "close"), Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, randf() * 0.1 + 0.9)
		"cake":
			return FarmBehavior.eat_cake(world, pos, player)
		"bed_foot", "bed_head":
			var head := pos
			if family == "bed_foot":
				head += Blocks.FACING_DIRECTIONS[Blocks.facing_table[id]]
			player.sleep_in(head)
		_:
			if DoorBehavior.is_door(id) and DoorBehavior.parts(id)[0] == "wooden":
				return DoorBehavior.toggle(world, pos)
			return false
	return true


## A network client's chest, furnace or dispenser: the host sends what is
## inside and the window opens then (a large chest: left half first).
func _open_remote_container(pos: Vector3i, id: int) -> void:
	var family := Blocks.family_of(id)
	var positions: Array[Vector3i] = [pos]
	if family == "dungeon_chest":
		Stats.grant("treasure")
	elif family.begins_with("chest"):
		Sounds.play("chest/open", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, randf() * 0.1 + 0.9)
		var other: Variant = ChestBehavior.partner(world, pos)
		if other != null:
			positions.assign([pos, other] if Blocks.chest_part_table[id] == ChestModel.Part.LEFT else [other, pos])
	Net.open_container(positions)


func _screen() -> InventoryScreen:
	if _inventory_screen == null:
		_inventory_screen = get_tree().root.find_children("*", "InventoryScreen", true, false)[0]
	return _inventory_screen


## The cell a placed block goes to: next to the targeted face, or the
## targeted cell itself when it is water.
func _place_cell() -> Variant:
	if not target.get("hit", false):
		return null
	if Blocks.replaceable_table[target.block] == 1:
		return target.pos # plants are simply replaced
	if target.normal == Vector3i.ZERO:
		return null
	var pos: Vector3i = target.pos + target.normal
	if pos.y >= world.height:
		player.message.emit(Lang.t("Height limit for building is %d blocks") % world.height)
		return null
	if not world.is_inside(pos) or Blocks.collides_table[world.get_block(pos)] == 1 or FenceBehavior.is_gate(world.get_block(pos)):
		return null # (an open gate lets players through, not blocks)
	return pos


## Where the targeted block was hit (world units).
func _hit_point() -> Vector3:
	return player.eye_position() + player.look_direction().normalized() * float(target.get("distance", 0.0))


## Whether a block placed now takes the upper half of its cell (top slabs,
## upside-down stairs), like the modern game: against a ceiling, or against
## the upper half of a side.
func _upper_placement() -> bool:
	if Blocks.replaceable_table[target.block] == 1:
		return false
	var normal: Vector3i = target.normal
	if normal == Vector3i.DOWN:
		return true
	return normal.y == 0 and normal != Vector3i.ZERO and _hit_point().y - float(target.pos.y) > 0.5


## A slab put to the other half of the same slab makes a double slab, like
## the modern game: the open face of the slab clicked, or the cell it is in
## pointed into from a neighbor's face. Returns true if it did.
func _merge_slab(id: int) -> bool:
	var family := Blocks.family_of(id)
	if not family.ends_with("_slab") or family.begins_with("double_") or not target.get("hit", false):
		return false
	var halves: Array[int] = [Blocks.id_of(family), Blocks.id_of(family + "_top")]
	var pos: Vector3i = target.pos
	var normal: Vector3i = target.normal
	if not ((target.block == halves[0] and normal == Vector3i.UP) or (target.block == halves[1] and normal == Vector3i.DOWN)):
		pos = target.pos + normal
		if normal == Vector3i.ZERO or not world.get_block(pos) in halves or player.intersects_block(pos):
			return false
	world.set_block(pos, Blocks.id_of("double_" + family))
	Sounds.play_block("place", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	player.swing()
	if not player.is_creative():
		player.inventory.take(player.selected_slot)
	return true


func _place_block(id: int) -> void:
	if _merge_slab(id):
		return
	var cell: Variant = _place_cell()
	if cell == null:
		return
	var pos: Vector3i = cell
	if Blocks.collides_table[id] == 1 and player.intersects_block(pos):
		return # not inside the player
	# Oriented blocks (chest, furnace, pumpkins, stairs) look at the player.
	var family := Blocks.family_of(id)
	# (Stairs families also hold their corner shapes, StairsBehavior: placed
	# straight, the shape follows from the neighbors once placed.)
	if (Blocks.family_ids(family).size() == 4 or StairsBehavior.is_stairs(id)) and Blocks.facing_table[id] >= 0:
		id = Blocks.variant(family, Blocks.facing_toward(player.look_direction()))
	# Like the modern game: stairs and slabs against a ceiling or the upper
	# half of a side go upside down / on top; logs lie along the clicked
	# side's axis.
	if (family.ends_with("_stairs") or (family.ends_with("_slab") and not family.begins_with("double_"))) \
			and _upper_placement():
		id = Blocks.variant(family + "_top", maxi(Blocks.facing_table[id], 0)) # "oak_stairs_top", "stone_slab_top"
	if family.ends_with("_log") and Blocks.replaceable_table[target.block] == 0 and target.normal.y == 0:
		if target.normal.x != 0:
			id = Blocks.id_of(family + "_x")
		elif target.normal.z != 0:
			id = Blocks.id_of(family + "_z")
	var block := Blocks.get_type(id)
	if block.on_update == Callable(NatureBehavior, "on_update"):
		if not NatureBehavior.can_stay(world, pos, id):
			return # cactus on sand, sugar cane by water, mushrooms in the dark
	elif block.shape == BlockType.Shape.CROSS and not PlantBehavior.can_stay(id, world.get_block(pos + Vector3i.DOWN)):
		return # plants only on their ground
	if family == "torch":
		# On the floor, or on the wall that was clicked (leaning away from it).
		var normal: Vector3i = target.normal if Blocks.replaceable_table[target.block] == 0 else Vector3i.UP
		if normal == Vector3i.DOWN:
			return
		if normal == Vector3i.UP:
			if not TorchBehavior.can_hold(world, pos + Vector3i.DOWN):
				return
		else:
			if not TorchBehavior.can_hold(world, pos - normal):
				return
			id = Blocks.variant("wall_torch", Blocks.FACING_DIRECTIONS.find(normal))
	if family == "wheat_crop" and not FarmBehavior.is_farmland(world.get_block(pos + Vector3i.DOWN)):
		return # seeds only on farmland
	if family == "cake" and Blocks.is_opaque_table[world.get_block(pos + Vector3i.DOWN)] == 0:
		return
	if family == "ladder" or family == "trapdoor":
		# On the side of the clicked block, held by it.
		var side: Vector3i = target.normal
		if side.y != 0 or side == Vector3i.ZERO or not TorchBehavior.can_hold(world, pos - side):
			return
		id = Blocks.variant(family, Blocks.FACING_DIRECTIONS.find(side))
	# Redstone parts and pistons pick their state from where they go.
	var clicked: Vector3i = target.normal if target.get("hit", false) and Blocks.replaceable_table[target.block] == 0 else Vector3i.UP
	var redstone := RedstoneComponents.placement(world, family, pos, clicked, player.look_direction())
	if redstone == -1:
		return
	if redstone >= 0:
		id = redstone
	if family == "piston" or family == "sticky_piston":
		id = PistonBehavior.base_id(PistonBehavior.facing_for(player.look_direction()), false, family == "sticky_piston")
	if family == "dispenser":
		# Toward the player, or up / down when looked at steeply (modern game).
		var front := PistonBehavior.facing_for(player.look_direction())
		id = Blocks.variant(family, 4 if front == Vector3i.UP else (5 if front == Vector3i.DOWN else Blocks.FACING_DIRECTIONS.find(front)))
	if block.placed_as != "":
		id = Blocks.id_of(block.placed_as) # placed leaves never decay
	if world.get_block(pos) != Blocks.AIR:
		world.destroy_block(pos, true, true, false) # a plant or liquid in the way
	if RailBehavior.is_rail(id):
		if not Redstone.is_solid(world.get_block(pos + Vector3i.DOWN)):
			return
		RailBehavior.place(world, pos, Blocks.family_of(id)) # joins the rails around
	elif ChestBehavior.is_chest(id):
		ChestBehavior.place(world, pos, Blocks.facing_table[id]) # may join a large chest
	else:
		world.set_block(pos, id)
	Sounds.play_block("place", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	player.swing()
	Stats.add("use." + Items.name_of(player.held_block()))
	if not player.is_creative():
		player.inventory.take(player.selected_slot)


## A bed takes two cells on solid ground, the head away from the player.
func _place_bed() -> void:
	if not target.get("hit", false) or target.normal != Vector3i.UP:
		return
	var look := player.look_direction()
	var facing := 2 # north
	if absf(look.x) > absf(look.z):
		facing = 3 if look.x > 0.0 else 1
	elif look.z > 0.0:
		facing = 0
	var foot: Vector3i = target.pos + Vector3i.UP
	var head: Vector3i = foot + Blocks.FACING_DIRECTIONS[facing]
	for cell: Vector3i in [foot, head]:
		var below := world.get_block(cell + Vector3i.DOWN)
		if not world.is_inside(cell) or Blocks.collides_table[world.get_block(cell)] == 1 \
				or Blocks.is_opaque_table[below] == 0 or player.intersects_block(cell):
			return
	world.set_block(foot, Blocks.variant("bed_foot", facing))
	world.set_block(head, Blocks.variant("bed_head", facing))
	Sounds.play_block("place", world.get_block(foot), Vector3(foot) + Vector3(0.5, 0.5, 0.5))
	player.swing()
	if not player.is_creative():
		player.inventory.take(player.selected_slot)


## A door stands in the cell in front of the clicked face (on solid ground),
## its panel on the edge of the half of the cell the cursor points at, hinged
## as DoorBehavior.hinge_flipped picks (the cursor's half of the cell when
## the neighbors don't decide).
func _place_door(kind: String) -> void:
	var cell: Variant = _place_cell()
	if cell == null:
		return
	var pos: Vector3i = cell
	var facing := Blocks.facing_toward(player.look_direction())
	if player.intersects_block(pos) or player.intersects_block(pos + Vector3i.UP):
		return
	var hit := _hit_point() - Vector3(pos)
	# The panel goes on the edge of the half of the cell the cursor points
	# at (split across the way the player looks): the far half puts it on
	# the far edge, the near half on the near one.
	var look := player.look_direction()
	var along := Vector2(signf(look.x), 0.0) if absf(look.x) > absf(look.z) else Vector2(0.0, signf(look.z))
	if (Vector2(hit.x, hit.z) - Vector2(0.5, 0.5)).dot(along) > 0.0:
		facing = (facing + 2) % 4
	if DoorBehavior.place(world, pos, kind, facing, Vector2(hit.x, hit.z)):
		Sounds.play_block("place", world.get_block(pos), Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		player.swing()
		if not player.is_creative():
			player.inventory.take(player.selected_slot)


## A sign post on a floor (facing the player, 16 directions) or a sign on
## the clicked wall; then its text is written.
func _place_sign() -> void:
	var cell: Variant = _place_cell()
	if cell == null:
		return
	var pos: Vector3i = cell
	var normal: Vector3i = target.normal
	var id := Blocks.AIR
	if normal == Vector3i.UP:
		if not TorchBehavior.can_hold(world, pos + Vector3i.DOWN):
			return
		# Toward the player, rounded to 1/16 of a turn.
		var look := player.look_direction()
		var angle := atan2(-look.x, -look.z) # where the sign's front points (toward the player)
		var rotation := posmod(roundi(-angle / deg_to_rad(22.5)), 16)
		id = Blocks.family_ids("sign")[rotation]
	elif normal != Vector3i.DOWN and normal != Vector3i.ZERO:
		if not TorchBehavior.can_hold(world, pos - normal):
			return
		id = Blocks.variant("wall_sign", Blocks.FACING_DIRECTIONS.find(normal))
	else:
		return
	world.set_block(pos, id)
	world.block_entity(pos)
	Sounds.play_block("place", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	player.swing()
	if not player.is_creative():
		player.inventory.take(player.selected_slot)
	_screen().get_parent().add_child(SignEditScreen.new(world, pos))


## Flint and steel lights a fire next to the clicked face (it wears out).
## The fishing rod: casts the bobber, or reels it in (a fish if one bites).
func _fish() -> void:
	player.swing()
	if player.fishing_bobber and not player.fishing_bobber.removed:
		var wear := player.fishing_bobber.reel_in()
		if wear > 0 and not player.is_creative():
			player.inventory.wear(player.selected_slot, wear)
	else:
		player.fishing_bobber = FishingBobber.cast(player)


## Beta bows shoot at once: an arrow from the inventory (free in creative).
## The bow like the game since Beta 1.8: hold the button to draw it (the
## string goes back in three steps, the view zooms in), let go to shoot;
## the longer it was drawn (full after a second), the faster and harder
## the arrow. A barely drawn bow doesn't shoot.
func _start_drawing() -> void:
	if not player.is_creative() and not Quiver.has_arrow(player.inventory):
		return
	_drawing = 0.0
	player.bow_pull = 0.0


## The game's bow power for `ticks` drawn: 0..1.
static func bow_power(ticks: float) -> float:
	var f := ticks / 20.0
	return minf((f * f + f * 2.0) / 3.0, 1.0)


func _release_bow() -> void:
	var power := bow_power(_drawing)
	_stop_drawing()
	_place_delay = PLACE_DELAY_TICKS
	if power < 0.1:
		return
	if not player.is_creative():
		if not Quiver.take_arrow(player.inventory): # (a quiver's first, then loose ones)
			return
		player.inventory.wear(player.selected_slot)
	var eye := player.eye_position()
	var look := player.look_direction()
	var shot := Arrow.shoot(world, eye + look * 0.3 - Vector3(0, 0.1, 0), eye + look * 10.0, 3.0 * power, 1.0, player)
	shot.velocity = look * 3.0 * power + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075
	shot.power = power


func _stop_drawing() -> void:
	_drawing = -1.0
	player.bow_pull = -1.0


func _strike_flint() -> void:
	if target.get("hit", false) and Blocks.get_type(target.block).name == "tnt":
		player.swing()
		PrimedTnt.light(world, target.pos)
		Stats.grant("lightItUp")
		if not player.is_creative():
			player.inventory.wear(player.selected_slot)
		return
	var cell: Variant = _place_cell()
	if cell == null:
		return
	player.swing()
	if FireBehavior.ignite(world, cell):
		Stats.grant("lightItUp")
		Sounds.play("fire/ignite", Vector3(cell) + Vector3(0.5, 0.5, 0.5), 1.0, randf_range(0.8, 1.2))
		if not player.is_creative():
			player.inventory.wear(player.selected_slot)


## An empty bucket scoops up a water or lava source.
func _fill_bucket() -> void:
	var hit := world.raycast(player.eye_position(), player.look_direction(), player.reach(), true)
	if not hit.get("hit", false) or Blocks.liquid_level_table[hit.block] != 0:
		return
	var filled := Items.id_of(Blocks.family_of(hit.block) + "_bucket")
	world.set_block(hit.pos, Blocks.AIR)
	player.swing()
	if player.is_creative():
		return
	var slot := player.selected_slot
	if player.inventory.count_at(slot) == 1:
		player.inventory.set_slot(slot, filled, 1)
	else:
		player.inventory.take(slot)
		var left := player.inventory.add(filled, 1)
		if left > 0:
			player.throw_items(filled, left)


## A filled bucket pours a source block out; the bucket stays.
func _empty_bucket(family: String) -> void:
	var cell: Variant = _place_cell()
	if cell == null:
		return
	if world.get_block(cell) != Blocks.AIR:
		world.destroy_block(cell, family == "water")
	world.set_block(cell, Blocks.id_of(family))
	player.swing()
	if not player.is_creative():
		player.inventory.set_slot(player.selected_slot, Items.id_of("bucket"), 1)


## Chewing: crumbs of the food from the mouth and a bite sound every 4
## ticks (the modern game's); eaten after EAT_TICKS. Another item in hand
## stops it.
func _continue_eating(ticks: float) -> void:
	var id := player.held_block()
	var item := Items.get_type(id)
	if item == null or item.food <= 0 or not player.can_eat(id):
		_stop_eating()
		return
	var before := int(_eating)
	_eating += ticks
	player.eating = _eating / EAT_TICKS
	if int(_eating) / 4 != before / 4 and _eating > 6.0:
		# Just in front of the mouth, below the middle of the view.
		var look := player.look_direction()
		var mouth := player.eye_position() + look * 0.6 - Vector3(0, 0.3 + randf() * 0.3, 0)
		world.particles.item_crumbs(id, mouth, look, 5, 0.5)
		Sounds.play("random/eat", null, 0.5 + 0.5 * randi_range(0, 1), randf_range(0.8, 1.2))
	if _eating >= EAT_TICKS:
		_finish_eating(id)
		_stop_eating()
		_place_delay = PLACE_DELAY_TICKS * 2


## Items thrown with RMB (Beta's snowballs and eggs): one a click, again
## every 4 ticks while held (eggs: a tap; holding eats one).
const THROWN := ["snowball", "egg"]


## Throws the snowball or egg in hand like Beta's: from the eyes a little
## below and aside, along the view (ThrownItem); one fewer.
func _throw_projectile() -> void:
	var id := player.held_block()
	var kind := Items.name_of(id)
	if not THROWN.has(kind) or player.inventory.count_at(player.selected_slot) <= 0:
		return
	var look := player.look_direction()
	var side := look.cross(Vector3.UP).normalized() if absf(look.y) < 0.99 else Vector3.RIGHT
	var from := player.eye_position() - Vector3(0, 0.1, 0) + side * 0.16 + look * 0.3
	ThrownItem.throw(world, kind, from - Vector3(0, 0.125, 0), look, player)
	player.swing()
	_place_delay = PLACE_DELAY_TICKS
	if not player.is_creative():
		player.inventory.take(player.selected_slot)


func _stop_eating() -> void:
	_eating = -1.0
	player.eating = -1.0


## Eats the food in hand: its effect, one fewer, the bowl stays.
func _finish_eating(id: int) -> void:
	player.eat(id)
	Sounds.play("random/burp", null, 0.5, randf_range(0.9, 1.0))
	if player.is_creative():
		return
	player.inventory.take(player.selected_slot)
	var container := Items.get_type(id).container
	if container != "":
		if player.inventory.is_empty_slot(player.selected_slot):
			player.inventory.set_slot(player.selected_slot, Items.id_of(container), 1)
		elif player.inventory.add(Items.id_of(container), 1) > 0:
			player.throw_items(Items.id_of(container), 1)


# --- Meshes --------------------------------------------------------------------------

static var _outline_material: ShaderMaterial
static var _outline_meshes := {} # block id -> ArrayMesh


## The outline of a block: the edges of its boxes taken together
## (_outline_edges; a little out of the faces, so they don't flicker into
## them), as screen-width lines (shaders/outline.gdshader).
static func _outline_mesh(id: int) -> ArrayMesh:
	if _outline_meshes.has(id):
		return _outline_meshes[id]
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = preload("res://shaders/outline.gdshader")
	var boxes: Array = Blocks.outline_table[id]
	var vertices := PackedVector3Array()
	var ends := PackedVector2Array()
	var others := PackedVector2Array()
	var indices := PackedInt32Array()
	for edge: Array in _outline_edges(boxes):
		var p: Vector3 = edge[0]
		var q: Vector3 = edge[1]
		var start := vertices.size()
		for corner: Array in [[p, q, -1.0], [p, q, 1.0], [q, p, 1.0], [q, p, -1.0]]:
			var at: Vector3 = corner[0]
			var other: Vector3 = corner[1]
			vertices.append(at)
			ends.append(Vector2(other.x, other.y))
			others.append(Vector2(other.z, corner[2]))
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = ends
	arrays[Mesh.ARRAY_TEX_UV2] = others
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _outline_material)
	mesh.custom_aabb = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(1.2, 1.7, 1.2))
	_outline_meshes[id] = mesh
	return mesh


## The edges of the solid that boxes make together, like the modern game's
## shape outlines: where boxes meet flat (a stairs' step on its slab, a
## fence bar on its post) no line is drawn. Worked out on the grid of the
## boxes' own coordinates: a grid line is an edge where the 4 cells around
## it are neither all alike nor two side by side (a flat face). Each edge
## [from, to] is pushed 0.002 out of the solid and made that much longer;
## a single box keeps its 12 edges.
static func _outline_edges(boxes: Array) -> Array:
	var lines: Array = [[], [], []] # per axis: the boxes' coordinates, sorted
	for box: AABB in boxes:
		for axis in 3:
			for v: float in [box.position[axis], box.end[axis]]:
				if not (lines[axis] as Array).any(func(known: float) -> bool: return absf(known - v) < 0.0001):
					lines[axis].append(v)
	for axis_lines: Array in lines:
		axis_lines.sort()
	var cells := Vector3i(lines[0].size() - 1, lines[1].size() - 1, lines[2].size() - 1)
	var solid := PackedByteArray()
	solid.resize(cells.x * cells.y * cells.z)
	for i in cells.x:
		for j in cells.y:
			for k in cells.z:
				var middle := Vector3((lines[0][i] + lines[0][i + 1]) * 0.5, (lines[1][j] + lines[1][j + 1]) * 0.5,
					(lines[2][k] + lines[2][k + 1]) * 0.5)
				for box: AABB in boxes:
					if box.has_point(middle):
						solid[(i * cells.y + j) * cells.z + k] = 1
						break
	var edges := []
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		for a in (lines[u] as Array).size():
			for b in (lines[w] as Array).size():
				var run_start := -1
				var run_push := Vector2.ZERO
				for i in cells[axis] + 1: # one past the end flushes the last run
					var push := Vector2.ZERO
					var edge := false
					if i < cells[axis]:
						var count := 0
						var sides := Vector2.ZERO # sum of the filled cells' sides
						for du in [-1, 0]:
							for dw in [-1, 0]:
								var cell := Vector3i.ZERO
								cell[axis] = i
								cell[u] = a + du
								cell[w] = b + dw
								if cell[u] < 0 or cell[w] < 0 or cell[u] >= cells[u] or cell[w] >= cells[w]:
									continue
								if solid[(cell.x * cells.y + cell.y) * cells.z + cell.z] == 1:
									count += 1
									sides += Vector2(du * 2 + 1, dw * 2 + 1)
						# Two filled cells side by side: a flat face (their sides sum
						# along one axis only); diagonal ones sum to zero: an edge.
						edge = count == 1 or count == 3 or (count == 2 and sides == Vector2.ZERO)
						push = -sides.sign() * 0.002
					if edge and run_start >= 0 and push == run_push:
						continue
					if run_start >= 0:
						var from := Vector3.ZERO
						from[axis] = lines[axis][run_start] - 0.002
						from[u] = lines[u][a] + run_push.x
						from[w] = lines[w][b] + run_push.y
						var to := from
						to[axis] = lines[axis][i] + 0.002
						edges.append([from, to])
					run_start = i if edge else -1
					run_push = push
	return edges


## The crack texture multiplied over a block, made on first use.
func _make_crack_mesh() -> ArrayMesh:
	_crack_material = ShaderMaterial.new()
	_crack_material.shader = preload("res://shaders/block_cracks.gdshader")
	_crack_material.set_shader_parameter("tiles",
		BlockMaterials.tiles())
	return _crack_mesh_for(Blocks.id_of("stone"))


## (This interaction's own: the meshes carry its _crack_material, so ones
## kept from an earlier world showed a material nobody updated any more,
## stuck on the first crack stage.)
var _crack_meshes := {} # block id -> ArrayMesh


## The cracks over a block's shape (its outline boxes: slabs, fences,
## torches, pistons...), a hair bigger. Like the game, each face shows the
## part of the crack picture its place in the block covers (texture
## coordinates from the position in the block), so the cracks keep their
## size on small faces instead of being squeezed into them.
func _crack_mesh_for(id: int) -> ArrayMesh:
	if _crack_meshes.has(id):
		return _crack_meshes[id]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for box: AABB in Blocks.outline_table[id]:
		var grown := box.grow(CRACK_GROW * 0.5)
		for face in 6:
			var start := vertices.size()
			for corner: Vector3 in ChunkMesher.FACE_CORNERS[face]:
				var p := grown.position + corner * grown.size
				vertices.append(p)
				var uv: Vector2
				match face:
					0, 1: uv = Vector2(p.x, p.z)       # top, bottom
					2, 3: uv = Vector2(p.z, 1.0 - p.y) # east, west
					_: uv = Vector2(p.x, 1.0 - p.y)    # south, north
				uvs.append(uv.clamp(Vector2.ZERO, Vector2.ONE))
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _crack_material)
	_crack_meshes[id] = mesh
	return mesh
