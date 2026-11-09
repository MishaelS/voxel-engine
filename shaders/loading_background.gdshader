// Background of the loading screen: a night-sky gradient, a soft glow
// behind the island, slowly twinkling pixel stars and a vignette.
shader_type canvas_item;

uniform vec3 top_color : source_color = vec3(0.04, 0.07, 0.16);
uniform vec3 bottom_color : source_color = vec3(0.13, 0.2, 0.32);
uniform vec3 glow_color : source_color = vec3(0.35, 0.55, 0.85);
uniform vec2 glow_center = vec2(0.5, 0.42);
uniform float star_cell = 6.0; // pixels per star cell

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 color = mix(top_color, bottom_color, uv.y);
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float glow = 1.0 - smoothstep(0.0, 0.55, length((uv - glow_center) * aspect));
	color += glow_color * glow * glow * 0.35;
	vec2 cell = floor(FRAGCOORD.xy / star_cell);
	float star = step(0.996, hash12(cell));
	float twinkle = 0.5 + 0.5 * sin(TIME * (1.0 + hash12(cell + 7.0) * 3.0) + hash12(cell) * 40.0);
	color += vec3(star * twinkle * (1.0 - uv.y) * 0.8);
	float vignette = smoothstep(0.35, 0.95, length((uv - 0.5) * 1.3));
	COLOR = vec4(color * (1.0 - vignette * 0.6), 1.0);
}
