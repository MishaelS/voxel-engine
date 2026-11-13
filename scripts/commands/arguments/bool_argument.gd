class_name BoolArgument
extends ArgumentType
## true / false.


func parse(text: String, _source: CommandSource) -> Dictionary:
	match text.to_lower():
		"true":
			return ok(true)
		"false":
			return ok(false)
	return fail(Lang.t("Expected true or false, got '%s'") % text)


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	return filter_prefix(PackedStringArray(["true", "false"]), partial)
