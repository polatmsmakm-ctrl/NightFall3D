shader_type sky;
// Night sky: big moon with surface detail, twinkling stars, drifting clouds.
uniform vec3 moon_dir = vec3(0.3, 0.32, -0.9);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(vec3(0.035, 0.05, 0.09), vec3(0.004, 0.008, 0.02), pow(h, 0.5));
	vec3 cell = floor(d * 220.0);
	float s = hash(cell);
	float star = step(0.9975, s) * smoothstep(0.0, 0.15, d.y);
	col += vec3(star * (0.6 + 0.4 * sin(TIME * 2.0 + s * 100.0)));
	vec3 md = normalize(moon_dir);
	float ang = acos(clamp(dot(d, md), -1.0, 1.0));
	float r = 0.055;
	float disc = smoothstep(r, r * 0.96, ang);
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 muv = vec2(dot(d, right), dot(d, up)) / r;
	float crater = texture(noise_tex, muv * 0.35 + 0.5).r;
	float limb = sqrt(max(0.0, 1.0 - dot(muv, muv)));
	vec3 mooncol = vec3(0.95, 0.93, 0.85) * (0.55 + 0.6 * crater) * (0.5 + 0.5 * limb);
	col += vec3(0.5, 0.6, 0.8) * (exp(-ang * 9.0) * 0.35 + exp(-ang * 40.0) * 0.4);
	col = mix(col, mooncol * 1.6, disc);
	if (d.y > 0.0) {
		vec2 cuv = d.xz / (d.y + 0.15) * 0.25 + TIME * vec2(0.004, 0.0015);
		float n = texture(noise_tex, cuv).r * 0.6 + texture(noise_tex, cuv * 2.7 + TIME * 0.003).r * 0.4;
		float cl = smoothstep(0.5, 0.8, n) * smoothstep(0.0, 0.2, d.y);
		vec3 ccol = vec3(0.05, 0.06, 0.09) + vec3(0.35, 0.4, 0.5) * exp(-ang * 3.0);
		col = mix(col, ccol, cl * 0.85);
	}
	COLOR = col;
}
