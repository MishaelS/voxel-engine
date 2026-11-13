class_name OptionsArgument
extends ArgumentType
## The rest of the input as "key=value" words (instead of the classic
## game's NBT): "size=4 no_ai=true". `keys` maps each allowed key to its
## values: a list to choose from, a Callable returning one, or an empty list
## for any value. Value = {key: value text}.

var keys := {}


func _init(allowed: Dictionary) -> void:
	token_count = GREEDY
	keys = allowed


func _values(key: String) -> PackedStringArray:
	var values: Variant = keys.get(key, [])
	return PackedStringArray(values.call() if values is Callable else values)


func parse(text: String, _source: CommandSource) -> Dictionary:
	var result := {}
	for word in text.split(" ", false):
		var eq := word.find("=")
		if eq <= 0:
			return fail(Lang.t("Expected an option, got '%s'") % word)
		var key := word.left(eq)
		var value := word.substr(eq + 1)
		if not keys.has(key):
			return fail(Lang.t("Unknown option '%s'") % key)
		var values := _values(key)
		if not values.is_empty() and not values.has(value):
			return fail(Lang.t("Invalid value '%s' for %s") % [value, key])
		if value.is_empty():
			return fail(Lang.t("Expected an option, got '%s'") % word)
		result[key] = value
	if result.is_empty():
		return fail(Lang.t("Expected an option"))
	return ok(result)


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	var space := partial.rfind(" ")
	var head := partial.left(space + 1)
	var word := partial.substr(space + 1)
	var result := PackedStringArray()
	var eq := word.find("=")
	if eq < 0:
		var names := PackedStringArray(keys.keys())
		names.sort()
		for key in filter_prefix(names, word):
			if not partial.contains(key + "="):
				result.append(head + key + "=")
		return result
	for value in filter_prefix(_values(word.left(eq)), word.substr(eq + 1)):
		result.append(head + word.left(eq + 1) + value)
	return result
