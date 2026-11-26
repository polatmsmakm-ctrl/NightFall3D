// The sea (Kuwait City's Gulf, the beach's lagoon): rolling Gerstner swells moving the surface, two
// scrolling ripple maps over them, the sky and the moon reflected more at a glancing angle (Fresnel),
// shallow water lighter and greener than the deep, foam where the water meets the shore and on the
// tops of the bigger waves. NightWorld.wave_y() follows the same swells, so boats ride them.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_col : source_color = vec4(0.012, 0.045, 0.08, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.03, 0.16, 0.18, 1.0);
uniform vec4 foam_col : source_color = vec4(0.78, 0.84, 0.86, 1.0);
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform float amp = 1.0;              // 1 the open sea, ~0.35 a lagoon
uniform vec2 shore_dir = vec2(1.0, 0.0); // pointing out to sea
uniform float shore_d = 62.0;         // the water line, along shore_dir
uniform float shallow_w = 26.0;       // how far out the water stays light
uniform float alpha_far = 0.94;

varying vec3 wpos;
varying float crest;

// (direction, wavelength m, amplitude m, steepness) — the same four swells as NightWorld.WAVES
const vec4 W0 = vec4(-0.94, 0.34, 21.0, 0.32);
const vec4 W1 = vec4(-0.62, -0.78, 13.0, 0.2);
const vec4 W2 = vec4(-0.99, -0.12, 7.5, 0.11);
const vec4 W3 = vec4(-0.4, 0.92, 4.2, 0.06);
const float STEEP = 0.55;

vec3 gerstner(vec4 w, vec2 p, float t, inout vec3 tang, inout vec3 bin) {
	vec2 d = normalize(w.xy);
	float k = 6.28318 / w.z;
	float c = sqrt(9.8 / k);
	float a = w.w * amp;
	float q = STEEP / (k * a * 4.0 + 0.001);
	q = min(q, 1.0);
	float f = k * (dot(d, p) - c * t);
	float wa = k * a;
	tang += vec3(-q * d.x * d.x * wa * sin(f), d.x * wa * cos(f), -q * d.x * d.y * wa * sin(f));
	bin += vec3(-q * d.x * d.y * wa * sin(f), d.y * wa * cos(f), -q * d.y * d.y * wa * sin(f));
	return vec3(q * a * d.x * cos(f), a * sin(f), q * a * d.y * cos(f));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = w.xz;
	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	// calmer right at the shore: the swell rises out of the shallows
	float out_d = dot(p, shore_dir) - shore_d;
	float calm = smoothstep(-2.0, 18.0, out_d);
	vec3 off = vec3(0.0);
	off += gerstner(W0, p, TIME, tang, bin);
	off += gerstner(W1, p, TIME, tang, bin);
	off += gerstner(W2, p, TIME, tang, bin);
	off += gerstner(W3, p, TIME, tang, bin);
	off *= mix(0.25, 1.0, calm);
	crest = off.y / max(amp * 0.7, 0.01);
	VERTEX += off; // (the sea plane is never turned or scaled: world and local axes agree)
	NORMAL = normalize(cross(bin, tang));
	wpos = w + off;
}

void fragment() {
	vec2 p = wpos.xz;
	// two ripple maps crossing at their own speeds
	vec3 na = texture(ripple_a, p * 0.045 + vec2(TIME * 0.018, TIME * 0.011)).xyz;
	vec3 nb = texture(ripple_b, p * 0.11 - vec2(TIME * 0.026, -TIME * 0.02)).xyz;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.9;
	float out_d = dot(p, shore_dir) - shore_d;
	float shallow = 1.0 - smoothstep(0.0, shallow_w, out_d);
	// the sky is in the water more the flatter you look across it
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 body = mix(deep_col.rgb, shallow_col.rgb, shallow * 0.85);
	body *= 1.0 + clamp(crest, 0.0, 1.0) * 0.35; // a little light through the wave tops
	// foam: a broken band where the waves reach the sand, and streaks on the biggest crests
	float ft = texture(foam_tex, p * 0.18 + vec2(TIME * 0.02, 0.0)).r;
	float ft2 = texture(foam_tex, p * 0.07 - vec2(0.0, TIME * 0.015)).r;
	float edge = 1.0 - smoothstep(0.0, 3.5 + 1.5 * sin(TIME * 0.7 + p.y * 0.12), out_d);
	float foam = clamp(edge * smoothstep(0.35, 0.75, ft * 0.6 + ft2 * 0.6), 0.0, 1.0);
	foam = max(foam, smoothstep(0.62, 0.95, crest) * smoothstep(0.45, 0.8, ft) * 0.8);
	ALBEDO = mix(body, foam_col.rgb, foam);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.2, foam);
	ALPHA = mix(mix(alpha_far, 0.72, shallow * (1.0 - foam)), 1.0, foam);
	ALBEDO *= mix(1.0, 0.55, fres * (1.0 - foam)); // a glancing view shows the reflection, not the water
}
