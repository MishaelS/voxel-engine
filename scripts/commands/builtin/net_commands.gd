class_name NetCommands
extends RefCounted
## The host's commands in a network game:
## /players          - who is here, with their tags (#first 8 of the hash)
##                     and addresses
## /kick <player>    - sends a player away
## /ban <player>     - bans a player's tag (their computer) and kicks them
## /pardon <tag|name> - lifts a ban
## /invite           - the invite code and the LAN addresses (copies the code)


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("players").describe("Lists the players and their tags (host)")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			return ctx.feedback(Net.describe_players())))
	d.register(CommandNode.literal("kick").describe("Sends a player away (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.kick(ctx.arg("player"))
			return ctx.feedback(Lang.t("Kicked %s") % name) if name != "" else ctx.error(Lang.t("No such player")))))
	d.register(CommandNode.literal("ban").describe("Bans a player's computer from this server (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.ban(ctx.arg("player"))
			return ctx.feedback(Lang.t("Banned %s") % name) if name != "" else ctx.error(Lang.t("No such player")))))
	d.register(CommandNode.literal("pardon").describe("Lifts a ban by tag or name (host)")
		.then(CommandNode.argument("tag", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.pardon(ctx.arg("tag"))
			return ctx.feedback(Lang.t("Unbanned %s") % name) if name != "" else ctx.error(Lang.t("No such ban")))))
	d.register(CommandNode.literal("invite").describe("Shows the invite code and copies it (host)")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			return ctx.feedback(invite_text(true))))


## The invite code (or why there's none) and the LAN addresses, for the chat.
## With `copy`, the code goes to the clipboard.
static func invite_text(copy: bool) -> String:
	var lines := PackedStringArray()
	var code := Net.invite_code()
	match Net.port_forward.state:
		PortForward.State.OPEN:
			if copy:
				DisplayServer.clipboard_set(code)
			lines.append(Lang.t("Invite code: %s (copied)" if copy else "Invite code: %s") % code)
			lines.append(Lang.t("Only share the code with people you trust"))
		PortForward.State.WORKING:
			lines.append(Lang.t("Opening the world to the internet..."))
		PortForward.State.FAILED:
			lines.append(Lang.t("Can't open the world to the internet: %s") % Lang.t(Net.port_forward.error))
		_:
			lines.append(Lang.t("Internet access is off (Game Menu > Invite Friends)"))
	for ip in InviteCode.lan_addresses():
		lines.append(Lang.t("LAN address: %s") % ("%s:%d" % [ip, Net.host_port]))
	return "\n".join(lines)
