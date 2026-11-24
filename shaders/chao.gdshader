// Chão de lajes de pedra desenhadas a tinta, com aquarela e luz da tocha.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/comum.gdshaderinc"
uniform float cel = 1.5;
varying vec3 w;
varying vec3 n_mundo;
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	vec2 v = voronoi(w.xz * 1.25);
	vec3 pedra = mix(vec3(0.72, 0.66, 0.56), COLOR.rgb * 1.5, 0.35);
	pedra *= 0.86 + v.y * 0.22;
	vec3 c = aquarela(pedra, w.xz, 0.6, 0.25);
	c *= 0.78 + 0.3 * smoothstep(0.0, 0.32, v.x);               // relevo: laje abaulada
	float rejunte = 1.0 - smoothstep(0.02, 0.07, v.x);
	c = mix(c, vec3(0.22, 0.17, 0.12), rejunte * 0.85);
	vec2 g = abs(fract(w.xz / cel + 0.5) - 0.5) * cel;
	float largura_grade = 0.02 + grade_forca * 0.05;
	c = mix(c, vec3(0.12, 0.08, 0.05), (1.0 - smoothstep(0.0, largura_grade, min(g.x, g.y))) * min(grade_forca * 1.4, 0.95));
	ALBEDO = tocha(c, w, FRAGCOORD.xy);
}
