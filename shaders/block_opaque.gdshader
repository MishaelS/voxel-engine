shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/block_common.gdshaderinc"

void fragment() {
	vec3 albedo = block_albedo(UV, COLOR).rgb;
	ALBEDO = albedo;
	EMISSION = albedo * block_emission();
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
