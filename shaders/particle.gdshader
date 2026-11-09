// Particles (BlockParticles): camera-facing squares showing a quarter of a
// block tile (the tile array), a quarter of an item icon (items.png) or a
// plain color (smoke, flames), like the classic game.
// INSTANCE_CUSTOM: x = tile layer (>= 0), -1 = item atlas, -2 = plain;
// yz = texture origin (0..1 within the tile, or within the item atlas);
// w = size in blocks. COLOR = tint * brightness, alpha = opacity.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2DArray tiles : source_color, filter_nearest, repeat_disable;
uniform sampler2D items : source_color, filter_nearest, repeat_disable;

varying flat vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_position = center + vec3(VERTEX.xy * INSTANCE_CUSTOM.w, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	// A quarter of a tile (4 x 4 texture pixels).
	float span = INSTANCE_CUSTOM.x == -1.0 ? 1.0 / 64.0 : 0.25;
	UV = INSTANCE_CUSTOM.yz + vec2(UV.x, UV.y) * span;
}

void fragment() {
	vec4 texel = vec4(1.0);
	if (custom.x >= 0.0) {
		texel = texture(tiles, vec3(UV, custom.x));
	} else if (custom.x == -1.0) {
		texel = texture(items, UV);
	}
	ALBEDO = texel.rgb * COLOR.rgb;
	ALPHA = texel.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
