class_name InventoryScreen
extends Control
## Inventory windows like the classic game:
## - Inventory (E): survival (container0.png) with armor slots and a 2x2
##   crafting grid, creative (container4.png) with a scrollable catalog of
##   every block and item;
## - Crafting table (container1.png): a 3x3 crafting grid;
## - Chest (container3.png): its 27 slots; large chest (container4.png): the
##   two halves' 27 slots each, the left half on top;
## - Furnace (container2.png): input, fuel and output with the fire and
##   the cooking arrow.
## Each shows the player's inventory and hotbar below.
##
## Mouse, like the classic game:
## - LMB: pick up / put down / swap a stack; RMB: pick up half, put one;
## - Shift + LMB: move a stack to the other part of the window (inventory:
##   hotbar <-> main; chest <-> inventory; furnace: into input or fuel;
##   result: craft all);
## - 1-9 over a slot: swap it with that hotbar slot; Q over a slot: throw
##   one item out (Ctrl+Q the stack);
## - clicking outside the window throws the held stack (RMB one item);
## - catalog: LMB takes a full stack, RMB one more; clicking it while
##   holding something deletes what is held; the mouse wheel scrolls it.
## Closing returns what is held and what is in the crafting grid to the
## inventory (what does not fit is thrown out).

enum Mode { INVENTORY, CRAFTING_TABLE, CHEST, FURNACE, LARGE_CHEST }
enum Kind { INVENTORY, CRAFT, RESULT, CATALOG, ARMOR, CONTAINER, OUTPUT }

const P := UiTheme.PIXEL
const CATALOG_COLUMNS := 9
const CATALOG_ROWS := 6
const TITLE_COLOR := Color("404040")
const TOOLTIP_BACKGROUND := Color(0.063, 0.0, 0.063, 0.94)
const TOOLTIP_BORDER := Color(0.31, 0.0, 1.0, 0.31)

@export var player: Player

var _open := false
var _mode := Mode.INVENTORY
var _creative := false
var _window: TextureRect
var _slots: Array[Dictionary] = [] # {kind, index, pos: Vector2i, view}
var _hover := -1
var _highlight: ColorRect
var _held: ItemSlotView
var _held_id := Blocks.AIR
var _held_count := 0
var _held_damage := 0
var _tooltip: PanelContainer
var _tooltip_label: Label
var _craft_width := 2
var _craft := Inventory.new(9)
var _catalog := PackedInt32Array()
var _scroll := 0
## The chest's or furnace's block entity (VoxelWorld.block_entity).
var _entity := {}
var _container: Inventory
## Every container inventory shown (both halves of a large chest).
var _containers: Array[Inventory] = []
var _flame: Control
var _arrow: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_catalog = Items.catalog()
	if player:
		player.inventory.changed.connect(_refresh)
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "gui_scale" and _open:
			_refresh.call_deferred())


func is_open() -> bool:
	return _open


## The player's inventory (E).
func open() -> void:
	_open_mode(Mode.INVENTORY)


func open_crafting_table() -> void:
	_open_mode(Mode.CRAFTING_TABLE)


## A chest or furnace: its block entity (VoxelWorld.block_entity).
func open_container(entity: Dictionary) -> void:
	if entity.is_empty():
		return
	_entity = entity
	_container = entity.inventory
	_containers = [_container]
	_container.changed.connect(_refresh)
	_open_mode(Mode.FURNACE if entity.type == "furnace" else Mode.CHEST)


## A large chest: the block entities of its left and right halves.
func open_large_chest(left: Dictionary, right: Dictionary) -> void:
	if left.is_empty() or right.is_empty():
		return
	_entity = left
	_container = left.inventory
	_containers = [left.inventory, right.inventory]
	for inventory in _containers:
		inventory.changed.connect(_refresh)
	_open_mode(Mode.LARGE_CHEST)


