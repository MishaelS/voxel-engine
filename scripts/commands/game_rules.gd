class_name GameRules
extends RefCounted
## Registry of game rules (like /gamerule in the classic game). A rule is a
## name, an argument type for its value and a getter/setter on the world.
## The /gamerule command is generated from this list, so adding a rule is
## one register() call. Rules are saved with the world (VoxelWorld.save_state).
## Rules without a world variable of their own keep their value in the
## world's metadata (flag_rule); the game reads them with flag().

## name -> {type: ArgumentType, get: Callable(world) -> value, set: Callable(world, value)}
static var rules := {}
static var _registered := _register_all()


static func _register_all() -> bool:
	register("doDaylightCycle", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.clock.daylight_cycle,
		func(world: VoxelWorld, value: Variant) -> void: world.clock.daylight_cycle = value)
	register("doWeatherCycle", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.weather.cycle,
		func(world: VoxelWorld, value: Variant) -> void: world.weather.cycle = value)
	register("keepInventory", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.keep_inventory,
		func(world: VoxelWorld, value: Variant) -> void: world.keep_inventory = value)
	register("randomTickSpeed", IntegerArgument.new(0, 4096),
		func(world: VoxelWorld) -> Variant: return world.random_tick_speed,
		func(world: VoxelWorld, value: Variant) -> void: world.random_tick_speed = value)
	# Natural spawning of creatures (MobSpawner; spawner blocks go on).
	register("doMobSpawning", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.get_meta("doMobSpawning", true),
		func(world: VoxelWorld, value: Variant) -> void:
			world.set_meta("doMobSpawning", value)
			if world.entities and not world.remote:
				if world.entities.spawner == null:
					world.entities.spawner = MobSpawner.new(world)
				world.entities.spawner.enabled = value)
	flag_rule("doFireTick")          # fire spreads and burns out (FireBehavior)
	flag_rule("mobGriefing")         # creepers' explosions break blocks (Explosion)
	flag_rule("doMobLoot")           # creatures drop things (Mob)
	flag_rule("doTileDrops")         # broken blocks drop items (VoxelWorld.destroy_block)
	flag_rule("sendCommandFeedback") # commands say what they did (CommandContext)
	return true


static func register(rule_name: String, type: ArgumentType, getter: Callable, setter: Callable) -> void:
	rules[rule_name] = {"type": type, "get": getter, "set": setter}


## A true/false rule kept in the world's metadata (true by default).
static func flag_rule(rule_name: String) -> void:
	register(rule_name, BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.get_meta(rule_name, true),
		func(world: VoxelWorld, value: Variant) -> void: world.set_meta(rule_name, value))


## A rule's value in `world` (true for any rule without a world).
static func flag(world: VoxelWorld, rule_name: String) -> bool:
	if world == null or not rules.has(rule_name):
		return true
	return bool(rules[rule_name].get.call(world))


static func names() -> PackedStringArray:
	var result := PackedStringArray(rules.keys())
	result.sort()
	return result
