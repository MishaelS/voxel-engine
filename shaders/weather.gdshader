// Falling rain and snow (WeatherEffects): sheets of streaks scrolling
// down (snow slowly, drifting), see-through, fading with the rain and
// toward the edge of the rain area, lit by the light at the eyes.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D streaks : source_color, filter_nearest, repeat_enable;
uniform float speed = 1.0;
uniform float strength = 1.0;
uniform float brightness = 1.0;

varying float distance_to_camera;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	distance_to_camera = length(world_position.xz - CAMERA_POSITION_WORLD.xz);
}

void fragment() {
	vec2 uv = UV;
	uv.y += TIME * speed * 2.5;
	if (speed < 0.5) {
		uv.x += sin(TIME * 0.7 + UV.x * 3.0) * 0.15;
	}
	vec4 texel = texture(streaks, uv);
	float fade = clamp(1.0 - distance_to_camera / 6.5, 0.0, 1.0);
	ALBEDO = texel.rgb * mix(0.25, 1.0, brightness);
	ALPHA = texel.a * strength * (fade * 0.5 + 0.5) * smoothstep(0.0, 0.15, fade) * 0.6;
}
