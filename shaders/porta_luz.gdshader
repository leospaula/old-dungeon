// Portas com modelo 3D texturizado: textura + névoa de guerra + contorno quente (fechada) e destaque do mouse,
// como shaders/objeto_luz.gdshader. 'corte' esconde metade do modelo (porta dupla: cada folha mostra a sua).
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/nevoa.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float fechada = 0.0;
uniform float destaque = 0.0;
uniform float corte = 0.0;        // 0 = inteira; +1 mantém z local > centro; -1 mantém z local < centro
uniform float corte_centro = 0.0;
varying vec3 w;
varying vec3 n_mundo;
varying float z_local;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; z_local = VERTEX.z;
}
void fragment() {
	if (corte != 0.0 && (z_local - corte_centro) * corte < 0.0) discard;
	float v = nevoa(w, normalize(n_mundo));
	ALBEDO = lembranca(texture(albedo_tex, UV).rgb, v);
	ROUGHNESS = 0.85;
	if (v > 0.2) {
		float borda = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		EMISSION = vec3(1.0, 0.62, 0.25) * (borda * 0.35 * fechada + destaque * (0.25 + borda * 0.6));
	}
	SPECULAR = 0.5 * smoothstep(0.08, 0.43, v);
}
