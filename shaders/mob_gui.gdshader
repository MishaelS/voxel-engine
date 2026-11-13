// The player's model in the inventory window (InventoryPlayerView): the
// mob skin lit like Beta's RenderHelper.enableStandardItemLighting - two
// white lights fixed to the view (diffuse 0.6 each) over a 0.4 ambient -
// so the shading turns smoothly with the body instead of by world axis.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D skin : source_color, filter_nearest, repeat_disable;
instance uniform float hurt = 0.0;

// The two lights' directions in view space (x right, y up, z toward the
// viewer), as GuiInventory sets them up: (0.2, 1, -0.7) and (-0.2, 1, 0.7)
// turned 135 degrees around y, then into the window's frame.
const vec3 LIGHT_0 = vec3(-0.514, 0.808, 0.286);
const vec3 LIGHT_1 = vec3(0.514, 0.808, -0.286);

varying float shade;

void vertex() {
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	shade = min(0.4 + 0.6 * (max(dot(n, LIGHT_0), 0.0) + max(dot(n, LIGHT_1), 0.0)), 1.0);
}

void fragment() {
	vec4 texel = texture(skin, UV);
	vec3 color = texel.rgb * shade;
	color = mix(color, vec3(shade, 0.0, 0.0), hurt * 0.4);
	ALBEDO = color;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
