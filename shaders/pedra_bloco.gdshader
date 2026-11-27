// Pedras grandes soltas (arco e batentes das portas): cada pedra tem a cor do vértice (tom próprio), a
// superfície da rocha (textura da caverna, projetada pelos três eixos, sem tom próprio) e o mesmo
// envelhecimento das paredes (manchas, limo nas fendas). Névoa de guerra como o resto da masmorra.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/nevoa.gdshaderinc"
uniform sampler2D rocha_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocha_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float escala = 0.9;
uniform float velhice = 0.5;
uniform vec3 cor_limo : source_color = vec3(0.2, 0.27, 0.12);
varying vec3 w;
varying vec3 n_mundo;
float _h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float _r3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(_h3(i), _h3(i + vec3(1,0,0)), f.x), mix(_h3(i + vec3(0,1,0)), _h3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(_h3(i + vec3(0,0,1)), _h3(i + vec3(1,0,1)), f.x), mix(_h3(i + vec3(0,1,1)), _h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float _fbm(vec3 p) { return _r3(p) * 0.5 + _r3(p * 2.03) * 0.25 + _r3(p * 4.1) * 0.15 + _r3(p * 8.3) * 0.1; }
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(n_mundo);
	vec3 pesos = pow(abs(n), vec3(4.0)); pesos /= (pesos.x + pesos.y + pesos.z);
	vec3 tx = texture(rocha_tex, w.zy / escala).rgb, ty = texture(rocha_tex, w.xz / escala).rgb, tz = texture(rocha_tex, w.xy / escala).rgb;
	vec3 t = tx * pesos.x + ty * pesos.y + tz * pesos.z;
	float l = dot(t, vec3(0.3, 0.59, 0.11));
	vec3 c = COLOR.rgb * vec3(1.08, 1.02, 0.9) * clamp(0.75 + (l - 0.16) * 2.4, 0.45, 1.25) * 0.92;   // tom da pedra × relevo
	c *= mix(1.0, mix(0.55, 1.05, smoothstep(0.3, 0.7, _fbm(w * 0.8))), velhice);
	float fenda = 1.0 - smoothstep(0.12, 0.3, l);                         // fendas escuras pegam limo
	float limo = clamp(fenda * smoothstep(0.4, 0.65, _fbm(w * 2.5 + 5.0)) * 1.4 + smoothstep(0.9, 0.0, w.y) * 0.5 * _fbm(w * 3.0), 0.0, 1.0);
	c = mix(c, cor_limo * (0.8 + 0.6 * _r3(w * 13.0)), limo * velhice);
	float v = nevoa(w, n);
	ALBEDO = lembranca(c, v);
	NORMAL_MAP = texture(rocha_normal, abs(n.x) > 0.5 ? w.zy / escala : (abs(n.z) > 0.5 ? w.xy / escala : w.xz / escala)).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = 0.9;
	SPECULAR = 0.45 * smoothstep(0.08, 0.43, v);
}
