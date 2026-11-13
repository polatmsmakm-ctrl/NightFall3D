shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform vec3 base_col : source_color = vec3(0.02, 0.045, 0.02);
uniform vec3 tip_col : source_color = vec3(0.09, 0.14, 0.06);

void vertex() {
	float k = UV.y * UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.27) + 0.5 * sin(TIME * 3.1 + wp.x * 0.9);
	VERTEX.x += w * 0.08 * k;
	VERTEX.z += w * 0.05 * k;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(base_col, tip_col, UV.y);
	ROUGHNESS = 0.9;
}
