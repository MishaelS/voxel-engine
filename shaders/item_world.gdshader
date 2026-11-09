// Flat items lying on the ground (ItemEntities): the extruded picture of
// an item or plant (ItemMeshes), with simple side shading and the light
// where the item lies (per instance).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D items : source_color, filter_nearest, repeat_disable;
instance uniform float brightness = 1.0;

varying flat float shade;

void vertex() {
	shade = abs(NORMAL.z) > 0.5 ? 1.0 : (abs(NORMAL.x) > 0.5 ? 0.7 : 0.85);
}

void fragment() {
	vec4 texel = texture(items, UV);
	ALBEDO = texel.rgb * COLOR.rgb * shade * brightness;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
