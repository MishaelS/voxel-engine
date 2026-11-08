// Inventory icons of blocks (BlockIcons): unshaded, with the fixed face
// shading of the classic game's item icons (top bright, sides darker).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

#define BLOCK_TILE_FILTER filter_nearest
#define BLOCK_CUSTOM_VERTEX
#include "res://shaders/block_common.gdshaderinc"

varying flat float shade;

void vertex() {
	tile_layers = UV2;
	shade = NORMAL.y > 0.5 ? 1.0 : (abs(NORMAL.z) > 0.5 ? 0.8 : 0.6);
}

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = albedo.rgb * shade;
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
