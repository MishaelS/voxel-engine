class_name PositionArgument
extends ArgumentType
## "x y z" with relative coordinates like the classic game: "~" is the
## source position, "~5" / "~-2" are offsets from it; local coordinates
## "^left ^up ^forward" go from the source position along its facing
## (all three or none).
## block_position = true gives a Vector3i of the block (floored),
## otherwise an exact Vector3.

var block_position := false


func _init(as_block_position: bool = false) -> void:
	token_count = 3
	block_position = as_block_position


func parse(text: String, source: CommandSource) -> Dictionary:
	var parts := text.split(" ", false)
	if parts.size() != 3:
		return fail(Lang.t("Expected x y z"))
	var origin := source.position()
	var local := 0
	for part in parts:
		if part.begins_with("^"):
			local += 1
	if local == 3:
		return _local(parts, source)
	if local > 0:
		return fail(Lang.t("Cannot mix world & local coordinates (everything must either use ^ or not)"))
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


## "^left ^up ^forward" along the source's facing, like the classic game.
func _local(parts: PackedStringArray, source: CommandSource) -> Dictionary:
	var offsets := Vector3()
	for axis in 3:
		var number_text := parts[axis].substr(1)
		if number_text != "" and not number_text.is_valid_float():
			return fail(Lang.t("Invalid coordinate '%s'") % parts[axis])
		offsets[axis] = number_text.to_float() if number_text != "" else 0.0
	var rotation := source.rotation()
	var value := source.position() + local_axes(rotation) * offsets
	if block_position:
		return ok(Vector3i(value.floor()))
	return ok(value)


## The basis of local coordinates for a facing (yaw, pitch in the classic
## game's degrees): columns left, up, forward.
static func local_axes(rotation: Vector2) -> Basis:
	var yaw := deg_to_rad(rotation.x + 90.0)
	var pitch := deg_to_rad(-rotation.y)
	var up_pitch := deg_to_rad(-rotation.y + 90.0)
	var forward := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
	var up := Vector3(cos(yaw) * cos(up_pitch), sin(up_pitch), sin(yaw) * cos(up_pitch))
	var left := -forward.cross(up)
	return Basis(left, up, forward)


func accepts_start(token: String) -> bool:
	return token.begins_with("~") or token.begins_with("^") or token.is_valid_float()


func suggest(partial: String, source: CommandSource) -> PackedStringArray:
	var parts := partial.split(" ", true)
	var typed := parts.size() - 1 # complete coordinates before the one being typed
	var prefix := " ".join(parts.slice(0, typed))
	var result := PackedStringArray()
	if partial.begins_with("^"):
		var local := PackedStringArray(parts)
		while local.size() < 3:
			local.append("^")
		if local[typed] == "":
			local[typed] = "^"
		return PackedStringArray([" ".join(local)])
	# Relative: complete the rest with "~".
	var relative := PackedStringArray([prefix]) if typed > 0 else PackedStringArray()
	if parts[typed] == "" or parts[typed] == "~":
		relative.append("~")
	else:
		relative.append(parts[typed])
	while relative.size() < 3:
		relative.append("~")
	result.append(" ".join(relative).strip_edges())
	# Absolute: the block at the source position; local: "^ ^ ^".
	if partial.strip_edges() == "":
		result.append("^ ^ ^")
		var block := Vector3i(source.position().floor())
		result.append("%d %d %d" % [block.x, block.y, block.z])
	return result
