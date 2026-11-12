// Mobs (Mob, MobModels): their skin, shaded by side like blocks, lit by the
// light where the mob stands (per instance) and flashing red when hurt.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled; // both sides: through see-through pixels the inside shows (the skeleton's spine)

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
	color = mix(color, vec3(1.0, 0.1, 0.1), hurt * 0.6);
	color = mix(color, vec3(1.0), flash * 0.7);
	ALBEDO = color;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
