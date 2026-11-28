shader_type spatial;
// «The Moon»'s ground: his lunar dust at two scales and two angles (no tiling shows), a slow macro
// mottling of darker and lighter regolith, fine grains, and his dust's normal map turned into a
// world-space bump (the terrain has no UVs or tangents). Vertex colour: crater floors, rims, shade.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D dust : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dust_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.28;
uniform float tint = 1.0;
uniform float bump = 0.6;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wp.xz * tile;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 uv2 = rot * (wp.xz * tile * 0.31) + vec2(0.37, 0.61);
	vec2 uv3 = rot * rot * (wp.xz * tile * 3.1);
	vec3 a = texture(dust, uv).rgb;
	vec3 b = texture(dust, uv2).rgb;
	vec3 c = texture(dust, uv3).rgb;
	float m = texture(macro, wp.xz * 0.0045).r;
	float m2 = texture(macro, wp.xz * 0.021 + 0.5).r;
	float m3 = texture(macro, wp.xz * 0.11 + 0.2).r;
	vec3 col = (a * 0.45 + b * 0.35 + c * 0.2) * 1.15;
	float lum = dot(col, vec3(0.33));
	col = mix(vec3(lum), col, 0.35);                         // regolith is nearly colourless
	col *= (0.7 + 0.55 * m) * (0.86 + 0.28 * m2) * (0.92 + 0.16 * m3);
	col *= mix(vec3(1.0), vec3(1.015, 1.0, 0.98), m2);     // the faintest warm / cool drift
	ALBEDO = col * COLOR.rgb * tint;
	vec2 n1 = texture(dust_n, uv).rg * 2.0 - 1.0;
	vec2 n2 = texture(dust_n, uv2).rg * 2.0 - 1.0;
	vec2 n3 = texture(dust_n, uv3).rg * 2.0 - 1.0;
	vec2 nn = (n1 * 0.45 + n2 * 0.7 + n3 * 0.15) * bump;
	vec3 N = normalize(wn + vec3(nn.x, 0.0, nn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
}
