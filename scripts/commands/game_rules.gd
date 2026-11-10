class_name GameRules
extends RefCounted
## Registry of game rules (like /gamerule in the classic game). A rule is a
## name, an argument type for its value and a getter/setter on the world.
## The /gamerule command is generated from this list, so adding a rule is
## one register() call.

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
	register("doHunger", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.hunger,
		func(world: VoxelWorld, value: Variant) -> void: world.hunger = value)
	register("keepInventory", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.keep_inventory,
		func(world: VoxelWorld, value: Variant) -> void: world.keep_inventory = value)
	register("naturalRegeneration", BoolArgument.new(),
		func(world: VoxelWorld) -> Variant: return world.natural_regeneration,
		func(world: VoxelWorld, value: Variant) -> void: world.natural_regeneration = value)
	register("randomTickSpeed", IntegerArgument.new(0, 4096),
		func(world: VoxelWorld) -> Variant: return world.random_tick_speed,
		func(world: VoxelWorld, value: Variant) -> void: world.random_tick_speed = value)
	return true


static func register(rule_name: String, type: ArgumentType, getter: Callable, setter: Callable) -> void:
	rules[rule_name] = {"type": type, "get": getter, "set": setter}


static func names() -> PackedStringArray:
	var result := PackedStringArray(rules.keys())
	result.sort()
	return result
