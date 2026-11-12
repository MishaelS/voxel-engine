// "Classic" shader pack, translucent blocks: water, ice. Color pass after
// block_translucent_depth (see block_translucent.gdshader for why).
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

#define BLOCK_CUSTOM_VERTEX
#define CLASSIC_GAMMA
#include "res://shaders/block_common.gdshaderinc"
#include "res://shaders/block_classic.gdshaderinc"

uniform float depth_bias = 0.00001;

void vertex() {
	BLOCK_VERTEX
	face_shade = classic_face_shade(NORMAL);
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Relative: depth is reverse Z (near/distance), so a fixed offset
	// would grow to decimeters far away and let faces behind show through.
	POSITION.z *= 1.0 + depth_bias;
}

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = classic_light(albedo.rgb);
	ALPHA = albedo.a;
}
