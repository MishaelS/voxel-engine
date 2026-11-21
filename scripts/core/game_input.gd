class_name GameInput
extends RefCounted
## Global switch for gameplay input. While a text field is in use (chat),
## gameplay must not react to keys polled with Input.* (WASD, arrows) or to
## mouse clicks in the world.

## Number of UI elements currently capturing the keyboard.
static var _locks := 0

## The "Phone" control mode (Settings' control_mode): fingers on the screen
## (TouchControls) in place of the mouse and the keys; the game is the same.
static var touch := false
## Phone mode's "the mouse is captured": the world is being played, no
## window is open (there is no cursor to hide).
static var _captured := false
## Phone mode: where the finger on the world points (a direction from the
## eye; ZERO: no finger), what it aims at like the crosshair does.
static var aim := Vector3.ZERO
## Phone mode: where that ray starts (the camera).
static var aim_from := Vector3.ZERO
## Phone mode: the finger is held on the world (breaking, eating, drawing).
static var hold := false


## Playing the world (true) or a window is open (false): on a PC the mouse
## is captured / shown.
static func capture(on: bool) -> void:
	_captured = on
	if not on:
		aim = Vector3.ZERO
		hold = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on and not touch else Input.MOUSE_MODE_VISIBLE


static func is_captured() -> bool:
	return _captured if touch else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Switches between the PC and the Phone controls (also while playing).
static func set_touch(on: bool) -> void:
	if on == touch:
		return
	var playing := is_captured()
	touch = on
	# A PC's mouse works as a finger, so the Phone mode can be tried there.
	Input.emulate_touch_from_mouse = on
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "sneak"]:
		Input.action_release(action)
	capture(playing)


static func is_blocked() -> bool:
	return _locks > 0


static func lock() -> void:
	_locks += 1


static func unlock() -> void:
	_locks = maxi(_locks - 1, 0)


## Clears all locks (when leaving the game scene: its UI is gone).
static func reset() -> void:
	_locks = 0
