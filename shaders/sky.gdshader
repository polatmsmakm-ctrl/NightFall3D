shader_type sky;
// Night sky: big moon with surface detail, twinkling stars, drifting clouds.
uniform vec3 moon_dir = vec3(0.3, 0.32, -0.9);
uniform float blood : hint_range(0.0, 1.0) = 0.0; // 1 = blood moon (gates open)
uniform float near : hint_range(0.0, 1.0) = 0.0; // 0..1: the moon falling toward the ground
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// the owner's moon: its near side seen face on (assets/sky/moon.jpg, rendered from his moon.glb)
uniform sampler2D moon_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float has_moon_tex = 0.0;
// the owner's night sky photograph (the Milky Way, assets/sky/milkyway.jpg): it replaces the drawn
// stars. Wrapped round the sky twice (mirrored, so there is no seam), the horizon at its bottom edge.
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float has_night_tex = 0.0;
uniform float day : hint_range(0.0, 1.0) = 0.0;  // 0 night, 1 daylight (the start screen only)
uniform float warm : hint_range(0.0, 1.0) = 0.0; // dawn / dusk colour
uniform float sun : hint_range(0.0, 1.0) = 0.0;  // 1 = daylight sandstorm: the disc is the sun
uniform float sun_disc : hint_range(0.0, 1.0) = 0.0; // «بين العصر والمغرب»: the disc is the sun in a clear sky

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
	float nightly = (1.0 - day) * (1.0 - sun) * (1.0 - 0.6 * warm);
	if (has_night_tex > 0.5) {
		float az = atan(d.x, d.z) / 6.2831853 + 0.5;
		float u = 1.0 - abs(1.0 - 2.0 * fract(az)); // 0 -> 1 -> 0 round the sky: mirrored, no seam
		float el = asin(clamp(d.y, 0.0, 1.0)) / 1.5707963;
		vec3 photo = texture(night_tex, vec2(u, 0.97 - el * 0.92)).rgb;
		col = mix(col, photo * 0.9, nightly * smoothstep(-0.04, 0.18, d.y));
	} else {
		vec3 cell = floor(d * 220.0);
		float s = hash(cell);
		float star = step(0.9975, s) * smoothstep(0.0, 0.15, d.y);
		col += vec3(star * (0.6 + 0.4 * sin(TIME * 2.0 + s * 100.0)) * nightly);
	}
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
	float sd = max(sun, sun_disc);
	float face = mix(0.55 + 0.6 * crater, 1.35, sd) * mix(0.5 + 0.5 * limb, 1.0, sd);
	vec3 suncol = mix(vec3(1.0, 0.95, 0.78), vec3(1.0, 0.55, 0.25), warm * sun_disc) * (1.0 + 1.5 * sun_disc);
	vec3 mooncol = mix(mix(vec3(0.95, 0.93, 0.85), suncol, sd), vec3(0.8, 0.11, 0.06), blood) * face;
	if (has_moon_tex > 0.5 && sd < 0.5) {
		// the real surface: maria, craters and rays; tinted red under the blood moon
		vec3 surf = texture(moon_tex, vec2(muv.x, -muv.y) * 0.5 + 0.5).rgb;
		float lum = dot(surf, vec3(0.3, 0.55, 0.15));
		vec3 red = vec3(1.0, 0.16, 0.08) * (0.35 + 1.2 * lum);
		mooncol = mix(surf * 1.25, red, blood) * (0.8 + 0.2 * limb);
	}
	vec3 halo = mix(mix(vec3(0.5, 0.6, 0.8), mix(vec3(1.0, 0.82, 0.45), vec3(1.0, 0.45, 0.18), warm * sun_disc), sd), vec3(0.95, 0.12, 0.06), blood);
	col += halo * (exp(-ang * 9.0 / (1.0 + 4.0 * near)) * (0.35 + 0.5 * near + 0.75 * sd) + exp(-ang * 40.0 / (1.0 + 4.0 * near)) * (0.4 + 0.6 * sd));
	col = mix(col, mooncol * 1.6, disc);
	if (d.y > 0.0) {
		vec2 cuv = d.xz / (d.y + 0.15) * 0.25 + TIME * vec2(0.004, 0.0015);
		float n = texture(noise_tex, cuv).r * 0.6 + texture(noise_tex, cuv * 2.7 + TIME * 0.003).r * 0.4;
		float cl = smoothstep(0.5, 0.8, n) * smoothstep(0.0, 0.2, d.y);
		vec3 ccol = mix(vec3(0.05, 0.06, 0.09), vec3(0.08, 0.03, 0.03), blood) + mix(vec3(0.35, 0.4, 0.5), vec3(0.6, 0.1, 0.06), blood) * exp(-ang * 3.0);
		float cover = 0.85;
		if (has_night_tex > 0.5) {
			// over the photograph: thinner, wispier veils, moonlit blue-grey, lit on their edges near
			// the moon, so the Milky Way still shows through them
			cl = smoothstep(0.56, 0.86, n) * smoothstep(0.0, 0.25, d.y);
			ccol = mix(vec3(0.07, 0.085, 0.13), vec3(0.09, 0.03, 0.03), blood) + mix(vec3(0.45, 0.5, 0.62), vec3(0.6, 0.1, 0.06), blood) * exp(-ang * 2.4) * (0.6 + 0.6 * smoothstep(0.6, 0.86, n));
			cover = mix(0.62, 0.85, day);
		}
		// in daylight the clouds are white, and gold to red as the sun goes down
		vec3 dayc = mix(vec3(0.9, 0.91, 0.95), vec3(1.0, 0.56, 0.36) * (0.7 + 0.6 * exp(-ang * 2.0)), warm);
		ccol = mix(ccol, dayc, max(day, warm * 0.85) * (1.0 - blood));
		ccol = mix(ccol, mix(vec3(0.72, 0.56, 0.36), vec3(0.42, 0.14, 0.08), blood), sun); // sheets of sand, not cloud
		col = mix(col, ccol, cl * mix(cover, 0.95, sun));
	}
	COLOR = col;
}
