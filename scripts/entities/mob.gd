class_name Mob
extends Entity
## Mobs like the classic game (Beta 1.7.3), all from one class driven by
## TYPES: the model (MobModels), size, health, speed, drops, sounds and the
## kind of behavior.
##
## Animals (pig, cow, sheep, chicken, wolf) wander about, look at the player
## now and then and run away when hurt. Sheep can be sheared and dyed and
## eat grass to grow their wool back; chickens lay eggs and flutter down;
## wolves are tamed with bones (then follow the player, sit on a click and
## fight what hurts the player). Squid swim in water.
## Monsters (zombie, skeleton, creeper, spider, slime) go after the player
## they can see within 16 blocks: zombies and spiders hit, skeletons shoot
## arrows from a distance, creepers swell up and explode, slimes jump at
## you and split when they die. Zombies and skeletons burn in daylight;
## spiders are calm in the light (above 11, the night taken off) unless hurt. Monsters far from the player
## disappear.
## All of them find their way on the block grid (Pathfinder: around walls
## and holes, up a block at a time, never into lava), walk with the entity
## physics like Beta's (walking pushes them, friction slows them, so a hit
## throws them back with a hop), turn smoothly, swim; the model swings its
## legs while walking, turns its head toward what it looks at, is tinted red
## like Beta's while hurt and falls over when it dies.
## Wolves are neutral like Beta's: a wild one turns on whoever hits it (and
## the pack around with it); a tame one follows its player, sits on a click
## and goes after what hurts the player or what the player hits.
## Some of modern's ways on top: hurt animals panic (run off away from the
## attacker for a while); animals follow a player holding their food, and
## fed they fall in love and breed (babies: small, big-headed, following a
## grown-up, growing up in a day); burning undead look for shade; monsters
## must see a player to notice it, and notice a sneaking one less far.

## type -> spec. speed: walking speed in blocks per tick; hostile: attacks
## the player; damage: per hit (Normal); drops: [item, min, max].
const TYPES := {
	"pig": {"health": 10, "speed": 0.09, "drops": [["porkchop", 1, 2]], "sound": "pig"},
	"cow": {"health": 10, "speed": 0.08, "drops": [["leather", 1, 2], ["raw_beef", 1, 3]], "sound": "cow"},
	"sheep": {"health": 10, "speed": 0.09, "drops": [], "sound": "sheep"},
	"chicken": {"health": 4, "speed": 0.09, "drops": [["feather", 1, 2], ["raw_chicken", 1, 1]], "sound": "chicken"},
	"wolf": {"health": 8, "speed": 0.12, "drops": [], "sound": "wolf"},
	"squid": {"health": 10, "speed": 0.04, "drops": [["ink_sac", 1, 3]], "sound": "", "water": true},
	"zombie": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["feather", 0, 2]], "sound": "zombie", "undead": true},
	"skeleton": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["bone", 0, 2], ["arrow", 0, 2]], "sound": "skeleton", "undead": true},
	"creeper": {"health": 20, "speed": 0.1, "hostile": true, "damage": 0, "drops": [["gunpowder", 0, 2]], "sound": "creeper"},
	"spider": {"health": 16, "speed": 0.13, "hostile": true, "damage": 2, "drops": [["string", 0, 2]], "sound": "spider"},
	"slime": {"health": 4, "speed": 0.1, "hostile": true, "damage": 1, "drops": [["slimeball", 0, 2]], "sound": "slime"},
}
## Meat a creature burnt to death drops cooked.
const COOKED := {"porkchop": "cooked_porkchop", "raw_beef": "cooked_beef", "raw_chicken": "cooked_chicken"}
## Shadow sizes of Beta's renderers (the rest 0.5); slimes' grow with them.
const SHADOW_SIZES := {"pig": 0.7, "cow": 0.7, "sheep": 0.7, "chicken": 0.3, "squid": 0.7, "spider": 1.0, "slime": 0.25}
const ANIMALS := ["pig", "cow", "sheep", "chicken"]
const MONSTERS := ["zombie", "skeleton", "creeper", "spider"]
const SIGHT := 16.0
const ATTACK_COOLDOWN := 20
const CREEPER_FUSE := 30
const CREEPER_POWER := 3.0
## A charged creeper's (struck by lightning, Beta's getPowered).
const CHARGED_CREEPER_POWER := 6.0
## Sheep wool colors (wool block names).
const WOOL_COLORS := ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
	"light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]
const WOOL_TINTS := {
	"white": Color(1, 1, 1), "orange": Color(0.92, 0.53, 0.25), "magenta": Color(0.7, 0.33, 0.8),
	"light_blue": Color(0.4, 0.55, 0.85), "yellow": Color(0.88, 0.85, 0.3), "lime": Color(0.45, 0.8, 0.25),
	"pink": Color(0.9, 0.55, 0.65), "gray": Color(0.3, 0.3, 0.3), "light_gray": Color(0.65, 0.65, 0.65),
	"cyan": Color(0.2, 0.5, 0.6), "purple": Color(0.5, 0.25, 0.7), "blue": Color(0.2, 0.25, 0.65),
	"brown": Color(0.4, 0.27, 0.15), "green": Color(0.25, 0.37, 0.15), "red": Color(0.65, 0.2, 0.2),
	"black": Color(0.1, 0.1, 0.1),
}

var mob_type := "pig"
var spec := {}
## Sheep: sheared, wool color; slime: size 1, 2 or 4; wolf: tamed, sitting.
var sheared := false
var wool_color := "white"
var size := 1
var tamed := false
var sitting := false
## Pigs: wearing a saddle (the player can ride them).
var saddled := false
## Stands still and lives on (the debug world's creatures, like the game's
## NoAI): no moving, attacking, burning, despawning or sounds.
var no_ai := false
## Beta's EntitySquid: its swim cycle (squidRotation, 0..2 pi, a stroke),
## the tentacles' spread, the speed of the push, its spin about itself and
## its lean (degrees, like Beta's), each with last tick's for drawing.
var _squid_cycle := 0.0
var _squid_cycle_speed := 0.0
var _squid_tentacles := 0.0
var _squid_prev_tentacles := 0.0
var _squid_speed := 0.0
var _squid_pitch := 0.0
var _squid_prev_pitch := 0.0
var _squid_heading := Vector3.ZERO
var angry := false

var target: Node3D
var _wander := Vector3.INF
var _panic := 0
var _attack_cooldown := 0
var _fuse := 0
var _prev_fuse := 0 # (last tick's: drawn in between)
var _look_at := Vector3.INF
var _look_ticks := 0
## Idle look-around: where the head turns (yaw, pitch) and when next.
var _idle_look := Vector2.ZERO
var _next_look := 0
var _jump := 0.0
var _fall := 0.0
var _squish := 0.0
var _was_on_ground := true
var _base_scale := 1.0 / 16.0
var _frame_delta := 0.0
var _limb_swing := 0.0
var _limb_amount := 0.0
var _prev_limb := 0.0
var _egg_timer := 0
var _was_wet := false
var _jump_timer := 0
var _say_timer := 0
var _model := {}
## The body's heading: set by the AI each tick, drawn between ticks.
var _yaw := 0.0
var _prev_yaw := 0.0
## Its path (Pathfinder) and where it leads.
var _path: Array[Vector3i] = []
var _path_goal := Vector3i.MAX
var _path_age := 0
var _stuck := 0
## A creeper struck by lightning (Beta's onStruckByLightning): it glows and
## blows up twice as hard.
var powered := false:
	set(value):
		if value != powered:
			powered = value
			_update_power()
var _power_shell: Array[MeshInstance3D] = []


## Lightning struck nearby (LightningBolt): a creeper is charged.
func struck_by_lightning() -> void:
	if mob_type == "creeper":
		powered = true


func _update_power() -> void:
	for mesh in _power_shell:
		mesh.queue_free()
	_power_shell.clear()
	if powered and not _model.is_empty():
		_power_shell = MobModels.power_shell(_model, MobModels.power_material())


## Who hurt it last (a creeper shot by a skeleton drops a disc) and from
## where (animals run away from there).
var _last_attacker: Node3D
var _flee_from := Vector3.INF

## Ticks between new paths to a moving goal.
const PATH_REFRESH := 30
## Paths are used beyond this distance; closer, it walks straight at it.
const PATH_FROM := 2.5
## Wolves: following the owner from this far, waiting closer than STAY.
const FOLLOW := 5.0
const STAY := 2.5
const TELEPORT := 12.0
## Wild wolves join a fight of their pack within this distance.
const PACK := 16.0
## Monsters notice a sneaking player from this share of SIGHT (modern's
## visibility); farther than NOTICE_BLIND they must see the player first.
const SNEAK_SIGHT := 0.8
## Right next to it (touching distance) a monster notices the player even
## without seeing it; farther it must see it (it noticed through walls from
## 3 blocks before).
const NOTICE_BLIND := 1.5
## A monster after a player it no longer sees makes for where it saw it
## last (it kept going after the player's real place before, through walls,
## as long as it was within 32): it gives up when it gets there and the
## player isn't to be seen, when it has no way there for FORGET_TICKS (5 s),
## and in any case after CHASE_MEMORY (15 s) without seeing it.
const FORGET_TICKS := 100
const CHASE_MEMORY := 300
## Nor does it follow farther than this.
const CHASE_RANGE := 24.0
## A chase's path search may look at this many cells (a longer way round a
## wall or a house than a walk's).
const CHASE_NODES := 700
## Hurt animals run (modern's PanicGoal) this long, this much faster.
const PANIC_TICKS := 100
const PANIC_SPEED := 1.5
## Burning undead look for shade (modern's FleeSunGoal): random spots this
## far (horizontal, vertical), now and then, and go there faster; a zombie
## fights on instead when its player is this close.
const SHADE_RANGE := Vector2i(10, 3)
const SHADE_TRIES := 10
const SHADE_SPEED := 1.3
const FIGHT_IN_SUN := 5.0
## Each animal's food (Release 1.0's: pigs ate wheat before carrots came):
## held, it draws them (TEMPT, stopping TEMPT_STOP away); fed, they breed.
const FOODS := {"cow": "wheat", "sheep": "wheat", "pig": "wheat", "chicken": "seeds"}
const TEMPT := 10.0
const TEMPT_STOP := 2.5
## Breeding like modern: in love this long, looking for a partner within
## LOVE_RANGE; together (BREED_CLOSE) for BREED_TICKS gives a baby, then
## both rest BREED_COOLDOWN. A baby grows up in GROW_TICKS (each feeding
## takes a tenth off), following a grown-up of its kind.
const LOVE_TICKS := 600
const LOVE_RANGE := 8.0
const BREED_CLOSE := 3.0
const BREED_TICKS := 60
const BREED_COOLDOWN := 6000
const GROW_TICKS := 24000
const PARENT_RANGE := 8.0
const PARENT_LOST := 16.0
## Babies: half the size, the head drawn this much bigger (modern's).
const BABY_SCALE := 0.5
const BABY_HEAD := 1.5

