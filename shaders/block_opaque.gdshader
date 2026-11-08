shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/block_common.gdshaderinc"

void fragment() {
	ALBEDO = block_albedo(UV, COLOR).rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
