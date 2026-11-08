extends Label
## Simple HUD: FPS, camera position, render stats and a controls hint.

@export var camera: Camera3D
@export var world: VoxelWorld


func _process(_delta: float) -> void:
	var pos := camera.global_position if camera else Vector3.ZERO
	var lines := PackedStringArray([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Position: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z],
		"Window: %dx%d" % [get_window().size.x, get_window().size.y],
	])

	if world and not world.stats.is_empty():
		var s := world.stats
		var culled: float = 100.0 * (1.0 - float(s.faces) / maxi(s.faces_naive, 1))
		lines.append("Chunks: %d" % s.chunks)
		lines.append("Faces: %d of %d (%.0f%% culled)" % [s.faces, s.faces_naive, culled])
		lines.append("Triangles: %d, vertices: %d" % [s.triangles, s.vertices])
		lines.append("Meshing: %.2f ms" % s.mesh_ms)

	lines.append("")
	lines.append("LMB - capture mouse, Esc - release")
	lines.append("WASD - movement, E/Space - up, Q - down")
	lines.append("Shift - speed boost, wheel - speed")
	lines.append("F11 / Alt+Enter - toggle fullscreen")
	text = "\n".join(lines)