## Ticks left as a baby (0: grown up), in love, before it can breed again.
var baby_ticks := 0
var love_ticks := 0
var breed_cooldown := 0
var _partner: Mob
var _breed_timer := 0
var _parent: Mob
## Where a burning undead goes for shade (Vector3i.MAX: nowhere known),
## when it looks next; the fire it has from the sun (put out in shade).
var _shade := Vector3i.MAX
var _shade_timer := 0
var _sunburn := false
## How long it has been going to its panic or wander spot.
var _goal_age := 0


static func create(type: String) -> Mob:
	var mob := Mob.new()
	mob.mob_type = type
	return mob


## A spawned sheep's wool like the classic game: mostly white, some gray,
## light gray, black and brown, pink very rarely.
static func natural_wool() -> String:
	var roll := randi_range(0, 99)
	if roll < 5:
		return "black"
	if roll < 10:
		return "gray"
	if roll < 15:
		return "light_gray"
	if roll < 18:
		return "brown"
	return "pink" if randi_range(0, 499) == 0 else "white"


func type_name() -> String:
	return mob_type


## The undead (zombies, skeletons) fear the sun: they catch fire in
## daylight under the open sky, like the game's.
func sound_category() -> String:
	return "hostile" if is_hostile() else "friendly"


## Creatures walking make footstep sounds like Beta's (squids swim).
func makes_steps() -> bool:
	return not spec.get("water", false) and not puppet


func is_undead() -> bool:
	return spec.get("undead", false)


func is_hostile() -> bool:
	return spec.get("hostile", false) and not (mob_type == "wolf")


var _held: MeshInstance3D
## Worn armor (zombies and skeletons: Mob.equip), helmet first; worn out by
## hits like the player's.
var armor := Inventory.new(4)
var _armor_meshes: Array[MeshInstance3D] = []
var _armor_remainder := 0
## What it holds in its right hand (a skeleton's bow, a weapon a zombie
## picked up).
var hand := Inventory.new(1)
## Picked up from the ground (armor slots 0..3, the hand 4): always dropped
## when it dies (what it spawned with: 8.5%).
var _picked := PackedByteArray([0, 0, 0, 0, 0])
## Picked something up: it no longer despawns (like the modern game's).
var persistent := false
## How far its arms are raised (0 at rest .. 1 after someone).
var _aim := 0.0
## Aiming on the host (a network client's copy: from its snapshots).
var _aiming := false
var _held_shown := -1
var _held_rest := Transform3D.IDENTITY
var _held_aim := Transform3D.IDENTITY


func _ready() -> void:
	spec = TYPES[mob_type]
	step_height = 0.5
	_model = MobModels.build(mob_type)
	add_child(_model.root)
	if mob_type == "skeleton" and hand.is_empty():
		hand.set_slot(0, Items.id_of("bow"), 1) # skeletons hold their bow, like the game's
	hand.changed.connect(_update_held)
	_update_held()
	_update_power()
	_apply_size()
	health = max_health
	_yaw = rotation.y
	_prev_yaw = _yaw
	_egg_timer = randi_range(6000, 12000)
	_say_timer = randi_range(80, 400)
	_update_wool()
	armor.changed.connect(_update_armor)
	_update_armor()


# --- Armor -----------------------------------------------------------------------------

## A skeleton riding `spider`, like Beta's spider jockey: it sits on its
## back (the spider walks, the skeleton shoots); dressed like any other.
static func add_jockey(world: VoxelWorld, spider: Mob) -> Mob:
	var skeleton := Mob.create("skeleton")
	skeleton.equip()
	world.entities.spawn(skeleton, spider.feet())
	skeleton.rotation.y = spider.rotation.y
	skeleton.set("_yaw", skeleton.rotation.y)
	skeleton.set("_prev_yaw", skeleton.rotation.y)
	skeleton.vehicle = spider
	spider.rider = skeleton
	return skeleton


## Where it looks this frame (debug hitboxes): its head's facing, or its
## body's for creatures without a head part.
func look_direction() -> Vector3:
	if _head == null and not _model.is_empty():
		for part: Dictionary in _model.spec.parts:
			if part.get("role", "") == "head" and _model.parts.has(part.name):
				_head = _model.parts[part.name]
	if _head and is_instance_valid(_head):
		return (_head.global_basis * Vector3.BACK).normalized() # (models face +z)
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


var _head: Node3D


## Its eyes (Beta's getEyeHeight: 0.85 of its height), where creatures
## that go after it look and aim.
func eye_position() -> Vector3:
	return feet() + Vector3(0, height * 0.85, 0)


## A spider's rider sits like Beta's (EntitySpider.getMountedYOffset: its
## height x 0.75 - 0.5 above its feet); the rest as any creature.
func seat_height() -> float:
	if mob_type == "spider":
		return height * 0.75 - 0.5 + RIDER_HIPS
	return super()


## Who may spawn in armor (like the modern game's zombies and skeletons).
const ARMORED := ["zombie", "skeleton"]
## The chance a natural spawn wears armor by difficulty (the modern game:
## 0.15 times how hard the place is).
const ARMOR_CHANCE := [0.0, 0.0375, 0.075, 0.1125]
## Materials from the worst (the modern game's armor levels).
const ARMOR_LEVELS := ["leather", "golden", "chainmail", "iron", "diamond"]
## The chance each worn piece drops when it dies (the modern game's).
const ARMOR_DROP := 0.085


## Dresses a zombie or skeleton that spawns naturally, like the modern
## game's setEquipmentBasedOnDifficulty: sometimes (more on harder
## difficulties) armor of one material - mostly leather or gold, rarely
## better (3 tries of 9.5% for each level up) - from the helmet down, each
## further piece stopping there 1 in 4 (Hard: 1 in 10), already worn
## (worn_damage).
func equip() -> void:
	if ARMORED.has(mob_type):
		_equip_armor()
	# Around Halloween (Holidays) a pumpkin on the head instead of a helmet,
	# like the modern game's: a carved one or now and then a jack o'lantern;
	# it never drops.
	if HALLOWEEN_HEADS.has(mob_type) and Holidays.halloween() and randf() < HALLOWEEN_CHANCE:
		armor.set_slot(0, Blocks.variant("jack_o_lantern" if randf() < 0.1 else "carved_pumpkin", 0), 1)


## Who may wear a pumpkin at Halloween, and how often (the modern game's).
const HALLOWEEN_HEADS := ["zombie", "skeleton", "creeper"]
const HALLOWEEN_CHANCE := 0.25


func _equip_armor() -> void:
	var difficulty: int = Settings.get_value("difficulty")
	if randf() >= ARMOR_CHANCE[clampi(difficulty, 0, 3)]:
		return
	var level := randi_range(0, 1)
	for i in 3:
		if randf() < 0.095:
			level += 1
	var stop := 0.1 if difficulty == 3 else 0.25
	for slot in 4:
		if slot > 0 and randf() < stop:
			break
		var id := Items.id_of("%s_%s" % [ARMOR_LEVELS[mini(level, 4)], Items.ARMOR_PIECES[slot]])
		armor.set_slot(slot, id, 1, worn_damage(Items.durability(id)))


## How worn a piece a creature spawns with is: the modern game's drop
## (what is left: random(1 + random(max(durability - 3, 1)))), mostly a
## quarter or less, never broken; then hits wear it further and it drops
## as it is.
static func worn_damage(durability: int) -> int:
	if durability <= 1:
		return 0
	var left := randi_range(0, randi_range(0, maxi(durability - 3, 1)))
	return clampi(durability - left, 0, durability - 1)


## Picks up armor for an empty slot and (zombies, an empty hand) a weapon
## lying where it stands (its box grown by 1 block sideways, like the
## player's), like the modern game's zombies and skeletons.
const WEAPONS := ["sword", "axe"]


func _pick_up_tick() -> void:
	if not ARMORED.has(mob_type) or is_dead() or world.items == null:
		return
	var box := AABB(feet() - Vector3(half_width + 1.0, 0.0, half_width + 1.0), Vector3(half_width * 2.0 + 2.0, height, half_width * 2.0 + 2.0))
	var taken: Dictionary = world.items.take_one(box, _wants)
	if taken.is_empty():
		return
	var item := Items.get_type(taken.id)
	if item and item.armor_slot >= 0:
		armor.set_slot(item.armor_slot, taken.id, 1, taken.damage)
		_picked[item.armor_slot] = 1
	else:
		hand.set_slot(0, taken.id, 1, taken.damage)
		_picked[4] = 1
	persistent = true
	Sounds.play("random/pop", center(), 0.2, ((randf() - randf()) * 0.7 + 1.0) * 2.0)


## Whether it takes this item now (into a slot that is free).
func _wants(id: int) -> bool:
	var item := Items.get_type(id)
	if item == null:
		return false
	if item.armor_slot >= 0 and item.armor_slot < 4 and not Items.is_block(id):
		return armor.count_at(item.armor_slot) <= 0
	return mob_type == "zombie" and hand.is_empty() and WEAPONS.has(item.tool)


## The item in its right hand drawn there; a bow is held like the
## player's at rest and upright in front of it with the arms raised
## (MobModels.aimed_transform).
func _update_held() -> void:
	if _model.is_empty():
		return
	var id := hand.id_at(0) if hand.count_at(0) > 0 else Blocks.AIR
	if id == _held_shown:
		return
	_held_shown = id
	if _held:
		_held.queue_free()
		_held = null
	_held = MobModels.held_item(mob_type, id)
	if _held:
		_held_rest = _held.transform
		_held_aim = MobModels.aimed_transform(id, _held_rest)
		(_model.parts.right_arm as Node3D).add_child(_held)


## Its melee hit: the creature's own plus the weapon's over a fist.
func _melee_damage() -> int:
	var bonus := Items.attack_damage(hand.id_at(0)) - 1 if hand.count_at(0) > 0 else 0
	return spec.damage + bonus


