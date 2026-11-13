class_name EntityArgument
extends ArgumentType
## Targets: a player's name or a selector (@p @a @r @s @e with filters, see
## EntitySelector); value = the EntitySelector, chosen when the command runs
## (CommandContext.targets()).
## single: only one target allowed; players: only players.

var single := false
var players := false


func _init(only_one: bool = false, only_players: bool = false) -> void:
	single = only_one
	players = only_players


func parse(text: String, _source: CommandSource) -> Dictionary:
	var parsed: Variant = EntitySelector.parse(text)
	if parsed is String:
		return fail(parsed)
	var selector := parsed as EntitySelector
	if single and not selector.is_single():
		return fail(Lang.t("Only one entity is allowed, but the provided selector allows more than one"))
	if players and not selector.players_only():
		return fail(Lang.t("Only players may be affected by this command, but the provided selector includes entities"))
	return ok(selector)


func suggest(partial: String, source: CommandSource) -> PackedStringArray:
	var bracket := partial.find("[")
	if bracket < 0:
		var candidates := PackedStringArray(["@a", "@e", "@p", "@r", "@s"])
		for target: Variant in CommandTargets.players(source.world):
			candidates.append(CommandTargets.name_of(target))
		var result := filter_prefix(candidates, partial)
		if partial.length() == 2 and partial.begins_with("@") and result.has(partial):
			result.append(partial + "[")
		return result
	if partial.ends_with("]"):
		return PackedStringArray()
	# Inside the brackets: complete the key or the value being typed.
	var start := maxi(partial.rfind(","), bracket) + 1
	var head := partial.left(start)
	var pair := partial.substr(start)
	var result := PackedStringArray()
	var eq := pair.find("=")
	if eq < 0:
		for key in EntitySelector.KEYS:
			if key.begins_with(pair):
				result.append(head + key + "=")
		if pair == "" and start > bracket + 1:
			result.append(partial.left(partial.length() - 1) + "]") # (after a comma: close instead)
		return result
	var key := pair.left(eq)
	var value := pair.substr(eq + 1)
	var negated := value.begins_with("!")
	var values := PackedStringArray()
	match key:
		"type":
			values = CommandTargets.type_names()
		"sort":
			values = PackedStringArray(EntitySelector.SORTS)
		"gamemode":
			values = PackedStringArray(EntitySelector.GAME_MODES)
		"limit":
			values = PackedStringArray(["1"])
		"distance":
			values = PackedStringArray(["..5", "..10", "..32"])
		"name":
			for target: Variant in CommandTargets.players(source.world):
				values.append(CommandTargets.name_of(target))
	var typed := value.substr(1) if negated and key in ["type", "name", "gamemode"] else value
	var prefix := head + key + "=" + ("!" if typed != value else "")
	for candidate in filter_prefix(values, typed):
		if candidate != typed:
			result.append(prefix + candidate)
	if result.is_empty() and value != "" and not value.ends_with("!"):
		result.append(partial + ",")
		result.append(partial + "]")
	return result
