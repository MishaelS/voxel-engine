// Breaking progress drawn over a block (BlockInteraction): the crack tile
// of the current stage multiplied over what is behind it.
shader_type spatial;
render_mode unshaded, blend_mul, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap, repeat_disable;
uniform int stage = 240;

void fragment() {
	vec4 crack = texture(tiles, vec3(UV, float(stage)));
	ALBEDO = mix(vec3(1.0), crack.rgb, crack.a);
}
