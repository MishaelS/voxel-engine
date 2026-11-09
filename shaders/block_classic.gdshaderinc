// Lighting of the "Classic" shader pack, like the original game: no
// real-time sun light or shadows. Everything is baked into the block:
// - light levels and voxel AO (block_common: at night sky light loses up to
//   11 levels, sky_darkness, like the classic game; caves stay as they are);
// - fixed face shading: top 1.0, north/south 0.8, east/west 0.6, bottom 0.5.
// Shaders that include this #define BLOCK_CUSTOM_VERTEX before including
// block_common.gdshaderinc, and in vertex() set
//   face_shade = classic_face_shade(NORMAL);
// (varyings can only be written in vertex() itself).

uniform bool face_shading = true;

varying flat float face_shade;

float classic_face_shade(vec3 normal) {
	if (!face_shading) {
		return 1.0;
	}
	if (normal.y > 0.5) return 1.0;
	if (normal.y < -0.5) return 0.5;
	return abs(normal.z) > 0.5 ? 0.8 : 0.6;
}

vec3 classic_light(vec3 albedo) {
	return albedo * face_shade;
}
