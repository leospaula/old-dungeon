// Paredes e rocha com luz de verdade: pedra aparelhada pintada nas laterais (projeção pelo eixo da face),
// tingida pela cor do bloco (caverna mais marrom), topo escuro. Iluminado pelas luzes do Godot.
shader_type spatial;
render_mode cull_back;
uniform sampler2D cor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D natural_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float escala = 2.4;
varying vec3 w;
varying vec3 n_mundo;
void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// malha gerada sem tangentes: tangente horizontal ao longo da face, binormal para cima
	if (abs(NORMAL.y) > 0.7) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
	else if (abs(NORMAL.x) > 0.5) { TANGENT = vec3(0.0, 0.0, -sign(NORMAL.x)); BINORMAL = vec3(0.0, -1.0, 0.0); }
	else { TANGENT = vec3(sign(NORMAL.z), 0.0, 0.0); BINORMAL = vec3(0.0, -1.0, 0.0); }
}
void fragment() {
	vec3 n = normalize(n_mundo);
	bool natural = COLOR.r - COLOR.b > 0.04;
	vec2 uv = (abs(n.x) > 0.5 ? w.zy : (abs(n.z) > 0.5 ? w.xy : w.xz)) / escala;
	vec3 c = natural ? texture(natural_tex, uv * 0.8).rgb * vec3(0.85, 0.78, 0.7) : texture(cor_tex, uv).rgb;
	c *= vec3(0.9, 0.93, 1.0);
	if (n.y > 0.7) c *= 0.35;                                           // topo da rocha: escuro
	c *= mix(0.6, 1.0, smoothstep(0.0, 1.0, w.y));                      // sombra de contato na base
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = natural ? 0.8 : 1.4;
	ROUGHNESS = 0.92;
}
