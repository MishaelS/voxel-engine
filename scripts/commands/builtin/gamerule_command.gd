class_name GameRuleCommand
extends RefCounted
## /gamerule <rule>          - show the value
## /gamerule <rule> <value>  - change it
## One branch per rule in GameRules, each with that rule's value type.


static func register(d: CommandDispatcher) -> void:
	var command := CommandNode.literal("gamerule").describe("Shows or changes game rules")
	for rule_name in GameRules.names():
		var rule: Dictionary = GameRules.rules[rule_name]
		command.then(CommandNode.literal(rule_name)
			.executes(func(ctx: CommandContext) -> int:
				return ctx.feedback(Lang.t("Gamerule %s is currently set to: %s") % [rule_name, rule.get.call(ctx.source.world)]))
			.then(CommandNode.argument("value", rule.type).executes(func(ctx: CommandContext) -> int:
				rule.set.call(ctx.source.world, ctx.arg("value"))
				return ctx.feedback(Lang.t("Gamerule %s is now set to: %s") % [rule_name, ctx.arg("value")]))))
	d.register(command)
