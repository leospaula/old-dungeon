// Funções comuns do estilo "tinta e aquarela" (Masmorra Clássica).
// Todos os shaders são unshaded: a "luz" é calculada aqui (faixas + tocha), o que é barato e roda no WebGL.

uniform vec3 luz_pos = vec3(10.5, 1.5, 7.5);   // posição da tocha (mundo)
uniform float luz_raio = 9.0;                  // B/X: tocha ilumina 9 m
uniform float luz_min = 0.18;                  // brilho fora da luz (escuridão)
uniform vec3 sol = vec3(0.45, 0.8, 0.35);      // direção "de desenho" para as faixas de sombra
uniform vec3 papel = vec3(0.93, 0.86, 0.72);

float hash1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float ruido(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1, 0)), f.x), mix(hash1(i + vec2(0, 1)), hash1(i + vec2(1, 1)), f.x), f.y);
}
// Voronoi: x = distância à borda da pedra (rejunte), y = id aleatório da pedra
vec2 voronoi(vec2 p) {
	vec2 n = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0; vec2 id = vec2(0);
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 o = 0.15 + 0.7 * hash2(n + g);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; id = n + g; } else if (d < d2) { d2 = d; }
	}
	return vec2(d2 - d1, hash1(id));
}
// Aquarela: tira saturação, puxa para o papel e mancha com ruído grande
vec3 aquarela(vec3 c, vec2 p, float satura, float mistura) {
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, satura);
	c = mix(c, papel * (0.35 + lum), mistura);
	float mancha = ruido(p * 0.35) * 0.6 + ruido(p * 1.3) * 0.4;
	return c * (0.88 + mancha * 0.22);
}
// Faixas de sombra (2 tons) com hachura a pena na sombra
vec3 faixas(vec3 c, vec3 n, vec2 frag) {
	float d = dot(normalize(n), normalize(sol));
	float banda = d > 0.45 ? 1.0 : (d > -0.05 ? 0.8 : 0.62);
	c *= banda * 1.1;
	if (banda < 0.95 && fract((frag.x - frag.y) / 5.0) < 0.2) c *= banda < 0.7 ? 0.6 : 0.82;
	return c;
}
// Tocha: luz quente perto, escuridão longe (com hachura cruzada no escuro)
vec3 tocha(vec3 c, vec3 w, vec2 frag) {
	float dist = distance(w.xz, luz_pos.xz);
	float l = smoothstep(luz_raio, luz_raio * 0.45, dist);
	vec3 quente = c * mix(vec3(1.0), vec3(1.12, 1.0, 0.82), l);
	vec3 r = mix(c * luz_min, quente, max(l, luz_min));
	if (l < 0.35 && fract((frag.x + frag.y) / 4.0) < 0.25) r *= 0.75;
	return r;
}
