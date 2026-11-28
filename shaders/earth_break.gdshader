shader_type spatial;
// His Blue Marble, with what the ending does to it: the surface burning round the meteor's impact,
// a shockwave running over it, glowing cracks spreading from it, and the planet in pieces — each piece
// draws only its own Voronoi cell of the sphere (`piece`), and the inside of the shell shows as molten
// rock. Directions are in the model's own space (its middle at the origin).
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : filter_linear_mipmap;
uniform vec3 seeds[12];
uniform int piece = -1;          // -1: the whole planet
uniform vec3 hit_dir = vec3(0.0, 0.0, 1.0);
uniform float burn = 0.0;        // 0..1: the fire round the impact
uniform float shock = -1.0;      // 0..1: how far the shockwave has run (as a fraction of half the globe)
uniform float crack = 0.0;       // 0..1: how far the cracks have spread
uniform float melt = 0.0;        // 0..1: the inside glows

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void fragment() {
	vec3 d = normalize(opos);
	float b1 = -2.0; float b2 = -2.0; int i1 = 0;
	for (int i = 0; i < 12; i++) {
		float v = dot(d, seeds[i]);
		if (v > b1) { b2 = b1; b1 = v; i1 = i; } else if (v > b2) { b2 = v; }
	}
	if (piece >= 0 && i1 != piece) discard;
	float from_hit = acos(clamp(dot(d, normalize(hit_dir)), -1.0, 1.0)) / 3.14159; // 0 at the impact, 1 opposite
	// a wobble so the crack lines are not ruler-straight
	float wob = (hash(floor(d * 40.0)) - 0.5) * 0.012;
	float edge = b1 - b2 + wob;
	float reach = smoothstep(crack * 1.05, crack * 1.05 - 0.12, from_hit);
	float line = (1.0 - smoothstep(0.0, 0.03, edge)) * reach;
	float fine = (1.0 - smoothstep(0.0, 0.012, abs(fract(dot(d, vec3(7.1, 3.3, 5.7)) + wob * 30.0) - 0.5) * 0.2)) * reach * 0.0;
	float fire = burn * smoothstep(0.2 * burn + 0.02, 0.0, from_hit);
	float ring = shock >= 0.0 ? exp(-pow((from_hit - shock) / 0.025, 2.0)) * (1.0 - shock) : 0.0;
	vec3 lava = vec3(1.0, 0.38, 0.06);
	if (!FRONT_FACING) { // the planet's inside: molten
		ALBEDO = vec3(0.08, 0.02, 0.0);
		ROUGHNESS = 1.0;
		EMISSION = lava * (1.5 + 3.0 * melt) * (0.7 + 0.3 * hash(floor(d * 60.0)));
	} else {
		vec3 alb = texture(albedo_tex, UV).rgb;
		ALBEDO = mix(alb, vec3(0.05, 0.02, 0.01), clamp(fire * 1.2 + line, 0.0, 1.0));
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		ROUGHNESS = mix(0.55, 0.95, texture(mr_tex, UV).g);
		METALLIC = 0.0;
		SPECULAR = 0.35;
		EMISSION = lava * (line * 9.0 + fire * 3.5 * (0.6 + 0.4 * hash(floor(d * 80.0))) + fine) + vec3(1.0, 0.85, 0.6) * ring * 7.0;
	}
}
