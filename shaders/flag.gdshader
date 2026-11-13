shader_type spatial;
render_mode cull_disabled;
// Kuwait flag: green / white / red bands with a black trapezoid at the hoist; waves in the wind.

void vertex() {
	float k = UV.x; // 0 at the pole, 1 at the free end
	float wave = sin(UV.x * 7.0 - TIME * 5.0 + UV.y * 1.5);
	VERTEX.z += wave * 0.24 * k + sin(UV.x * 13.0 - TIME * 8.0) * 0.07 * k;
	VERTEX.y += sin(UV.x * 5.0 - TIME * 4.0) * 0.06 * k - k * k * 0.18;
	NORMAL = normalize(vec3(-cos(UV.x * 7.0 - TIME * 5.0 + UV.y * 1.5) * 0.7 * k, 0.0, 1.0));
}

void fragment() {
	vec3 col = UV.y < 0.3333 ? vec3(0.0, 0.45, 0.22) : (UV.y < 0.6667 ? vec3(0.93) : vec3(0.78, 0.06, 0.13));
	float t = UV.x / 0.25;
	if (UV.x < 0.25 && UV.y > mix(0.0, 0.3333, t) && UV.y < mix(1.0, 0.6667, t)) col = vec3(0.015);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = col * 0.2; // stays readable at night
}
