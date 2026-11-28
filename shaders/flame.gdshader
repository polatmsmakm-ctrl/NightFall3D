shader_type spatial;
// A rocket's exhaust: a cone of light, white-hot at the nozzle, fading out along its length, flickering.
// Drawn additive and unshaded, both sides. UV.y runs from the nozzle (0) to the tip (1) on a CylinderMesh
// whose wide end is the nozzle.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform vec4 tail : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform float power = 1.0;     // 0 off .. 1 full .. 2 boost
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float t = UV.y; // 0 at the nozzle, 1 at the tip
	float fl = 0.82 + 0.18 * sin(TIME * 41.0 + seed * 7.0) * sin(TIME * 23.0 + seed);
	float ring = sin(t * 34.0 - TIME * 70.0) * 0.5 + 0.5; // shock diamonds running down it
	vec3 c = mix(core.rgb * 2.4, tail.rgb, smoothstep(0.0, 0.55, t));
	float edge = 0.35 + 0.65 * pow(abs(dot(NORMAL, VIEW)), 2.0); // brighter where it faces you: soft edges
	float a = (1.0 - t) * (1.0 - t) * edge * fl * (0.75 + 0.25 * ring * (1.0 - t));
	ALBEDO = c * a * clamp(power, 0.0, 2.5) * 1.25;
}
