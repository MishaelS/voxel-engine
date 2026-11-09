// The block in the player's hand (HeldItem): drawn over the world (no depth
// test, so it never sinks into walls), with fixed face shading like the
// classic game and the light at the player.
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_always, shadows_disabled, fog_disabled;

#define BLOCK_TILE_FILTER filter_nearest
#define BLOCK_CUSTOM_VERTEX
#include "res://shaders/block_common.gdshaderinc"

uniform float brightness = 1.0;

varying flat float shade;

void vertex() {
	BLOCK_VERTEX
	shade = NORMAL.y > 0.5 ? 1.0 : (NORMAL.y < -0.5 ? 0.5 : (abs(NORMAL.x) > 0.5 ? 0.6 : 0.8));
}

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = albedo.rgb * shade * brightness;
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
