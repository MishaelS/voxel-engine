// Breaking progress drawn over a block (BlockInteraction): the crack tile
// of the current stage darkens what is behind it, like Beta's multiply
// (the block times the crack's gray). Drawn as black with the darkening as
// its alpha (behind * (1 - a) is behind * gray): a multiplying blend would
// also darken the crack's empty texels in the Mobile renderer, which
// stores colors at half strength.
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap, repeat_disable;
uniform int stage = 240;

void fragment() {
	vec4 crack = texture(tiles, vec3(UV, float(stage)));
	float gray = dot(crack.rgb, vec3(1.0 / 3.0));
	ALBEDO = vec3(0.0);
	ALPHA = crack.a * (1.0 - gray);
}
