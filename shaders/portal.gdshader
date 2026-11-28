shader_type spatial;
// «The Moon»'s gates: a vortex of light in the crystal arch, a tunnel turning in on itself. Shut: a
// slow dim swirl you cannot pass; open (power 1): bright and racing — step in and it takes you
// through to the rocket.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 col_a : source_color = vec4(0.25, 0.5, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.7, 0.3, 1.0, 1.0);
uniform float arch = 0.29; // how much of the height the round top takes
uniform float aspect = 1.71; // height / width

void fragment() {
	vec2 q = UV;
	vec2 dtop = vec2(q.x - 0.5, (q.y - arch) * aspect);
	float inside = q.y > arch ? smoothstep(0.0, 0.04, min(q.x, 1.0 - q.x)) : smoothstep(0.5, 0.46, length(dtop));
	inside *= smoothstep(1.0, 0.97, q.y);
	vec2 p = vec2(q.x - 0.5, (q.y - 0.52) * aspect * 0.62);
	float r = length(p) + 1e-4;
	float a = atan(p.y, p.x);
	float speed = mix(0.35, 2.6, power);
	float t = TIME * speed;
	float swirl = sin(a * 4.0 + 3.2 / r - t * 3.0) * 0.5 + 0.5;
	float swirl2 = sin(-a * 7.0 + 5.0 / (r + 0.1) - t * 4.3) * 0.5 + 0.5;
	float rings = sin(9.0 / (r + 0.06) - t * 5.0) * 0.5 + 0.5;
	float core = exp(-r * mix(7.0, 4.0, power));
	vec3 col = mix(col_a.rgb, col_b.rgb, swirl);
	float lum = (0.18 + 0.6 * swirl * swirl2 + 0.35 * rings * swirl) * (0.35 + 0.65 * smoothstep(0.55, 0.05, r));
	vec3 o = col * lum * mix(0.45, 0.95, power) + vec3(0.7, 0.85, 1.0) * core * mix(0.35, 0.8, power);
	o += vec3(0.9, 0.95, 1.0) * flash * 2.0;
	float edge = q.y > arch ? smoothstep(0.08, 0.0, min(q.x, 1.0 - q.x)) : smoothstep(0.42, 0.5, length(dtop));
	o += col_a.rgb * edge * mix(0.4, 0.9, power);
	ALBEDO = o * inside;
}