var _armor_shown := PackedInt32Array()


func _update_armor() -> void:
	if _model.is_empty():
		return
	var shown := PackedInt32Array()
	for slot in armor.size():
		shown.append(armor.id_at(slot) if armor.count_at(slot) > 0 else Blocks.AIR)
	if shown == _armor_shown:
		return # (only worn more)
	_armor_shown = shown
	for mesh in _armor_meshes:
		_model.meshes.erase(mesh)
		mesh.queue_free()
	_armor_meshes = MobModels.armor_pieces(_model, armor)
	var head := armor.id_at(0)
	if armor.count_at(0) > 0 and Items.is_block(head) and (_model.parts as Dictionary).has("head"):
		# A pumpkin on the head, a little bigger than it (10 pixels), its
		# face forward, like the player's (PlayerModel).
		var pumpkin := MeshInstance3D.new()
		pumpkin.mesh = FallingBlocks.block_mesh(Blocks.variant(Blocks.family_of(head), 0))
		pumpkin.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3(-5, -1, -5))
		pumpkin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pumpkin.set_meta("block", true) # (lit through entity_light: FallingBlocks.light)
		(_model.parts.head as Node3D).add_child(pumpkin)
		_armor_meshes.append(pumpkin)
	_model.meshes.append_array(_armor_meshes) # (lit with the body)


## The armor's points like the player's (Beta: the same for every
## material, less as it wears out).
func armor_value() -> int:
	var points := 0
	var left := 0
	var total := 0
	for slot in armor.size():
		var item := Items.get_type(armor.id_at(slot))
		if armor.count_at(slot) <= 0 or item == null or item.armor_slot < 0:
			continue
		points += item.armor
		total += item.durability
		left += item.durability - armor.damage_at(slot)
	if total == 0:
		return 0
	return (points - 1) * left / total + 1


## Armor takes (armor value) / 25 of each hit and wears by it, like the
## player's (Entity.damage).
func _absorb(amount: int) -> int:
	var value := armor_value()
	if value <= 0:
		return amount
	for slot in armor.size():
		if armor.count_at(slot) > 0 and not Items.is_block(armor.id_at(slot)): # (a pumpkin doesn't wear)
			# (worn here, not by Inventory.wear: that counts the player's
			# stats and plays at the player)
			var damaged := armor.damage_at(slot) + amount
			if damaged >= Items.durability(armor.id_at(slot)):
				armor.set_slot(slot, Blocks.AIR, 0)
				Sounds.play("random/break", center(), 0.8, randf_range(0.8, 1.2))
			else:
				armor.set_slot(slot, armor.id_at(slot), 1, damaged)
	var scaled := amount * (25 - value) + _armor_remainder
	_armor_remainder = scaled % 25
	return scaled / 25


# --- Behavior --------------------------------------------------------------------------

## Box, health and model size (slimes come in sizes 1, 2 and 4).
func _apply_size() -> void:
	shadow_size = SHADOW_SIZES.get(mob_type, 0.5) * (size if mob_type == "slime" else 1)
	var model := MobModels.model(mob_type)
	half_width = float(model.get("width", 0.6)) / 2.0
	height = float(model.get("height", 1.0))
	max_health = spec.health
	if mob_type == "wolf" and tamed:
		max_health = 20
	var scale := float(model.get("scale", 1.0)) / 16.0
	if mob_type == "slime":
		half_width *= size
		height *= size
		max_health = size * size
		scale *= size
	if is_baby():
		half_width *= BABY_SCALE
		height *= BABY_SCALE
		shadow_size *= BABY_SCALE
		scale *= BABY_SCALE
	_base_scale = scale
	if not _model.is_empty():
		_model.root.scale = Vector3.ONE * scale
		for part: Dictionary in _model.spec.parts:
			if part.get("role", "") == "head" and _model.parts.has(part.name):
				(_model.parts[part.name] as Node3D).scale = Vector3.ONE * (BABY_HEAD if is_baby() else 1.0)


func is_baby() -> bool:
	return baby_ticks > 0


## Like Paper's entity activation range: a creature far from the players
## (over ACTIVATION_RANGE blocks) with nothing going on - standing on the
## ground, no target, not hurt, burning, swimming, in love, tame or riding -
## may be ticked only now and then (EntityManager); anything else keeps
## ticking every tick.
const ACTIVATION_RANGE := 32.0


func can_rest(players: Array[Vector3]) -> bool:
	if not on_ground or in_water or in_lava or fire_ticks > 0 or hurt_ticks > 0 or is_dead() \
			or target != null or _panic > 0 or love_ticks > 0 or tamed or vehicle != null or rider != null:
		return false
	var at := feet()
	for p in players:
		if Vector2(p.x - at.x, p.z - at.z).length_squared() <= ACTIVATION_RANGE * ACTIVATION_RANGE:
			return false
	return true


## A tick out of the simulated area (EntityManager, now and then): nothing
## moves, but monsters far from every player still go away like Beta's
## (over 128 blocks: at once).
func rest() -> void:
	super()
	_prev_yaw = _yaw


func sleep_tick() -> void:
	if is_hostile() and not persistent and not no_ai:
		_despawn(null)


func _ai_tick() -> void:
	_prev_yaw = _yaw
	_prev_fuse = _fuse
	_path_age += 1
	_attack_cooldown = maxi(_attack_cooldown - 1, 0)
	_look_ticks -= 1
	if _look_ticks <= 0:
		_look_at = Vector3.INF
	_panic = maxi(_panic - 1, 0)
	if no_ai:
		return
	_breeding_tick()
	var player = _player()
	if is_hostile() and not persistent and _despawn(player):
		return
	if age % 2 == 0:
		_pick_up_tick()
	if is_hostile() and Settings.get_value("difficulty") == 0:
		removed = true # peaceful: no monsters
		return
	_say_timer -= 1
	if _say_timer <= 0:
		_say_timer = randi_range(80, 400)
		_sound(_living_sound(), 1.0)
	if mob_type == "wolf":
		# Out of the water onto the ground: shakes itself dry (Beta's sound).
		var wet := is_wet()
		if _was_wet and not wet and on_ground:
			_sound("shake", 0.4)
		if wet or on_ground:
			_was_wet = wet
	if is_undead():
		_burn_in_daylight()
	if spec.get("water", false):
		_squid_tick()
		return
	match mob_type:
		"creeper":
			_monster_tick(player)
			_creeper_tick(player)
		"skeleton":
			_skeleton_tick(player)
		"slime":
			_slime_tick(player)
		"spider":
			_monster_tick(player)
			if horizontal_collision:
				velocity.y = 0.2 # climbs walls
		"zombie":
			_monster_tick(player)
		"wolf":
			_wolf_tick(player)
		_:
			_animal_tick(player)
	if mob_type == "chicken":
		velocity.y = maxf(velocity.y, -0.06) # flutters down
		_egg_timer -= 1
		if _egg_timer <= 0:
			_egg_timer = randi_range(6000, 12000)
			if not is_baby(): # (chicks lay none)
				world.items.spawn(Items.id_of("egg"), 1, center(), Vector3(0, 0.1, 0))
				_sound("plop", 1.0)
	if mob_type == "sheep" and sheared and randi_range(0, 999) == 0:
		_eat_grass()
	if in_water:
		velocity.y += 0.04 # keeps its head above water


## The player it goes after or looks at: the nearest one alive and not in
## creative (in a network game the others too: RemotePlayer acts like one).
func _player():
	var best = null
	var best_distance := INF
	for who in _players():
		if who == null or who.dead or who.is_creative():
			continue
		var distance: float = (who.global_position as Vector3).distance_squared_to(feet())
		if distance < best_distance:
			best_distance = distance
			best = who
	return best


## Every player in the world (the local one, the network game's others).
func _players() -> Array:
	var result := [world.player] if world.player else []
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if is_instance_valid(avatar):
				result.append(avatar)
	return result


static func _is_player(who) -> bool:
	return who is Player or who is RemotePlayer


## Monsters far from the player disappear (128+ at once, 32+ now and then).
func _despawn(_player_near) -> bool:
	var distance := INF
	for who in _players():
		if who != null:
			distance = minf(distance, (who.global_position as Vector3).distance_to(feet()))
	if distance == INF:
		return false
	if distance > 128.0 or (distance > 32.0 and randi_range(0, 799) == 0):
		removed = true
		return true
	return false


## Animals (and calm monsters, wild wolves): run when hurt (panic), go to
## their partner when in love, follow food held near, a baby its grown-up,
## else wander and look at the player now and then.
func _animal_tick(player) -> void:
	_goal_age += 1
	if _panic > 0:
		_panic_tick()
		return
	_flee_from = Vector3.INF
	if mob_type in ANIMALS and (_love_tick() or _tempt_tick() or _follow_parent_tick()):
		return
	if player and randi_range(0, 49) == 0 and player.global_position.distance_to(feet()) < 6.0:
		_look_at = player.eye_position()
		_look_ticks = randi_range(20, 60) # like the game: looks for a while
	var stranded := _keeps_dry() and _in_deep_water()
	if _wander == Vector3.INF and (randi_range(0, 119) == 0 or stranded):
		# (in deep water: straight for the nearest shore)
		_wander = _shore_spot() if stranded else _wander_spot()
		_goal_age = 0
	if _wander != Vector3.INF:
		if _walk_over(_wander) or randi_range(0, 199) == 0:
			_wander = Vector3.INF
			_path.clear()
		else:
			_navigate(_wander, spec.speed, false, 150)


## Modern's PanicGoal: off to spots away from what hurt it (water first when
## burning), a new one when there, out of reach or after a while.
func _panic_tick() -> void:
	if _wander == Vector3.INF or _walk_over(_wander) or _goal_age > 60:
		_wander = _panic_spot()
		_goal_age = 0
	_navigate(_wander, spec.speed * PANIC_SPEED, false, 150)


## Whether walking to `goal` is over: there, its path ran out short of it
## (out of reach), or it keeps bumping into something close to it.
func _walk_over(goal: Vector3) -> bool:
	if Vector2(goal.x - _x, goal.z - _z).length() < 1.0:
		return true
	var near := goal.distance_to(feet()) < PATH_FROM
	if _goal_age > 5 and not near and _path.is_empty() and _path_goal == Vector3i(goal.floor()):
		return true
	return _goal_age > 20 and near and horizontal_collision


