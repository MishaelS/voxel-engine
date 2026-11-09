// Color pass of translucent blocks (water, ice), drawn after
// block_translucent_depth: only the nearest translucent surface passes the
// depth test. Water's texture is animated by WaterAnimation (written into
// the tile array), so nothing water-specific is needed here.
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_never;

#define BLOCK_CUSTOM_VERTEX
#include "res://shaders/block_common.gdshaderinc"

// Pulls the surface a hair toward the camera so it passes the depth test
// against its own depth pass (reverse Z: larger is nearer).
uniform float depth_bias = 0.00001;
// Water shine (Dynamic Lighting pack option).
uniform float specular_strength = 1.0;

void vertex() {
	BLOCK_VERTEX
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Relative: depth is reverse Z (near/distance), so a fixed offset
	// would grow to decimeters far away and let faces behind show through.
	POSITION.z *= 1.0 + depth_bias;
}

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	ROUGHNESS = 0.15;
	SPECULAR = 0.5 * specular_strength;
}
