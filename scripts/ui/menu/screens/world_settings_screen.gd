class_name WorldSettingsScreen
extends MenuScreen
## Settings of the current world: game rules (from the GameRules registry)
## and world generation. Not saved with the player options: they belong to
## the world.

const GENERATORS := ["Beta 1.7.3", "Random Blocks"]


func _init() -> void:
	title = "World Settings"


func build() -> void:
	var world := menu.world
	if world == null:
		add_done_button()
		return

	for rule_name in GameRules.names():
		add_option(_rule_setting(world, rule_name))

	add_option(Setting.choice("generator", "Generator", PackedStringArray(GENERATORS), 0).bind(
		func() -> Variant: return int(world.generator),
		func(value: Variant) -> void: world.generator = value))
	var seed_label := Label.new()
	seed_label.text = "Seed: %d" % world.world_seed
	seed_label.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_list_item(seed_label)

	add_bottom_button("Regenerate World (same seed)", func() -> void:
		world.generate()
		menu.close())
	add_bottom_button("New World (random seed)", func() -> void:
		world.world_seed = randi()
		world.generate()
		menu.close())
	add_done_button()


## A menu option for a game rule, built from the rule's argument type.
static func _rule_setting(world: VoxelWorld, rule_name: String) -> Setting:
	var rule: Dictionary = GameRules.rules[rule_name]
	var setting: Setting
	if rule.type is BoolArgument:
		setting = Setting.toggle(rule_name, rule_name, true)
	else:
		var type: IntegerArgument = rule.type
		setting = Setting.range_of(rule_name, rule_name, type.min_value, mini(type.max_value, rule.get("ui_max", 100)), 0)
	var is_range := setting.kind == Setting.Kind.RANGE # not `setting`: avoids a reference cycle
	return setting.bind(
		func() -> Variant: return rule.get.call(world),
		func(value: Variant) -> void:
			rule.set.call(world, int(value) if is_range else value))
