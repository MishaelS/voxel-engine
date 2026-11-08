extends Label
## Simple HUD: FPS, camera position, and a controls hint.

@export var camera: Camera3D


func _process(_delta: float) -> void:
	var pos := camera.global_position if camera else Vector3.ZERO
	text = "FPS: %d\nPosition: (%.1f, %.1f, %.1f)\n\nLMB - capture mouse, Esc - release\nWASD - movement, E/Space - up, Q - down\nShift - speed boost, wheel - speed" % [
		Engine.get_frames_per_second(), pos.x, pos.y, pos.z,
	]
