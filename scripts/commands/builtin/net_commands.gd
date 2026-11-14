class_name NetCommands
extends RefCounted
## The host's commands in a network game:
## /players          - who is here, with their tags (#first 8 of the hash)
##                     and addresses
## /kick <player> [reason] - sends a player away
## /ban <player>     - bans a player's tag (their computer) and kicks them
## /pardon <tag|name> - lifts a ban
## /ban-ip <player|address>, /pardon-ip <address> - bans by address
## /op <player>, /deop <player> - ops run the cheat and admin commands
## /whitelist add|remove <name>, list, on, off - who may join
## /save-all         - saves the world (and the players) now
## /stop             - a dedicated server saves and stops
## /invite           - the invite code and the LAN addresses (copies the code)
## Clients run them on the host (Net.HOST_COMMANDS) only as ops
## (Net.OP_COMMANDS); the host of an Open to LAN game always may.


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
			var words: String = ctx.arg("player")
			var name := Net.kick(words.get_slice(" ", 0), words.substr(words.find(" ") + 1) if words.contains(" ") else "")
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
	d.register(CommandNode.literal("ban-ip").describe("Bans an address or a player's address (host)")
		.then(CommandNode.argument("target", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var address := Net.ban_ip(ctx.arg("target"))
			return ctx.feedback(Lang.t("Banned the address %s") % address) if address != "" else ctx.error(Lang.t("No such player or address")))))
	d.register(CommandNode.literal("pardon-ip").describe("Lifts a ban of an address (host)")
		.then(CommandNode.argument("address", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var address: String = str(ctx.arg("address")).strip_edges()
			return ctx.feedback(Lang.t("Unbanned the address %s") % address) if Net.pardon_ip(address) else ctx.error(Lang.t("No such ban")))))
	d.register(CommandNode.literal("op").describe("Lets a player use cheats and the server's commands (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.op_player(ctx.arg("player"))
			return ctx.feedback(Lang.t("Made %s a server operator") % name) if name != "" else ctx.error(Lang.t("No such player")))))
	d.register(CommandNode.literal("deop").describe("Takes a player's operator rights (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.deop_player(ctx.arg("player"))
			return ctx.feedback(Lang.t("Made %s no longer a server operator") % name) if name != "" else ctx.error(Lang.t("That player is not an operator")))))
	var whitelist := CommandNode.literal("whitelist").describe("Who may join the server (host)")
	whitelist.then(CommandNode.literal("add").then(CommandNode.argument("name", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
		if not Net.is_host():
			return ctx.error(Lang.t("Only the host of a network game can do this"))
		var name := Net.whitelist_add(ctx.arg("name"))
		return ctx.feedback(Lang.t("Added %s to the whitelist") % name) if name != "" else ctx.error(Lang.t("Names have 3-16 letters (A-Z), digits and _")))))
	whitelist.then(CommandNode.literal("remove").then(CommandNode.argument("name", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
		if not Net.is_host():
			return ctx.error(Lang.t("Only the host of a network game can do this"))
		var name := Net.whitelist_remove(ctx.arg("name"))
		return ctx.feedback(Lang.t("Removed %s from the whitelist") % name) if name != "" else ctx.error(Lang.t("That player is not on the whitelist")))))
	whitelist.then(CommandNode.literal("list").executes(func(ctx: CommandContext) -> int:
		var names := Net.lists.whitelist()
		return ctx.feedback(Lang.t("There are %d whitelisted players: %s") % [names.size(), ", ".join(names)])))
	for state: Array in [["on", true], ["off", false]]:
		whitelist.then(CommandNode.literal(state[0]).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			Net.set_whitelist(state[1])
			return ctx.feedback(Lang.t("The whitelist is on") if state[1] else Lang.t("The whitelist is off"))))
	d.register(whitelist)
	d.register(CommandNode.literal("save-all").describe("Saves the world now (host)")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.is_host() and Net.is_online():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			Net.save_all()
			return ctx.feedback(Lang.t("Saved the game"))))
	d.register(CommandNode.literal("stop").describe("Saves and stops a dedicated server")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.dedicated or Net.server == null:
				return ctx.error(Lang.t("Only a dedicated server can be stopped"))
			Net.server.stop() # (it says so in the log)
			return 1))
	d.register(CommandNode.literal("invite").describe("Shows the invite code and copies it (host)")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			# (A player asking a server: the answer goes to them, the server's
			# clipboard stays as it is.)
			return ctx.feedback(invite_text(ctx.source.name == Net.player_name and not Net.dedicated))))


## The invite code (or why there's none) and the LAN addresses, for the chat.
## With `copy`, the code goes to the clipboard.
static func invite_text(copy: bool) -> String:
	var lines := PackedStringArray()
	var code := Net.invite_code()
	var state := Net.port_forward.state if Net.public_address == "" else PortForward.State.OPEN
	match state:
		PortForward.State.OPEN:
			if copy:
				DisplayServer.clipboard_set(code)
			if Net.public_address != "":
				lines.append(Lang.t("Players connect to: %s") % code)
			else:
				lines.append(Lang.t("Invite code: %s (copied)" if copy else "Invite code: %s") % code)
				lines.append(Lang.t("Only share the code with people you trust"))
		PortForward.State.WORKING:
			lines.append(Lang.t("Opening the world to the internet..."))
		PortForward.State.FAILED:
			lines.append(Lang.t("Can't open the world to the internet: %s") % Lang.t(Net.port_forward.error))
		_:
			if Net.dedicated:
				lines.append(Lang.t("Internet access: forward the ports, or upnp / public-address in server.properties"))
			else:
				lines.append(Lang.t("Internet access is off (Game Menu > Invite Friends)"))
	for ip in InviteCode.lan_addresses():
		lines.append(Lang.t("LAN address: %s") % ("%s:%d" % [ip, Net.host_port]))
	return "\n".join(lines)
