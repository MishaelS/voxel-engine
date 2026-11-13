class_name SummonCommand
extends RefCounted
## /summon <entity> [<pos>] [<options>]  - makes an entity: any creature,
## item, tnt, arrow, boat, minecart (chest_ / furnace_), lightning_bolt or
## falling_block. Options are key=value words instead of the classic
## game's NBT:
##   creatures: no_ai=true health=<n>; slime: size=1|2|4; sheep: wool=<color>
##   sheared=true; pig: saddled=true; wolf: tamed=true angry=true sitting=true
##   item: item=<name> count=<n>; tnt: fuse=<ticks>; falling_block: block=<name>
## e.g. /summon slime ~ ~ ~ size=4   /summon item ~ ~1 ~ item=diamond count=5

const TYPES: Array[String] = ["item", "tnt", "arrow", "boat", "minecart", "chest_minecart", "furnace_minecart",
	"lightning_bolt", "falling_block"]
const BOOLS: Array[String] = ["true", "false"]
## Option -> the entity types it is for ("mob": every creature).
const APPLIES := {
	"no_ai": ["mob"], "health": ["mob"], "size": ["slime"], "wool": ["sheep"], "sheared": ["sheep"],
	"saddled": ["pig"], "tamed": ["wolf"], "angry": ["wolf"], "sitting": ["wolf"],
	"item": ["item"], "count": ["item"], "fuse": ["tnt"], "block": ["falling_block"],
}


static func entity_types() -> PackedStringArray:
	var names := PackedStringArray(Mob.TYPES.keys())
	names.append_array(TYPES)
	names.sort()
	return names


static func register(d: CommandDispatcher) -> void:
	var block_names := func() -> PackedStringArray:
		var names := PackedStringArray()
		for block in Blocks.types:
			if block.id != Blocks.AIR and block.in_catalog:
				names.append(block.name)
		return names
	var item_names := func() -> PackedStringArray:
		var names := PackedStringArray()
		for id in Items.catalog():
			names.append(Items.name_of(id))
		return names
	var options := OptionsArgument.new({
		"no_ai": BOOLS, "health": [], "size": ["1", "2", "4"], "wool": Mob.WOOL_COLORS, "sheared": BOOLS,
		"saddled": BOOLS, "tamed": BOOLS, "angry": BOOLS, "sitting": BOOLS,
		"item": item_names, "count": [], "fuse": [], "block": block_names,
	})
	d.register(CommandNode.literal("summon").describe("Summons an entity")
		.then(CommandNode.argument("entity", ChoiceArgument.new(entity_types, "entity type"))
			.executes(func(ctx: CommandContext) -> int: return _summon(ctx, ctx.source.position(), {}))
			.then(CommandNode.argument("pos", PositionArgument.new())
				.executes(func(ctx: CommandContext) -> int: return _summon(ctx, ctx.arg("pos"), {}))
				.then(CommandNode.argument("options", options).executes(func(ctx: CommandContext) -> int:
					return _summon(ctx, ctx.arg("pos"), ctx.arg("options")))))))


static func _summon(ctx: CommandContext, pos: Vector3, options: Dictionary) -> int:
	var world := ctx.source.world
	var type: String = ctx.arg("entity")
	for key: String in options:
		var applies: Array = APPLIES[key]
		if not (type in applies or ("mob" in applies and Mob.TYPES.has(type))):
			return ctx.error(Lang.t("Option '%s' does not apply to %s") % [key, type])
		if key in ["health", "count", "fuse"] and not (options[key] as String).is_valid_int():
			return ctx.error(Lang.t("Expected integer, got '%s'") % options[key])
	if not world.is_inside(Vector3i(pos.floor())):
		return ctx.error(Lang.t("That position is not loaded"))
	var display := Lang.t(type.capitalize())
	match type:
		"item":
			var id := Items.id_of(options.get("item", "stone"))
			var count := clampi(int(options.get("count", "1")), 1, Items.MAX_STACK)
			world.items.spawn(id, count, pos, Vector3.ZERO, 10)
			display = Items.display_name(id)
		"falling_block":
			var id := Blocks.id_of(options.get("block", "sand"))
			world.falling_blocks.spawn(Vector3i(pos.floor()), id)
			display = Blocks.display_name(id)
		"lightning_bolt":
			LightningBolt.strike(world, Vector3i(pos.floor()))
		_:
			var entity := world.entities.create(type)
			if entity == null:
				return ctx.error(Lang.t("Unable to summon entity"))
			if entity is Mob:
				_set_up_mob(entity as Mob, options)
			elif entity is PrimedTnt and options.has("fuse"):
				(entity as PrimedTnt).fuse = maxi(int(options.fuse), 0)
			world.entities.spawn(entity, pos)
			if entity is Mob and options.has("health"):
				entity.health = clampi(int(options.health), 1, entity.max_health)
	return ctx.feedback(Lang.t("Summoned new %s") % display)


## Options set before the creature is added (its model and size depend
## on them).
static func _set_up_mob(mob: Mob, options: Dictionary) -> void:
	if options.has("size"):
		mob.size = int(options.size)
	if options.has("wool"):
		mob.wool_color = options.wool
	mob.sheared = options.get("sheared", "false") == "true"
	mob.saddled = options.get("saddled", "false") == "true"
	mob.tamed = options.get("tamed", "false") == "true"
	mob.angry = options.get("angry", "false") == "true"
	mob.sitting = options.get("sitting", "false") == "true"
	if "no_ai" in mob:
		mob.set("no_ai", options.get("no_ai", "false") == "true")
