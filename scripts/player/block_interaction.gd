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
##   not while sneaking), else use the item in hand: place a block (chests
##   and furnaces face the player), place a bed, fill / empty a bucket,
##   or eat (hold for 1.6 s). Holding repeats placing every 4 ticks.
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
## Ticks of eating, like the classic game (32).
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
## Survival breaking progress of `target` (0..1).
var break_progress := 0.0

var _outline: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_material: ShaderMaterial
var _breaking_pos := Vector3i(0, -1000, 0)
var _break_delay := 0.0 # ticks
var _place_delay := 0.0 # ticks
var _tick_time := 0.0
var _eating := -1.0 # ticks eaten, -1 = not eating
var _hit_ticks := 0
var _inventory_screen: InventoryScreen


func _ready() -> void:
	_outline = MeshInstance3D.new()
	_outline.mesh = _make_outline_mesh()
	_outline.visible = false
	add_child(_outline)
	_cracks = MeshInstance3D.new()
	_cracks.mesh = _make_crack_mesh()
	_cracks.visible = false
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cracks.scale = Vector3.ONE * (1.0 + CRACK_GROW)
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
	var hit: bool = target.get("hit", false)
	_outline.visible = hit and not player.sleeping
	if hit:
		_outline.global_position = Vector3(target.pos)
		# The outline follows the block's shape (slabs, torches, doors).
		var box: AABB = Blocks.selection_table[target.block]
		_outline.global_position = Vector3(target.pos) + box.position
		_outline.scale = box.size

	var ticks := delta / TICK
	_break_delay = maxf(_break_delay - ticks, 0.0)
	_place_delay = maxf(_place_delay - ticks, 0.0)
	var active := _captured() and not GameInput.is_blocked() and not player.dead and not player.sleeping
	if active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hit:
		_continue_breaking(target.pos, ticks)
	else:
		_stop_breaking()
	var using := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if using and _eating >= 0.0:
		_continue_eating(ticks)
	else:
		_stop_eating()
		if using and _place_delay <= 0.0:
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
				if target_entity and not player.dead and not player.sleeping:
					_attack(target_entity)
				elif target.get("hit", false) and Blocks.family_of(target.block) == "note_block":
					MusicBehavior.play_note(world, target.pos)
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
	player.swing()
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
		if sheared:
			world.items.drop_from_block(pos, Blocks.id_of(Blocks.get_type(id).name), 1)
		player.block_broken()
		if Items.durability(tool) > 0 and (hardness > 0.0 or Items.name_of(tool) == "shears"):
			player.inventory.wear(player.selected_slot, 2 if Items.get_type(tool).tool == "sword" else 1)
		_stop_breaking()
		_break_delay = BREAK_DELAY_TICKS
		return
	_cracks.visible = true
	_cracks.global_position = Vector3(pos) - Vector3.ONE * CRACK_GROW * 0.5
	_crack_material.set_shader_parameter("stage", CRACK_TILE + mini(int(break_progress * 10.0), 9))


func _stop_breaking() -> void:
	break_progress = 0.0
	_breaking_pos = Vector3i(0, -1000, 0)
	_cracks.visible = false


# --- Using -------------------------------------------------------------------------

## LMB on a creature: hits it with the item in hand, like the classic game.
func _attack(entity: Entity) -> void:
	player.swing()
	var tool := player.held_block()
	if not entity.damage(Items.attack_damage(tool), player.global_position):
		return
	if entity is Mob:
		(entity as Mob).hurt_by(player)
	var item := Items.get_type(tool)
	if item and Items.durability(tool) > 0 and not player.is_creative():
		player.inventory.wear(player.selected_slot, 1 if item.tool == "sword" else 2)


## RMB: the targeted block's own use first (unless sneaking), then the item.
func _use() -> void:
	if target_entity is Mob and (target_entity as Mob).interact(player, player.held_block()):
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
	if item.food > 0:
		if not player.can_eat(id):
			return
		if world.hunger:
			_eating = 0.0
		else:
			# Beta 1.7.3: eaten at once, heals right away.
			_finish_eating(id)
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
			_shoot_bow()
		"fishing_rod":
			_fish()
		"painting":
			if hit and Painting.hang(world, target.pos, target.normal):
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


## Crafting table, chest, furnace and bed react to RMB. Returns true if used.
func _use_block(pos: Vector3i, id: int) -> bool:
	if Blocks.family_of(id) == "dungeon_chest":
		DungeonBehavior.open_chest(world, pos)
		id = world.get_block(pos)
	var family := Blocks.family_of(id)
	match family:
		"crafting_table":
			_screen().open_crafting_table()
		"jukebox":
			return MusicBehavior.use_jukebox(world, pos, player, player.held_block())
		"note_block":
			MusicBehavior.tune(world, pos)
		"chest", "chest_left", "chest_right":
			var other: Variant = ChestBehavior.partner(world, pos)
			Sounds.play("chest/open", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, randf() * 0.1 + 0.9)
			if other == null:
				_screen().open_container(world.block_entity(pos))
			elif Blocks.chest_part_table[id] == ChestModel.Part.LEFT:
				_screen().open_large_chest(world.block_entity(pos), world.block_entity(other))
			else:
				_screen().open_large_chest(world.block_entity(other), world.block_entity(pos))
		"furnace", "furnace_lit":
			_screen().open_container(world.block_entity(pos))
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
	if not world.is_inside(pos) or Blocks.collides_table[world.get_block(pos)] == 1:
		return null
	return pos


