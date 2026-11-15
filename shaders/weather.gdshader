// Falling snow and rain (WeatherEffects), like Beta 1.7.3's
// EntityRenderer.renderRainSnow: the sheets' texture moves with the
// game's ticks by each column's own numbers (CUSTOM0), tinted by the
// light there (CUSTOM1.r) and more see-through toward the
// edge of the area (UV2: the column's middle).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D streaks : source_color, filter_nearest, repeat_enable;
uniform bool snow = false;
uniform float strength = 1.0;
// The game's ticks and the part of the next one (rendererUpdateCount + partial).
uniform float ticks = 0.0;
uniform float partial = 0.0;
uniform vec2 eye;
uniform float radius = 10.0;

varying vec2 offset;
varying float light;
varying float alpha;

void vertex() {
	float distance = length(UV2 - eye) / radius;
	light = CUSTOM1.r;
	if (snow) {
		float f4 = ticks + partial;
		float f5 = (mod(ticks, 512.0) + partial) / 512.0;
		float f6 = CUSTOM0.x + f4 * 0.01 * CUSTOM0.y;  // nextFloat + t * 0.01 * nextGaussian
		float f7 = CUSTOM0.z + f4 * CUSTOM0.w * 0.001; // nextFloat + t * nextGaussian * 0.001
		offset = vec2(f6, f5 + f7);
		alpha = ((1.0 - distance * distance) * 0.3 + 0.5) * strength;
	} else {
		// (ticks + the column's hash) & 31, plus the partial tick, of 32, times 3..4
		float f11 = (mod(ticks + CUSTOM0.y, 32.0) + partial) / 32.0 * (3.0 + CUSTOM0.x);
		offset = vec2(0.0, f11);
		alpha = ((1.0 - distance * distance) * 0.5 + 0.5) * strength;
	}
}

void fragment() {
	vec4 texel = texture(streaks, UV + offset);
	// The game multiplied the picture's colors by the light (sRGB values).
	ALBEDO = texel.rgb * pow(clamp(light, 0.0, 1.0), 2.2);
	ALPHA = texel.a * clamp(alpha, 0.0, 1.0);
	if (ALPHA <= 0.01) {
		discard; // (the game's alpha test: 0.01)
	}
}
