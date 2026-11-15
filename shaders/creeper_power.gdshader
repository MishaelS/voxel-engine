// A charged creeper's glow (Mob, MobModels.power_shell), like Beta 1.7.3's
// RenderCreeper: armor/power.png on a model a little bigger (Beta's 2
// pixels, ours 1: MobModels.POWER_SHELL), the picture
// sliding along both axes 0.01 a tick, at half color, added to what is
// behind (GL_ONE, GL_ONE), not lit.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D skin : source_color, filter_nearest, repeat_enable;
// The game's ticks and the part of the next one.
uniform float ticks = 0.0;

void fragment() {
	float slide = ticks * 0.01;
	vec4 texel = texture(skin, UV + vec2(slide, slide));
	ALBEDO = texel.rgb * 0.5;
}
