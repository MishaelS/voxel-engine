class_name TimeArgument
extends ArgumentType
## Duration in game ticks: "100" or "100t" ticks, "5s" seconds (20 ticks),
## "1d" or "0.5d" days (24000 ticks), like the classic game.

const UNITS := {"t": 1.0, "s": 20.0, "d": float(WorldClock.TICKS_PER_DAY)}


func parse(text: String, _source: CommandSource) -> Dictionary:
	var number_text := text
	var factor := 1.0
	var unit := text.right(1).to_lower()
	if UNITS.has(unit):
		factor = UNITS[unit]
		number_text = text.left(-1)
	if not number_text.is_valid_float():
		return fail("Invalid time '%s' (use ticks, or a number with t, s or d)" % text)
	var ticks := roundi(number_text.to_float() * factor)
	if ticks < 0:
		return fail("Time must not be negative")
	return ok(ticks)


func suggest(partial: String, _source: CommandSource) -> PackedStringArray:
	if partial.is_valid_float():
		return PackedStringArray([partial + "t", partial + "s", partial + "d"])
	return PackedStringArray()
