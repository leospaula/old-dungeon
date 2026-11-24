// Objetos da masmorra (portas, ferro, esteiras, cristais): cor por vértice + PBR simples + névoa de guerra.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/nevoa.gdshaderinc"
uniform float metalico = 0.0;
uniform float rugosidade = 0.85;
uniform vec3 emissao = vec3(0.0);
uniform float emissao_forca = 0.0;
varying vec3 w;
varying vec3 n_mundo;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float v = nevoa(w, normalize(n_mundo));
	ALBEDO = lembranca(COLOR.rgb, v);
	METALLIC = metalico;
	ROUGHNESS = rugosidade;
	EMISSION = emissao * emissao_forca * step(0.9, v);
	if (v < 0.2) { SPECULAR = 0.0; }
}