func _open_mode(mode: Mode) -> void:
	if _open or player == null or player.dead:
		return
	_open = true
	_mode = mode
	_creative = player.is_creative() and mode == Mode.INVENTORY
	_craft_width = 3 if mode == Mode.CRAFTING_TABLE else 2
	_build()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameInput.lock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	if _mode == Mode.CHEST or _mode == Mode.LARGE_CHEST:
		Sounds.play("chest/close", null, 0.5, randf() * 0.1 + 0.9)
	# Nothing is lost: the held stack and the crafting grid go back.
	_give(_held_id, _held_count, _held_damage)
	_held_id = Blocks.AIR
	_held_count = 0
	_held_damage = 0
	for i in _craft.size():
		_give(_craft.id_at(i), _craft.count_at(i), _craft.damage_at(i))
	_craft.clear()
	for inventory in _containers:
		if inventory.changed.is_connected(_refresh):
			inventory.changed.disconnect(_refresh)
	_containers.clear()
	_container = null
	_entity = {}
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameInput.unlock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Back into the inventory; what does not fit is thrown out.
func _give(id: int, count: int, damage: int = 0) -> void:
	if id != Blocks.AIR and count > 0:
		var left := player.inventory.add(id, count, damage)
		if left > 0:
			player.throw_items(id, left, damage)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _hover >= 0:
		if event.is_action_pressed("drop_item"):
			_throw_from_slot(_slots[_hover], event is InputEventWithModifiers and (event.ctrl_pressed or event.meta_pressed))
			get_viewport().set_input_as_handled()
			return
		for i in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				_swap_with_hotbar(_slots[_hover], i)
				get_viewport().set_input_as_handled()
				return


func _unhandled_input(event: InputEvent) -> void:
	if not _open and event.is_action_pressed("inventory") and not GameInput.is_blocked():
		open()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open and _mode == Mode.FURNACE:
		_update_furnace_progress()


# --- Layout -----------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_slots.clear()
	_hover = -1
	_flame = null
	_arrow = null

	add_child(UiTheme.blur_rect()) # the world behind is slightly blurred
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.06, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var texture := "container/container0.png"
	if _creative:
		texture = "container/container4.png"
	elif _mode == Mode.CRAFTING_TABLE:
		texture = "container/container1.png"
	elif _mode == Mode.FURNACE:
		texture = "container/container2.png"
	elif _mode == Mode.CHEST:
		texture = "container/container3.png"
	elif _mode == Mode.LARGE_CHEST:
		texture = "container/container4.png"
	_window = TextureRect.new()
	_window.texture = UiTheme.gui_texture(texture)
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

	var main_y := 84
	var hotbar_y := 142
	match _mode:
		Mode.INVENTORY:
			if _creative:
				main_y = 140
				hotbar_y = 198
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
		Mode.CRAFTING_TABLE:
			_title("Crafting", Vector2(28, 6))
			_title("Inventory", Vector2(8, 72))
			for i in 9:
				_add_slot(Kind.CRAFT, i, Vector2i(30 + (i % 3) * 18, 17 + (i / 3) * 18))
			_add_slot(Kind.RESULT, 0, Vector2i(124, 35))
		Mode.CHEST:
			main_y = 85
			hotbar_y = 143
			_title("Chest", Vector2(8, 6))
			_title("Inventory", Vector2(8, 73))
			for i in VoxelWorld.CHEST_SIZE:
				_add_slot(Kind.CONTAINER, i, Vector2i(8 + (i % 9) * 18, 18 + (i / 9) * 18), _container)
		Mode.LARGE_CHEST:
			main_y = 140
			hotbar_y = 198
			_title("Large Chest", Vector2(8, 6))
			_title("Inventory", Vector2(8, 128))
			for i in VoxelWorld.CHEST_SIZE * 2:
				_add_slot(Kind.CONTAINER, i % VoxelWorld.CHEST_SIZE, Vector2i(8 + (i % 9) * 18, 18 + (i / 9) * 18),
					_containers[i / VoxelWorld.CHEST_SIZE])
		Mode.FURNACE:
			_title("Furnace", Vector2(60, 6))
			_title("Inventory", Vector2(8, 72))
			_add_slot(Kind.CONTAINER, 0, Vector2i(56, 17))
			_add_slot(Kind.CONTAINER, 1, Vector2i(56, 53))
			_add_slot(Kind.OUTPUT, 2, Vector2i(116, 35))
			_flame = _progress_clip("container/fuelProgress.png", Vector2i(56, 36))
			_arrow = _progress_clip("container/smeltingProgress.png", Vector2i(79, 34))
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


func _add_slot(kind: Kind, index: int, pos: Vector2i, inventory: Inventory = null) -> void:
	var view := ItemSlotView.new()
	view.position = Vector2(pos) * P
	_window.add_child(view)
	_slots.append({"kind": kind, "index": index, "pos": pos, "view": view, "inventory": inventory})


## A progress picture (furnace fire / arrow) shown through a clipping box.
func _progress_clip(path: String, pos: Vector2i) -> Control:
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(pos) * P
	clip.size = Vector2.ZERO
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.texture = UiTheme.gui_texture(path)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.name = "Picture"
	clip.add_child(picture)
	_window.add_child(clip)
	return clip


