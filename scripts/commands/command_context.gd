class_name CommandContext
extends RefCounted
## Everything a command executor gets: the source and the parsed arguments.
## Executors return an int like in the classic game: > 0 success (often a
## count), 0 failure. feedback() and error() return 1 and 0 for convenience:
##   return ctx.feedback(Lang.t("Set the time to %d") % ticks)

var source: CommandSource
var input := ""
var _arguments := {}


func _init(command_source: CommandSource, command_input: String, arguments: Dictionary) -> void:
	source = command_source
	input = command_input
	_arguments = arguments


func has(argument_name: String) -> bool:
	return _arguments.has(argument_name)


## Parsed value of an argument, or `default` if it was not given.
func arg(argument_name: String, default: Variant = null) -> Variant:
	return _arguments.get(argument_name, default)


## The targets of an EntityArgument (chosen now, for this source).
func targets(argument_name: String) -> Array:
	var selector: EntitySelector = _arguments.get(argument_name)
	return selector.select(source) if selector else []


## Success output (hidden with the sendCommandFeedback game rule off).
func feedback(text: String) -> int:
	if GameRules.flag(source.world, "sendCommandFeedback"):
		source.send(text, CommandSource.MessageKind.SUCCESS)
	return 1


func error(text: String) -> int:
	source.send(text, CommandSource.MessageKind.ERROR)
	return 0
