class_name RotationArgument
extends ArgumentType
## "yaw pitch" in degrees like the classic game (yaw 0 = south, 90 = west,
## pitch 90 = down); "~" / "~10" are relative to the source's facing.
## Value = Vector2(yaw, pitch).


func _init() -> void:
	token_count = 2


func parse(text: String, source: CommandSource) -> Dictionary:
	var parts := text.split(" ", false)
	if parts.size() != 2:
		return fail(Lang.t("Expected yaw and pitch"))
	var current := source.rotation()
	var value := Vector2()
	for axis in 2:
		var part := parts[axis]
		var relative := part.begins_with("~")
		var number_text := part.substr(1) if relative else part
		if number_text != "" and not number_text.is_valid_float():
			return fail(Lang.t("Invalid rotation '%s'") % part)
		if number_text == "" and not relative:
			return fail(Lang.t("Invalid rotation '%s'") % part)
		var number := number_text.to_float() if number_text != "" else 0.0
		value[axis] = current[axis] + number if relative else number
	value.x = wrapf(value.x, -180.0, 180.0)
	value.y = clampf(value.y, -90.0, 90.0)
	return ok(value)


func accepts_start(token: String) -> bool:
	return token.begins_with("~") or token.begins_with("^") or token.is_valid_float()


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	var parts := partial.split(" ", true)
	if parts.size() == 1:
		return filter_prefix(PackedStringArray(["~ ~", "0 0"]), partial)
	if parts[1] == "":
		return PackedStringArray([parts[0] + " ~"])
	return PackedStringArray()