## The fire burns down from the top; the arrow fills from the left, like
## the classic game.
func _update_furnace_progress() -> void:
	if _flame == null or _entity.is_empty():
		return
	var burn: int = _entity.get("burn", 0)
	var total: int = maxi(_entity.get("burn_total", 0), 1)
	var flame_height := 0
	if burn > 0:
		flame_height = burn * 12 / total + 2
	_flame.position = Vector2(56, 36 + 14 - flame_height) * P
	_flame.size = Vector2(14, flame_height) * P
	(_flame.get_node("Picture") as Control).position = Vector2(0, -(14 - flame_height)) * P
	var cook: int = _entity.get("cook", 0)
	_arrow.size = Vector2(cook * 24 / Smelting.COOK_TICKS + (1 if cook > 0 else 0), 17) * P


# --- Contents ------------------------------------------------------------------------

## The inventory behind a slot, or null (result, catalog, armor).
func _inventory_of(slot: Dictionary) -> Inventory:
	if slot.inventory != null:
		return slot.inventory
	match slot.kind:
		Kind.INVENTORY:
			return player.inventory
		Kind.CRAFT:
			return _craft
		Kind.CONTAINER, Kind.OUTPUT:
			return _container
	return null


## [id, count, damage] in a slot.
func _content(slot: Dictionary) -> Array:
	var inventory := _inventory_of(slot)
	if inventory:
		var index: int = slot.index
		return [inventory.id_at(index), inventory.count_at(index), inventory.damage_at(index)]
	match slot.kind:
		Kind.RESULT:
			var result := Crafting.result_of(_craft_grid(), _craft_width)
			return [result.id, result.count, 0] if not result.is_empty() else [Blocks.AIR, 0, 0]
		Kind.CATALOG:
			var i := _scroll * CATALOG_COLUMNS + int(slot.index)
			return [_catalog[i], 1, 0] if i < _catalog.size() else [Blocks.AIR, 0, 0]
	return [Blocks.AIR, 0, 0]


func _put(slot: Dictionary, id: int, count: int, damage: int = 0) -> void:
	var inventory := _inventory_of(slot)
	if inventory:
		inventory.set_slot(slot.index, id, count, damage)
		_refresh()


func _craft_grid() -> PackedInt32Array:
	var grid := PackedInt32Array()
	for i in _craft_width * _craft_width:
		grid.append(_craft.id_at(i))
	return grid


func _refresh() -> void:
	if not _open:
		return
	for slot in _slots:
		var content := _content(slot)
		(slot.view as ItemSlotView).set_item(content[0], content[1], slot.kind != Kind.CATALOG, content[2])
	_held.set_item(_held_id, _held_count, true, _held_damage)
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
				var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
				var index := _slot_at(event.position)
				if index >= 0:
					_click(_slots[index], right, event.shift_pressed)
					_refresh()
				elif _held_count > 0 and not Rect2(_window.position, _window.size).has_point(event.position):
					# Outside the window: throw the held stack (one with RMB).
					var thrown := 1 if right else _held_count
					player.throw_items(_held_id, thrown, _held_damage)
					_held_count -= thrown
					if _held_count == 0:
						_held_id = Blocks.AIR
						_held_damage = 0
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
		_tooltip_label.text = Items.display_name(id)
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
		Kind.OUTPUT:
			_click_output(slot, shift)
		_:
			if shift:
				_quick_move(slot)
			else:
				_click_stack(slot, right)


## The usual stack rules between the held stack and a slot.
func _click_stack(slot: Dictionary, right: bool) -> void:
	var content := _content(slot)
	var id: int = content[0]
	var count: int = content[1]
	var damage: int = content[2]
	if _held_count == 0:
		if count == 0:
			return
		var taken := (count + 1) / 2 if right else count
		_held_id = id
		_held_count = taken
		_held_damage = damage
		_put(slot, id, count - taken, damage)
	elif count == 0 or (id == _held_id and damage == _held_damage):
		var moved := 1 if right else _held_count
		moved = mini(moved, Items.max_stack(_held_id) - count)
		if moved <= 0:
			return
		_put(slot, _held_id, count + moved, _held_damage)
		_held_count -= moved
		if _held_count == 0:
			_held_id = Blocks.AIR
			_held_damage = 0
	else:
		_put(slot, _held_id, _held_count, _held_damage)
		_held_id = id
		_held_count = count
		_held_damage = damage


