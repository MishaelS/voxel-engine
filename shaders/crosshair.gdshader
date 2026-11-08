// Crosshair that inverts what is behind it (like the classic game), so it
// stays visible on any background.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 cross_pixel = texture(TEXTURE, UV);
	vec3 behind = texture(screen_texture, SCREEN_UV).rgb;
	COLOR = vec4(vec3(1.0) - behind, cross_pixel.a);
}
