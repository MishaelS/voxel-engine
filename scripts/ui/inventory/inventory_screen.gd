class_name InventoryScreen
extends Control
## The inventory window (E), like the classic game. Two layouts:
## - Survival (container0.png): armor slots, a 2x2 crafting grid with its
##   result, the main inventory and the hotbar.
## - Creative (container4.png): every block in a scrollable 9x6 catalog
##   above the main inventory and the hotbar.
##
## Mouse, like the classic game:
## - LMB: pick up / put down / swap a stack; RMB: pick up half, put one;
## - Shift + LMB: move a stack between the hotbar and the main inventory
##   (catalog: a full stack into the inventory; result: craft all);
## - 1-9 over a slot: swap it with that hotbar slot;
## - catalog: LMB takes a full stack, RMB one more; clicking it while
##   holding something deletes what is held;
## - mouse wheel scrolls the catalog.
## Closing returns what is held and what is in the crafting grid to the
## inventory.

enum Kind { INVENTORY, CRAFT, RESULT, CATALOG, ARMOR }

const P := UiTheme.PIXEL
const CATALOG_COLUMNS := 9
const CATALOG_ROWS := 6
const TITLE_COLOR := Color("404040")
const TOOLTIP_BACKGROUND := Color(0.063, 0.0, 0.063, 0.94)
const TOOLTIP_BORDER := Color(0.31, 0.0, 1.0, 0.31)

@export var player: Player

var _open := false
var _creative := false
var _dim: ColorRect
var _window: TextureRect
var _slots: Array[Dictionary] = [] # {kind, index, pos: Vector2i, view}
var _hover := -1
var _highlight: ColorRect
var _held: ItemSlotView
var _held_id := Blocks.AIR
var _held_count := 0
var _tooltip: PanelContainer
var _tooltip_label: Label
var _craft_ids := PackedInt32Array([0, 0, 0, 0])
var _craft_counts := PackedInt32Array([0, 0, 0, 0])
var _catalog := PackedInt32Array()
var _scroll := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for id in range(1, Blocks.count()):
		_catalog.append(id)
	if player:
		player.inventory.changed.connect(_refresh)
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "gui_scale" and _open:
			_refresh.call_deferred())


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or player == null:
		return
	_open = true
	_creative = player.is_creative()
	_build()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameInput.lock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	# Nothing is lost: the held stack and the crafting grid go back.
	_give(_held_id, _held_count)
	_held_id = Blocks.AIR
	_held_count = 0
	for i in 4:
		_give(_craft_ids[i], _craft_counts[i])
		_craft_ids[i] = Blocks.AIR
		_craft_counts[i] = 0
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameInput.unlock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _give(id: int, count: int) -> void:
	if id != Blocks.AIR and count > 0:
		player.inventory.add(id, count)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _hover >= 0:
		for i in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				_swap_with_hotbar(_slots[_hover], i)
				get_viewport().set_input_as_handled()
				return


func _unhandled_input(event: InputEvent) -> void:
	if not _open and event.is_action_pressed("inventory") and not GameInput.is_blocked():
		open()
		get_viewport().set_input_as_handled()


# --- Layout -----------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_slots.clear()
	_hover = -1

	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.06, 0.08, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_window = TextureRect.new()
	_window.texture = UiTheme.gui_texture("container/container4.png" if _creative else "container/container0.png")
	_window.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var window_size := _window.texture.get_size() # gui_texture is already PIXEL-scaled
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -roundf(window_size.x / 2.0)
	_window.offset_top = -roundf(window_size.y / 2.0)
	_window.offset_right = _window.offset_left + window_size.x
	_window.offset_bottom = _window.offset_top + window_size.y
	add_child(_window)

	var main_y := 140 if _creative else 84
	var hotbar_y := 198 if _creative else 142
	if _creative:
		_title("Creative", Vector2(8, 6))
		_title("Inventory", Vector2(8, 128))
		for i in CATALOG_COLUMNS * CATALOG_ROWS:
			_add_slot(Kind.CATALOG, i, Vector2i(8 + (i % 9) * 18, 18 + (i / 9) * 18))
	else:
		_title("Crafting", Vector2(97, 7))
		for i in 4:
			_add_slot(Kind.ARMOR, i, Vector2i(8, 8 + i * 18))
		for i in 4:
			_add_slot(Kind.CRAFT, i, Vector2i(98 + (i % 2) * 18, 18 + (i / 2) * 18))
		_add_slot(Kind.RESULT, 0, Vector2i(154, 28))
	for i in 27:
		_add_slot(Kind.INVENTORY, Inventory.HOTBAR_SIZE + i, Vector2i(8 + (i % 9) * 18, main_y + (i / 9) * 18))
	for i in Inventory.HOTBAR_SIZE:
		_add_slot(Kind.INVENTORY, i, Vector2i(8 + i * 18, hotbar_y))

	_highlight = ColorRect.new()
	_highlight.color = Color(1, 1, 1, 0.5)
	_highlight.size = Vector2(16, 16) * P
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	_window.add_child(_highlight)

	_held = ItemSlotView.new()
	_held.visible = false
	add_child(_held)

	_tooltip = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = TOOLTIP_BACKGROUND
	box.border_color = TOOLTIP_BORDER
	box.set_border_width_all(P)
	box.set_content_margin_all(2 * P)
	box.content_margin_top = P
	_tooltip.add_theme_stylebox_override("panel", box)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)