func _click_catalog(slot: Dictionary, right: bool, shift: bool) -> void:
	var id: int = _content(slot)[0]
	if id == Blocks.AIR:
		return
	var stack := Items.max_stack(id)
	if shift:
		player.inventory.add(id, stack)
	elif _held_count > 0 and not (right and _held_id == id):
		_held_id = Blocks.AIR # dropping onto the catalog deletes it
		_held_count = 0
		_held_damage = 0
	elif right:
		_held_id = id
		_held_count = mini(_held_count + 1, stack)
	else:
		_held_id = id
		_held_count = stack
		_held_damage = 0


func _click_result(shift: bool) -> void:
	var result := Crafting.result_of(_craft_grid(), _craft_width)
	while not result.is_empty():
		if shift:
			if player.inventory.room_for(result.id) < result.count:
				break
			player.inventory.add(result.id, result.count)
		else:
			if _held_count > 0 and (_held_id != result.id or _held_count + result.count > Items.max_stack(result.id)):
				return
			_held_id = result.id
			_held_count += result.count
			_held_damage = 0
		for i in _craft_width * _craft_width:
			if _craft.count_at(i) > 0:
				# A water bucket leaves its bucket (no such recipes yet).
				_craft.take(i)
		if not shift:
			return
		result = Crafting.result_of(_craft_grid(), _craft_width)


## Furnace output: take only (the whole stack, or into the inventory).
func _click_output(slot: Dictionary, shift: bool) -> void:
	var content := _content(slot)
	var id: int = content[0]
	var count: int = content[1]
	if count == 0:
		return
	if shift:
		_put(slot, id, player.inventory.add(id, count))
	elif _held_count == 0 or (_held_id == id and _held_count + count <= Items.max_stack(id)):
		_held_id = id
		_held_count += count
		_held_damage = 0
		_put(slot, Blocks.AIR, 0)


## Shift-click: to the other part of the window.
func _quick_move(slot: Dictionary) -> void:
	var content := _content(slot)
	var id: int = content[0]
	if content[1] == 0:
		return
	var left: int = content[1]
	if slot.kind == Kind.INVENTORY:
		match _mode:
			Mode.CHEST, Mode.LARGE_CHEST:
				for inventory in _containers:
					left = _insert(inventory, id, left, content[2], 0, inventory.size())
			Mode.FURNACE:
				if Smelting.result_of(id) != Blocks.AIR:
					left = _insert(_container, id, left, content[2], 0, 1)
				elif Items.fuel_ticks(id) > 0:
					left = _insert(_container, id, left, content[2], 1, 2)
			_:
				# Hotbar <-> main inventory.
				var in_hotbar: bool = slot.index < Inventory.HOTBAR_SIZE
				var from := Inventory.HOTBAR_SIZE if in_hotbar else 0
				var to := Inventory.SIZE if in_hotbar else Inventory.HOTBAR_SIZE
				left = _insert(player.inventory, id, left, content[2], from, to)
	else:
		# Chest, furnace or crafting grid -> the inventory.
		left = _insert(player.inventory, id, left, content[2], 0, Inventory.SIZE)
	_put(slot, id, left, content[2])


## Puts items into slots [from, to) of an inventory: existing stacks first,
## then empty slots. Returns what did not fit.
func _insert(inventory: Inventory, id: int, count: int, damage: int, from: int, to: int) -> int:
	var stack := Items.max_stack(id)
	for pass_empty in [false, true]:
		for i in range(from, to):
			if count == 0:
				return 0
			var empty := inventory.is_empty_slot(i)
			if empty != pass_empty or (not empty and (inventory.id_at(i) != id or inventory.damage_at(i) != damage)):
				continue
			var moved := mini(count, stack - inventory.count_at(i))
			if moved > 0:
				inventory.set_slot(i, id, inventory.count_at(i) + moved, damage)
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
				inventory.set_slot(hotbar, id, Items.max_stack(id))
		Kind.CRAFT, Kind.CONTAINER, Kind.OUTPUT:
			var content := _content(slot)
			if slot.kind == Kind.OUTPUT and not inventory.is_empty_slot(hotbar):
				return
			_put(slot, inventory.id_at(hotbar), inventory.count_at(hotbar), inventory.damage_at(hotbar))
			inventory.set_slot(hotbar, content[0], content[1], content[2])
	_refresh()


## Q over a slot: throw one item (or the stack) out of it.
func _throw_from_slot(slot: Dictionary, whole: bool) -> void:
	if _inventory_of(slot) == null:
		return
	var content := _content(slot)
	if content[1] == 0:
		return
	var thrown: int = content[1] if whole else 1
	player.throw_items(content[0], thrown, content[2])
	_put(slot, content[0], content[1] - thrown, content[2])
