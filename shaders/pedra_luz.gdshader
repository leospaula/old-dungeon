// Paredes e rocha com luz de verdade: pedra aparelhada pintada nas laterais (projeção pelo eixo da face),
// tingida pela cor do bloco (caverna mais marrom), topo escuro. Iluminado pelas luzes do Godot.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/nevoa.gdshaderinc"
uniform sampler2D cor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D natural_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caverna_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caverna_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float escala = 2.4;
// Envelhecimento (protótipo 27/11): manchas escuras grandes, escorridos de umidade, limo perto do chão e nas
// juntas úmidas, e relevo irregular. Tudo procedural no espaço do mundo (não repete com a textura).
uniform float velhice = 0.0;
uniform vec3 cor_limo : source_color = vec3(0.2, 0.27, 0.12);
varying vec3 w;
varying vec3 n_mundo;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// malha gerada sem tangentes: tangente horizontal ao longo da face, binormal para cima
	if (abs(NORMAL.y) > 0.7) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
	else if (abs(NORMAL.x) > 0.5) { TANGENT = vec3(0.0, 0.0, -sign(NORMAL.x)); BINORMAL = vec3(0.0, -1.0, 0.0); }
	else { TANGENT = vec3(sign(NORMAL.z), 0.0, 0.0); BINORMAL = vec3(0.0, -1.0, 0.0); }
}
float _h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float _r3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(_h3(i), _h3(i + vec3(1,0,0)), f.x), mix(_h3(i + vec3(0,1,0)), _h3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(_h3(i + vec3(0,0,1)), _h3(i + vec3(1,0,1)), f.x), mix(_h3(i + vec3(0,1,1)), _h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float _fbm(vec3 p) { return _r3(p) * 0.5 + _r3(p * 2.03) * 0.25 + _r3(p * 4.1) * 0.15 + _r3(p * 8.3) * 0.1; }
void fragment() {
	vec3 n = normalize(n_mundo);
	bool natural = COLOR.r - COLOR.b > 0.04;
	vec2 uv = (abs(n.x) > 0.5 ? w.zy : (abs(n.z) > 0.5 ? w.xy : w.xz)) / escala;
	vec3 c = texture(cor_tex, uv).rgb;
	vec3 nm = texture(normal_tex, uv).rgb;
	if (natural) {   // rocha de caverna: textura própria pelos três eixos (a rocha deformada tem faces em todo ângulo)
		vec3 pw = pow(abs(n), vec3(4.0)); pw /= (pw.x + pw.y + pw.z);
		float e = escala * 1.1;
		c = (texture(caverna_tex, w.zy / e).rgb * pw.x + texture(caverna_tex, w.xz / e).rgb * pw.y + texture(caverna_tex, w.xy / e).rgb * pw.z) * vec3(1.6, 1.5, 1.35);
		nm = texture(caverna_normal, abs(n.x) > 0.5 ? w.zy / e : (abs(n.z) > 0.5 ? w.xy / e : w.xz / e)).rgb;
	}
	c *= vec3(0.9, 0.93, 1.0);
	float relevo = 0.0;
	if (velhice > 0.0 && n.y < 0.7) {
		float mancha = _fbm(w * 0.45);                                   // manchas grandes, mais escuras
		c *= mix(1.0, mix(0.3, 1.1, smoothstep(0.3, 0.7, mancha)), velhice);
		float escorre = _fbm(vec3(w.x * 5.0, w.y * 0.35, w.z * 5.0));    // escorridos verticais de umidade
		float faixa = smoothstep(0.55, 0.8, escorre) * smoothstep(3.0, 1.6, w.y) * smoothstep(0.0, 0.6, w.y);
		c *= 1.0 - 0.55 * faixa * velhice;
		float umido = smoothstep(1.4, 0.1, w.y) + smoothstep(0.58, 0.72, _fbm(w * 0.9 + 7.0)) * 0.7;
		float junta = 1.0 - smoothstep(0.25, 0.5, dot(texture(cor_tex, uv).rgb, vec3(0.33)));   // fendas escuras pegam mais limo
		float limo = clamp(umido * (0.6 + junta) * smoothstep(0.35, 0.6, _fbm(w * 2.2 + 3.0)) * 1.6, 0.0, 1.0);
		c = mix(c, cor_limo * (0.8 + 0.7 * _r3(w * 11.0)), limo * 0.9 * velhice);
		relevo = (_fbm(w * 1.7) - 0.5) * velhice;                        // pedra deformada
	}
	if (n.y > 0.7) c *= natural ? 0.6 : 0.35;                           // topo da rocha: escuro
	c *= mix(0.6, 1.0, smoothstep(0.0, 1.0, w.y));                      // sombra de contato na base
	float v = nevoa(w, n);
	ALBEDO = lembranca(c, v);
	SPECULAR = 0.5 * smoothstep(0.08, 0.43, v);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = (natural ? 0.8 : 1.4) * (1.0 + abs(relevo) * 1.6);
	ROUGHNESS = 0.92 - 0.25 * velhice * smoothstep(1.2, 0.0, w.y);   // úmido perto do chão brilha um pouco
}