## A spot 4-8 blocks away from the attacker (anywhere without one), the
## best of a few tries: farthest from it, on the ground (no walls, no
## cliffs: Pathfinder.standable), not in water unless burning.
func _panic_spot() -> Vector3:
	var away := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	if _flee_from != Vector3.INF:
		away = (feet() - _flee_from) * Vector3(1, 0, 1)
	away = away.normalized() if away.length_squared() > 1e-4 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var water_bonus := 6.0 if fire_ticks > 0 else (-INF if _keeps_dry() else -6.0)
	var best := Vector3.INF
	var best_score := -INF
	for attempt in 10:
		var offset := away.rotated(Vector3.UP, randf_range(-1.2, 1.2)) * randf_range(4.0, 8.0)
		var cell := _ground_near(Vector3i(floori(_x + offset.x), floori(_y + 0.01), floori(_z + offset.z)), 3)
		if cell == Vector3i.MAX:
			continue
		var spot := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		var score := spot.distance_to(_flee_from) if _flee_from != Vector3.INF else randf() * 4.0
		if _water_at(cell):
			score += water_bonus
		if score > best_score:
			best_score = score
			best = spot
	return best if best != Vector3.INF else feet() + away * 6.0


## A wander goal up to 10 blocks off, on the ground; the undead keep to the
## shade by day, animals to dry land (INF: stays for now).
func _wander_spot() -> Vector3:
	var cell := _ground_near(_feet_cell() + Vector3i(randi_range(-10, 10), 0, randi_range(-10, 10)), 3)
	if cell == Vector3i.MAX or (_fears_sun() and not _shaded(cell)) or (_keeps_dry() and _water_at(cell)):
		return Vector3.INF
	return Vector3(cell) + Vector3(0.5, 0.0, 0.5)


## Animals keep to dry land: they come down to the water (it may be walked
## where it is a block deep) but don't swim off into it; in deep water they
## make for the nearest shore.
func _keeps_dry() -> bool:
	return mob_type in ANIMALS


## In water with no ground right under its feet.
func _in_deep_water() -> bool:
	if not in_water:
		return false
	var under := world.get_block(_feet_cell() + Vector3i.DOWN)
	return Blocks.liquid_table[under] == 1 or under == Blocks.AIR


## The nearest dry ground to stand on, ring by ring up to 12 blocks off
## (INF: none found: it swims about as before).
func _shore_spot() -> Vector3:
	var here := _feet_cell()
	for ring in range(1, 13):
		for dx in range(-ring, ring + 1):
			for dz: int in ([-ring, ring] if absi(dx) != ring else range(-ring, ring + 1)):
				var cell := _ground_near(here + Vector3i(dx, 0, dz), 3)
				if cell != Vector3i.MAX and not _water_at(cell):
					return Vector3(cell) + Vector3(0.5, 0.0, 0.5)
	return Vector3.INF


## The cell nearest `cell`'s height in its column (up to `vertical` up or
## down) where it can stand; Vector3i.MAX if none.
func _ground_near(cell: Vector3i, vertical: int) -> Vector3i:
	var tall := _tall()
	for i in vertical * 2 + 1:
		var dy := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
		var here := cell + Vector3i(0, dy, 0)
		if Pathfinder.standable(world, here, tall):
			return here
	return Vector3i.MAX


func _water_at(cell: Vector3i) -> bool:
	return Blocks.liquid_table[world.get_block(cell)] == 1


# --- Animals: food, love and babies ----------------------------------------------------

## The food this animal follows and breeds with (-1: none).
func _food_id() -> int:
	return Items.id_of(FOODS[mob_type]) if FOODS.has(mob_type) else -1


## Modern's TemptGoal: the nearest player within TEMPT holding its food
## (creative too) draws it, to TEMPT_STOP away, looking at them.
func _tempt_tick() -> bool:
	var food := _food_id()
	var best = null
	var best_distance := TEMPT
	for who in _players():
		if who == null or who.dead or who.held_block() != food:
			continue
		var distance: float = (who.global_position as Vector3).distance_to(feet())
		if distance < best_distance:
			best_distance = distance
			best = who
	if best == null:
		return false
	_wander = Vector3.INF
	_look_at = best.eye_position()
	_look_ticks = 5
	if best_distance > TEMPT_STOP:
		_navigate(best.global_position, spec.speed)
	else:
		_path.clear()
		_face(best.global_position)
	return true


## In love (fed): goes to the nearest one of its kind in love within
## LOVE_RANGE; after BREED_TICKS together, close, a baby (modern's BreedGoal).
func _love_tick() -> bool:
	if love_ticks <= 0 or is_baby():
		return false
	if not _can_mate(_partner) and age % 10 == 0:
		_partner = null
		var best_distance := LOVE_RANGE
		for entity in world.entities.near(center(), LOVE_RANGE):
			var distance := entity.center().distance_to(center())
			if entity != self and _can_mate(entity as Mob) and distance < best_distance:
				best_distance = distance
				_partner = entity as Mob
	if not _can_mate(_partner):
		_breed_timer = 0
		return false
	var goal := _partner.feet()
	_look_at = _partner.center()
	_look_ticks = 5
	if goal.distance_to(feet()) > 1.2:
		_navigate(goal, spec.speed)
	_breed_timer += 1
	if _breed_timer >= BREED_TICKS and goal.distance_to(feet()) < BREED_CLOSE:
		_breed(_partner)
	return true


func _can_mate(other: Mob) -> bool:
	return other != null and is_instance_valid(other) and other != self and not other.removed and not other.is_dead() \
		and other.mob_type == mob_type and other.love_ticks > 0 and not other.is_baby()


## A baby between the two (a lamb's wool from one of them); both rest.
func _breed(partner: Mob) -> void:
	var child := Mob.create(mob_type)
	child.baby_ticks = GROW_TICKS
	if mob_type == "sheep":
		child.wool_color = wool_color if randi_range(0, 1) == 0 else partner.wool_color
	world.entities.spawn(child, (feet() + partner.feet()) * 0.5)
	child._yaw = randf() * TAU
	for parent: Mob in [self, partner]:
		parent.love_ticks = 0
		parent.breed_cooldown = BREED_COOLDOWN
		parent._breed_timer = 0
		parent._partner = null
	world.particles.hearts(child.center() + Vector3(0, 0.3, 0))


## Modern's FollowParentGoal: a baby keeps near a grown-up of its kind (the
## nearest within PARENT_RANGE, until PARENT_LOST away), wandering when close.
func _follow_parent_tick() -> bool:
	if not is_baby():
		return false
	var lost := _parent == null or not is_instance_valid(_parent) or _parent.removed or _parent.is_dead() \
		or _parent.feet().distance_to(feet()) > PARENT_LOST
	if lost or age % 20 == 0:
		_parent = null
		var best_distance := PARENT_RANGE
		for entity in world.entities.near(center(), PARENT_RANGE):
			if entity is Mob and (entity as Mob).mob_type == mob_type and not (entity as Mob).is_baby():
				var distance := entity.feet().distance_to(feet())
				if distance < best_distance:
					best_distance = distance
					_parent = entity as Mob
	if _parent == null or _parent.feet().distance_to(feet()) < 3.0:
		return false
	_wander = Vector3.INF
	_navigate(_parent.feet(), spec.speed * 1.1)
	return true


## Every tick (host): a baby grows, love and the rest after breeding wear
## off; hearts now and then while in love.
func _breeding_tick() -> void:
	if baby_ticks > 0:
		baby_ticks -= 1
		if baby_ticks == 0:
			_apply_size() # grown up
	breed_cooldown = maxi(breed_cooldown - 1, 0)
	if love_ticks > 0:
		love_ticks -= 1
		if love_ticks % 10 == 0:
			_love_heart()


func _love_heart() -> void:
	if world and world.particles:
		world.particles.heart(center() + Vector3(randf_range(-half_width, half_width), height * 0.5 + randf() * 0.5, randf_range(-half_width, half_width)))


## Fed its food: a baby grows a tenth of the way faster; a grown-up that
## can breed falls in love. Returns true if it took the food.
func _feed(player) -> bool:
	if is_baby():
		baby_ticks = maxi(baby_ticks - baby_ticks / 10, 1)
	elif love_ticks == 0 and breed_cooldown == 0:
		love_ticks = LOVE_TICKS
		_partner = null
		world.particles.hearts(center() + Vector3(0, height * 0.5, 0))
	else:
		return false
	if not player.is_creative():
		player.inventory.take(player.selected_slot)
	return true


# --- Monsters ---------------------------------------------------------------------------

## Whether a monster notices `player` to go after it: closer than SIGHT (a
## sneaking one SNEAK_SIGHT of that) and seen, unless right next to it.
func _notices(player) -> bool:
	if player == null:
		return false
	var sneaking: bool = player.is_sneaking() if player.has_method("is_sneaking") else bool(player.get("sneaking"))
	var distance: float = (player.global_position as Vector3).distance_to(feet())
	if distance >= SIGHT * (SNEAK_SIGHT if sneaking else 1.0):
		return false
	return distance < NOTICE_BLIND or _sees(player)


func _sees(player) -> bool:
	if player == null:
		return false
	var eye := center() + Vector3(0, height * 0.35, 0)
	var to: Vector3 = player.eye_position()
	if eye.distance_to(to) > SIGHT:
		return false
	var hit := world.raycast(eye, to - eye, eye.distance_to(to))
	return not hit.get("hit", false)


## Zombies, spiders and creepers: go after the player they notice (seen
## within 16 blocks, like Beta's; less far while it sneaks), along paths
## round walls; out of sight to where they saw it last, and they give it up
## (_keep_track); hit it when close (spiders leap). Burning undead go for shade first.
## Spiders are calm where it is brighter than this (the night taken off),
## like Beta's EntitySpider: its brightness under 0.5 is light 11 or less.
const SPIDER_CALM_LIGHT := 11


