// Slight blur of everything drawn behind it (the title panorama), like the
// classic title screen: a small gaussian over a lower mip of the screen.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 4.0) = 1.3; // mip level

void fragment() {
	vec2 step_size = SCREEN_PIXEL_SIZE * exp2(strength);
	vec3 color = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float weight = exp(-float(x * x + y * y) / 4.0);
			color += textureLod(screen, SCREEN_UV + vec2(float(x), float(y)) * step_size, strength).rgb * weight;
			total += weight;
		}
	}
	COLOR = vec4(color / total, 1.0);
}
