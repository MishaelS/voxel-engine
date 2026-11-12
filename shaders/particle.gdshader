// Particles (BlockParticles): camera-facing squares showing a quarter of a
// block tile (the tile array), a quarter of an item icon (items.png), a
// picture of the particle atlas (particles-atlas.png: smoke, flames,
// hearts, sweeps...) or a plain color, like the classic game.
// INSTANCE_CUSTOM: x = tile layer (>= 0), -1 = item atlas, -2 = plain,
// -10 / -11 / -12 = a particle atlas picture of 8 x 8 / 16 x 16 / 32 x 16
// pixels; yz = texture origin (0..1 within the tile or atlas); w = size in
// blocks (the height; 32 x 16 pictures are twice as wide). COLOR = tint *
// brightness, alpha = opacity.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2DArray tiles : source_color, filter_nearest, repeat_disable;
uniform sampler2D items : source_color, filter_nearest, repeat_disable;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_size = vec2(512.0, 256.0);

varying flat vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	vec2 corner = VERTEX.xy;
	vec2 span = vec2(INSTANCE_CUSTOM.x == -1.0 ? 1.0 / 64.0 : 0.25); // a quarter of a tile / icon
	if (INSTANCE_CUSTOM.x <= -9.5) {
		int code = int(-10.0 - INSTANCE_CUSTOM.x + 0.5);
		vec2 pixels = code == 0 ? vec2(8.0) : (code == 1 ? vec2(16.0) : vec2(32.0, 16.0));
		span = pixels / atlas_size;
		corner.x *= pixels.x / pixels.y;
	}
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_position = center + vec3(corner * INSTANCE_CUSTOM.w, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	UV = INSTANCE_CUSTOM.yz + vec2(UV.x, UV.y) * span;
}

void fragment() {
	vec4 texel = vec4(1.0);
	if (custom.x >= 0.0) {
		texel = texture(tiles, vec3(UV, custom.x));
	} else if (custom.x == -1.0) {
		texel = texture(items, UV);
	} else if (custom.x <= -9.5) {
		texel = texture(atlas, UV);
	}
	ALBEDO = texel.rgb * COLOR.rgb;
	ALPHA = texel.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
