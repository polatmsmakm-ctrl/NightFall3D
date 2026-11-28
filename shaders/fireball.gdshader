shader_type spatial;
// The impact's fireball: a boiling ball of fire, white at the heart, dark smoke at the edge.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform float age = 0.0;    // 0..1 over its life
uniform sampler2D noise_tex : repeat_enable, filter_linear;

void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	vec2 uv = UV * vec2(3.0, 2.0) + vec2(TIME * 0.05, -TIME * 0.08);
	float n = texture(noise_tex, uv).r * 0.6 + texture(noise_tex, uv * 2.3 + 0.37).r * 0.4;
	float heat = clamp(f * 1.3 - age * 0.9 + n * 0.35, 0.0, 1.0);
	vec3 c = mix(vec3(0.5, 0.06, 0.0), vec3(1.0, 0.55, 0.12), smoothstep(0.2, 0.6, heat));
	c = mix(c, vec3(1.0, 0.95, 0.8), smoothstep(0.75, 1.0, heat));
	ALBEDO = c * (2.5 + 4.0 * (1.0 - age)) * smoothstep(0.0, 0.25, heat) * (1.0 - smoothstep(0.75, 1.0, age));
}
