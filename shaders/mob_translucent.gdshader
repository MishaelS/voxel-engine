// See-through mob parts (MobModels, a part's "translucent": the slime's
// outer jelly): like mob.gdshader (the skin, shaded by side, lit where the
// mob stands, red when hurt) but blended by the skin's own alpha.
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque, shadows_disabled;

uniform sampler2D skin : source_color, filter_nearest, repeat_disable;
instance uniform float brightness = 1.0;
instance uniform float hurt = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
// Creeper about to blow: flashing white.
instance uniform float flash = 0.0;

varying flat float shade;

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	shade = n.y > 0.5 ? 1.0 : (n.y < -0.5 ? 0.5 : (abs(n.x) > 0.5 ? 0.6 : 0.8));
}

void fragment() {
	vec4 texel = texture(skin, UV);
	vec3 color = texel.rgb * tint.rgb * shade * brightness;
	// Hurt (and dying): Beta's red overlay, (brightness, 0, 0) at 40%.
	color = mix(color, vec3(brightness * shade, 0.0, 0.0), hurt * 0.4);
	color = mix(color, vec3(1.0), flash * 0.7);
	ALBEDO = color;
	ALPHA = texel.a;
}