func _monster_tick(player) -> void:
	# Beta's spider: in the light it looks for nobody and now and then (1 in
	# 100 ticks) forgets who it was after; hit, it stays angry.
	var calm := mob_type == "spider" and not angry \
		and world.get_combined_light(Vector3i(center().floor()), MobSpawner.sky_darkness(world)) > SPIDER_CALM_LIGHT
	if calm and target != null and randi_range(0, 99) == 0:
		target = null
	if not calm and player and player != target and (target == null or _is_player(target)) and _notices(player):
		target = player
		_unseen = 0
		_path_goal = Vector3i.MAX # (a path to it at once, not at the next refresh)
	_keep_track()
	if _flee_sun():
		return
	if target == null:
		_animal_tick(null)
		return
	var goal: Vector3 = _chase_goal()
	if _unseen == 0:
		_look_at = target.eye_position()
		_look_ticks = 5
	# (leaps and hits at the player itself, never at where it was last seen)
	var real: Vector3 = target.global_position
	var flat := Vector2(real.x - _x, real.z - _z).length()
	if mob_type == "creeper" and _fuse > 0:
		return # stands still while it swells
	if mob_type == "spider" and _unseen == 0 and flat < 3.0 and flat > 1.5 and on_ground and randi_range(0, 9) == 0:
		var leap := Vector3(real.x - _x, 0, real.z - _z).normalized()
		velocity = Vector3(leap.x * 0.4, 0.4, leap.z * 0.4)
		return
	_navigate(goal, spec.speed, true, CHASE_NODES)
	if mob_type != "creeper" and flat < half_width + 0.9 and absf(real.y - _y) < height and _attack_cooldown == 0:
		_attack_cooldown = ATTACK_COOLDOWN
		target.damage(_scaled_damage(_melee_damage()))
		target.knockback(center())
		if _is_player(target):
			guard_owner(self)


## Ticks since the monster last saw the player it is after, and where.
var _unseen := 0
var _last_seen := Vector3.INF


## Keeps track of the player a monster is after: seen, it knows where the
## player is; unseen, it makes for where it saw it last (see FORGET_TICKS
## for when it gives up); gone, dead, in creative or out of CHASE_RANGE,
## it lets go.
func _keep_track() -> void:
	if target == null or not _is_player(target):
		return
	if target.dead or target.is_creative() or (target.global_position as Vector3).distance_to(feet()) > CHASE_RANGE:
		_forget()
		return
	if _sees(target):
		_unseen = 0
		_last_seen = target.global_position
		return
	_unseen += 1
	var there := _last_seen != Vector3.INF and Vector2(_last_seen.x - _x, _last_seen.z - _z).length() < 1.5 \
		and absf(_last_seen.y - _y) < 2.0
	var lost := _unseen > FORGET_TICKS and (_path.is_empty() or _stuck > 10) # (no way there)
	if there or lost or _unseen > CHASE_MEMORY:
		_forget()


func _forget() -> void:
	target = null
	_unseen = 0
	_last_seen = Vector3.INF
	_path.clear()


## Where it goes after its player: the player while seen, else the spot it
## saw it last.
func _chase_goal() -> Vector3:
	if _is_player(target) and _unseen > 0 and _last_seen != Vector3.INF:
		return _last_seen
	return target.global_position


## Damage by difficulty like Beta: easy half + 1, hard x1.5.
static func _scaled_damage(amount: int) -> int:
	match Settings.get_value("difficulty"):
		1:
			return amount / 2 + 1
		3:
			return amount * 3 / 2
	return amount


func _creeper_tick(player) -> void:
	var close: bool = player != null and player.global_position.distance_to(feet()) < 3.0 and _sees(player)
	if close or (_fuse > 0 and player != null and player.global_position.distance_to(feet()) < 7.0):
		if _fuse == 0:
			Sounds.play("mob/creeper/fuse", center(), 1.0, 0.5)
		_fuse += 1
		if _fuse >= CREEPER_FUSE:
			removed = true
			Explosion.explode(world, center(), CHARGED_CREEPER_POWER if powered else CREEPER_POWER, self)
	else:
		_fuse = maxi(_fuse - 1, 0)


## Skeletons like Beta's (EntitySkeleton.attackEntity in EntityCreature):
## they go after the player they notice (out of sight to where they saw it
## last, then they give it up: _keep_track); within 10 blocks and in sight they shoot
## every 30 ticks, face the player and keep walking the path they had (no
## new one: so they step about while shooting), now and then (1 in 100)
## dropping it.
const SKELETON_RANGE := 10.0
const SKELETON_RELOAD := 30


func _skeleton_tick(player) -> void:
	var noticed := false
	if player and player != target and (target == null or _is_player(target)) and not player.is_creative() \
			and _sees(player) and _notices(player):
		target = player
		noticed = true
		_unseen = 0
	_keep_track()
	if _flee_sun():
		return
	if target == null:
		_animal_tick(null)
		return
	var goal: Vector3 = _chase_goal()
	var distance := goal.distance_to(feet())
	if noticed:
		# (Beta: a path to the player found the moment it is noticed)
		_path_goal = Vector3i.MAX
		_navigate(goal, spec.speed, true, CHASE_NODES)
	elif distance < SKELETON_RANGE and _unseen == 0:
		if randi_range(0, 99) == 0:
			_path.clear()
		_follow_path(spec.speed)
		_face(goal)
		_look_at = target.eye_position()
		_look_ticks = 5
		if _attack_cooldown == 0:
			_attack_cooldown = SKELETON_RELOAD
			Arrow.shoot(world, center() + Vector3(0, height * 0.3, 0), target.eye_position() - Vector3(0, 0.4, 0), 0.6 * 1.6, 12.0, self)
	else:
		if _unseen == 0:
			_look_at = target.eye_position()
			_look_ticks = 5
		_navigate(goal, spec.speed, true, CHASE_NODES)


## Slimes hop toward the player (or about) and hurt it on touch (big ones).
func _slime_tick(player) -> void:
	_jump_timer -= 1
	if on_ground:
		velocity.x = 0.0
		velocity.z = 0.0
	if _jump_timer <= 0 and on_ground:
		_jump_timer = randi_range(10, 30)
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if _sees(player):
			dir = Vector3(player.global_position.x - _x, 0, player.global_position.z - _z).normalized()
			_jump_timer /= 3
			_face(player.global_position)
		velocity = Vector3(dir.x * 0.15 * size, 0.42, dir.z * 0.15 * size)
		Sounds.play("mob/slime/" + ("big" if size > 1 else "small"), center(), 0.4 * size, Sounds.beta_pitch() / 0.8)
	if player and size > 1 and _attack_cooldown == 0 and player.global_position.distance_to(feet()) < half_width + 0.8:
		_attack_cooldown = ATTACK_COOLDOWN
		player.damage(_scaled_damage(size))


## Wolves like Beta's, neutral: a wild one wanders and only turns on
## whoever hurts it (hurt_by: its pack around joins in); a tame one follows
## its player along a path (teleporting when far behind), sits when told,
## and fights what hurts the player or what the player hits (guard_owner).
func _wolf_tick(player) -> void:
	if sitting:
		return
	if angry and not _target_alive():
		angry = false # the fight is over
		target = null
	if angry and target:
		var goal: Vector3 = target.global_position if not (target is Entity) else (target as Entity).feet()
		var reach: float = (target as Entity).center().distance_to(center()) if target is Entity else goal.distance_to(feet())
		if reach > 32.0:
			angry = false
			target = null
			return
		_look_at = goal + Vector3(0, 1, 0)
		_look_ticks = 5
		_navigate(goal, spec.speed * 1.2)
		if reach < 1.5 and _attack_cooldown == 0:
			_attack_cooldown = ATTACK_COOLDOWN
			if target is Entity:
				if (target as Entity).damage(4 if tamed else 2, center()) and target is Mob:
					(target as Mob).hurt_by(self)
			else:
				target.damage(_scaled_damage(4 if tamed else 2))
				target.knockback(center())
		return
	if tamed and world.player and not world.player.dead:
		var owner: Vector3 = world.player.global_position
		var distance := owner.distance_to(feet())
		if distance > TELEPORT:
			_teleport_near(owner)
		elif distance > FOLLOW or (distance > STAY and not _path.is_empty()):
			_navigate(owner, spec.speed * 1.3)
		else:
			_path.clear()
			if randi_range(0, 39) == 0:
				_look_at = world.player.eye_position()
				_look_ticks = randi_range(20, 60)
		return
	_animal_tick(player)


## Whether what it fights is still there to fight.
func _target_alive() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Entity:
		return not (target as Entity).removed and not (target as Entity).is_dead()
	return not bool(target.get("dead"))


## A tame wolf left far behind: next to its player, on a free spot (like
## Beta's wolves catching up).
func _teleport_near(owner: Vector3) -> void:
	var base := Vector3i(owner.floor())
	for attempt in 12:
		var cell := base + Vector3i(randi_range(-2, 2), randi_range(-1, 1), randi_range(-2, 2))
		if Vector2(cell.x - base.x, cell.z - base.z).length() >= 1.0 and Pathfinder.standable(world, cell, _tall()):
			teleport(Vector3(cell) + Vector3(0.5, 0.0, 0.5))
			_path.clear()
			return


## A tame wolf's player was hurt by `attacker`, or hit it: the tame wolves
## around go after it (not after their own player, not after each other).
static func guard_owner(attacker: Node3D) -> void:
	if not (attacker is Mob):
		return
	var mob := attacker as Mob
	if mob.mob_type == "wolf" and mob.tamed:
		return
	guard_owner_against(mob)


## Squid like Beta's: under water they swim in pushes (a new, mostly level
## direction now and then, the push fading), staying under the surface;
## the body leans into the way it goes. Out of water they flop.
## Squids like Beta 1.7.3's EntitySquid, number for number: a stroke cycle
## turns at 0.1..0.2 a tick (a new pace 1 in 10 strokes); in the first half
## of it the tentacles open and close (sin(f^2 pi) x pi/4), at 3/4 of it a
## push (speed 1) that then dies away (x 0.9 a tick); every tick 1 in 50 (or when it has none) it picks a new
## way (0.2 sideways, -0.1..0.1 up or down) and moves that way x the speed,
## no gravity or drag in water; its body turns toward where it goes and
## leans along it (10% a tick). Out of water it falls, tentacles flapping,
## and tips over onto its side.
func _squid_tick() -> void:
	_squid_prev_tentacles = _squid_tentacles
	_squid_prev_pitch = _squid_pitch
	if _squid_cycle_speed == 0.0:
		_squid_cycle_speed = 1.0 / (randf() + 1.0) * 0.2
	_squid_cycle += _squid_cycle_speed
	if _squid_cycle > TAU:
		_squid_cycle -= TAU
		if randi_range(0, 9) == 0:
			_squid_cycle_speed = 1.0 / (randf() + 1.0) * 0.2
	# (updatePlayerActionState: a new way now and then)
	if randi_range(0, 49) == 0 or not in_water or _squid_heading == Vector3.ZERO:
		var angle := randf() * TAU
		_squid_heading = Vector3(cos(angle) * 0.2, -0.1 + randf() * 0.2, sin(angle) * 0.2)
	if in_water:
		if _squid_cycle < PI:
			var f := _squid_cycle / PI
			_squid_tentacles = sin(f * f * PI) * PI * 0.25
			if f > 0.75:
				_squid_speed = 1.0
		else:
			_squid_tentacles = 0.0
			_squid_speed *= 0.9
		velocity = _squid_heading * _squid_speed
		var flat := Vector2(velocity.x, velocity.z).length()
		if flat > 1e-6:
			_yaw += angle_difference(_yaw, atan2(velocity.x, velocity.z)) * 0.1
		_squid_pitch += (-rad_to_deg(atan2(flat, velocity.y)) - _squid_pitch) * 0.1
	else:
		_squid_tentacles = absf(sin(_squid_cycle)) * PI * 0.25
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = (velocity.y - 0.08) * 0.98
		_squid_pitch += (-90.0 - _squid_pitch) * 0.02


