class_name CommandDispatcher
extends RefCounted
## Holds the command tree and does everything with it: runs commands,
## computes suggestions for the text being typed and builds usage strings.
## Commands are registered as CommandNode trees (see CommandNode).

## Root of the tree; its children are the commands ("time", "tp", ...).
var root := CommandNode.literal("")


## Result of walking the tokens of an input through the tree.
class WalkResult:
	var node: CommandNode
	var consumed := 0          ## Tokens consumed.
	var arguments := {}        ## Parsed argument values by name.
	var error := ""            ## Set when a token matches nothing.
	var error_start := -1      ## Position of the failing token in the input.
	## Argument that needs more tokens than were typed (e.g. "1 2" of "x y z").
	var pending: CommandNode


func register(command: CommandNode) -> void:
	var existing := root.find_literal(command.name)
	if existing:
		root.children.erase(existing)
	root.children.append(command)


## Top-level commands sorted by name.
func commands() -> Array[CommandNode]:
	var result := root.children.duplicate()
	result.sort_custom(func(a: CommandNode, b: CommandNode) -> bool: return a.name < b.name)
	return result


## Splits by spaces, keeping each token's position: [{text, start, end}].
static func tokenize(input: String) -> Array:
	var tokens := []
	var i := 0
	while i < input.length():
		if input[i] == " ":
			i += 1
			continue
		var start := i
		while i < input.length() and input[i] != " ":
			i += 1
		tokens.append({"text": input.substr(start, i - start), "start": start, "end": i})
	return tokens


## Runs a command (with or without the leading "/"). Returns the executor's
## result, 0 on any error (the error is sent to the source).
func execute(input: String, source: CommandSource) -> int:
	var command := input.strip_edges()
	if command.begins_with("/"):
		command = command.substr(1)
	var tokens := tokenize(command)
	if tokens.is_empty():
		return 0

	var walk := _walk(command, tokens, source)
	if walk.error != "":
		source.send("%s: %s<--[HERE]" % [walk.error, command.substr(0, walk.error_start + tokens[walk.consumed].text.length())],
			CommandSource.MessageKind.ERROR)
		return 0
	if walk.pending != null or not walk.node.is_executable():
		var prefix := "/" + command.substr(0, tokens[walk.consumed - 1].end) if walk.consumed > 0 else "/"
		var lines := PackedStringArray()
		var node := walk.pending if walk.pending != null else walk.node
		for usage in usages(node):
			lines.append((prefix + " " + usage).strip_edges())
		source.send("Incomplete command. Usage:\n" + "\n".join(lines), CommandSource.MessageKind.ERROR)
		return 0
	return walk.node.executor.call(CommandContext.new(source, command, walk.arguments))


## Suggestions for the text before the cursor (input may start with "/"):
## {start: Int position where a chosen suggestion replaces the text,
##  items: PackedStringArray, usage: "<expected argument>", error: String}.
func suggest(input: String, cursor: int, source: CommandSource) -> Dictionary:
	var offset := 1 if input.begins_with("/") else 0
	var text := input.substr(offset, maxi(cursor - offset, 0))
	var tokens := tokenize(text)
	var partial := ""
	var partial_start := text.length()
	if not tokens.is_empty() and not text.ends_with(" "):
		var last: Dictionary = tokens.pop_back()
		partial = last.text
		partial_start = last.start

	var result := {"start": offset + partial_start, "items": PackedStringArray(), "usage": "", "error": ""}
	var walk := _walk(text, tokens, source)
	if walk.error != "":
		result.error = walk.error
		return result

	var items := PackedStringArray()
	if walk.pending != null:
		# A multi-token argument is being typed: complete it as a whole.
		var argument_start: int = tokens[walk.consumed].start
		result.start = offset + argument_start
		items = walk.pending.argument_type.suggest(text.substr(argument_start), source)
		result.usage = walk.pending.usage_token()
	else:
		var expected := PackedStringArray()
		for child in walk.node.children:
			if child.is_literal():
				if child.name.begins_with(partial.to_lower()):
					items.append(child.name)
			else:
				items.append_array(child.argument_type.suggest(partial, source))
				expected.append(child.usage_token())
		result.usage = " | ".join(expected)
		# Nothing matches what is being typed: report why, like a wrong token.
		if items.is_empty() and partial != "":
			result.error = _partial_error(walk.node, partial, source)
	items.sort()
	result.items = items
	return result


## Usage suffixes of every executable path below a node: ["set <time>", ...].
func usages(node: CommandNode) -> PackedStringArray:
	var result := PackedStringArray()
	if node.is_executable():
		result.append("")
	for child in node.children:
		for sub in usages(child):
			result.append(child.usage_token() + (" " + sub if sub != "" else ""))
	return result


## Error for a partially typed token that no child of `node` can accept,
## or "" if it may still become valid (an argument parses it, or it is the
## start of a multi-token argument).
func _partial_error(node: CommandNode, partial: String, source: CommandSource) -> String:
	var error := "Unknown command" if node == root else "Incorrect argument for command"
	for child in node.children:
		if child.is_literal():
			continue
		if child.argument_type.token_count != 1:
			return "" # multi-token / greedy: judged when complete
		var parsed := child.argument_type.parse(partial, source)
		if not parsed.has("error"):
			return ""
		error = parsed.error
	return error


func _walk(input: String, tokens: Array, source: CommandSource) -> WalkResult:
	var walk := WalkResult.new()
	walk.node = root
	var i := 0
	while i < tokens.size():
		var token: Dictionary = tokens[i]
		var next := walk.node.find_literal(token.text)
		if next != null:
			i += 1
		else:
			var last_error := ""
			for child in walk.node.children:
				if child.is_literal():
					continue
				var count := child.argument_type.token_count
				if count == ArgumentType.GREEDY:
					count = tokens.size() - i
				if i + count > tokens.size():
					walk.pending = child
					walk.consumed = i
					return walk
				var end: int = tokens[i + count - 1].end
				var parsed := child.argument_type.parse(input.substr(token.start, end - token.start), source)
				if parsed.has("error"):
					last_error = parsed.error
					continue
				walk.arguments[child.name] = parsed.value
				next = child
				i += count
				break
			if next == null:
				if last_error != "":
					walk.error = last_error
				elif walk.node == root:
					walk.error = "Unknown command"
				else:
					walk.error = "Incorrect argument for command"
				walk.error_start = token.start
				walk.consumed = i
				return walk
		walk.node = next
	walk.consumed = i
	return walk
