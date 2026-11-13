class_name GiveCommand
extends RefCounted
## /give <targets> <item> [<count>] [<damage>]  - puts items into players'
## inventories (what does not fit drops at their feet); damage is the
## item's wear or kind (like Beta's /give <id> <count> <damage>).
## /clear [<targets>] [<item>] [<max count>]  - takes items away from the
## inventory and the armor (max count 0: only counts them).

const MAX_COUNT := Inventory.SIZE * Items.MAX_STACK


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("give").describe("Gives items to players")
		.then(CommandNode.argument("targets", EntityArgument.new(false, true))
			.then(CommandNode.argument("item", ItemArgument.new())
				.executes(func(ctx: CommandContext) -> int: return _give(ctx, 1, 0))
				.then(CommandNode.argument("count", IntegerArgument.new(1, MAX_COUNT))
					.executes(func(ctx: CommandContext) -> int: return _give(ctx, ctx.arg("count"), 0))
					.then(CommandNode.argument("damage", IntegerArgument.new(0, 32767))
						.executes(func(ctx: CommandContext) -> int: return _give(ctx, ctx.arg("count"), ctx.arg("damage"))))))))

	var clear_node := CommandNode.argument("targets", EntityArgument.new(false, true)) \
		.executes(func(ctx: CommandContext) -> int: return _clear(ctx, ctx.targets("targets"), -1, -1)) \
		.then(CommandNode.argument("item", ItemArgument.new())
			.executes(func(ctx: CommandContext) -> int: return _clear(ctx, ctx.targets("targets"), ctx.arg("item"), -1))
			.then(CommandNode.argument("max count", IntegerArgument.new(0, MAX_COUNT))
				.executes(func(ctx: CommandContext) -> int:
					return _clear(ctx, ctx.targets("targets"), ctx.arg("item"), ctx.arg("max count")))))
	d.register(CommandNode.literal("clear").describe("Clears items from player inventories")
		.executes(func(ctx: CommandContext) -> int:
			return _clear(ctx, [ctx.source.origin] if ctx.source.origin else [], -1, -1))
		.then(clear_node))


static func _give(ctx: CommandContext, count: int, damage: int) -> int:
	var targets := ctx.targets("targets")
	if targets.is_empty():
		return ctx.error(Lang.t("No player was found"))
	var id: int = ctx.arg("item")
	var given := 0
	for target: Variant in targets:
		if target is Player:
			var player := target as Player
			var left := player.inventory.add(id, count, damage)
			if left > 0 and player.world:
				player.world.items.spawn(id, left, player.global_position + Vector3(0, 0.5, 0), Vector3.ZERO, 0, damage)
			Sounds.play("random/pop", null, 0.2, ((randf() - randf()) * 0.7 + 1.0) * 2.0)
			given += 1
		elif target is RemotePlayer:
			# A client's player: its own computer fills its inventory (Net).
			var peer := (target as RemotePlayer).peer_id
			var left := count
			while left > 0:
				var stack := mini(left, Items.max_stack(id))
				Net.rpc_id(peer, "_give", id, stack, damage)
				left -= stack
			given += 1
	if given == 0:
		return ctx.error(Lang.t("No player was found"))
	var item_name := Items.display_name(id)
	if given == 1:
		ctx.feedback(Lang.t("Gave %d [%s] to %s") % [count, item_name, CommandTargets.name_of(targets[0])])
	else:
		ctx.feedback(Lang.t("Gave %d [%s] to %d players") % [count, item_name, given])
	return given


## Removes up to `max_count` (-1: all) of `item` (-1: anything).
static func _clear(ctx: CommandContext, targets: Array, item: int, max_count: int) -> int:
	if targets.is_empty():
		return ctx.error(Lang.t("No player was found"))
	var total := 0
	var cleared := 0
	for target: Variant in targets:
		if not target is Player:
			ctx.error(Lang.t("Another player's inventory can't be changed from here"))
			continue
		var player := target as Player
		var found := 0
		for container: Inventory in [player.inventory, player.armor]:
			for slot in container.size():
				var slot_count := container.count_at(slot)
				if slot_count <= 0 or (item >= 0 and container.id_at(slot) != item):
					continue
				if max_count < 0:
					found += slot_count
					container.take(slot, slot_count)
				elif max_count == 0:
					found += slot_count
				else:
					var taken := mini(slot_count, max_count - found)
					if taken > 0:
						found += taken
						container.take(slot, taken)
		total += found
		if found > 0:
			cleared += 1
	var one := targets.size() == 1
	var who := CommandTargets.name_of(targets[0])
	if total == 0:
		if one:
			return ctx.error(Lang.t("No items were found on player %s") % who)
		return ctx.error(Lang.t("No items were found on %d players") % targets.size())
	if max_count == 0:
		if one:
			ctx.feedback(Lang.t("Found %d matching item(s) on player %s") % [total, who])
		else:
			ctx.feedback(Lang.t("Found %d matching item(s) on %d players") % [total, targets.size()])
	elif one:
		ctx.feedback(Lang.t("Removed %d item(s) from player %s") % [total, who])
	else:
		ctx.feedback(Lang.t("Removed %d item(s) from %d players") % [total, cleared])
	return total
