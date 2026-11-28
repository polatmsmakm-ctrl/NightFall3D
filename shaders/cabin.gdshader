// The rocket's cabin, seen from inside: a grey shell with portholes (part 0, the wall, along z) or the
// front bulkhead with its wide window (part 1). The holes are cut out so space shows through them.
shader_type spatial;
render_mode cull_disabled;
uniform int part = 0;
uniform vec4 col : source_color = vec4(0.72, 0.74, 0.78, 1.0);
uniform vec4 trim : source_color = vec4(0.16, 0.17, 0.2, 1.0);
uniform float radius = 1.55;
uniform float row0 = -2.4;
uniform float pitch = 1.6;
uniform float rows = 4.0;
uniform float win_y = 0.18;      // the portholes' height (in the cabin's cross-section)
uniform float win_r = 0.3;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = col.rgb;
	float rough = 0.55;
	if (part == 0) {
		float a = atan(lp.y, lp.x);                 // round the cabin
		float ac = asin(clamp(win_y / radius, -1.0, 1.0));
		float best = 9.0;
		for (int k = 0; k < 8; k++) {
			float zc = row0 + pitch * float(k / 2);
			if (float(k / 2) >= rows) break;
			float side = (k % 2 == 0) ? ac : (3.14159265 - ac);
			float da = a - side;
			da = mod(da + 3.14159265, 6.2831853) - 3.14159265;
			vec2 q = vec2(da * radius, lp.z - zc);
			best = min(best, length(q));
		}
		if (best < win_r) discard;
		if (best < win_r * 1.28) { c = trim.rgb; rough = 0.3; }
		// panel seams every 0.8 m and a darker band low down
		float seam = smoothstep(0.012, 0.0, abs(fract(lp.z / 0.8) - 0.5) - 0.488);
		c *= 1.0 - 0.25 * seam;
		if (lp.y < -0.55) c *= 0.62;
	} else if (part == 1) {
		vec2 q = abs(lp.xy - vec2(0.0, 0.32)) - vec2(0.95, 0.38);
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.12;
		if (d < 0.0) discard;
		if (d < 0.07) { c = trim.rgb; rough = 0.3; }
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = 0.25;
}
