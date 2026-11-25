// Blood on the ground and on walls: the owner's Meshy puddle and smear, drawn as MultiMesh
// instances. Each instance carries its own state in INSTANCE_CUSTOM:
//   x  how far it has spread (0..1, the mesh grows out from its middle)
//   y  how dry it is (0 fresh and glossy, 1 dark, matte and flat)
//   z  how much of it is left (dithered away, so it stays an opaque draw)
//   w  a random seed (the slow liquid movement is out of step from one mark to the next)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform bool has_normal = false;
uniform vec3 fresh : source_color = vec3(0.42, 0.022, 0.028);
uniform vec3 dried : source_color = vec3(0.15, 0.036, 0.026);

varying vec4 cd;
varying vec3 wpos;

void vertex() {
	cd = INSTANCE_CUSTOM;
	VERTEX.xz *= cd.x;
	VERTEX.y *= mix(1.0, 0.3, cd.y); // a drying pool sinks flat
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	if (cd.z < 0.999 && hash(FRAGCOORD.xy) > cd.z) discard; // fading out
	vec4 t = texture(albedo_tex, UV);
	float dry = cd.y;
	// the bake's own light and dark stay as variation; the colour is taken down to blood, not paint
	float shade = clamp(0.45 + t.r * 1.15, 0.35, 1.45);
	float n1 = hash(floor(wpos.xz * 9.0) + cd.w * 31.0);
	vec3 col = mix(fresh, dried, smoothstep(0.0, 1.0, dry)) * shade * (0.9 + 0.2 * n1);
	// the thin edge dries first and goes brown-black
	col = mix(col, dried * 0.7, dry * (1.0 - clamp(t.r * 1.4, 0.0, 1.0)) * 0.5);
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = mix(0.75, 0.35, dry);
	ROUGHNESS = mix(0.035 + 0.05 * n1, 0.62, dry);
	// a fresh pool is still liquid: its surface moves a little
	vec3 nm = has_normal ? texture(normal_tex, UV).xyz : vec3(0.5, 0.5, 1.0);
	float wob = (1.0 - dry) * 0.05;
	nm.xy += vec2(sin(wpos.x * 21.0 + TIME * 1.2 + cd.w * 40.0), cos(wpos.z * 17.0 + TIME * 0.9 + cd.w * 25.0)) * wob;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(1.4, 0.6, dry);
}
