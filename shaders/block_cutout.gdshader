shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/block_common.gdshaderinc"

void fragment() {
	vec4 albedo = block_albedo(UV, COLOR);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
