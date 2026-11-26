shader_type spatial;
// A survivor being eaten on «الوحش»'s hook (scripts/feast.gd): the character's own maps, with nothing
// drawn under `cut_y` (world height) or, on the last stage, outside a ball round the head. The edge is
// ragged and wet red, and the inside of the body (its back faces, seen through the opening) is flesh.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool has_normal = false;
uniform bool has_mr = false;
uniform float normal_k = 1.0;
uniform float metal = 0.0;
uniform float rough = 1.0;
uniform float cut_y = -1000.0;
uniform vec3 head_c = vec3(0.0);
uniform float head_r = 100.0;
uniform float seed = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// torn, not sliced: the cut wanders up and down with two layers of noise round the body
	vec2 q = vec2(atan(wpos.x - head_c.x, wpos.z - head_c.z) * 2.2, wpos.y * 3.0) + seed;
	float rag = (noise(q * 2.0) - 0.5) * 0.07 + (noise(q * 7.0) - 0.5) * 0.025;
	float edge = wpos.y - (cut_y + rag);
	float ball = head_r - length(wpos - head_c) + rag * 0.6;
	float left = min(edge, ball);
	if (left < 0.0) discard;
	vec4 a = texture(albedo_tex, UV) * albedo_col;
	float wet = 1.0 - smoothstep(0.0, 0.07, left);
	// blood running down the outside from the edge, in streaks
	float run = smoothstep(0.55, 0.9, noise(vec2(q.x * 6.0, 0.0))) * (1.0 - smoothstep(0.0, 0.22, left));
	wet = max(wet, run * 0.85);
	vec3 blood = vec3(0.24, 0.012, 0.01);
	if (!FRONT_FACING) {
		// inside: raw, dark, glistening
		float m = noise(UV * 60.0 + seed);
		ALBEDO = mix(vec3(0.16, 0.01, 0.01), vec3(0.36, 0.05, 0.04), m);
		ROUGHNESS = 0.22;
		SPECULAR = 0.6;
	} else {
		ALBEDO = mix(a.rgb, blood, wet);
		float r = rough;
		float mt = metal;
		if (has_mr) {
			vec4 t = texture(mr_tex, UV);
			r *= t.g;
			mt *= t.b;
		}
		ROUGHNESS = mix(r, 0.18, wet);
		METALLIC = mix(mt, 0.0, wet);
		SPECULAR = mix(0.5, 0.65, wet);
		if (has_normal) {
			NORMAL_MAP = texture(normal_tex, UV).rgb;
			NORMAL_MAP_DEPTH = normal_k * (1.0 - wet * 0.7);
		}
	}
}
