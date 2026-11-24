// Névoa de guerra: textura com 1 pixel por célula da grade (R: 0 nunca visto · ~0,43 já visto · 1 à vista).
// Cada face amostra a célula para onde ela olha (paredes ficam do lado de quem as viu).
uniform sampler2D nevoa_tex : filter_nearest;
uniform vec2 nevoa_tam = vec2(62.0, 38.0);

float nevoa(vec3 w, vec3 n) {
	vec2 p = (w.xz + n.xz * 0.35) / 1.5;
	if (p.x < 0.0 || p.y < 0.0 || p.x >= nevoa_tam.x || p.y >= nevoa_tam.y) return 0.0;
	return texelFetch(nevoa_tex, ivec2(floor(p)), 0).r;
}

// Cor de acordo com a névoa: preto, lembrança (apagada e quase sem cor) ou normal.
vec3 lembranca(vec3 c, float v) {
	if (v > 0.9) return c;
	if (v < 0.2) return vec3(0.0);
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	return mix(vec3(l) * vec3(0.85, 0.9, 1.0), c, 0.3) * 0.55;
}
