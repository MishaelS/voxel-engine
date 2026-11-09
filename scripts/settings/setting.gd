class_name Setting
extends RefCounted
## One option shown in menus: a toggle, a choice from a list or a number in
## a range. Menus build the right widget from it (a cycling button or a
## slider), so any value - a saved setting, a game rule - is described once.
##
## Values: BOOL -> bool, CHOICE -> int index into `choices`, RANGE -> float.
## get_value/set_value go through `getter`/`setter` (for saved settings they
## read and write the Settings store).

enum Kind { BOOL, CHOICE, RANGE }

var key := ""
var label := ""
var kind: Kind = Kind.BOOL
var default_value: Variant = false
var choices := PackedStringArray()
var min_value := 0.0
var max_value := 1.0
var step := 1.0
## Optional f(value) -> String for the shown value (e.g. "75%").
var formatter := Callable()
## Optional hint shown under the widget.
var tooltip := ""
var getter := Callable()
var setter := Callable()


static func toggle(setting_key: String, setting_label: String, default: bool) -> Setting:
	var s := Setting.new()
	s.key = setting_key
	s.label = setting_label
	s.kind = Kind.BOOL
	s.default_value = default
	return s


static func choice(setting_key: String, setting_label: String, options: PackedStringArray, default_index: int) -> Setting:
	var s := Setting.new()
	s.key = setting_key
	s.label = setting_label
	s.kind = Kind.CHOICE
	s.choices = options
	s.default_value = default_index
	return s


static func range_of(setting_key: String, setting_label: String, minimum: float, maximum: float, default: float, step_size: float = 1.0) -> Setting:
	var s := Setting.new()
	s.key = setting_key
	s.label = setting_label
	s.kind = Kind.RANGE
	s.min_value = minimum
	s.max_value = maximum
	s.default_value = default
	s.step = step_size
	return s


func format_with(callable: Callable) -> Setting:
	formatter = callable
	return self


func bind(get_callable: Callable, set_callable: Callable) -> Setting:
	getter = get_callable
	setter = set_callable
	return self


func get_value() -> Variant:
	return getter.call() if getter.is_valid() else default_value


func set_value(value: Variant) -> void:
	if setter.is_valid():
		setter.call(sanitize(value))


## Clamps and converts a value to this setting's type.
func sanitize(value: Variant) -> Variant:
	match kind:
		Kind.BOOL:
			return bool(value)
		Kind.CHOICE:
			return clampi(int(value), 0, maxi(choices.size() - 1, 0))
		_:
			return clampf(snappedf(float(value), step), min_value, max_value)


## "VSync: ON", "Shadows: High", "FOV: 75", in the current language
## (formatters translate their own texts with Lang.t).
func display_text() -> String:
	return "%s: %s" % [Lang.t(label), display_value()]


func display_value() -> String:
	var value: Variant = get_value()
	if formatter.is_valid():
		return formatter.call(value)
	match kind:
		Kind.BOOL:
			return Lang.t("ON") if value else Lang.t("OFF")
		Kind.CHOICE:
			return Lang.t(choices[int(value)])
		_:
			return str(int(value)) if step >= 1.0 else str(snappedf(value, step))
