// Objetos e personagens: aquarela com faixas de sombra, textura opcional e luz da tocha.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/comum.gdshaderinc"
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool usa_tex = false;
uniform float satura = 0.9;
uniform float mistura = 0.12;
uniform float brilho = 0.0;   // >0 para cristais
varying vec3 w;
varying vec3 n_mundo;
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	vec3 base = usa_tex ? texture(tex, UV).rgb : COLOR.rgb;
	vec3 c = faixas(aquarela(base, w.xz * 3.0, satura, mistura), n_mundo, FRAGCOORD.xy);
	c = tocha(c, w, FRAGCOORD.xy);
	ALBEDO = c + base * brilho;
}
