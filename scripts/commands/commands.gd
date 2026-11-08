class_name Commands
extends RefCounted
## The game's command dispatcher with all built-in commands registered.
## To add a command: create scripts/commands/builtin/<name>_command.gd with
## a static register(dispatcher) and call it in _create().

static var dispatcher: CommandDispatcher:
	get:
		if dispatcher == null:
			dispatcher = _create()
		return dispatcher


static func _create() -> CommandDispatcher:
	var d := CommandDispatcher.new()
	HelpCommand.register(d)
	TimeCommand.register(d)
	TickCommand.register(d)
	GameRuleCommand.register(d)
	SetBlockCommand.register(d)
	FillCommand.register(d)
	TeleportCommand.register(d)
	GameModeCommand.register(d)
	SeedCommand.register(d)
	SayCommand.register(d)
	return d
