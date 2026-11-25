// Retrato redondo com aro (padrão visual "Grimório escuro", docs/padrao-visual.md).
// Corta a imagem em círculo e pinta o aro na borda; fora do círculo fica transparente.
shader_type canvas_item;

uniform vec4 aro : source_color = vec4(0.77, 0.6, 0.32, 1.0);
uniform vec4 contorno : source_color = vec4(0.1, 0.07, 0.05, 1.0);
uniform float largura = 0.05;   // aro, em fração do raio
uniform float apagado = 0.0;    // 0..1: cinza e escuro (caído, já agiu)

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float aa = fwidth(r) * 1.2;
	vec4 c = COLOR;
	float cinza = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(cinza) * 0.55, apagado);
	// aro dourado com um fio escuro por fora e por dentro
	float dentro = 1.0 - largura;
	float t_aro = smoothstep(dentro - aa, dentro, r);
	c = mix(c, aro, t_aro);
	float t_fio = smoothstep(1.0 - largura * 0.35 - aa, 1.0 - largura * 0.35, r);
	c = mix(c, contorno, t_fio);
	c.a *= 1.0 - smoothstep(1.0 - aa, 1.0, r);
	COLOR = c;
}
