class_name FloatArgument
extends ArgumentType
## Decimal number within [min_value, max_value].

var min_value: float
var max_value: float


func _init(minimum: float = -INF, maximum: float = INF) -> void:
	min_value = minimum
	max_value = maximum


func parse(text: String, _source: CommandSource) -> Dictionary:
	if not text.is_valid_float():
		return fail(Lang.t("Expected number, got '%s'") % text)
	var value := text.to_float()
	if value < min_value or value > max_value:
		return fail(Lang.t("Number must be between %s and %s, found %s") % [min_value, max_value, value])
	return ok(value)
