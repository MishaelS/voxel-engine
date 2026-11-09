// Full-screen overlay drawn over the 3D view, under the HUD:
// - vignette like the classic game's fancy graphics: dark corners, stronger
//   in the dark;
// - a color tint (blue under water).
// Uses only SCREEN_UV (no screen texture read), so it is one cheap pass.
shader_type canvas_item;

uniform float vignette : hint_range(0.0, 1.0) = 0.3;
uniform vec4 tint : source_color = vec4(0.0);

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	float corners = smoothstep(0.25, 0.8, length(p) * 1.15);
	float dark = corners * vignette;
	// Tint first, then darken: alpha-blended over the frame.
	vec3 color = tint.rgb * (1.0 - dark);
	float alpha = 1.0 - (1.0 - tint.a) * (1.0 - dark);
	COLOR = vec4(alpha > 0.0 ? color * tint.a / alpha : vec3(0.0), alpha);
}
