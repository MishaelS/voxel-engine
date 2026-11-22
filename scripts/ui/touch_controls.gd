class_name TouchControls
extends Control
## The Phone control mode's screen controls (Settings' control_mode), like
## the mobile game's: a cross of movement arrows at the bottom left with the
## sneak button (a diamond; a tap switches sneaking on and off) in its
## middle, the jump button at the bottom right, chat and pause at the top
## right, the inventory button beside the hotbar. The finger may slide from
## one arrow to another; between two arrows it walks diagonally. A finger anywhere else is on the world: dragging turns
## the view, a short tap uses / places (hits a creature), holding breaks the
## block under the finger (eats the food, draws the bow in hand). A tap on
## a hotbar slot selects it.
##
## Everything goes through the same input actions and the same code as the
## keys and the mouse (Player, BlockInteraction), so the game is the same.
## Each finger has its own job, so walking, looking and jumping work at once.

const P := UiTheme.PIXEL
## Button sizes at 100% (Options > Controls > Button Size scales them).
const BASE_BUTTON := 32 * P
const BASE_SMALL_BUTTON := 24 * P
const MARGIN := 10 * P
## One button of the movement cross (it is 3 x 3 of them).
const BASE_PAD_CELL := 32 * P
## The breaking ring under a held finger (its radius).
const RING := 14 * P
## A finger that moved less than this is still a tap / a hold.
const TAP_SLOP := 7.0 * P
## Seconds a finger stays in place before it breaks rather than taps.
const HOLD_SECONDS := 0.3
## View turn per GUI unit of a finger's move, in mouse pixels.
const LOOK_SCALE := 1.5

## The buttons' pictures are in assets/textures/extra/touch/ (replace them
## to change the look): a 16 x 16 icon is drawn on a menu button (UiTheme),
## a larger picture is the whole button, stretched over it. Seen through.
const OPACITY := 0.6
const ICONS := "res://assets/textures/extra/touch/"
var _icons := {} # name -> Texture2D

enum Job { STICK, WORLD, BUTTON, HOTBAR }

var player: Player
var hotbar: Hotbar
var interaction: BlockInteraction
var screenshots: Node

## Finger index -> {job, start, at, moved, time, held, aims, button}.
var _fingers := {}
## The movement cross: -1 / 0 / 1 sideways and forward (y up is -1).
var _stick := Vector2i.ZERO
var _sneaking := false
var _was_active := false


var _button_size := BASE_BUTTON
var _small_button := BASE_SMALL_BUTTON
## One button of the movement cross, as large as the setting makes it.
var _cell_size := BASE_PAD_CELL


func _ready() -> void:
	_apply_size()
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "touch_button_size":
			_apply_size())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	modulate.a = OPACITY
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _exit_tree() -> void:
	_release_all()


func _active() -> bool:
	return GameInput.touch and GameInput.is_captured() and not GameInput.is_blocked()


func _process(_delta: float) -> void:
	if GameInput.touch and not GameInput.is_captured() and _can_play():
		GameInput.capture(true) # a window closed: back to playing (no click needed)
	var active := _active()
	visible = active and not (screenshots and screenshots.get("hud_hidden"))
	if active != _was_active:
		_was_active = active
		if not active:
			_release_all()
		queue_redraw()
	if not active:
		return
	if GameInput.hold:
		queue_redraw() # the breaking ring under the finger
	var now := Time.get_ticks_msec() / 1000.0
	for finger: Dictionary in _fingers.values():
		if finger.job == Job.WORLD and finger.aims and not finger.moved and not finger.held \
				and now - finger.time >= HOLD_SECONDS:
			finger.held = true
			GameInput.hold = true
			interaction.touch_hold()


## Nothing is open and the player is up: the world can be played.
func _can_play() -> bool:
	return not GameInput.is_blocked() and not get_tree().paused and not LoadingScreen.active \
		and player != null and not player.dead and not player.sleeping \
		and not (screenshots and screenshots.get("isometric"))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active():
				_finger_down(event.index, event.position)
		elif _fingers.has(event.index):
			_finger_up(event.index, event.position)
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		_finger_moved(event.index, event.position, event.relative)


