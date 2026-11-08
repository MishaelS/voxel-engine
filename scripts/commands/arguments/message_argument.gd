class_name MessageArgument
extends ArgumentType
## Free text up to the end of the input.


func _init() -> void:
	token_count = GREEDY


func parse(text: String, _source: CommandSource) -> Dictionary:
	if text.strip_edges().is_empty():
		return fail("Expected a message")
	return ok(text)
