// The map held in both hands (HeldItem): the parchment, the map's picture
// and the player's marker, drawn over the world like the held item, in that
// order (render_priority), lit by the light at the player.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D picture : source_color, filter_nearest, repeat_disable;
uniform float brightness = 1.0;

void fragment() {
	vec4 texel = texture(picture, UV);
	ALBEDO = texel.rgb * brightness;
	ALPHA = texel.a;
}