## The camera's view (its frustum planes), worked out once a frame for
## every creature.
static var _view_planes: Array[Plane] = []
static var _view_frame := -1


## Whether the creature (a ball round its middle, a little bigger than it)
## can be in the camera's sight.
func _in_view() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _view_frame:
		_view_frame = frame
		var camera := get_viewport().get_camera_3d()
		_view_planes = camera.get_frustum() if camera else ([] as Array[Plane])
	if _view_planes.is_empty():
		return true
	var middle := global_position + Vector3(0, height * 0.5, 0)
	var radius := maxf(height, half_width * 2.0) + 1.0 # (held items, riders, a swinging limb)
	for plane in _view_planes:
		if plane.distance_to(middle) > radius:
			return false
	return true


## Beta's EntitySquid moves just by its motion (no gravity, drag or water
## pull of its own: _squid_tick sets it); the rest as any creature.
func _physics() -> void:
	if mob_type != "squid":
		super()
		return
	var start_y := _y
	move(velocity)
	_track_fall(start_y)


## The undead catch fire under the open sky by day (like Beta's); out of it
## (shade, water) the sun's fire goes out (not other fire: lava's is longer).
func _burn_in_daylight() -> void:
	if fire_ticks > 160:
		_sunburn = false
	if _fears_sun() and not is_wet() and world.get_light(Vector3i((center() + Vector3(0, height * 0.4, 0)).floor())) >= SkyLight.MAX:
		if fire_ticks <= 0:
			fire_ticks = 160 # (set only when out: kept up every tick, it never reached a 20th tick to hurt)
		_sunburn = true
	elif _sunburn:
		_sunburn = false
		fire_ticks = 0


func _daylight() -> float:
	var atmosphere := Atmosphere.find(world.get_tree())
	return atmosphere.daylight if atmosphere else 1.0


func _fears_sun() -> bool:
	# (a helmet keeps the sun off, like the modern game's)
	return is_undead() and _daylight() > 0.5 and armor.count_at(0) <= 0


## Out of the sun at `cell` (feet): its head has no open sky above (a tree,
## an overhang, a roof), or it is in water.
func _shaded(cell: Vector3i) -> bool:
	return _water_at(cell) or world.get_light(cell + Vector3i(0, floori(height * 0.9), 0)) < SkyLight.MAX


## Modern's FleeSunGoal: burning in the sun, an undead looks for shade now
## and then (SHADE_TRIES random spots within SHADE_RANGE: the nearest
## shaded one) and hurries there; true while it goes. A zombie with its
## player close fights on instead.
func _flee_sun() -> bool:
	if not _sunburn or fire_ticks <= 0:
		_shade = Vector3i.MAX
		return false
	if mob_type == "zombie" and target and (target as Node3D).global_position.distance_to(feet()) < FIGHT_IN_SUN:
		return false
	if _shade != Vector3i.MAX and not _shaded(_shade):
		_shade = Vector3i.MAX
	if _shade == Vector3i.MAX:
		_shade_timer -= 1
		if _shade_timer > 0:
			return false
		_shade_timer = randi_range(20, 40)
		_shade = _find_shade()
		if _shade == Vector3i.MAX:
			return false
		_path.clear()
	var goal := Vector3(_shade) + Vector3(0.5, 0.0, 0.5)
	_look_ticks = 0
	_navigate(goal, spec.speed * SHADE_SPEED, false, 200)
	return true


func _find_shade() -> Vector3i:
	var base := _feet_cell()
	var best := Vector3i.MAX
	var best_distance := INF
	for attempt in SHADE_TRIES:
		# (spread around it, denser close by)
		var angle := randf() * TAU
		var radius := randf_range(1.0, float(SHADE_RANGE.x))
		var column := base + Vector3i(roundi(cos(angle) * radius), 0, roundi(sin(angle) * radius))
		var cell := _ground_near(column, SHADE_RANGE.y)
		if cell == Vector3i.MAX or not _shaded(cell):
			continue
		var distance := Vector3(cell - base).length()
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## Walks toward a point like Beta's creatures: turns to it and pushes
## itself that way (friction gives it its speed: `speed` blocks a tick on
## the ground; less control in the air, slower in water), so a hit's
## knockback is not cancelled; jumps up a block in the way.
func _walk_toward(point: Vector3, speed: float) -> void:
	var dir := Vector3(point.x - _x, 0, point.z - _z)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	_face(point)
	var accel: float
	if in_water or in_lava:
		accel = speed * 0.2 * 0.6
	elif on_ground:
		var below := world.get_block(Vector3i(floori(_x), floori(_y - 0.5), floori(_z)))
		var friction := (Blocks.get_type(below).slipperiness if below != Blocks.AIR else 0.6) * 0.91
		accel = speed * (1.0 - friction)
	else:
		accel = speed * 0.03
	velocity.x += dir.x * accel
	velocity.z += dir.z * accel
	if horizontal_collision and on_ground:
		velocity.y = 0.42


func _face(point: Vector3) -> void:
	var dir := Vector3(point.x - _x, 0, point.z - _z)
	if dir.length_squared() < 0.0001:
		return
	var wanted := atan2(dir.x, dir.z)
	_yaw = lerp_angle(_yaw, wanted, 0.35)


## How many cells high it is for paths.
func _tall() -> int:
	return clampi(ceili(height - 0.01), 1, 3)


func _feet_cell() -> Vector3i:
	return Vector3i(floori(_x), floori(_y + 0.01), floori(_z))


## Goes to a point along a path (Pathfinder), found again when the goal
## moves away (`moving` goals also now and then) or when it got stuck;
## straight at it when close, or while no path is known yet (searches wait
## their turn: Pathfinder.NODE_BUDGET). `reach`: how many cells a search
## may look at (short walks need few).
func _navigate(goal: Vector3, speed: float, moving: bool = true, reach: int = Pathfinder.MAX_NODES) -> void:
	if goal.distance_to(feet()) < PATH_FROM and absf(goal.y - _y) < 1.5:
		_path.clear()
		_walk_toward(goal, speed)
		return
	var goal_cell := Vector3i(goal.floor())
	_stuck = _stuck + 1 if horizontal_collision and on_ground else 0
	var stale := _path_goal == Vector3i.MAX or (_path.is_empty() and _path_goal != goal_cell) or _stuck > 10 \
		or Vector2(goal_cell.x - _path_goal.x, goal_cell.z - _path_goal.z).length_squared() > 4.0 \
		or (moving and _path_age >= PATH_REFRESH)
	var allowed := Pathfinder.budget(world.clock.game_time, reach) if stale else 0
	if allowed > 0:
		# (animals don't plan swims; one already in deep water may, to get out)
		var swim := not _keeps_dry() or _in_deep_water()
		_path = Pathfinder.find(world, _feet_cell(), goal_cell, _tall(), allowed, swim)
		_path_goal = goal_cell
		_path_age = 0
		_stuck = 0
	if _path.is_empty():
		_walk_toward(goal, speed)
		return
	_follow_path(speed)


## One step along the path there is (none: stands); false if there is none.
func _follow_path(speed: float) -> bool:
	if _path.is_empty():
		return false
	var next := _path[0]
	var point := Vector3(next.x + 0.5, next.y, next.z + 0.5)
	var flat := Vector2(point.x - _x, point.z - _z).length()
	if flat < 0.35 and absf(_y - next.y) < 1.0:
		_path.remove_at(0)
		if _path.is_empty():
			return true
		next = _path[0]
		point = Vector3(next.x + 0.5, next.y, next.z + 0.5)
		flat = Vector2(point.x - _x, point.z - _z).length()
	_walk_toward(point, speed)
	if next.y > floori(_y + 0.01) and on_ground and flat < 1.4:
		velocity.y = 0.42 # up a block
	return true


func _eat_grass() -> void:
	var below := Vector3i(floori(_x), floori(_y - 0.5), floori(_z))
	if Blocks.get_type(world.get_block(below)).name.begins_with("grass_"):
		world.set_block(below, Blocks.id_of("dirt"))
		sheared = false
		_update_wool()


# --- Interaction ---------------------------------------------------------------------

## The player right-clicks the mob with an item. Returns true if it did
## something (shearing, dyeing, milking, taming, sitting).
## RMB with item_id in hand: shears, dye, saddle, bucket, bone. `player`: the
## Player, or a client's NetPlayerProxy (network game).
func interact(player, item_id: int) -> bool:
	if is_dead():
		return false
	var item_name := Items.name_of(item_id) if item_id != Blocks.AIR else ""
	if item_name != "" and FOODS.get(mob_type, "") == item_name and _feed(player):
		return true
	match mob_type:
		"sheep":
			if item_name == "shears" and not sheared and not is_baby():
				sheared = true
				_update_wool()
				var wool := Blocks.id_of(wool_color + "_wool")
				for i in randi_range(1, 3):
					world.items.spawn(wool, 1, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)))
				if not player.is_creative():
					player.inventory.wear(player.selected_slot)
				return true
			var dye := _dye_color(item_name)
			if dye != "" and not sheared and dye != wool_color:
				wool_color = dye
				_update_wool()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				return true
		"pig":
			if not saddled and item_name == "saddle" and not is_baby():
				saddled = true
				_update_wool()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				return true
			if saddled and player.vehicle == null:
				player.mount(self)
				return true
		"cow":
			if item_name == "bucket" and not is_baby():
				if not player.is_creative():
					var slot: int = player.selected_slot
					if player.inventory.count_at(slot) == 1:
						player.inventory.set_slot(slot, Items.id_of("milk_bucket"), 1)
					else:
						player.inventory.take(slot)
						player.inventory.add(Items.id_of("milk_bucket"), 1)
				return true
		"wolf":
			if not tamed and item_name == "bone":
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				if randi_range(0, 2) == 0:
					tamed = true
					angry = false
					target = null
					max_health = 20 # tame wolves have 20 health, like Beta
					if player is Player:
						Stats.grant("tamer")
					health = max_health
					_update_wool()
					world.particles.hearts(center() + Vector3(0, height * 0.5, 0))
				else:
					world.particles.smoke(center(), 4)
				return true
			if tamed:
				sitting = not sitting
				velocity = Vector3.ZERO
				return true
	return false


