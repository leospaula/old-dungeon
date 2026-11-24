// Chão com luz de verdade: laje pintada + relevo (normal map) projetados de cima, tingidos pela
// cor do tipo de área (vertex color), e a grade de combate por cima. Iluminado pelas luzes do Godot.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/nevoa.gdshaderinc"
uniform sampler2D cor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float escala = 3.0;           // metros por repetição da textura
uniform float cel = 1.5;              // tamanho da célula da grade
uniform float grade_forca = 0.12;     // 0.12 exploração · 0.6 combate
uniform float tinge = 0.55;           // quanto a cor do tipo de área tinge a laje
varying vec3 w;
varying vec3 n_mundo;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0);   // malha gerada sem tangentes
}
void fragment() {
	vec2 uv = w.xz / escala;
	vec3 c = texture(cor_tex, uv).rgb;
	vec3 tinta = COLOR.rgb / max(max(COLOR.r, COLOR.g), max(COLOR.b, 0.001));   // matiz do tipo de área
	c *= mix(vec3(1.0), tinta, tinge);
	c *= vec3(0.92, 0.95, 1.0);                                                  // tira um pouco do laranja
	vec2 g = abs(fract(w.xz / cel + 0.5) - 0.5) * cel;
	float largura = 0.015 + grade_forca * 0.04;
	c = mix(c, vec3(0.05, 0.04, 0.03), (1.0 - smoothstep(0.0, largura, min(g.x, g.y))) * min(grade_forca * 1.4, 0.95));
	float v = nevoa(w, normalize(n_mundo));
	ALBEDO = lembranca(c, v);
	if (v < 0.2) { SPECULAR = 0.0; }
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 1.3;
	ROUGHNESS = 0.88;
}
