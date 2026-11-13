class_name CommandDispatcher
extends RefCounted
## Holds the command tree and does everything with it: runs commands,
## computes suggestions for the text being typed and builds usage strings.
## Commands are registered as CommandNode trees (see CommandNode).
## Redirects (CommandNode.redirects) let a command go on in another part of
## the tree: /execute chains its parts and "run"s any command; each part's
## modifier gives the sources the rest runs with (once per source).

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
	## Where the last node's text starts in the input.
	var node_start := 0
	## Stopped at a node with a modifier, more tokens following (executing).
	var stopped := false


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
## result (summed over /execute's sources), 0 on any error (the error is
## sent to the source).
func execute(input: String, source: CommandSource) -> int:
	var command := input.strip_edges()
	if command.begins_with("/"):
		command = command.substr(1)
	var tokens := tokenize(command)
	if tokens.is_empty():
		return 0
	# The whole command is checked first, then run part by part.
	var walk := _walk(command, tokens, source)
	if not _complete(walk, command, tokens, source):
		return 0
	return _run(command, tokens, source, root, 0)


## Runs from `start` (token `index`) with `source`: up to a node with a
## modifier, then the rest once per source it gives.
func _run(command: String, tokens: Array, source: CommandSource, start: CommandNode, index: int) -> int:
	var walk := _walk(command, tokens, source, start, index, true)
	if not walk.stopped:
		if not _complete(walk, command, tokens, source):
			return 0
		return walk.node.executor.call(CommandContext.new(source, command, walk.arguments))
	if walk.error != "":
		_complete(walk, command, tokens, source)
		return 0
	var node := walk.node
	var sources: Array = node.modifier.call(CommandContext.new(source, command, walk.arguments))
	var total := 0
	for next: CommandSource in sources:
		total += _run(command, tokens, next, node.redirect, walk.consumed)
	return total


## Sends the error of a walk that failed or stopped short; true if it is a
## whole, runnable command.
func _complete(walk: WalkResult, command: String, tokens: Array, source: CommandSource) -> bool:
	if walk.error != "":
		source.send("%s: %s<--[%s]" % [walk.error, command.substr(0, walk.error_start + tokens[walk.consumed].text.length()),
			Lang.t("HERE")], CommandSource.MessageKind.ERROR)
		return false
	if walk.pending != null or not walk.node.is_executable():
		var prefix := "/" + command.substr(0, tokens[walk.consumed - 1].end) if walk.consumed > 0 else "/"
		var lines := PackedStringArray()
		var node := walk.pending if walk.pending != null else walk.node
		for usage in usages(node if node.redirect == null or walk.pending != null else node.redirect):
			lines.append((prefix + " " + usage).strip_edges())
		source.send(Lang.t("Incomplete command. Usage:") + "\n" + "\n".join(lines), CommandSource.MessageKind.ERROR)
		return false
	return true


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
	elif not walk.node.is_literal() and walk.node.argument_type.token_count == ArgumentType.GREEDY and walk.consumed > 0:
		# More words of a greedy argument ("key=value key=value"): it goes on.
		result.start = offset + walk.node_start
		items = walk.node.argument_type.suggest(text.substr(walk.node_start), source)
		result.usage = walk.node.usage_token()
	else:
		var from := _next_of(walk.node)
		var expected := PackedStringArray()
		for child in from.children:
			if child.is_literal():
				if child.name.begins_with(partial.to_lower()):
					items.append(child.name)
			else:
				items.append_array(child.argument_type.suggest(partial, source))
				expected.append(child.usage_token())
		result.usage = " | ".join(expected)
		# Nothing matches what is being typed: report why, like a wrong token.
		if items.is_empty() and partial != "":
			result.error = _partial_error(from, partial, source)
	items.sort()
	result.items = items
	return result


## Usage suffixes of every executable path below a node: ["set <time>", ...].
## A redirect shows as "..." (more follows, as from where it leads).
func usages(node: CommandNode) -> PackedStringArray:
	var result := PackedStringArray()
	if node.is_executable():
		result.append("")
	if node.redirect != null:
		result.append("<command>" if node.redirect == root else "...")
	for child in node.children:
		for sub in usages(child):
			result.append(child.usage_token() + (" " + sub if sub != "" else ""))
	return result


## The node whose children the next token is matched against.
func _next_of(node: CommandNode) -> CommandNode:
	return node.redirect if node.redirect != null else node


## Error for a partially typed token that no child of `node` can accept,
## or "" if it may still become valid (an argument parses it, or it is the
## start of a multi-token argument).
func _partial_error(node: CommandNode, partial: String, source: CommandSource) -> String:
	var error := Lang.t("Unknown command") if node == root else Lang.t("Incorrect argument for command")
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


## Matches tokens from `start_index` on, beginning at `start` (whose
## children the first token is matched against, through its redirect).
## Executing (`stop_at_modifier`), it stops after a node with a modifier
## when more tokens follow.
func _walk(input: String, tokens: Array, source: CommandSource, start: CommandNode = null,
		start_index: int = 0, stop_at_modifier: bool = false) -> WalkResult:
	var walk := WalkResult.new()
	walk.node = start if start != null else root
	var i := start_index
	while i < tokens.size():
		if stop_at_modifier and i > start_index and walk.node.redirect != null and walk.node.modifier.is_valid():
			walk.stopped = true
			break
		var token: Dictionary = tokens[i]
		var from := _next_of(walk.node)
		var next := from.find_literal(token.text)
		if next != null:
			i += 1
		else:
			var last_error := ""
			var likely_error := "" # from the first argument the token could begin
			var pending: CommandNode = null
			for child in from.children:
				if child.is_literal():
					continue
				var count := child.argument_type.token_count
				if count == ArgumentType.GREEDY:
					count = tokens.size() - i
				var plausible := child.argument_type.accepts_start(token.text)
				if i + count > tokens.size():
					if pending == null and plausible:
						pending = child
					continue
				var end: int = tokens[i + count - 1].end
				var parsed := child.argument_type.parse(input.substr(token.start, end - token.start), source)
				if parsed.has("error"):
					last_error = parsed.error
					if plausible and likely_error == "":
						likely_error = parsed.error
					continue
				walk.arguments[child.name] = parsed.value
				next = child
				i += count
				break
			if next == null:
				walk.consumed = i
				if pending != null:
					walk.pending = pending
					return walk
				if last_error != "":
					walk.error = likely_error if likely_error != "" else last_error
				elif from == root:
					walk.error = Lang.t("Unknown command")
				else:
					walk.error = Lang.t("Incorrect argument for command")
				walk.error_start = token.start
				return walk
		walk.node = next
		walk.node_start = token.start
	walk.consumed = i
	return walk
