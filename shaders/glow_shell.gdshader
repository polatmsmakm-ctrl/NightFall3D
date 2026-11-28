shader_type spatial;
// A soft halo round a sphere seen from outside: the Earth's blue air, or the fire round a meteor
// entering it. Additive, drawn on a slightly bigger sphere; strongest at the rim.
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform float power = 1.0;
uniform float rim = 3.0;
uniform vec3 hot_dir = vec3(0.0, 0.0, 1.0); // in view of the hot side (the meteor's front) it burns brighter
uniform float hot = 0.0;

void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	float a = pow(f, rim);
	float h = hot * smoothstep(0.0, 1.0, dot(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), normalize(hot_dir)));
	ALBEDO = col.rgb * (a + h * 0.8) * power;
}
