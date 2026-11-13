class_name ChatCommands
extends RefCounted
## /list                          - who is in the game
## /me <action>                   - "* Name action" in the chat
## /msg <targets> <message>       - a private message (also /tell, /w)


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("list").describe("Lists the players in the game")
		.executes(func(ctx: CommandContext) -> int:
			var names := PackedStringArray()
			if Net.is_online():
				for id: int in Net.players:
					names.append(str(Net.players[id].name))
			else:
				names.append(Net.player_name if Net.player_name != "" else ctx.source.name)
			names.sort()
			return ctx.feedback(Lang.t("There are %d players online: %s") % [names.size(), ", ".join(names)])))
	d.register(CommandNode.literal("me").describe("Says what you are doing")
		.then(CommandNode.argument("action", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			var action: String = ctx.arg("action")
			ctx.source.send("* %s %s" % [ctx.source.name, action], CommandSource.MessageKind.CHAT)
			if Net.is_online() and ctx.source.player() != null:
				Net.say("* " + action) # the others see it as this player's line
			return 1)))
	for command_name: String in ["msg", "tell", "w"]:
		d.register(CommandNode.literal(command_name).describe("Sends a private message to players")
			.then(CommandNode.argument("targets", EntityArgument.new(false, true))
				.then(CommandNode.argument("message", MessageArgument.new()).executes(_whisper))))


static func _whisper(ctx: CommandContext) -> int:
	var message: String = ctx.arg("message")
	var targets := ctx.targets("targets")
	if targets.is_empty():
		return ctx.error(Lang.t("No player was found"))
	for target: Variant in targets:
		var text := Lang.t("%s whispers to you: %s") % [ctx.source.name, message]
		if target is RemotePlayer:
			Net.rpc_id((target as RemotePlayer).peer_id, "_command_output", text, CommandSource.MessageKind.INFO)
		elif target is Player and target != ctx.source.origin:
			var chat := (target as Player).get_tree().get_first_node_in_group("chat") as Chat
			if chat:
				chat.add_message(text, CommandSource.MessageKind.INFO)
		ctx.source.send(Lang.t("You whisper to %s: %s") % [CommandTargets.name_of(target), message], CommandSource.MessageKind.INFO)
	return targets.size()