func _place_block(id: int) -> void:
	var cell: Variant = _place_cell()
	if cell == null:
		return
	var pos: Vector3i = cell
	if Blocks.collides_table[id] == 1 and player.intersects_block(pos):
		return # not inside the player
	# Oriented blocks (chest, furnace) look at the player.
	var family := Blocks.family_of(id)
	if Blocks.family_ids(family).size() == 4 and Blocks.facing_table[id] >= 0:
		id = Blocks.variant(family, Blocks.facing_toward(player.look_direction()))
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
	if family.ends_with("_slab") and not family.begins_with("double_") and target.normal == Vector3i.UP \
			and Blocks.family_of(target.block) == family:
		# A slab on the same slab: a double slab.
		world.set_block(target.pos, Blocks.id_of("double_" + family))
		Sounds.play_block("place", id, Vector3(target.pos) + Vector3(0.5, 0.5, 0.5))
		player.swing()
		if not player.is_creative():
			player.inventory.take(player.selected_slot)
		return
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
	if block.placed_as != "":
		id = Blocks.id_of(block.placed_as) # placed leaves never decay
	if world.get_block(pos) != Blocks.AIR:
		world.destroy_block(pos, true, true, false) # a plant or liquid in the way
	if ChestBehavior.is_chest(id):
		ChestBehavior.place(world, pos, Blocks.facing_table[id]) # may join a large chest
	else:
		world.set_block(pos, id)
	Sounds.play_block("place", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	player.swing()
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


## A door stands on the clicked top face, its panel on the far side.
func _place_door(kind: String) -> void:
	if not target.get("hit", false) or target.normal != Vector3i.UP:
		return
	var pos: Vector3i = target.pos + Vector3i.UP
	var facing := (Blocks.facing_toward(player.look_direction()) + 2) % 4
	if player.intersects_block(pos) or player.intersects_block(pos + Vector3i.UP):
		return
	if DoorBehavior.place(world, pos, kind, facing):
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
func _shoot_bow() -> void:
	var arrow := Items.id_of("arrow")
	if not player.is_creative():
		var slot := player.inventory.find(arrow)
		if slot < 0:
			return
		player.inventory.take(slot)
		player.inventory.wear(player.selected_slot)
	var eye := player.eye_position()
	var look := player.look_direction()
	var shot := Arrow.shoot(world, eye + look * 0.3 - Vector3(0, 0.1, 0), eye + look * 10.0, 1.5, 1.0, player)
	shot.velocity = look * 1.5 + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075
	player.swing()


func _strike_flint() -> void:
	if target.get("hit", false) and Blocks.get_type(target.block).name == "tnt":
		player.swing()
		PrimedTnt.light(world, target.pos)
		if not player.is_creative():
			player.inventory.wear(player.selected_slot)
		return
	var cell: Variant = _place_cell()
	if cell == null:
		return
	player.swing()
	if FireBehavior.ignite(world, cell):
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


func _continue_eating(ticks: float) -> void:
	var id := player.held_block()
	var item := Items.get_type(id)
	if item == null or item.food <= 0:
		_stop_eating()
		return
	var before := int(_eating)
	_eating += ticks
	player.eating = _eating / EAT_TICKS
	# Crumbs every 4 ticks from the mouth.
	if int(_eating) / 4 != before / 4 and _eating > 6.0:
		var mouth := player.eye_position() + player.look_direction() * 0.4 - Vector3(0, 0.15, 0)
		world.particles.item_crumbs(id, mouth, player.look_direction())
		Sounds.play("random/eat", null, 0.5 + 0.5 * randi_range(0, 1), randf_range(0.8, 1.2))
	if _eating >= EAT_TICKS:
		_finish_eating(id)
		_stop_eating()
		_place_delay = PLACE_DELAY_TICKS * 2


## Eats the food in hand: its effect, one fewer, the bowl stays.
func _finish_eating(id: int) -> void:
	player.eat(id)
	Sounds.play("random/burp" if world.hunger else "random/eat", null, 0.5, randf_range(0.9, 1.0))
	player.swing()
	if player.is_creative():
		return
	player.inventory.take(player.selected_slot)
	var container := Items.get_type(id).container
	if container != "":
		if player.inventory.is_empty_slot(player.selected_slot):
			player.inventory.set_slot(player.selected_slot, Items.id_of(container), 1)
		elif player.inventory.add(Items.id_of(container), 1) > 0:
			player.throw_items(Items.id_of(container), 1)


func _stop_eating() -> void:
	_eating = -1.0
	if player:
		player.eating = -1.0


# --- Meshes --------------------------------------------------------------------------

## The 12 edges of a block, slightly enlarged to avoid z-fighting.
static func _make_outline_mesh() -> ImmediateMesh:
	const E := 0.002
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(1.0 + E if i & 1 else -E, 1.0 + E if i & 2 else -E, 1.0 + E if i & 4 else -E))
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0, 0, 0, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for a in 8:
		for bit in [1, 2, 4]:
			if a & bit == 0:
				mesh.surface_add_vertex(corners[a])
				mesh.surface_add_vertex(corners[a | bit])
	mesh.surface_end()
	return mesh


## A block cube (the mesher's, so UVs are 0..1 per face) drawn with the
## crack texture multiplied over the block; the node is slightly enlarged.
func _make_crack_mesh() -> ArrayMesh:
	_crack_material = ShaderMaterial.new()
	_crack_material.shader = preload("res://shaders/block_cracks.gdshader")
	_crack_material.set_shader_parameter("tiles",
		BlockMaterials.tiles())
	return ChunkMesher.block_mesh(Blocks.id_of("stone"), _crack_material)
