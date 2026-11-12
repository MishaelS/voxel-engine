// Far terrain (FarTerrain): the blocks' own textures (the tile array, layer
// in UV2.x) repeated once per block (UV in blocks), times the vertex color
// (biome tint and the face's shade, linear), times the sky's brightness now.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap, repeat_enable;
uniform float brightness = 1.0;

varying flat float layer;

void vertex() {
	layer = UV2.x;
}

void fragment() {
	// Repeated per block; the mip level from the unwrapped coordinates (no
	// seams at the block edges).
	vec2 uv = fract(UV);
	vec4 texel = textureGrad(tiles, vec3(uv, layer), dFdx(UV), dFdy(UV));
	ALBEDO = texel.rgb * COLOR.rgb * brightness;
}
