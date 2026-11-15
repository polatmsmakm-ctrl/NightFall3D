shader_type sky;
// Night sky: big moon with surface detail, twinkling stars, drifting clouds.
uniform vec3 moon_dir = vec3(0.3, 0.32, -0.9);
uniform float blood : hint_range(0.0, 1.0) = 0.0; // 1 = blood moon (gates open)
uniform float near : hint_range(0.0, 1.0) = 0.0; // 0..1: the moon falling toward the ground
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float day : hint_range(0.0, 1.0) = 0.0;  // 0 night, 1 daylight (the start screen only)
uniform float warm : hint_range(0.0, 1.0) = 0.0; // dawn / dusk colour
uniform float sun : hint_range(0.0, 1.0) = 0.0;  // 1 = daylight sandstorm: the disc is the sun

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(vec3(0.035, 0.05, 0.09), vec3(0.004, 0.008, 0.02), pow(h, 0.5));
	vec3 lit = mix(vec3(0.62, 0.76, 0.96), vec3(0.17, 0.37, 0.76), pow(h, 0.6));
	vec3 glow = mix(vec3(0.98, 0.52, 0.26), vec3(0.22, 0.26, 0.5), pow(h, 0.5));
	col = mix(col, lit, day);
	col = mix(col, glow, warm * (1.0 - 0.4 * day));
	// the Empty Quarter at noon: no blue left, the whole sky is the dust in the air
	vec3 storm = mix(vec3(0.88, 0.68, 0.42), vec3(0.58, 0.46, 0.33), pow(h, 0.45));
	col = mix(col, storm, sun);
	vec3 cell = floor(d * 220.0);
	float s = hash(cell);
	float star = step(0.9975, s) * smoothstep(0.0, 0.15, d.y);
	col += vec3(star * (0.6 + 0.4 * sin(TIME * 2.0 + s * 100.0)) * (1.0 - day) * (1.0 - sun) * (1.0 - 0.6 * warm));
	vec3 md = normalize(moon_dir);
	float ang = acos(clamp(dot(d, md), -1.0, 1.0));
	float r = 0.055 * (1.0 + 2.0 * near + 9.0 * near * near * near);
	float disc = smoothstep(r, r * 0.96, ang);
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 muv = vec2(dot(d, right), dot(d, up)) / r;
	float crater = texture(noise_tex, muv * (0.35 + 0.5 * near) + 0.5).r;
	float limb = sqrt(max(0.0, 1.0 - dot(muv, muv)));
	col = mix(col, col * vec3(1.5, 0.45, 0.4) + vec3(0.025, 0.0, 0.0) * (1.0 - h), blood);
	// the sun has no craters and no shaded limb: it is a flat white disc behind the dust
	float face = mix(0.55 + 0.6 * crater, 1.35, sun) * mix(0.5 + 0.5 * limb, 1.0, sun);
	vec3 mooncol = mix(mix(vec3(0.95, 0.93, 0.85), vec3(1.0, 0.95, 0.78), sun), vec3(0.8, 0.11, 0.06), blood) * face;
	vec3 halo = mix(mix(vec3(0.5, 0.6, 0.8), vec3(1.0, 0.82, 0.45), sun), vec3(0.95, 0.12, 0.06), blood);
	col += halo * (exp(-ang * 9.0 / (1.0 + 4.0 * near)) * (0.35 + 0.5 * near + 0.75 * sun) + exp(-ang * 40.0 / (1.0 + 4.0 * near)) * (0.4 + 0.6 * sun));
	col = mix(col, mooncol * 1.6, disc);
	if (d.y > 0.0) {
		vec2 cuv = d.xz / (d.y + 0.15) * 0.25 + TIME * vec2(0.004, 0.0015);
		float n = texture(noise_tex, cuv).r * 0.6 + texture(noise_tex, cuv * 2.7 + TIME * 0.003).r * 0.4;
		float cl = smoothstep(0.5, 0.8, n) * smoothstep(0.0, 0.2, d.y);
		vec3 ccol = mix(vec3(0.05, 0.06, 0.09), vec3(0.08, 0.03, 0.03), blood) + mix(vec3(0.35, 0.4, 0.5), vec3(0.6, 0.1, 0.06), blood) * exp(-ang * 3.0);
		ccol = mix(ccol, mix(vec3(0.72, 0.56, 0.36), vec3(0.42, 0.14, 0.08), blood), sun); // sheets of sand, not cloud
		col = mix(col, ccol, cl * mix(0.85, 0.95, sun));
	}
	COLOR = col;
}
