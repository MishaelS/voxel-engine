// Flat items in the player's hand (HeldItem): the icon from items.png
// extruded into a thin 3D shape, drawn over the world like the held block,
// with simple side shading and the light at the player.
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_always, shadows_disabled, fog_disabled;

uniform sampler2D items : source_color, filter_nearest, repeat_disable;
uniform float brightness = 1.0;

varying flat float shade;

void vertex() {
	shade = abs(NORMAL.z) > 0.5 ? 1.0 : (abs(NORMAL.x) > 0.5 ? 0.7 : 0.85);
}

void fragment() {
	vec4 texel = texture(items, UV);
	ALBEDO = texel.rgb * shade * brightness;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