func _finger_down(index: int, at: Vector2) -> void:
	var finger := {"job": Job.WORLD, "start": at, "at": at, "moved": false, "held": false, "aims": false,
		"time": Time.get_ticks_msec() / 1000.0, "button": ""}
	var button := _button_at(at)
	if button != "":
		finger.job = Job.BUTTON
		finger.button = button
		if button == "jump":
			_action("jump", true)
		elif button == "sneak":
			_sneaking = not _sneaking
			_action("sneak", _sneaking)
	elif _hotbar_rect().has_point(at):
		finger.job = Job.HOTBAR
		hotbar.select(clampi(int((at.x - hotbar.global_position.x - 1 * P) / (20 * P)), 0, Hotbar.SLOT_COUNT - 1))
	elif _pad_rect().grow(4 * P).has_point(at) and not _has_job(Job.STICK):
		if _pad_cell(at) == Vector2i.ZERO:
			finger.job = Job.BUTTON
			finger.button = "sneak"
			_sneaking = not _sneaking
			_action("sneak", _sneaking)
		else:
			finger.job = Job.STICK
			_set_stick(_pad_cell(at))
	elif not _has_aim():
		finger.aims = true # the first finger on the world points at blocks
		_aim(at)
	_fingers[index] = finger
	queue_redraw()


func _finger_moved(index: int, at: Vector2, relative: Vector2) -> void:
	var finger: Dictionary = _fingers[index]
	finger.at = at
	match finger.job:
		Job.STICK:
			_set_stick(_pad_cell(at))
		Job.WORLD:
			if not finger.moved and at.distance_to(finger.start) > TAP_SLOP:
				finger.moved = true
			if finger.moved or finger.held:
				player.turn(relative * LOOK_SCALE)
			if finger.aims:
				if finger.moved and not finger.held:
					GameInput.aim = Vector3.ZERO # looking around: nothing is pointed at
				else:
					_aim(at)
	queue_redraw()


func _finger_up(index: int, at: Vector2) -> void:
	var finger: Dictionary = _fingers[index]
	_fingers.erase(index)
	match finger.job:
		Job.STICK:
			_set_stick(Vector2i.ZERO)
		Job.BUTTON:
			if finger.button == "jump":
				_action("jump", false)
			elif finger.button != "sneak" and _button_at(at) == finger.button:
				# Chat, pause, inventory: the same actions as their keys.
				var action: String = {"chat": "open_chat", "pause": "ui_cancel", "inventory": "inventory"}[finger.button]
				_action(action, true)
				_action(action, false)
		Job.WORLD:
			if finger.aims:
				if finger.held:
					GameInput.hold = false
				elif not finger.moved:
					_aim(at)
					interaction.touch_tap()
				GameInput.aim = Vector3.ZERO
	queue_redraw()


func _has_job(job: Job) -> bool:
	for finger: Dictionary in _fingers.values():
		if finger.job == job:
			return true
	return false


func _has_aim() -> bool:
	for finger: Dictionary in _fingers.values():
		if finger.aims:
			return true
	return false


