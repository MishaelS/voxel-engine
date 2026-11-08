class_name IntegerArgument
extends ArgumentType
## Whole number within [min_value, max_value].

var min_value: int
var max_value: int


func _init(minimum: int = -2147483648, maximum: int = 2147483647) -> void:
	min_value = minimum
	max_value = maximum


func parse(text: String, _source: CommandSource) -> Dictionary:
	if not text.is_valid_int():
		return fail("Expected integer, got '%s'" % text)
	var value := text.to_int()
	if value < min_value or value > max_value:
		return fail("Integer must be between %d and %d, found %d" % [min_value, max_value, value])
	return ok(value)
