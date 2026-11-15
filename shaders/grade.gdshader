shader_type canvas_item;
// The grade over the finished frame: a dark vignette that squeezes the edges of the screen and
// a little film grain, and the edges go red as the killer closes in. It is a *darkening overlay*
// on purpose — it never reads the screen back, so there is no backbuffer copy and it stays cheap
// on a phone. Drawn under the HUD (main._build_grade).
uniform float vignette : hint_range(0.0, 1.0) = 0.8;
uniform float grain : hint_range(0.0, 0.2) = 0.055;
uniform float pulse = 0.0; // 0..1, pushed up while he is near, or while you are down

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.0, 0.72)); // the screen is wide: keep the vignette round
	float v = smoothstep(0.30, 0.80, r);
	float a = v * vignette * (1.0 + 0.35 * pulse);
	float g = hash(UV * vec2(1920.0, 1080.0) + fract(TIME) * 37.0);
	a += g * grain * (0.35 + 0.65 * v); // grain, heavier out at the edges
	// the red lives in the corners only: at the middle of the screen the tint stays black,
	// so a close killer squeezes the frame instead of washing the whole picture red
	vec3 tint = vec3(0.30, 0.012, 0.008) * clamp(pulse, 0.0, 1.0) * v;
	COLOR = vec4(tint, clamp(a, 0.0, 0.88));
}