func _title(text: String, pos: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos * P
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(label)


func _add_slot(kind: Kind, index: int, pos: Vector2i) -> void:
	var view := ItemSlotView.new()
	view.position = Vector2(pos) * P
	_window.add_child(view)
	_slots.append({"kind": kind, "index": index, "pos": pos, "view": view})


# --- Contents ------------------------------------------------------------------------

## [id, count] in a slot.
func _content(slot: Dictionary) -> Array:
	var index: int = slot.index
	match slot.kind:
		Kind.INVENTORY:
			return [player.inventory.id_at(index), player.inventory.count_at(index)]
		Kind.CRAFT:
			return [_craft_ids[index], _craft_counts[index]]
		Kind.RESULT:
			var result := Crafting.result_of(_craft_grid(), 2)
			return [result.id, result.count] if not result.is_empty() else [Blocks.AIR, 0]
		Kind.CATALOG:
			var i := _scroll * CATALOG_COLUMNS + index
			return [_catalog[i], 1] if i < _catalog.size() else [Blocks.AIR, 0]
	return [Blocks.AIR, 0]


func _put(slot: Dictionary, id: int, count: int) -> void:
	if count <= 0:
		id = Blocks.AIR
		count = 0
	var index: int = slot.index
	match slot.kind:
		Kind.INVENTORY:
			player.inventory.set_slot(index, id, count)
		Kind.CRAFT:
			_craft_ids[index] = id
			_craft_counts[index] = count
			_refresh()


func _craft_grid() -> PackedInt32Array:
	var grid := PackedInt32Array()
	for i in 4:
		grid.append(_craft_ids[i] if _craft_counts[i] > 0 else Blocks.AIR)
	return grid


func _refresh() -> void:
	if not _open:
		return
	for slot in _slots:
		var content := _content(slot)
		(slot.view as ItemSlotView).set_item(content[0], content[1], slot.kind != Kind.CATALOG)
	_held.set_item(_held_id, _held_count)
	_held.visible = _held_count > 0
	_update_hover(get_local_mouse_position())


# --- Mouse ----------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if _creative:
					var rows := ceili(_catalog.size() / float(CATALOG_COLUMNS))
					var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
					_scroll = clampi(_scroll + step, 0, maxi(rows - CATALOG_ROWS, 0))
					_refresh()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				var index := _slot_at(event.position)
				if index >= 0:
					_click(_slots[index], event.button_index == MOUSE_BUTTON_RIGHT, event.shift_pressed)
					_refresh()
		accept_event()


func _slot_at(point: Vector2) -> int:
	var local := (point - _window.position) / P
	for i in _slots.size():
		var pos: Vector2i = _slots[i].pos
		if local.x >= pos.x - 1 and local.x < pos.x + 17 and local.y >= pos.y - 1 and local.y < pos.y + 17:
			return i
	return -1


func _update_hover(point: Vector2) -> void:
	_held.position = point - Vector2(8, 8) * P
	_hover = _slot_at(point)
	var slot: Dictionary = _slots[_hover] if _hover >= 0 else {}
	_highlight.visible = _hover >= 0 and slot.kind != Kind.ARMOR
	var id := Blocks.AIR
	if _hover >= 0:
		_highlight.position = Vector2(slot.pos) * P
		id = _content(slot)[0]
	_tooltip.visible = id != Blocks.AIR and _held_count == 0
	if _tooltip.visible:
		_tooltip_label.text = Blocks.display_name(id)
		_tooltip.reset_size()
		_tooltip.position = point + Vector2(12, -12) * P
	# The held stack is drawn above everything.
	move_child(_held, get_child_count() - 1)


func _click(slot: Dictionary, right: bool, shift: bool) -> void:
	match slot.kind:
		Kind.ARMOR:
			return # no armor items yet
		Kind.CATALOG:
			_click_catalog(slot, right, shift)
		Kind.RESULT:
			_click_result(shift)
		_:
			if shift and slot.kind == Kind.INVENTORY:
				_quick_move(slot)
			elif shift and slot.kind == Kind.CRAFT:
				var content := _content(slot)
				_put(slot, content[0], player.inventory.add(content[0], content[1]))
			else:
				_click_stack(slot, right)


## The usual stack rules between the held stack and a slot.
func _click_stack(slot: Dictionary, right: bool) -> void:
	var content := _content(slot)
	var id: int = content[0]
	var count: int = content[1]
	if _held_count == 0:
		if count == 0:
			return
		var taken := (count + 1) / 2 if right else count
		_held_id = id
		_held_count = taken
		_put(slot, id, count - taken)
	elif count == 0 or id == _held_id:
		var moved := 1 if right else _held_count
		moved = mini(moved, Inventory.MAX_STACK - count)
		_put(slot, _held_id, count + moved)
		_held_count -= moved
		if _held_count == 0:
			_held_id = Blocks.AIR
	else:
		_put(slot, _held_id, _held_count)
		_held_id = id
		_held_count = count


func _click_catalog(slot: Dictionary, right: bool, shift: bool) -> void:
	var id: int = _content(slot)[0]
	if id == Blocks.AIR:
		return
	if shift:
		player.inventory.add(id, Inventory.MAX_STACK)
	elif _held_count > 0 and not (right and _held_id == id):
		_held_id = Blocks.AIR # dropping onto the catalog deletes it
		_held_count = 0
	elif right:
		_held_id = id
		_held_count = mini(_held_count + 1, Inventory.MAX_STACK)
	else:
		_held_id = id
		_held_count = Inventory.MAX_STACK


func _click_result(shift: bool) -> void:
	var result := Crafting.result_of(_craft_grid(), 2)
	while not result.is_empty():
		if shift:
			if player.inventory.add(result.id, result.count) > 0:
				break # inventory full (what did not fit is lost, like overflow)
		else:
			if _held_count > 0 and (_held_id != result.id or _held_count + result.count > Inventory.MAX_STACK):
				return
			_held_id = result.id
			_held_count += result.count
		for i in 4:
			if _craft_counts[i] > 0:
				_craft_counts[i] -= 1
				if _craft_counts[i] == 0:
					_craft_ids[i] = Blocks.AIR
		if not shift:
			return
		result = Crafting.result_of(_craft_grid(), 2)


## Shift-click: hotbar <-> main inventory, merging into stacks first.
func _quick_move(slot: Dictionary) -> void:
	var index: int = slot.index
	var content := _content(slot)
	if content[1] == 0:
		return
	var in_hotbar := index < Inventory.HOTBAR_SIZE
	var from := Inventory.HOTBAR_SIZE if in_hotbar else 0
	var to := Inventory.SIZE if in_hotbar else Inventory.HOTBAR_SIZE
	var left := _insert(content[0], content[1], from, to)
	_put(slot, content[0], left)


## Puts items into inventory slots [from, to): existing stacks first, then
## empty slots. Returns what did not fit.
func _insert(id: int, count: int, from: int, to: int) -> int:
	var inventory := player.inventory
	for pass_empty in [false, true]:
		for i in range(from, to):
			if count == 0:
				return 0
			var empty := inventory.is_empty_slot(i)
			if empty != pass_empty or (not empty and inventory.id_at(i) != id):
				continue
			var moved := mini(count, Inventory.MAX_STACK - inventory.count_at(i))
			if moved > 0:
				inventory.set_slot(i, id, inventory.count_at(i) + moved)
				count -= moved
	return count


## Number key over a slot: exchange it with hotbar slot `hotbar`.
func _swap_with_hotbar(slot: Dictionary, hotbar: int) -> void:
	var inventory := player.inventory
	match slot.kind:
		Kind.INVENTORY:
			if slot.index != hotbar:
				inventory.swap(slot.index, hotbar)
		Kind.CATALOG:
			var id: int = _content(slot)[0]
			if id != Blocks.AIR:
				inventory.set_slot(hotbar, id, Inventory.MAX_STACK)
		Kind.CRAFT:
			var content := _content(slot)
			_put(slot, inventory.id_at(hotbar), inventory.count_at(hotbar))
			inventory.set_slot(hotbar, content[0], content[1])
	_refresh()
