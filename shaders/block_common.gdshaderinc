// Shared code for block materials.
// Vertex data written by ChunkMesher:
//   UV     - position inside the tile (0..1)
//   UV2    - x: base tile layer + AO level (0..3) / 4, y: overlay layer (-1 = none)
//   COLOR  - rgb: tint (linear, biome colors included), a: smooth sky light / 15
// Brightness is computed here like the classic game: the light level, minus
// the night's darkness (sky_darkness, levels), through the classic light
// curve; times the corner's ambient occlusion.
//
// Includers may #define before including:
//   BLOCK_TILE_FILTER   - texture filter of the tiles (default: mipmapped)
//   BLOCK_CUSTOM_VERTEX - write their own vertex(), starting with BLOCK_VERTEX

#ifndef BLOCK_TILE_FILTER
#define BLOCK_TILE_FILTER filter_nearest_mipmap_anisotropic
#endif

uniform sampler2DArray tiles : source_color, BLOCK_TILE_FILTER, repeat_disable;
// Set by BlockMaterials / Atmosphere / settings.
uniform vec4 ao_levels = vec4(0.22, 0.45, 0.68, 1.0);
uniform float ao_strength = 1.0;
uniform float shadow_contrast = 1.35;
// Light levels taken away from sky light at night (Classic pack), 0..11.
uniform float sky_darkness = 0.0;

varying flat vec2 tile_layers;
varying float block_ao;

// The vertex part every block shader runs: tile layers and AO.
#define BLOCK_VERTEX tile_layers = vec2(floor(UV2.x + 0.01), UV2.y); block_ao = mix(1.0, ao_levels[clamp(int(fract(UV2.x + 0.01) * 4.0 + 0.5), 0, 3)], ao_strength);

#ifndef BLOCK_CUSTOM_VERTEX
void vertex() {
	BLOCK_VERTEX
}
#endif

// Brightness of a light level (0..1 = 0..15), the classic curve: each
// level a clear step down, level 0 keeps 5%.
float light_brightness(float level01) {
	float level = clamp(level01 * 15.0 - sky_darkness, 0.0, 15.0);
	float darkness = 1.0 - level / 15.0;
	float classic = (1.0 - darkness) / (darkness * 3.0 + 1.0);
	return pow(classic, shadow_contrast) * 0.95 + 0.05;
}

// Returns linear albedo (rgb) and coverage (a).
vec4 block_albedo(vec2 uv, vec4 vertex_color) {
	vec4 base = texture(tiles, vec3(uv, tile_layers.x));
	vec3 rgb;
	if (tile_layers.y >= 0.0) {
		// Overlay (e.g. grass fringe on dirt): tint applies to the overlay only.
		vec4 overlay = texture(tiles, vec3(uv, tile_layers.y));
		rgb = mix(base.rgb, overlay.rgb * vertex_color.rgb, overlay.a);
	} else {
		rgb = base.rgb * vertex_color.rgb;
	}
	return vec4(rgb * block_ao * light_brightness(vertex_color.a), base.a);
}
