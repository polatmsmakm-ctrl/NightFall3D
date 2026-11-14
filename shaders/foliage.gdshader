shader_type spatial;
render_mode cull_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);  // snow / halloween themes recolour the leaves

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 0.9 + wp.x * 0.1 + wp.z * 0.13) * 0.012 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	float n = texture(noise_tex, UV * vec2(6.0, 2.0)).r;
	ALBEDO = mix(vec3(0.025, 0.055, 0.035), vec3(0.09, 0.15, 0.07), n) * tint;
	ROUGHNESS = 0.85;
}
