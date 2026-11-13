class_name BlockArgument
extends ArgumentType
## A block type by registry name (e.g. "stone", "oak_log"); value = block id.


func parse(text: String, _source: CommandSource) -> Dictionary:
	for block in Blocks.types:
		if block.name == text:
			return ok(block.id)
	return fail(Lang.t("Unknown block '%s'") % text)


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	var names := PackedStringArray()
	for block in Blocks.types:
		names.append(block.name)
	var result := filter_prefix(names, partial)
	# Also match inside names: "log" -> oak_log, birch_log, ...
	if partial.length() >= 2:
		for block_name in names:
			if not result.has(block_name) and block_name.contains(partial.to_lower()):
				result.append(block_name)
	return result
