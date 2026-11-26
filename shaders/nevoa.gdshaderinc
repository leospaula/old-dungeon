// Névoa de guerra: textura com 1 pixel por célula da grade (R: 0 nunca visto · ~0,43 já visto · 1 à vista).
// Cada face amostra a célula para onde ela olha (paredes ficam do lado de quem as viu).
uniform sampler2D nevoa_tex : filter_nearest;
uniform vec2 nevoa_tam = vec2(62.0, 38.0);

float _nev_cel(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(nevoa_tam.x) || c.y >= int(nevoa_tam.y)) return 0.0;
	return texelFetch(nevoa_tex, c, 0).r;
}

// Borda suave: mistura com as células vizinhas (bilinear), mas só para escurecer (min com a própria
// célula). Assim a borda da visão sai lisa e nenhuma célula não vista ganha luz das vizinhas.
float nevoa(vec3 w, vec3 n) {
	vec2 p = (w.xz + n.xz * 0.35) / 1.5;
	if (p.x < 0.0 || p.y < 0.0 || p.x >= nevoa_tam.x || p.y >= nevoa_tam.y) return 0.0;
	float propria = _nev_cel(ivec2(floor(p)));
	vec2 q = p - 0.5; ivec2 b = ivec2(floor(q)); vec2 f = smoothstep(0.0, 1.0, fract(q));
	float bil = mix(mix(_nev_cel(b), _nev_cel(b + ivec2(1, 0)), f.x),
	                mix(_nev_cel(b + ivec2(0, 1)), _nev_cel(b + ivec2(1, 1)), f.x), f.y);
	return min(propria, bil);
}

// Cor de acordo com a névoa, em gradação contínua: preto (0) → lembrança apagada (~0,43) → normal (1).
vec3 lembranca(vec3 c, float v) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 lemb = mix(vec3(l) * vec3(0.85, 0.9, 1.0), c, 0.3) * 0.55;
	if (v >= 0.43) return mix(lemb, c, smoothstep(0.43, 0.98, v));
	return mix(vec3(0.0), lemb, smoothstep(0.08, 0.43, v));
}