## The wool color a dye gives.
static func _dye_color(item_name: String) -> String:
	return Items.DYE_COLORS.get(item_name, "")


func _update_wool() -> void:
	if _model.is_empty():
		return
	for part: Dictionary in _model.spec.parts:
		if part.get("saddle", false):
			(_model.instances[part.name] as MeshInstance3D).visible = saddled
		if part.get("collar", false):
			# A red collar on tame wolves.
			var collar: MeshInstance3D = _model.instances[part.name]
			collar.visible = tamed
			collar.set_instance_shader_parameter("tint", Color(0.85, 0.15, 0.15))
	if mob_type != "sheep":
		return
	# The fleece: the model's parts marked "wool" (body, head and legs).
	for part: Dictionary in _model.spec.parts:
		if part.get("wool", false):
			var instance: MeshInstance3D = _model.instances[part.name]
			instance.visible = not sheared
			instance.set_instance_shader_parameter("tint", WOOL_TINTS.get(wool_color, Color.WHITE))


## A wolf's skin like Beta's: mob/wolf_tame.png when tame, wolf_angry.png
## when angry, else wolf.png (a texture pack can draw each).
var _wolf_skin := ""


func _update_wolf_skin() -> void:
	var skin := "wolf_tame" if tamed else ("wolf_angry" if angry else "")
	if skin == _wolf_skin:
		return
	_wolf_skin = skin
	var material: Material = MobModels.state_material("pale_wolf", skin) if skin != "" else null
	for part: Dictionary in _model.spec.parts:
		if part.get("texture", "pale_wolf") == "pale_wolf":
			(_model.instances[part.name] as MeshInstance3D).material_override = material


# --- Health ---------------------------------------------------------------------------

## Hurt by anything (a hit, a fall, fire): the sound, and animals run;
## who did it is hurt_by's (a fall makes no wolf angry at anyone).
func damage(amount: int, from: Variant = null) -> bool:
	var hurt := super(amount, from)
	if hurt and not is_dead():
		_sound("hurt", 1.0)
		if not is_hostile():
			_panic = PANIC_TICKS # (monsters don't run, like Beta's)
			_wander = Vector3.INF
			love_ticks = 0
		if from is Vector3:
			_flee_from = from
	return hurt


## Hit by a player or a creature: animals run from it; monsters and wolves
## fight back (a wild wolf's pack with it), a tame wolf forgives its player;
## the player's tame wolves go after what the player hits.
func hurt_by(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker == self:
		return
	_last_attacker = attacker
	_flee_from = attacker.global_position
	# Beta: a creeper killed by a skeleton's arrow drops a music disc.
	if mob_type == "creeper" and is_dead() and death_ticks == 0 and attacker is Mob and (attacker as Mob).mob_type == "skeleton":
		var disc := "music_disc_13" if randi_range(0, 1) == 0 else "music_disc_cat"
		world.items.spawn(Items.id_of(disc), 1, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)))
	if _is_player(attacker) and not (mob_type == "wolf" and tamed):
		guard_owner_against(self)
	if is_dead():
		return
	if mob_type == "wolf":
		if tamed and _is_player(attacker):
			return
		sitting = false
		_anger(attacker)
		if not tamed:
			for entity in world.entities.near(center(), PACK):
				if entity is Mob and entity != self and (entity as Mob).mob_type == "wolf" and not (entity as Mob).tamed:
					(entity as Mob)._anger(attacker)
		return
	if spec.get("hostile", false):
		target = attacker
		angry = mob_type == "spider" or angry


func _anger(attacker: Node3D) -> void:
	target = attacker
	angry = true
	_path.clear()


## The tame wolves around a player go after `mob` (the player hit it).
static func guard_owner_against(mob: Mob) -> void:
	if mob.world == null:
		return
	for entity in mob.world.entities.near(mob.center(), 24.0):
		if entity is Mob and entity != mob and (entity as Mob).mob_type == "wolf" and (entity as Mob).tamed and not (entity as Mob).sitting:
			(entity as Mob).target = mob
			(entity as Mob).angry = true


func _on_death() -> void:
	_sound("death", 1.0)
	if mob_type == "slime" and size > 1:
		for i in randi_range(2, 4):
			var child := Mob.create("slime")
			child.size = size / 2
			world.entities.spawn(child, feet() + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)))
		return
	if not GameRules.flag(world, "doMobLoot") or is_baby():
		return # (babies drop nothing, like modern's)
	for drop: Array in spec.drops:
		var count := randi_range(drop[1], drop[2])
		var item: String = drop[0]
		if fire_ticks > 0 and COOKED.has(item):
			item = COOKED[item] # (burnt to death: cooked)
		if count > 0:
			world.items.spawn(Items.id_of(item), count, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)))
	if mob_type == "sheep" and not sheared:
		world.items.spawn(Blocks.id_of(wool_color + "_wool"), 1, center(), Vector3(0, 0.2, 0))
	for slot in armor.size():
		if armor.count_at(slot) > 0 and Items.is_block(armor.id_at(slot)) and _picked[slot] == 0:
			continue # (a Halloween pumpkin)
		if armor.count_at(slot) > 0 and (_picked[slot] == 1 or randf() < ARMOR_DROP):
			world.items.spawn(armor.id_at(slot), 1, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)),
				ItemEntities.PICKUP_DELAY, armor.damage_at(slot))
	if hand.count_at(0) > 0 and _picked[4] == 1:
		world.items.spawn(hand.id_at(0), 1, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)),
			ItemEntities.PICKUP_DELAY, hand.damage_at(0))



## What it says now and then: a wolf like Beta's EntityWolf (growls when
## angry; else 1 in 3 whines when tame and hurt below 10 or pants; else
## barks); the others their "say".
func _living_sound() -> String:
	if mob_type != "wolf":
		return "say"
	if angry:
		return "growl"
	if randi_range(0, 2) == 0:
		return "whine" if tamed and health < 10 else "panting"
	return "say"


func _sound(kind: String, volume: float) -> void:
	var group: String = spec.get("sound", "")
	if group != "":
		Sounds.play("mob/%s/%s" % [group, kind], center(), volume, Sounds.beta_pitch() * (1.5 if mob_type == "slime" and size == 1 else 1.0))


