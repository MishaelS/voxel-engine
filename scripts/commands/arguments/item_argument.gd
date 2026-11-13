class_name ItemArgument
extends ArgumentType
## An item or block by registry name ("diamond", "stone", "oak_log");
## value = item id (Items).


func parse(text: String, _source: CommandSource) -> Dictionary:
	if text != "air" and Items.has_name(text):
		var id := Items.id_of(text)
		if Items.exists(id):
			return ok(id)
	return fail(Lang.t("Unknown item '%s'") % text)


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	var names := PackedStringArray()
	for id in Items.catalog():
		names.append(Items.name_of(id))
	var result := filter_prefix(names, partial)
	# Also match inside names: "sword" -> wooden_sword, stone_sword, ...
	if partial.length() >= 2:
		for item_name in names:
			if not result.has(item_name) and item_name.contains(partial.to_lower()):
				result.append(item_name)
	return result
