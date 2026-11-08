// Shared code for block materials.
// Vertex data written by ChunkMesher:
//   UV     - position inside the tile (0..1)
//   UV2    - x: base tile layer, y: overlay tile layer (-1 = none)
//   COLOR  - rgb: biome tint (linear), a: baked voxel AO (linear multiplier)

//
// Includers may #define before including:
//   BLOCK_TILE_FILTER   - texture filter of the tiles (default: mipmapped)
//   BLOCK_CUSTOM_VERTEX - write their own vertex() (must set tile_layers = UV2)

#ifndef BLOCK_TILE_FILTER
#define BLOCK_TILE_FILTER filter_nearest_mipmap_anisotropic
#endif

uniform sampler2DArray tiles : source_color, BLOCK_TILE_FILTER, repeat_disable;

varying flat vec2 tile_layers;

#ifndef BLOCK_CUSTOM_VERTEX
void vertex() {
	tile_layers = UV2;
}
#endif

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
	return vec4(rgb * vertex_color.a, base.a);
}
