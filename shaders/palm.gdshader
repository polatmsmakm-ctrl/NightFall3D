shader_type spatial;
render_mode cull_disabled;
// Date-palm fronds: a curved ribbon cut into feathery leaflets, lit on both sides.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 0.9 + wp.x * 0.1 + wp.z * 0.13) * 0.012 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	float edge = abs(UV.x - 0.5) * 2.0; // 0 on the spine, 1 at the leaflet tips
	float stripe = fract((UV.y + edge * 0.12) * 30.0);
	if (edge > 0.1 && stripe > 0.66 - edge * 0.22) discard;
	if (!FRONT_FACING) NORMAL = -NORMAL;
	float n = texture(noise_tex, UV * vec2(2.0, 5.0)).r;
	ALBEDO = mix(vec3(0.06, 0.11, 0.04), vec3(0.2, 0.28, 0.1), n) * (1.0 - edge * 0.25);
	ROUGHNESS = 0.8;
}
