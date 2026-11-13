class_name WeatherCommand
extends RefCounted
## /weather clear|rain|thunder [seconds]
## Sets the weather for a while (5 minutes by default), then the weather
## cycle goes on as usual (unless doWeatherCycle is off).

const DEFAULT_SECONDS := 300


static func register(d: CommandDispatcher) -> void:
	var root := CommandNode.literal("weather").describe("Sets the weather")
	for kind: String in ["clear", "rain", "thunder"]:
		root.then(CommandNode.literal(kind)
			.executes(func(ctx: CommandContext) -> int: return _change(ctx, kind, DEFAULT_SECONDS))
			.then(CommandNode.argument("seconds", IntegerArgument.new(1, 1000000)).executes(func(ctx: CommandContext) -> int:
				return _change(ctx, kind, ctx.arg("seconds")))))
	d.register(root)


static func _change(ctx: CommandContext, kind: String, seconds: int) -> int:
	ctx.source.world.weather.set_weather(kind, seconds * 20)
	var names := {"clear": "clear", "rain": "rain", "thunder": "rain & thunder"}
	return ctx.feedback(Lang.t("Changing to %s") % Lang.t(names[kind]))
