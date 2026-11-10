class_name StatsScreen
extends MenuScreen
## Statistics like the classic game: General (time, distances, jumps,
## deaths, kills...), Blocks (mined) and Items (crafted, used, broken),
## switched with the buttons at the bottom.

var _page := "general"


func _init(page: String = "general") -> void:
	title = "Statistics"
	columns = 2
	_page = page


func build() -> void:
	match _page:
		"general":
			for row: Array in Stats.GENERAL:
				_row(Lang.t(row[1]), Stats.format(row[0], row[2]))
		"blocks":
			_rows(Stats.with_prefix("mine."), "Mined")
		"items":
			var crafted := Stats.with_prefix("craft.")
			var used := Stats.with_prefix("use.")
			var broken := Stats.with_prefix("break.")
			var names := {}
			for source: Dictionary in [crafted, used, broken]:
				for name: String in source:
					names[name] = true
			var sorted := names.keys()
			sorted.sort()
			if sorted.is_empty():
				_row(Lang.t("Nothing yet"), "")
			for name: String in sorted:
				_row(_display(name), "%s %d   %s %d   %s %d" % [Lang.t("Crafted"), crafted.get(name, 0),
					Lang.t("Used"), used.get(name, 0), Lang.t("Broken"), broken.get(name, 0)])
	add_bottom_row([
		["General", func() -> void: menu.replace(StatsScreen.new("general"))],
		["Blocks", func() -> void: menu.replace(StatsScreen.new("blocks"))],
		["Items", func() -> void: menu.replace(StatsScreen.new("items"))],
	], UiTheme.HALF_BUTTON * 2.0 / 3.0)
	add_done_button()


func _rows(counts: Dictionary, label: String) -> void:
	var names := counts.keys()
	names.sort()
	if names.is_empty():
		_row(Lang.t("Nothing yet"), "")
	for name: String in names:
		_row(_display(name), "%s %d" % [Lang.t(label), counts[name]])


static func _display(name: String) -> String:
	return Items.display_name(Items.id_of(name)) if Items.has_name(name) else name


func _row(left: String, right: String) -> void:
	for text in [left, right]:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT * 0.6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if text == left else HORIZONTAL_ALIGNMENT_RIGHT
		add_list_item(label)