# --- Drawing --------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if _model.is_empty():
		return
	if not _in_view():
		# Out of the camera's sight: only turned, not posed or lit (that was
		# most of the frame's script time with many creatures around).
		rotation.y = lerp_angle(_prev_yaw, _yaw, TickLoop.alpha)
		return
	if mob_type == "wolf":
		_update_wolf_skin()
	var alpha := TickLoop.alpha
	# The heading between the last two ticks (no jumps 20 times a second).
	rotation.y = lerp_angle(_prev_yaw, _yaw, alpha)
	var moved := Vector2(_x - _prev.x, _z - _prev.z).length() if vehicle == null else 0.0 # carried, not walking
	_limb_amount = lerpf(_limb_amount, minf(moved * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += moved * 4.0 * delta * 20.0
	var swing := cos(_limb_swing * 0.6662) * 1.4 * _limb_amount
	_frame_delta = delta
	var t := age + alpha
	var smooth := minf(delta * 12.0, 1.0)
	_jump = lerpf(_jump, MobAnimation.jump_amount(velocity.y, on_ground, in_water), smooth)
	_fall = lerpf(_fall, MobAnimation.fall_amount(velocity.y, on_ground, in_water), smooth)
	if age >= _next_look:
		# Now and then glances somewhere else, or back ahead.
		_next_look = age + randi_range(MobAnimation.LOOK_AROUND.x, MobAnimation.LOOK_AROUND.y)
		_idle_look = Vector2(randf_range(-0.7, 0.7), randf_range(-0.3, 0.2)) if randf() < 0.6 else Vector2.ZERO
	var parts: Dictionary = _model.parts
	var biped := parts.has("right_arm") and parts.has("right_leg")
	if biped:
		# Zombies and skeletons raise their arms when after someone, at rest
		# they hang (and swing as they walk).
		var after := (_aiming if puppet else (target != null and is_hostile())) and ARMORED.has(mob_type)
		_aim = move_toward(_aim, 1.0 if after else 0.0, delta * 4.0)
		MobAnimation.pose_biped(parts, t, _limb_swing, _limb_amount, _held != null, _aim if ARMORED.has(mob_type) else 0.0, _jump, _fall)
		if _held:
			_held.transform = _held_rest.interpolate_with(_held_aim, _aim)
		if vehicle:
			# Sitting in a boat or minecart: the legs straight ahead, a little apart.
			for side: Array in [["right_leg", -1.0], ["left_leg", 1.0]]:
				(parts[side[0]] as Node3D).rotation = Vector3(-PI * 2.0 / 5.0, float(side[1]) * PI / 10.0, 0)
	for part: Dictionary in _model.spec.parts:
		var node: Node3D = parts.get(part.name)
		if node == null:
			continue # moves with its parent part
		match str(part.role):
			"leg_a", "leg_b":
				if not biped:
					var front := str(part.name).begins_with("leg_f") or mob_type == "chicken"
					MobAnimation.pose_quadruped_leg(node, front, part.role == "leg_a", _limb_swing, _limb_amount, _jump, _fall)
			"arm_right", "arm_left":
				pass # posed with the legs (pose_biped)
			"wing_right", "wing_left":
				var flap := 0.0 if on_ground else sin(Time.get_ticks_msec() / 40.0) * 0.8 + 0.8
				node.rotation.z = flap if part.role == "wing_left" else -flap
			"tentacle":
				# Beta's ModelSquid: each tentacle opens outward, away from
				# the body's middle, by the stroke's angle (all of them at
				# once: a fan when they open, straight down when closed).
				node.rotation = Vector3(lerpf(_squid_prev_tentacles, _squid_tentacles, TickLoop.alpha),
					atan2(-node.position.x, -node.position.z), 0.0)
			"tail":
				# Wild wolves hold the tail low; tame ones high, lower when hurt
				# (the classic health gauge).
				node.rotation.x = (0.55 - (max_health - health) * 0.02) * PI if tamed else PI / 5.0
				if sitting:
					node.rotation.x = PI / 4.0
			"head":
				_turn_head(node)
			_:
				if str(part.role).begins_with("spider_leg"):
					MobAnimation.pose_spider_leg(node, str(part.role), swing)
	if mob_type == "wolf" and sitting:
		_model.root.position.y = -0.15
	if mob_type == "slime":
		# The game's squish: stretched up when it jumps, squashed on landing.
		if on_ground and not _was_on_ground:
			_squish = -0.5
		elif not on_ground and _was_on_ground and velocity.y > 0.0:
			_squish = 1.0
		_was_on_ground = on_ground
		_squish *= pow(0.6, delta * 20.0)
		_model.root.scale = MobAnimation.slime_scale(_squish, size) * _base_scale
	if mob_type == "squid":
		# Beta's RenderSquid: leaned along its way (its pitch: -90 swimming
		# level, 0 going up), around its middle, between the last two ticks.
		# (Not spun about its own length on every push like Beta's: it
		# turned half round each time.)
		var lean := deg_to_rad(-lerpf(_squid_prev_pitch, _squid_pitch, TickLoop.alpha))
		var middle := Vector3(0, height * 0.5, 0)
		var size := float(MobModels.model("squid").get("scale", 1.0)) / 16.0
		_model.root.transform = Transform3D(Basis(Vector3.RIGHT, lean), middle) \
			* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), -middle)
	var brightness := world.brightness_at(center()) if world else 1.0
	var flash := 0.0
	if mob_type == "creeper":
		# Beta's RenderCreeper: the fuse (0..1, between ticks) swells it -
		# hardly at first, then fast (to the 4th power), wider (+40%) than
		# taller (+10%), trembling a little - and lays a faint white over
		# its skin (up to 20%) that blinks every tenth of the fuse.
		var fuse := clampf(lerpf(_prev_fuse, _fuse, alpha) / (CREEPER_FUSE - 2), 0.0, 1.0)
		var tremble := 1.0 + sin(fuse * 100.0) * fuse * 0.01
		var swell := fuse * fuse * fuse * fuse
		var base := float(MobModels.model(mob_type).get("scale", 1.0)) / 16.0
		_model.root.scale = Vector3((1.0 + swell * 0.4) * tremble, (1.0 + swell * 0.1) / tremble, (1.0 + swell * 0.4) * tremble) * base
		if fuse > 0.0 and int(fuse * 10.0) % 2 == 1:
			flash = fuse * 0.2
	if _held:
		FallingBlocks.light(_held, brightness)
	if powered:
		# (the glow's picture slides with the game's ticks, one material for all)
		MobModels.power_material().set_shader_parameter("ticks", float(TickLoop.tick_count) + TickLoop.alpha)
	for mesh: MeshInstance3D in _model.meshes:
		if mesh.has_meta("block"):
			FallingBlocks.light(mesh, brightness)
			continue
		mesh.set_instance_shader_parameter("brightness", 1.0 if mesh.has_meta("glow") else brightness)
		mesh.set_instance_shader_parameter("hurt", 1.0 if hurt_ticks > 0 or is_dead() else 0.0)
		mesh.set_instance_shader_parameter("flash", flash)
	if is_dead():
		# Falls over sideways, like the classic game.
		var fall_t := minf((death_ticks + alpha) / DEATH_TICKS * 1.6, 1.0)
		_model.root.rotation.z = sqrt(fall_t) * PI / 2.0


func _death_puff() -> void:
	if world:
		world.particles.poof(hit_box(), 20)


func _turn_head(node: Node3D) -> void:
	if _look_at == Vector3.INF:
		# Idle: turns slowly toward where it glances, with a little nod.
		var ease := minf(_frame_delta * 3.0, 1.0)
		var idle := _idle_look if _limb_amount < 0.3 else Vector2.ZERO
		node.rotation.y = lerpf(node.rotation.y, idle.x, ease)
		node.rotation.x = lerpf(node.rotation.x, idle.y + MobAnimation.head_bob(age + TickLoop.alpha), ease)
		node.rotation.z = 0.0
		return
	var local := global_transform.affine_inverse() * _look_at
	var head := node.global_position
	var to := _look_at - head
	var yaw := atan2(local.x, local.z)
	node.rotation.y = clampf(yaw, -1.2, 1.2)
	node.rotation.x = clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.8, 0.8)


# --- Saving ---------------------------------------------------------------------------

func net_state() -> Dictionary:
	var state := super()
	state.merge({"fuse": _fuse, "angry": angry, "sheared": sheared, "sitting": sitting, "saddled": saddled, "tamed": tamed,
		"baby": is_baby(), "love": love_ticks > 0, "aiming": target != null and is_hostile(),
		"mount": vehicle.net_id if vehicle is Mob and is_instance_valid(vehicle) else 0, "powered": powered})
	if ARMORED.has(mob_type):
		state["gear"] = PackedInt32Array([armor.id_at(0) if armor.count_at(0) > 0 else 0, armor.id_at(1) if armor.count_at(1) > 0 else 0,
			armor.id_at(2) if armor.count_at(2) > 0 else 0, armor.id_at(3) if armor.count_at(3) > 0 else 0,
			hand.id_at(0) if hand.count_at(0) > 0 else 0])
	return state


func apply_net_state(at: Vector3, yaw: float, state: Dictionary) -> void:
	var was_hurt := hurt_ticks > 0
	super(at, yaw, state)
	if hurt_ticks > 0 and not was_hurt and death_ticks < 0:
		_sound("hurt", 1.0) # (the host's creature was hit)
	_fuse = int(state.get("fuse", 0))
	angry = bool(state.get("angry", false))
	sitting = bool(state.get("sitting", false))
	saddled = bool(state.get("saddled", false))
	tamed = bool(state.get("tamed", false))
	_aiming = bool(state.get("aiming", false))
	powered = bool(state.get("powered", false)) and mob_type == "creeper"
	var mount := int(state.get("mount", 0))
	if mount == 0:
		if vehicle is Mob:
			vehicle = null
	elif world and (vehicle == null or vehicle.net_id != mount):
		var ridden := world.entities.by_net_id(mount)
		if ridden is Mob:
			vehicle = ridden # (drawn on its seat: Entity._process)
	var gear: Variant = state.get("gear")
	if gear is PackedInt32Array and (gear as PackedInt32Array).size() == 5:
		# (what it picked up or wore out on the host)
		for slot in 4:
			var id: int = gear[slot]
			if id != (armor.id_at(slot) if armor.count_at(slot) > 0 else 0):
				armor.set_slot(slot, id if Items.exists(id) else Blocks.AIR, 1 if id != 0 and Items.exists(id) else 0)
		if gear[4] != (hand.id_at(0) if hand.count_at(0) > 0 else 0):
			hand.set_slot(0, gear[4] if Items.exists(gear[4]) else Blocks.AIR, 1 if gear[4] != 0 and Items.exists(gear[4]) else 0)
	love_ticks = LOVE_TICKS if bool(state.get("love", false)) else 0
	if bool(state.get("baby", false)) != is_baby():
		baby_ticks = GROW_TICKS if not is_baby() else 0
		_apply_size() # (born or grown up on the host)
	if bool(state.get("sheared", false)) != sheared:
		sheared = not sheared
		_update_wool()


func save_state() -> Dictionary:
	var state := super()
	state.merge({"sheared": sheared, "wool": wool_color, "size": size, "tamed": tamed, "sitting": sitting, "saddled": saddled, "no_ai": no_ai,
		"baby": baby_ticks, "love": love_ticks, "breed_cooldown": breed_cooldown})
	if rider is Mob and is_instance_valid(rider) and not rider.removed and not rider.is_dead() and rider.vehicle == self:
		state["rider"] = rider.save_state() # (a spider jockey: saved as one)
	if not armor.is_empty():
		state["armor"] = armor.save_state()
	if not hand.is_empty():
		state["hand"] = hand.save_state()
	if powered:
		state["powered"] = true
	if persistent:
		state["persistent"] = true
		state["picked"] = Array(_picked)
	return state


## A client's copy: the heading drawn between snapshots too.
func puppet_tick() -> void:
	_prev_yaw = _yaw
	super()
	if love_ticks > 0 and age % 10 == 0:
		_love_heart()


func load_state(saved: Dictionary) -> void:
	super(saved)
	_yaw = rotation.y
	_prev_yaw = _yaw
	sheared = saved.get("sheared", false)
	wool_color = saved.get("wool", "white")
	size = saved.get("size", 1)
	tamed = saved.get("tamed", false)
	sitting = saved.get("sitting", false)
	saddled = saved.get("saddled", false)
	no_ai = saved.get("no_ai", false)
	baby_ticks = saved.get("baby", 0)
	love_ticks = saved.get("love", 0)
	breed_cooldown = saved.get("breed_cooldown", 0)
	if saved.has("armor") and saved.armor is Dictionary:
		armor.load_state(saved.armor)
	if saved.has("hand") and saved.hand is Dictionary:
		hand.load_state(saved.hand)
	var ridden: Variant = saved.get("rider")
	if ridden is Dictionary and not puppet and world and not world.remote and Mob.TYPES.has(str(ridden.get("type", ""))):
		# Its rider back on its back (a network client's copy gets the
		# host's rider on its own).
		var back := Mob.create(str(ridden.type))
		world.entities.spawn(back, feet())
		back.load_state(ridden)
		back.vehicle = self
		rider = back
	persistent = bool(saved.get("persistent", false))
	powered = bool(saved.get("powered", false)) and mob_type == "creeper"
	var picked: Variant = saved.get("picked")
	if picked is Array and (picked as Array).size() == 5:
		for i in 5:
			_picked[i] = 1 if int(picked[i]) != 0 else 0
	_update_wool()
	_apply_size()
	health = mini(saved.get("health", max_health), max_health)
	_update_wool()
