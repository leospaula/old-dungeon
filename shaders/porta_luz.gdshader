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
// Ferro envelhecido (grades): a textura do modelo só dá o relevo (claro/escuro); a cor vem daqui,
// igual nos dois lados do portão, com manchas de ferrugem no espaço do mundo. Sem textura (barras): só a cor.
uniform bool ferro_velho = false;
uniform bool usar_textura = true;
uniform vec3 cor_ferro : source_color = vec3(0.2, 0.18, 0.165);
uniform vec3 cor_ferrugem : source_color = vec3(0.3, 0.17, 0.09);
varying vec3 w;
varying vec3 n_mundo;
varying float z_local;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; z_local = VERTEX.z;
}
float _h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float _ruido(vec3 p) {
	vec3 i = floor(p); vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(_h(i), _h(i + vec3(1,0,0)), f.x), mix(_h(i + vec3(0,1,0)), _h(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(_h(i + vec3(0,0,1)), _h(i + vec3(1,0,1)), f.x), mix(_h(i + vec3(0,1,1)), _h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	if (corte != 0.0 && (z_local - corte_centro) * corte < 0.0) discard;
	float v = nevoa(w, normalize(n_mundo));
	vec3 cor = texture(albedo_tex, UV).rgb;
	if (ferro_velho) {
		// Relevo local: brilho do ponto dividido pelo brilho médio em volta (mipmap borrado). Assim os dois
		// lados do modelo, um mais claro que o outro na textura, ficam com o mesmo tom.
		float lum = dot(cor, vec3(0.3, 0.59, 0.11));
		float media = dot(textureLod(albedo_tex, UV, 7.0).rgb, vec3(0.3, 0.59, 0.11));
		float rel = usar_textura ? clamp(lum / max(media, 0.02), 0.45, 1.5) : 1.0;
		float m = _ruido(w * 3.1) * 0.65 + _ruido(w * 9.0) * 0.35;
		cor = mix(cor_ferro, cor_ferrugem, smoothstep(0.5, 0.85, m)) * rel * 1.6;
		METALLIC = 0.3;
	}
	ALBEDO = lembranca(cor, v);
	ROUGHNESS = ferro_velho ? 0.62 : 0.85;
	if (v > 0.2) {
		float borda = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		EMISSION = vec3(1.0, 0.62, 0.25) * (borda * 0.35 * fechada + destaque * (0.25 + borda * 0.6));
	}
	SPECULAR = 0.5 * smoothstep(0.08, 0.43, v);
}
