class_name GameInput
extends RefCounted
## Global switch for gameplay input. While a text field is in use (chat),
## gameplay must not react to keys polled with Input.* (WASD, arrows) or to
## mouse clicks in the world.

## Number of UI elements currently capturing the keyboard.
static var _locks := 0


static func is_blocked() -> bool:
	return _locks > 0


static func lock() -> void:
	_locks += 1


static func unlock() -> void:
	_locks = maxi(_locks - 1, 0)
