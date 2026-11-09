// First pass of translucent blocks (water, ice): writes only depth, so the
// color pass (block_translucent, its next_pass) draws just the nearest
// translucent surface of every pixel. Inside a chunk mesh triangles are not
// sorted; without this, faces behind each other blend in random order
// (dark half-quads), like the classic game sorts them per chunk.
// Only front faces: the water surface seen from below is its own
// downward-facing copy (ChunkMesher).
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_always, shadows_disabled, fog_disabled;

void vertex() {
	// Same expression as the color pass, so both get the same depth.
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
