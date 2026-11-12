// The outline of the targeted block (BlockInteraction): each edge is a quad
// whose two sides are pushed apart on screen, so lines are always WIDTH
// pixels thick however far the block is (GPU lines are only 1 pixel).
// UV + UV2.x hold the edge's other end, UV2.y which side (-1 / +1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Half of each line sinks behind the block's faces: about 2 pixels show,
// black and a little see-through, like the game's.
uniform float width = 4.0;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.55);

void vertex() {
	mat4 to_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX;
	vec4 here = to_clip * vec4(VERTEX, 1.0);
	vec4 there = to_clip * vec4(UV.x, UV.y, UV2.x, 1.0);
	vec2 a = here.xy / here.w;
	vec2 b = there.xy / there.w;
	vec2 along = (b - a) * VIEWPORT_SIZE;
	vec2 across = length(along) > 0.0001 ? normalize(vec2(-along.y, along.x)) : vec2(0.0, 1.0);
	here.xy += across * UV2.y * width / VIEWPORT_SIZE * here.w;
	here.z += 0.0002 * here.w; // a hair toward the camera (reversed depth)
	POSITION = here;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
