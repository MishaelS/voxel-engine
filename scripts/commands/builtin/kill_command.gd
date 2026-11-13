class_name KillCommand
extends RefCounted
## /kill [<targets>]  - kills entities (the executor without targets):
## creatures die (with their drops), things and dropped items vanish,
## players die even in creative.
## /damage <targets> <amount>  - hurts entities like a hit (half hearts).


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("kill").describe("Kills entities (players, mobs, items...)")
		.executes(func(ctx: CommandContext) -> int:
			return _kill(ctx, [ctx.source.origin] if ctx.source.origin else []))
		.then(CommandNode.argument("targets", EntityArgument.new()).executes(func(ctx: CommandContext) -> int:
			return _kill(ctx, ctx.targets("targets")))))
	d.register(CommandNode.literal("damage").describe("Hurts entities")
		.then(CommandNode.argument("targets", EntityArgument.new())
			.then(CommandNode.argument("amount", IntegerArgument.new(1, 1000)).executes(_damage))))


static func _kill(ctx: CommandContext, targets: Array) -> int:
	var killed := []
	for target: Variant in targets:
		var target_name := CommandTargets.name_of(target)
		if CommandTargets.kill(target):
			killed.append(target_name)
	if killed.is_empty():
		return ctx.error(Lang.t("No entity was found"))
	if killed.size() == 1:
		ctx.feedback(Lang.t("Killed %s") % killed[0])
	else:
		ctx.feedback(Lang.t("Killed %d entities") % killed.size())
	return killed.size()


static func _damage(ctx: CommandContext) -> int:
	var amount: int = ctx.arg("amount")
	var hurt := []
	for target: Variant in ctx.targets("targets"):
		if CommandTargets.damage(target, amount):
			hurt.append(CommandTargets.name_of(target))
	if hurt.is_empty():
		return ctx.error(Lang.t("No entity was damaged"))
	if hurt.size() == 1:
		ctx.feedback(Lang.t("Applied %d damage to %s") % [amount, hurt[0]])
	else:
		ctx.feedback(Lang.t("Applied %d damage to %d entities") % [amount, hurt.size()])
	return hurt.size()
