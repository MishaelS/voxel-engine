shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

#include "res://shaders/block_common.gdshaderinc"

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
}
