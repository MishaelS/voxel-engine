// Sky of the title screen (no world): a calm evening, in the style of the
// loading screen. Deep blue overhead fading to a warm glow at the horizon,
// a soft halo where the light comes from, twinkling pixel stars (fading
// out toward the bright horizon) and a dark sea of haze below.
shader_type sky;

#include "res://shaders/stars.gdshaderinc"

uniform vec3 zenith_color : source_color = vec3(0.03, 0.06, 0.16);
uniform vec3 middle_color : source_color = vec3(0.10, 0.18, 0.36);
uniform vec3 horizon_color : source_color = vec3(0.55, 0.42, 0.52);
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.38);
uniform vec3 below_color : source_color = vec3(0.05, 0.07, 0.13);
// Where the glow is (toward the light of the scene).
uniform vec3 glow_direction = vec3(0.55, 0.1, -0.5);

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 color;
	if (dir.y >= 0.0) {
		float h = pow(dir.y, 0.5);
		color = mix(horizon_color, middle_color, smoothstep(0.0, 0.45, h));
		color = mix(color, zenith_color, smoothstep(0.45, 1.0, h));
	} else {
		color = mix(horizon_color * 0.6, below_color, smoothstep(0.0, 0.2, -dir.y));
	}
	// Warm glow toward the light, strongest at the horizon.
	float toward = max(dot(dir, normalize(glow_direction)), 0.0);
	float horizon = 1.0 - smoothstep(0.0, 0.5, abs(dir.y));
	color += glow_color * pow(toward, 6.0) * (0.25 + 0.6 * horizon);
	if (!AT_CUBEMAP_PASS && dir.y > 0.0) {
		color += vec3(stars(dir, TIME)) * smoothstep(0.08, 0.45, dir.y);
	}
	COLOR = color;
}
