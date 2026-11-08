extends Label
## Simple HUD: FPS, camera position, render stats and a controls hint.

@export var camera: Camera3D
@export var world: VoxelWorld


func _process(_delta: float) -> void:
	var pos := camera.global_position if camera else Vector3.ZERO
	var viewport_rid := get_viewport().get_viewport_rid()
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	var lines := PackedStringArray([
		"FPS: %d (VSync %s)" % [Engine.get_frames_per_second(), "on" if vsync else "off"],
		"Frame: %.2f ms (render CPU %.2f ms)" % [
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
				+ RenderingServer.get_frame_setup_time_cpu(),
		],
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
	lines.append("F11 / Alt+Enter - toggle fullscreen, F3 - toggle VSync")
	text = "\n".join(lines)
