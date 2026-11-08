class_name CommandNode
extends RefCounted
## One node of the command tree (the approach of Brigadier, the command
## library of the classic game). A command is a tree of literals (fixed
## words) and arguments (typed values); a node with an executor can end
## the command. Parsing, execution, suggestions and /help usage are all
## derived from the same tree, so a command is described exactly once:
##
##   CommandNode.literal("time").then(
##       CommandNode.literal("set").then(
##           CommandNode.argument("time", TimeArgument.new()).executes(_set_time)))

var name := ""
## null for literals.
var argument_type: ArgumentType
var children: Array[CommandNode] = []
## Called as executor(ctx: CommandContext) -> int.
var executor := Callable()
## Shown by /help for top-level commands.
var description := ""


static func literal(literal_name: String) -> CommandNode:
	var node := CommandNode.new()
	node.name = literal_name
	return node


static func argument(argument_name: String, type: ArgumentType) -> CommandNode:
	var node := CommandNode.new()
	node.name = argument_name
	node.argument_type = type
	return node


func then(child: CommandNode) -> CommandNode:
	children.append(child)
	return self


func executes(callable: Callable) -> CommandNode:
	executor = callable
	return self


func describe(text: String) -> CommandNode:
	description = text
	return self


func is_literal() -> bool:
	return argument_type == null


func is_executable() -> bool:
	return executor.is_valid()


## How the node looks in usage strings: "set" or "<time>".
func usage_token() -> String:
	return name if is_literal() else "<%s>" % name


func find_literal(literal_name: String) -> CommandNode:
	for child in children:
		if child.is_literal() and child.name == literal_name:
			return child
	return null
