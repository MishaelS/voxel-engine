// 3D clouds like the classic game's "fancy" clouds: a layer of boxes, one
// per cell of a repeating 256x256 cloud pattern, drifting along +X.
//
// The mesh is a fixed grid of boxes around the camera (all 6 faces of
// every cell, UV = cell index). The vertex shader reads the pattern and
// collapses the faces of empty cells and the faces between two cloud
// cells, so moving and scrolling the clouds costs no CPU work at all.
shader_type spatial;
render_mode unshaded, cull_back, depth_prepass_alpha, fog_disabled, shadows_disabled;

uniform sampler2D pattern : filter_nearest, repeat_enable;
// Pattern cell of the mesh's cell (0, 0).
uniform ivec2 offset;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float opacity = 0.8;
uniform vec3 camera_position;
uniform float fade_start = 150.0;
uniform float fade_end = 280.0;

varying float shade;
varying vec3 world_position;

bool cloud_at(ivec2 cell) {
	ivec2 size = textureSize(pattern, 0);
	ivec2 wrapped = ((cell % size) + size) % size;
	return texelFetch(pattern, wrapped, 0).r > 0.5;
}

void vertex() {
	ivec2 cell = ivec2(floor(UV + 0.5)) + offset;
	bool visible = cloud_at(cell);
	if (visible && abs(NORMAL.y) < 0.5) {
		// Side faces only between a cloud cell and an empty one.
		visible = !cloud_at(cell + ivec2(int(round(NORMAL.x)), int(round(NORMAL.z))));
	}
	if (!visible) {
		VERTEX = vec3(0.0); // degenerate triangle: nothing is drawn
	}
	// Fixed face shading of the classic clouds.
	shade = NORMAL.y > 0.5 ? 1.0 : (NORMAL.y < -0.5 ? 0.7 : (abs(NORMAL.x) > 0.5 ? 0.9 : 0.8));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = cloud_color * shade;
	float distance = length(world_position.xz - camera_position.xz);
	ALPHA = opacity * (1.0 - smoothstep(fade_start, fade_end, distance));
}
