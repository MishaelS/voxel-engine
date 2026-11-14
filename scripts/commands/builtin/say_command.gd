class_name SayCommand
extends RefCounted
## /say <message>  - broadcasts a message


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("say").describe("Sends a message to the chat")
		.then(CommandNode.argument("message", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			var text := "[%s] %s" % [ctx.source.name, NetGuard.clean_text(ctx.arg("message"))]
			if Net.is_host():
				Net.broadcast_message(text) # everyone in the network game, here and the log
				return 1
			ctx.source.send(text, CommandSource.MessageKind.CHAT)
			return 1)))