## The finger at `at` points into the world like the crosshair does: the
## ray from the camera through that point (in the GUI's units, like the
## camera's own; also behind the player in the third person view).
func _aim(at: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		GameInput.aim = camera.project_ray_normal(at)
		GameInput.aim_from = camera.project_ray_origin(at)


func _set_stick(value: Vector2i) -> void:
	_stick = value
	_strength("move_forward", -value.y)
	_strength("move_back", value.y)
	_strength("move_left", -value.x)
	_strength("move_right", value.x)


func _strength(action: String, value: float) -> void:
	if value > 0.0:
		Input.action_press(action, value)
	else:
		Input.action_release(action)


## Presses / releases an action like its key does (an event, so what waits
## for the press gets it: the menus, the double jump of flying).
func _action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_all() -> void:
	_fingers.clear()
	_set_stick(Vector2i.ZERO)
	_sneaking = false
	Input.action_release("jump")
	Input.action_release("sneak")
	GameInput.aim = Vector3.ZERO
	GameInput.hold = false


## The buttons' size setting (percent), in whole GUI units.
func _apply_size() -> void:
	var factor := float(Settings.get_value("touch_button_size")) / 100.0
	_button_size = roundf(BASE_BUTTON * factor)
	_small_button = roundf(BASE_SMALL_BUTTON * factor)
	_cell_size = roundf(BASE_PAD_CELL * factor)
	queue_redraw()


# --- Layout -----------------------------------------------------------------------

func _pad_rect() -> Rect2:
	return Rect2(MARGIN, size.y - MARGIN - _cell_size * 3, _cell_size * 3, _cell_size * 3)


## The cross's button under a point: (-1..1, -1..1), (0, 0) its middle.
func _pad_cell(at: Vector2) -> Vector2i:
	var cell := ((at - _pad_rect().position) / _cell_size).floor()
	return Vector2i(clampi(int(cell.x), 0, 2) - 1, clampi(int(cell.y), 0, 2) - 1)


func _pad_button(cell: Vector2i) -> Rect2:
	return Rect2(_pad_rect().position + Vector2(cell + Vector2i.ONE) * _cell_size, Vector2(_cell_size, _cell_size)).grow(-P)


func _hotbar_rect() -> Rect2:
	return hotbar.get_global_rect().grow(2 * P) if hotbar and hotbar.is_visible_in_tree() else Rect2()


func _buttons() -> Dictionary:
	var right := size.x - MARGIN
	var result := {
		"jump": Rect2(right - _button_size, size.y - MARGIN - _button_size, _button_size, _button_size),
		"pause": Rect2(right - _small_button, MARGIN / 2.0, _small_button, _small_button),
		"chat": Rect2(right - _small_button * 2 - 4 * P, MARGIN / 2.0, _small_button, _small_button),
	}
	if hotbar and hotbar.is_visible_in_tree():
		var bar := hotbar.get_global_rect()
		result["inventory"] = Rect2(bar.end.x + 2 * P, bar.position.y, bar.size.y, bar.size.y)
	return result


func _button_at(at: Vector2) -> String:
	var buttons := _buttons()
	for id: String in buttons:
		if (buttons[id] as Rect2).grow(2 * P).has_point(at):
			return id
	return ""


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	var pressed := {}
	for finger: Dictionary in _fingers.values():
		if finger.job == Job.BUTTON:
			pressed[finger.button] = true
	var buttons := _buttons()
	for id: String in buttons:
		var rect: Rect2 = buttons[id]
		_button(id, rect, pressed.has(id))
	# The movement cross: four arrows, sneak in the middle; walking forward,
	# like the mobile game, two more beside the forward one go forward
	# diagonally (the finger slides onto them).
	var cells: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	if _stick.y < 0:
		cells.append_array([Vector2i(-1, -1), Vector2i(1, -1)])
	for cell: Vector2i in cells:
		var lit := _stick == cell or (cell.x == 0 or cell.y == 0) and \
			((cell.x != 0 and cell.x == _stick.x) or (cell.y != 0 and cell.y == _stick.y))
		_button(WALK_ICONS[cell], _pad_button(cell), lit)
	_button("sneak", _pad_button(Vector2i.ZERO), _sneaking)
	# Breaking: a ring under the finger fills up, like the mobile game's.
	for finger: Dictionary in _fingers.values():
		if finger.aims and finger.held and interaction and interaction.break_progress > 0.0:
			var center: Vector2 = finger.at
			draw_arc(center, RING, 0.0, TAU, 32, UiTheme.SHADOW_COLOR, 3 * P)
			draw_arc(center, RING, -PI / 2, -PI / 2 + TAU * clampf(interaction.break_progress, 0.0, 1.0),
				32, UiTheme.TEXT_COLOR, 2 * P)


## The arrow of the movement cross's button for `way`.
const WALK_ICONS := {
	Vector2i(0, -1): "walk_forward", Vector2i(0, 1): "walk_back",
	Vector2i(-1, 0): "walk_left", Vector2i(1, 0): "walk_right",
	Vector2i(-1, -1): "walk_forward_left", Vector2i(1, -1): "walk_forward_right",
}


## Pictures up to this size are icons drawn on a menu button; larger ones
## are the whole button (its own background), filling it.
const ICON_SIZE := 16
## A whole-button picture while pressed: lighter.
const PRESSED := Color(1.35, 1.35, 1.35)


## A button: its picture (ICONS) on a menu button's box (the highlighted
## one while pressed), as large as whole pixels fit; or, a picture larger
## than an icon, the picture alone stretched over the button.
func _button(id: String, rect: Rect2, lit: bool) -> void:
	if not _icons.has(id):
		_icons[id] = TexturePacks.load_texture(ICONS + id + ".png")
	var texture: Texture2D = _icons[id]
	var picture := texture.get_size() if texture else Vector2.ZERO
	if picture.x > ICON_SIZE or picture.y > ICON_SIZE:
		draw_texture_rect(texture, rect, false, PRESSED if lit else Color.WHITE)
		return
	draw_style_box(UiTheme.theme().get_stylebox("hover" if lit else "normal", "Button"), rect)
	if texture == null:
		return
	var scale := maxf(floorf(minf(rect.size.x / picture.x, rect.size.y / picture.y)), 1.0)
	var drawn := picture * scale
	draw_texture_rect(texture, Rect2((rect.position + (rect.size - drawn) / 2.0).round(), drawn), false)
