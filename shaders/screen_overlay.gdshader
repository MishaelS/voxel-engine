// Full-screen overlay drawn over the 3D view, under the HUD:
// - vignette like the classic game's fancy graphics: dark corners, stronger
//   in the dark;
//   (a texture pack's misc/vignette.png instead, like Beta's: white where
//   it darkens);
// - a color tint (blue under water), or a texture pack's misc/water.png
//   over the screen like Beta's (4 x 4 times, moving with the view).
// Uses only SCREEN_UV (no screen texture read), so it is one cheap pass.
shader_type canvas_item;

uniform float vignette : hint_range(0.0, 1.0) = 0.3;
uniform vec4 tint : source_color = vec4(0.0);
uniform bool use_vignette_map = false;
uniform sampler2D vignette_map : source_color, filter_linear, hint_default_black;
uniform float water_overlay = 0.0; // brightness of misc/water.png (0: none)
uniform vec2 water_offset = vec2(0.0);
uniform sampler2D water_map : source_color, filter_nearest, repeat_enable, hint_default_transparent;

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	float corners = use_vignette_map ? texture(vignette_map, SCREEN_UV).r
		: smoothstep(0.25, 0.8, length(p) * 1.15);
	float dark = corners * vignette;
	vec4 over = tint;
	if (water_overlay > 0.0) {
		vec4 water = texture(water_map, SCREEN_UV * 4.0 + water_offset);
		over = vec4(water.rgb * water_overlay, 0.5 * water.a);
	}
	// Tint first, then darken: alpha-blended over the frame.
	vec3 color = over.rgb * (1.0 - dark);
	float alpha = 1.0 - (1.0 - over.a) * (1.0 - dark);
	COLOR = vec4(alpha > 0.0 ? color * over.a / alpha : vec3(0.0), alpha);
}
