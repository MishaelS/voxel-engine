// "Classic" shader pack, opaque blocks (see block_classic.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_back;

#define BLOCK_CUSTOM_VERTEX
#define CLASSIC_GAMMA
#include "res://shaders/block_common.gdshaderinc"
#include "res://shaders/block_classic.gdshaderinc"

void vertex() {
	BLOCK_VERTEX
	face_shade = classic_face_shade(NORMAL);
}

void fragment() {
	ALBEDO = classic_light(block_albedo(UV, COLOR).rgb);
}
