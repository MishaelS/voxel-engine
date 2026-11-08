class_name HelpCommand
extends RefCounted
## /help              - list all commands
## /help <command>    - all usages of a command
## Both are generated from the command tree.


static func register(d: CommandDispatcher) -> void:
	var command_names := func() -> PackedStringArray:
		var names := PackedStringArray()
		for command in d.commands():
			names.append(command.name)
		return names

	d.register(CommandNode.literal("help").describe("Lists commands or shows how to use one")
		.executes(func(ctx: CommandContext) -> int:
			var lines := PackedStringArray()
			for command in d.commands():
				lines.append("/%s - %s" % [command.name, command.description] if command.description else "/" + command.name)
			return ctx.feedback("Commands:\n" + "\n".join(lines)))
		.then(CommandNode.argument("command", ChoiceArgument.new(command_names, "command"))
			.executes(func(ctx: CommandContext) -> int:
				var command := d.root.find_literal(ctx.arg("command"))
				var lines := PackedStringArray()
				for usage in d.usages(command):
					lines.append(("/%s %s" % [command.name, usage]).strip_edges())
				var header := "/%s - %s\n" % [command.name, command.description] if command.description else ""
				return ctx.feedback(header + "\n".join(lines)))))
