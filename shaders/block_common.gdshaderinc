// Shared code for block materials.
// Vertex data written by ChunkMesher:
//   UV     - position inside the tile (0..1)
//   UV2    - x: base tile layer + AO level (0..3) / 4, y: overlay layer (-1 = none,
//            -2 = glowing: full bright whatever the light, like lava)
//   COLOR  - rgb: tint (linear, biome colors included), a: smooth sky light / 15
//   CUSTOM0 - r: smooth block light / 15 (torches, lava: BlockLight)
// Brightness is computed here like the classic game: the brighter of sky
// light minus the night's darkness (sky_darkness, levels) and block light,
// through the classic light curve; times the corner's ambient occlusion.
//
// Includers may #define before including:
//   CLASSIC_GAMMA       - light, AO and face shading worked out like the
//                         classic game, on the texture's sRGB colors (its
//                         light table, smooth lighting's 0.4 / 0.6 / 0.8
//                         corners), then turned into linear: the original's
//                         deep corners and dark sides (Classic pack)
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
// Brightness setting (Classic): 0 = Moody (the classic game) .. 1 = Bright,
// lifting dark light levels like the modern game's gamma.
uniform float classic_gamma = 0.5;

// Blocks drawn as things (dropped block items, falling sand): the
// brightness where they are (VoxelWorld.brightness_at), set per instance;
// below 0 (the world's chunks) the light comes from the vertices.
instance uniform float entity_light = -1.0;

varying flat vec2 tile_layers;
varying float block_ao;
varying float block_glow;

// The vertex part every block shader runs: tile layers and AO.
#ifdef CLASSIC_GAMMA
// The classic smooth lighting: a corner by 3 / 2 / 1 / 0 solid blocks keeps
// 0.4 / 0.6 / 0.8 / 1 of the light (sRGB, made linear below).
const vec4 CLASSIC_AO = vec4(0.4, 0.6, 0.8, 1.0);
#define BLOCK_AO(level) pow(mix(1.0, CLASSIC_AO[level], ao_strength), 2.2)
#else
#define BLOCK_AO(level) mix(1.0, ao_levels[level], ao_strength)
#endif
#define BLOCK_VERTEX tile_layers = vec2(floor(UV2.x + 0.01), UV2.y); block_ao = BLOCK_AO(clamp(int(fract(UV2.x + 0.01) * 4.0 + 0.5), 0, 3)); block_glow = CUSTOM0.r;

#ifndef BLOCK_CUSTOM_VERTEX
void vertex() {
	BLOCK_VERTEX
}
#endif

// Brightness of a light level (0..1 = 0..15), the classic curve: each
// level a clear step down, level 0 keeps 5%.
float light_brightness(float level01) {
	float level = max(clamp(level01 * 15.0 - sky_darkness, 0.0, 15.0), block_glow * 15.0);
	float darkness = 1.0 - level / 15.0;
	float classic = (1.0 - darkness) / (darkness * 3.0 + 1.0);
#ifdef CLASSIC_GAMMA
	float table = classic * 0.95 + 0.05; // the game's light table (sRGB)
	float lifted = 1.0 - (1.0 - table) * (1.0 - table) * (1.0 - table) * (1.0 - table);
	return pow(mix(table, lifted, classic_gamma), 2.2); // made linear
#else
	return pow(classic, shadow_contrast) * 0.95 + 0.05;
#endif
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
	if (tile_layers.y < -1.5) {
		return vec4(rgb, base.a); // glowing (lava)
	}
	float light = entity_light >= 0.0 ? entity_light : light_brightness(vertex_color.a);
	return vec4(rgb * block_ao * light, base.a);
}

// 1 for glowing blocks (lava): lit shaders add their color as emission.
float block_emission() {
	return tile_layers.y < -1.5 ? 1.0 : 0.0;
}
