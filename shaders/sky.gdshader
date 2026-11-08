// Blocky retro sky: color gradient, textured sun and moon (with moon
// phases), pixel stars and a flat layer of blocky clouds drifting overhead.
// sun_direction is driven by DayNightCycle; everything else reacts to it.
shader_type sky;

// Direction TOWARD the sun. The moon is always opposite.
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.4);

group_uniforms colors;
uniform vec3 day_zenith : source_color = vec3(0.47, 0.65, 1.0);
uniform vec3 day_horizon : source_color = vec3(0.75, 0.85, 1.0);
uniform vec3 night_zenith : source_color = vec3(0.01, 0.012, 0.03);
uniform vec3 night_horizon : source_color = vec3(0.03, 0.04, 0.09);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.42, 0.12);
uniform vec3 void_color : source_color = vec3(0.16, 0.18, 0.28);

group_uniforms sun_and_moon;
// Textures include the halo; the disc is the opaque square in the middle.
uniform sampler2D sun_texture : source_color, filter_nearest, repeat_disable, hint_default_black;
uniform sampler2D moon_texture : source_color, filter_nearest, repeat_disable, hint_default_black;
uniform float sun_size = 0.36;  // half-size of the whole texture, tangent-plane units
uniform float moon_size = 0.3;
uniform float sun_intensity = 1.0;       // disc brightness (the disc replaces the sky)
uniform float sun_halo_intensity = 0.9;  // soft halo around the disc
uniform float moon_intensity = 1.1;
uniform float moon_halo_intensity = 0.6;
// 0 = new moon, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;
// Brightness of the unlit part of the disc (light reflected from Earth).
uniform float earthshine : hint_range(0.0, 1.0) = 0.07;
// Size of the moon disc in texture pixels and the texture size, used to
// keep the phase terminator on the texture's pixel grid.
uniform float moon_disc_pixels = 8.0;
uniform float moon_texture_pixels = 32.0;

group_uniforms clouds;
uniform float cloud_height = 110.0;  // world Y of the cloud layer
uniform float cloud_cell = 12.0;     // world size of one cloud "pixel"
uniform float cloud_speed = 1.0;     // blocks per second, along +X
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float cloud_fade_distance = 1200.0;

group_uniforms stars;
uniform float star_density : hint_range(0.0, 0.05) = 0.006;
uniform float star_grid = 150.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

// Projects dir onto the plane tangent to the sky sphere at center:
// a square in these coordinates is a flat square billboard in the sky.
vec2 billboard(vec3 dir, vec3 center) {
	vec3 right = cross(vec3(0.0, 1.0, 0.0), center);
	right = length(right) < 1e-3 ? vec3(1.0, 0.0, 0.0) : normalize(right);
	vec3 up = cross(center, right);
	return vec2(dot(dir, right), dot(dir, up)) / max(dot(dir, center), 1e-4);
}

// Texture UV of a billboard of the given half-size (outside 0..1 = not hit).
// "right" in billboard() points to the viewer's left, so x is flipped;
// texture v grows downward.
vec2 billboard_uv(vec3 dir, vec3 center, float half_size) {
	vec2 p = billboard(dir, center) / half_size;
	return vec2(0.5 - p.x * 0.5, 0.5 - p.y * 0.5);
}

// Lit fraction of the whole disc for the current phase (0 = new, 1 = full).
float moon_illumination() {
	return 0.5 - 0.5 * cos(moon_phase * TAU);
}

