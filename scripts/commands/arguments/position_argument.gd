class_name PositionArgument
extends ArgumentType
## "x y z" with relative coordinates like the classic game: "~" is the
## source position, "~5" / "~-2" are offsets from it.
## block_position = true gives a Vector3i of the block (floored),
## otherwise an exact Vector3.

var block_position := false


func _init(as_block_position: bool = false) -> void:
	token_count = 3
	block_position = as_block_position


func parse(text: String, source: CommandSource) -> Dictionary:
	var parts := text.split(" ", false)
	if parts.size() != 3:
		return fail("Expected x y z")
	var origin := source.position()
	var value := Vector3()
	for axis in 3:
		var part := parts[axis]
		var relative := part.begins_with("~")
		var number_text := part.substr(1) if relative else part
		var number := 0.0
		if number_text != "":
			if not number_text.is_valid_float():
				return fail("Invalid coordinate '%s'" % part)
			number = number_text.to_float()
		elif not relative:
			return fail("Invalid coordinate '%s'" % part)
		value[axis] = origin[axis] + number if relative else number
		# Whole absolute numbers address the block center for exact positions.
		if not relative and not block_position and number_text.is_valid_int():
			value[axis] += 0.5
	if block_position:
		return ok(Vector3i(value.floor()))
	return ok(value)


func suggest(partial: String, source: CommandSource) -> PackedStringArray:
	var parts := partial.split(" ", true)
	var typed := parts.size() - 1 # complete coordinates before the one being typed
	var prefix := " ".join(parts.slice(0, typed))
	var result := PackedStringArray()
	# Relative: complete the rest with "~".
	var relative := PackedStringArray([prefix]) if typed > 0 else PackedStringArray()
	if parts[typed] == "" or parts[typed] == "~":
		relative.append("~")
	else:
		relative.append(parts[typed])
	while relative.size() < 3:
		relative.append("~")
	result.append(" ".join(relative).strip_edges())
	# Absolute: the block at the source position.
	if partial.strip_edges() == "":
		var block := Vector3i(source.position().floor())
		result.append("%d %d %d" % [block.x, block.y, block.z])
	return result
