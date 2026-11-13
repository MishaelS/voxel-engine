class_name HelpCommand
extends RefCounted
## /help [<page>]     - the commands, PAGE_SIZE a page
## /help <command>    - all usages of a command
## Both are generated from the command tree.

const PAGE_SIZE := 8


static func register(d: CommandDispatcher) -> void:
	var command_names := func() -> PackedStringArray:
		var names := PackedStringArray()
		for command in d.commands():
			names.append(command.name)
		return names

	d.register(CommandNode.literal("help").describe("Lists commands or shows how to use one")
		.executes(func(ctx: CommandContext) -> int: return _page(ctx, d, 1))
		.then(CommandNode.argument("page", IntegerArgument.new(1, 1000)).executes(func(ctx: CommandContext) -> int:
			return _page(ctx, d, ctx.arg("page"))))
		.then(CommandNode.argument("command", ChoiceArgument.new(command_names, "command"))
			.executes(func(ctx: CommandContext) -> int:
				var command := d.root.find_literal(ctx.arg("command"))
				var lines := PackedStringArray()
				for usage in d.usages(command):
					lines.append(("/%s %s" % [command.name, usage]).strip_edges())
				var header := "/%s - %s\n" % [command.name, Lang.t(command.description)] if command.description else ""
				return ctx.feedback(header + "\n".join(lines)))))


static func _page(ctx: CommandContext, d: CommandDispatcher, page: int) -> int:
	var all := d.commands()
	var pages := ceili(all.size() / float(PAGE_SIZE))
	if page > pages:
		return ctx.error(Lang.t("There are only %d help pages") % pages)
	var lines := PackedStringArray([Lang.t("--- Showing help page %d of %d (/help <page>) ---") % [page, pages]])
	for command in all.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE):
		lines.append("/%s - %s" % [command.name, Lang.t(command.description)] if command.description else "/" + command.name)
	return ctx.feedback("\n".join(lines))