// 1 if this point of the moon disc is lit for the current phase.
// The moon is treated as a sphere seen face-on: the terminator is the
// ellipse x = k * sqrt(1 - y^2), k = cos(phase angle). Waxing moon is lit
// on the right, waning on the left (as seen from the northern hemisphere).
// Evaluated per texture pixel so the shape stays pixelated.
float moon_lit(vec2 uv) {
	vec2 pixel = floor(uv * moon_texture_pixels) + 0.5;
	vec2 p = (pixel - moon_texture_pixels * 0.5) / (moon_disc_pixels * 0.5); // disc spans -1..1
	float half_width = sqrt(max(1.0 - p.y * p.y, 1e-4));
	float x = clamp(p.x / half_width, -1.0, 1.0);
	if (moon_phase > 0.5) {
		x = -x; // waning: lit side on the left
	}
	float k = cos(moon_phase * TAU);
	return step(k, x) * step(0.001, moon_illumination());
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float day = smoothstep(-0.2, 0.25, sun.y);

	vec3 zenith = mix(night_zenith, day_zenith, day);
	vec3 horizon = mix(night_horizon, day_horizon, day);

	// Sunrise / sunset: orange glow on the horizon on the sun's side.
	float low_sun = 1.0 - smoothstep(0.0, 0.4, abs(sun.y + 0.05));
	float toward_sun = 0.0;
	if (length(dir.xz) > 1e-4 && length(sun.xz) > 1e-4) {
		toward_sun = max(dot(normalize(dir.xz), normalize(sun.xz)), 0.0);
	}
	horizon = mix(horizon, sunset_color, low_sun * toward_sun * toward_sun * 0.85);

	vec3 color;
	if (dir.y >= 0.0) {
		color = mix(horizon, zenith, pow(dir.y, 0.6));
	} else {
		color = mix(horizon, void_color * (0.15 + 0.85 * day), smoothstep(0.0, 0.25, -dir.y));
	}

	// Details are skipped in the radiance cubemap (ambient light and
	// reflections only need the gradient) to keep sky updates cheap.
	if (!AT_CUBEMAP_PASS) {
		// Stars: random cells of a grid on the sky sphere, only after dusk.
		float night = 1.0 - smoothstep(-0.25, 0.02, sun.y);
		if (dir.y > 0.0 && night > 0.0) {
			vec3 cell = floor(dir * star_grid);
			if (hash13(cell) < star_density) {
				float brightness = 0.4 + 0.6 * hash13(cell + 17.0);
				color += vec3(brightness) * night * smoothstep(0.0, 0.15, dir.y);
			}
		}

		// Sun: textured billboard with its halo, added on top of the sky
		// (hidden below the horizon), redder and dimmer when low.
		if (dot(dir, sun) > 0.0 && dir.y > -0.02) {
			vec2 uv = billboard_uv(dir, sun, sun_size);
			if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
				vec4 texel = texture(sun_texture, uv);
				vec3 tint = mix(vec3(1.0), vec3(1.0, 0.45, 0.2), low_sun * 0.9);
				float disc = step(0.99, texel.a);
				float dim = 0.2 + 0.8 * smoothstep(0.0, 0.35, sun.y);
				// The opaque disc covers the sky; the halo is added on top.
				color = disc > 0.5
					? texel.rgb * tint * sun_intensity * max(dim, 0.6)
					: color + texel.rgb * texel.a * tint * sun_halo_intensity * dim;
			}
		}

		// Moon: textured billboard with phases (hidden below the horizon).
		vec3 moon = -sun;
		if (dot(dir, moon) > 0.0 && dir.y > -0.02) {
			vec2 uv = billboard_uv(dir, moon, moon_size);
			if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
				vec4 texel = texture(moon_texture, uv);
				float lit = moon_lit(uv);
				// Unlit part stays faintly visible (earthshine); the halo
				// follows how much of the disc is lit.
				float disc = step(0.99, texel.a);
				// The disc covers the sky (and the stars behind it); the halo is added.
				color = disc > 0.5
					? texel.rgb * mix(earthshine, 1.0, lit) * moon_intensity
					: color + texel.rgb * texel.a * moon_illumination() * moon_halo_intensity;
			}
		}

		// Flat layer of blocky clouds.
		if (dir.y > 0.01 && POSITION.y < cloud_height) {
			float dist = (cloud_height - POSITION.y) / dir.y;
			vec2 hit = POSITION.xz + dir.xz * dist;
			hit.x += TIME * cloud_speed;
			vec2 cell = floor(hit / cloud_cell);
			float n = value_noise(cell * 0.12) * 0.65 + value_noise(cell * 0.31) * 0.35;
			float cover = step(1.0 - cloud_coverage, n);
			float fade = 1.0 - smoothstep(cloud_fade_distance * 0.3, cloud_fade_distance, dist);
			// Night clouds are dark silhouettes, just above the night sky color.
			vec3 cloud_color = mix(night_horizon * 1.4, vec3(1.0), day);
			cloud_color = mix(cloud_color, cloud_color * vec3(1.0, 0.7, 0.55), low_sun * 0.6);
			color = mix(color, cloud_color, cover * fade * cloud_opacity);
		}
	}

	COLOR = color;
}
