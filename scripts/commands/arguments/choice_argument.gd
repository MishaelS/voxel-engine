class_name ChoiceArgument
extends ArgumentType
## One word out of a fixed or dynamic list. Pass the choices directly or a
## Callable returning them (evaluated on use, e.g. names from a registry).

var _choices: PackedStringArray
var _provider := Callable()
var _what := "value"


func _init(choices: Variant, what: String = "value") -> void:
	if choices is Callable:
		_provider = choices
	else:
		_choices = PackedStringArray(choices)
	_what = what


func choices() -> PackedStringArray:
	return PackedStringArray(_provider.call()) if _provider.is_valid() else _choices


func parse(text: String, _source: CommandSource) -> Dictionary:
	if choices().has(text):
		return ok(text)
	return fail(Lang.t("Unknown %s '%s'") % [Lang.t(_what), text])


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	return filter_prefix(choices(), partial)
