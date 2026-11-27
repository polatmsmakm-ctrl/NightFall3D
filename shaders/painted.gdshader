shader_type canvas_item;
// The owner's painted backgrounds (the camp, the map cards), kept exactly as he made them, with only a
// few things moving: the fire (heat shimmer, flicker, glow, sparks, its reflection in the puddles), the
// moon (a slow breath of light and thin cloud drifting over it) and, where asked, trees and palms
// swaying. Everything is in the picture's own pixels (img_size), so the same numbers work at any size.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 img_size = vec2(1672.0, 941.0);
uniform float fire_on = 0.0;
uniform vec4 fire_rect = vec4(590.0, 490.0, 720.0, 650.0);   // the flames: x0, y0, x1, y1
uniform vec2 fire_base = vec2(655.0, 640.0);                // where the flames rise from
uniform float fire_glow_r = 300.0;
uniform vec4 refl_rect = vec4(610.0, 690.0, 790.0, 860.0);   // the fire in the puddles
uniform float moon_on = 0.0;
uniform vec2 moon_c = vec2(1030.0, 110.0);
uniform float moon_r = 62.0;
uniform vec4 sway0 = vec4(0.0);  // regions that sway (trees, palms): x0, y0, x1, y1
uniform vec4 sway1 = vec4(0.0);
uniform vec4 sway2 = vec4(0.0);
uniform vec4 sway3 = vec4(0.0);
uniform float sway_amp = 2.5;    // pixels at the top of a region
uniform vec2 lamp = vec2(-1.0);  // a small window light that flickers
uniform float lamp_r = 14.0;

float n2(vec2 p) { return texture(noise_tex, p).r; }

float box(vec2 p, vec4 r, float f) {
	return smoothstep(r.x, r.x + f, p.x) * (1.0 - smoothstep(r.z - f, r.z, p.x))
		* smoothstep(r.y, r.y + f, p.y) * (1.0 - smoothstep(r.w - f, r.w, p.y));
}

float sway(vec2 p, vec4 r, float seed) {
	if (r.z <= r.x) return 0.0;
	float m = box(p, r, 10.0);
	float k = clamp(1.0 - (p.y - r.y) / max(r.w - r.y, 1.0), 0.0, 1.0); // the tops move, the feet stay
	float w = sin(TIME * 1.05 + p.x * 0.012 + seed) + 0.45 * sin(TIME * 2.3 + p.y * 0.035 + seed * 2.0);
	return m * k * k * w * sway_amp;
}

void fragment() {
	vec2 p = UV * img_size;
	vec2 off = vec2(0.0);
	off.x += sway(p, sway0, 0.0) + sway(p, sway1, 1.7) + sway(p, sway2, 3.1) + sway(p, sway3, 4.6);
	float fm = 0.0;
	if (fire_on > 0.5) {
		// heat shimmer rising through the flames: the painted flames lick upward
		fm = box(p, fire_rect, 26.0);
		float up = clamp((fire_base.y - p.y) / max(fire_base.y - fire_rect.y, 1.0), 0.0, 1.0);
		vec2 q = p / vec2(70.0, 55.0) + vec2(0.0, TIME * 1.7);
		vec2 h = vec2(n2(q * 0.11) - 0.5, n2(q * 0.11 + vec2(0.37, 0.71)) - 0.5);
		off += h * vec2(7.0, 11.0) * fm * (0.25 + up);
	}
	vec4 c = texture(TEXTURE, UV - off / img_size);
	if (fire_on > 0.5) {
		float t = TIME;
		float flick = 0.86 + 0.16 * sin(t * 11.0) * sin(t * 3.7) + 0.08 * sin(t * 23.0 + 1.3) + 0.12 * (n2(vec2(t * 0.35, 0.5)) - 0.5);
		float hot = smoothstep(0.32, 0.8, c.r) * smoothstep(0.08, 0.45, c.r - c.b);   // only the flame's own colours
		c.rgb *= 1.0 + (flick - 1.0) * 1.6 * hot * fm;
		// the light it throws round itself, breathing with it
		float d = distance(p, fire_base + vec2(0.0, -40.0));
		float g = exp(-d / fire_glow_r * 2.2);
		c.rgb += vec3(1.0, 0.42, 0.1) * 0.07 * g * flick;
		// and in the wet ground in front of it
		float rm = box(p, refl_rect, 30.0);
		float wav = n2(vec2(p.x * 0.004, p.y * 0.02 - t * 0.25));
		c.rgb *= 1.0 + rm * hot * ((flick - 1.0) * 1.8 + (wav - 0.5) * 0.5);
		// sparks: a dozen embers drifting up out of the fire and fading
		for (int i = 0; i < 14; i++) {
			float fi = float(i);
			float life = 2.2 + 1.4 * fract(sin(fi * 12.9898) * 43758.5);
			float ph = fract(t / life + fi * 0.137);
			vec2 sp = fire_base + vec2(sin(fi * 7.3 + t * 0.9 + ph * 4.0) * (14.0 + 40.0 * ph) + (fract(sin(fi * 78.233) * 4375.0) - 0.5) * 60.0,
				-30.0 - ph * 300.0);
			float dd = distance(p, sp);
			c.rgb += vec3(1.0, 0.6, 0.2) * smoothstep(2.6, 0.0, dd) * (1.0 - ph) * 0.9;
		}
	}
	if (moon_on > 0.5) {
		float d = distance(p, moon_c);
		float breath = 0.85 + 0.15 * sin(TIME * 0.6);
		c.rgb += vec3(0.62, 0.68, 0.86) * 0.09 * breath * exp(-max(d - moon_r, 0.0) / (moon_r * 0.9)) * step(moon_r * 0.98, d);
		// thin cloud drifting across it, slowly
		float cl = n2(p / vec2(moon_r * 5.0, moon_r * 2.2) * 0.25 + vec2(TIME * 0.006, TIME * 0.0015));
		float near = 1.0 - smoothstep(moon_r * 0.6, moon_r * 2.6, d);
		c.rgb *= 1.0 - 0.28 * smoothstep(0.52, 0.78, cl) * near;
	}
	if (lamp.x >= 0.0) {
		float d = distance(p, lamp);
		float f = 0.8 + 0.3 * sin(TIME * 7.0) * sin(TIME * 2.9);
		c.rgb *= 1.0 + (f - 1.0) * (1.0 - smoothstep(lamp_r * 0.3, lamp_r, d));
	}
	COLOR = c;
}
