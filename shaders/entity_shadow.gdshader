shader_type spatial;
// Beta's round shadow under creatures (Entity._show_shadow): misc/shadow.png
// blended over the blocks, its strength in the vertex alpha.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D shadow_texture : source_color, filter_linear, repeat_disable;

void fragment() {
	vec4 texel = texture(shadow_texture, UV);
	ALBEDO = texel.rgb;
	ALPHA = texel.a * COLOR.a;
}
