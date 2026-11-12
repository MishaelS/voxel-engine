// Flat entity pictures (the arrow's crossed planes): their texture,
// see-through where it is clear, both sides, the light where they are.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D picture : source_color, filter_nearest, repeat_disable;
instance uniform float brightness = 1.0;

void fragment() {
	vec4 texel = texture(picture, UV);
	ALBEDO = texel.rgb * brightness;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
