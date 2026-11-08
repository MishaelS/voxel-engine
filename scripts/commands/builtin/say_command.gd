class_name SayCommand
extends RefCounted
## /say <message>  - broadcasts a message


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("say").describe("Sends a message to the chat")
		.then(CommandNode.argument("message", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			ctx.source.send("[%s] %s" % [ctx.source.name, ctx.arg("message")], CommandSource.MessageKind.CHAT)
			return 1)))
