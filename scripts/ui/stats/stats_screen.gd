class_name StatsScreen
extends MenuScreen
## Statistics like Beta 1.7.3's GuiStats: General (time, distances, jumps,
## deaths, kills...), Blocks and Items. Blocks and Items are lists like the
## game's: each block or item in a slot frame (gui/slot.png) with its
## numbers under three columns - Blocks: crafted, used (placed), mined;
## Items: crafted, used, broken - headed by slot.png's pictures (anvil,
## crafting table, pickaxe, broken shovel); a click on a heading sorts by it
## (again: the other way, an arrow shows which), "-" for none, the name in a
## tooltip. Buttons like the game's: General, Blocks and Items in a row
## (a page with nothing in it can't be opened), Done under them on the right.

const P := UiTheme.PIXEL
## Where each column's numbers end (Beta's x + 115, 165, 215) and a row.
const COLUMN_ENDS := [115, 165, 215]
const ROW_HEIGHT := 20
const LIST_WIDTH := 230
## slot.png: the item slot, the heading slot, the sort arrows (down, up) and
## the heading pictures.
const SLOT := Rect2i(0, 0, 18, 18)
const HEADING_SLOT := Rect2i(0, 18, 18, 18)
const ARROW_DOWN := Rect2i(18, 0, 18, 18)
const ARROW_UP := Rect2i(36, 0, 18, 18)
const CRAFTED := Rect2i(18, 18, 18, 18)
const USED := Rect2i(36, 18, 18, 18)
const MINED := Rect2i(54, 18, 18, 18)
const BROKEN := Rect2i(72, 18, 18, 18)

var _page := "general"
## The sorting: column (-1 none) and which way (1 most first, -1 least).
var _sort_column := -1
var _sort_way := 1


func _init(page: String = "general", sort_column: int = -1, sort_way: int = 1) -> void:
	title = "Statistics"
	columns = 2 if page == "general" else 1
	_page = page
	_sort_column = sort_column
	_sort_way = sort_way


func build() -> void:
	match _page:
		"general":
			for row: Array in Stats.GENERAL:
				_row(Lang.t(row[1]), Stats.format(row[0], row[2]))
		"blocks", "items":
			_stat_list(_columns_of(_page), [CRAFTED, USED, MINED] if _page == "blocks" else [BROKEN, CRAFTED, USED])
	add_bottom_row([
		["General", func() -> void: menu.replace(StatsScreen.new("general"))],
		["Blocks", func() -> void: menu.replace(StatsScreen.new("blocks"))],
		["Items", func() -> void: menu.replace(StatsScreen.new("items"))],
	], 100 * P)
	var done := add_bottom_row([["Done", func() -> void: menu.back()]], 150 * P)[0]
	# (Beta's Done stands under the right half: a gap the width of the rest)
	var row := done.get_parent() as HBoxContainer
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(150 * P, 0)
	row.add_child(gap)
	row.move_child(gap, 0)


## The three columns of a page: their counts by name (Stats).
static func _columns_of(page: String) -> Array:
	if page == "blocks":
		return [Stats.with_prefix("craft."), Stats.with_prefix("use."), Stats.with_prefix("mine.")]
	return [Stats.with_prefix("break."), Stats.with_prefix("craft."), Stats.with_prefix("use.")]


## Names a recipe or the furnace makes.
static var _made := {}


static func _craftable(name: String) -> bool:
	if _made.is_empty():
		for recipe: Dictionary in Crafting.RECIPES:
			_made[str(recipe.get("result", ""))] = true
		for output: String in Smelting.RECIPES.values():
			_made[output] = true
	return _made.has(name)


## Whether a page's column means something for `id` (Beta: "-" where it
## doesn't, "0" where it does but hasn't happened): Blocks - crafted (a
## recipe or the furnace makes it), used (placed), mined (not unbreakable);
## Items - broken (it wears out), crafted, used.
func _has_column(id: int, column: int) -> bool:
	var name := Items.name_of(id)
	if _page == "blocks":
		match column:
			0:
				return _craftable(name)
			1:
				return true
			_:
				return Blocks.get_type(id).hardness >= 0.0
	match column:
		0:
			return Items.durability(id) > 0
		1:
			return _craftable(name)
	return true


## The game's list: every block (or item) there is, in their order, with
## its numbers; sorted by a column when one was clicked.
func _stat_list(counts: Array, pictures: Array) -> void:
	var ids := PackedInt32Array()
	for id in Items.catalog():
		if Items.is_block(id) == (_page == "blocks"):
			ids.append(id)
	var order := Array(ids)
	if _sort_column >= 0:
		var column: Dictionary = counts[_sort_column]
		order.sort_custom(func(a: int, b: int) -> bool:
			var x := int(column.get(Items.name_of(a), 0)) if _has_column(a, _sort_column) else -1
			var y := int(column.get(Items.name_of(b), 0)) if _has_column(b, _sort_column) else -1
			return (x > y if _sort_way > 0 else x < y) if x != y else a < b)
	add_list_item(_heading(pictures))
	var row := 0
	for id: int in order:
		add_list_item(_entry(id, counts, row % 2 == 1))
		row += 1


func _heading(pictures: Array) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(LIST_WIDTH, ROW_HEIGHT) * P
	for i in 3:
		var at := Vector2(COLUMN_ENDS[i] - 18, 1)
		var slot := _picture(HEADING_SLOT, at)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.tooltip_text = Lang.t((["Crafted", "Used", "Mined"] if _page == "blocks" else ["Broken", "Crafted", "Used"])[i])
		var column := i
		slot.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				Sounds.play("random/click", null, 1.0, 1.0)
				var way := -_sort_way if _sort_column == column else 1
				menu.replace(StatsScreen.new(_page, column, way)))
		row.add_child(slot)
		row.add_child(_picture(pictures[i], at + Vector2(1, 1)))
		if _sort_column == i:
			row.add_child(_picture(ARROW_DOWN if _sort_way > 0 else ARROW_UP, at - Vector2(18, 0)))
	return row


## A block or item: its picture in a slot, its numbers ("-" where the
## column means nothing for it), every other row grey like Beta's.
func _entry(id: int, counts: Array, grey: bool) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(LIST_WIDTH, ROW_HEIGHT) * P
	var slot := _picture(SLOT, Vector2(1, 1))
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var name := Items.name_of(id)
	slot.tooltip_text = Items.display_name(id)
	row.add_child(slot)
	var view := ItemSlotView.new()
	view.position = Vector2(2, 2) * P
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_item(id, 1, false)
	row.add_child(view)
	for i in 3:
		var label := Label.new()
		var count := int((counts[i] as Dictionary).get(name, 0))
		label.text = str(count) if _has_column(id, i) else "-"
		label.add_theme_color_override("font_color", Color("909090") if grey else Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.size = Vector2(46, ROW_HEIGHT - 4) * P
		label.position = Vector2(COLUMN_ENDS[i] - 46, 4) * P
		row.add_child(label)
	return row


## A piece of slot.png at `at` (GUI pixels).
func _picture(region: Rect2i, at: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = UiTheme.gui_texture("slot.png")
	atlas.region = Rect2(Rect2i(region.position * P, region.size * P))
	picture.texture = atlas
	picture.position = at * P
	picture.size = Vector2(region.size) * P
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _row(left: String, right: String) -> void:
	for text in [left, right]:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT * 0.6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if text == left else HORIZONTAL_ALIGNMENT_RIGHT
		add_list_item(label)
