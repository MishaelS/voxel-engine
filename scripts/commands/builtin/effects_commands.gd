class_name EffectsCommands
extends RefCounted
## /particle <name> [<pos>] [<count>]               - shows particles
## /particle block <block> [<pos>] [<count>]        - a block's breaking bits
## /playsound <sound> [<pos>] [<volume>] [<pitch>]  - plays a sound (a
##   group of assets/sounds like "mob/zombie/say" or "random/explode"),
##   in the world at <pos> or straight to the ears without it.
## Both only show / sound on this computer.

const MAX_COUNT := 1000
## Particle name -> how BlockParticles shows one at a point.
const PARTICLES := ["smoke", "steam", "embers", "lava", "explosion", "dust", "bubble", "splash", "rain",
	"note", "heart", "flame", "damage_indicator", "crit", "sweep_attack", "void"]


static func register(d: CommandDispatcher) -> void:
	var particle := CommandNode.literal("particle").describe("Shows particles")
	for particle_name: String in PARTICLES:
		particle.then(_with_position(CommandNode.literal(particle_name), func(ctx: CommandContext, at: Vector3, count: int) -> int:
			return _particle(ctx, particle_name, -1, at, count)))
	particle.then(CommandNode.literal("block")
		.then(_with_position(CommandNode.argument("block", BlockArgument.new()), func(ctx: CommandContext, at: Vector3, count: int) -> int:
			return _particle(ctx, "block", ctx.arg("block"), at, count))))
	d.register(particle)

	var sound_names := func() -> PackedStringArray:
		var names := PackedStringArray((Sounds.get("_groups") as Dictionary).keys())
		names.sort()
		return names
	d.register(CommandNode.literal("playsound").describe("Plays a sound")
		.then(CommandNode.argument("sound", ChoiceArgument.new(sound_names, "sound"))
			.executes(func(ctx: CommandContext) -> int: return _play(ctx, null, 1.0, 1.0))
			.then(CommandNode.argument("pos", PositionArgument.new())
				.executes(func(ctx: CommandContext) -> int: return _play(ctx, ctx.arg("pos"), 1.0, 1.0))
				.then(CommandNode.argument("volume", FloatArgument.new(0.0, 4.0))
					.executes(func(ctx: CommandContext) -> int: return _play(ctx, ctx.arg("pos"), ctx.arg("volume"), 1.0))
					.then(CommandNode.argument("pitch", FloatArgument.new(0.5, 2.0)).executes(func(ctx: CommandContext) -> int:
						return _play(ctx, ctx.arg("pos"), ctx.arg("volume"), ctx.arg("pitch"))))))))


## `node` [<pos>] [<count>], calling show(ctx, at, count).
static func _with_position(node: CommandNode, show: Callable) -> CommandNode:
	return node.executes(func(ctx: CommandContext) -> int: return show.call(ctx, ctx.source.position() + Vector3(0, 1, 0), 1)) \
		.then(CommandNode.argument("pos", PositionArgument.new())
			.executes(func(ctx: CommandContext) -> int: return show.call(ctx, ctx.arg("pos"), 1))
			.then(CommandNode.argument("count", IntegerArgument.new(1, MAX_COUNT)).executes(func(ctx: CommandContext) -> int:
				return show.call(ctx, ctx.arg("pos"), ctx.arg("count")))))


static func _particle(ctx: CommandContext, particle_name: String, block: int, at: Vector3, count: int) -> int:
	var particles := ctx.source.world.particles
	if particles == null:
		return ctx.error(Lang.t("Nothing to show particles with"))
	for i in count:
		var point := at
		if count > 1:
			point += Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
		match particle_name:
			"smoke":
				particles.smoke(point, 1 if count > 1 else 8)
			"steam":
				particles.steam(point)
			"embers":
				particles.embers(point, 3)
			"lava":
				particles.lava_pop(point)
			"explosion":
				particles.explosion(point, 2.0)
			"dust":
				particles.redstone(point, 15)
			"bubble":
				particles.bubble(point)
			"splash":
				particles.splash(point)
			"rain":
				particles.rain_splash(point, false)
			"note":
				particles.note(point, randi_range(0, 24))
			"heart":
				particles.hearts(point)
			"flame":
				particles.torch(point)
			"damage_indicator":
				particles.damage(point, 4)
			"crit":
				particles.crit(point)
			"sweep_attack":
				particles.sweep(point)
			"void":
				particles.void_speck(point)
			"block":
				particles.break_block(Vector3i(point.floor()), block)
	return ctx.feedback(Lang.t("Displaying particle %s") % particle_name)


static func _play(ctx: CommandContext, at: Variant, volume: float, pitch: float) -> int:
	var sound: String = ctx.arg("sound")
	Sounds.play(sound, at, volume, pitch)
	return ctx.feedback(Lang.t("Played sound %s") % sound)
