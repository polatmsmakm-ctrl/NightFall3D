shader_type spatial;
// A blast ring on a flat quad: a hot bright band at `rad` (0..1 of the quad's half size) with a soft
// haze inside it, drawn additive and unshaded. The defeat film's shockwaves (scripts/ending.gd).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float rad = 0.2;
uniform float width = 0.03;
uniform float alpha = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float n = texture(noise_tex, vec2(a / 6.2831853 * 3.0, r * 1.5 - TIME * 0.2)).r;
	float w = width * (0.7 + 0.8 * n);
	float band = exp(-pow((r - rad) / w, 2.0));
	float haze = smoothstep(rad, rad * 0.2, r) * 0.18 * (0.6 + 0.8 * n);
	float edge = smoothstep(1.0, 0.92, r);
	vec3 c = mix(col.rgb, hot.rgb, band * band) * (band * 2.2 + haze);
	ALBEDO = c * alpha * edge;
}
