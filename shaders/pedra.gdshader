// Paredes e rocha. Faces laterais: pedra aparelhada (salas) ou rocha irregular (cavernas).
// Topo da rocha: hachura a lápis, como a área "não acessível" de um mapa desenhado.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/comum.gdshaderinc"
varying vec3 w;
varying vec3 n_mundo;
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	vec3 n = normalize(n_mundo);
	bool natural = COLOR.r - COLOR.b > 0.04;
	vec3 c;
	if (n.y > 0.7) {
		// Topo: papel escuro hachurado
		c = aquarela(vec3(0.34, 0.31, 0.28), w.xz, 0.5, 0.15);
		float h1 = fract((w.x - w.z) * 9.0 + ruido(w.xz * 2.0) * 0.3);
		float h2 = fract((w.x + w.z) * 9.0 + ruido(w.xz) * 0.5);
		if (h1 < 0.35) c *= 0.7;
		if (h2 < 0.25) c *= 0.85;
	} else {
		vec2 p = abs(n.x) > 0.5 ? w.zy : w.xy;
		if (natural) {
			vec2 v = voronoi(p * vec2(1.1, 1.6));
			c = aquarela(vec3(0.58, 0.50, 0.42) * (0.85 + v.y * 0.25), p, 0.6, 0.25);
			c *= 0.75 + 0.35 * smoothstep(0.0, 0.3, v.x);          // relevo da rocha
			c = mix(c, vec3(0.18, 0.13, 0.10), (1.0 - smoothstep(0.02, 0.09, v.x)) * 0.9);
		} else {
			// Pedra aparelhada: fileiras de 0,5 m, blocos de 0,9 m, juntas desencontradas
			float fila = floor(p.y / 0.5);
			float bx = p.x / 0.9 + fila * 0.5;
			float id = hash1(vec2(floor(bx), fila));
			c = aquarela(vec3(0.64, 0.60, 0.54) * (0.84 + id * 0.24), p, 0.55, 0.25);
			float jy = abs(fract(p.y / 0.5) - 0.5) * 0.5;
			float jx = abs(fract(bx) - 0.5) * 0.9;
			float borda = min(0.25 - jy, 0.45 - jx);
			c *= 0.78 + 0.32 * smoothstep(0.0, 0.12, borda);          // relevo do bloco
			float junta = 1.0 - smoothstep(0.012, 0.035, borda);
			c = mix(c, vec3(0.20, 0.15, 0.11), junta * 0.85);
		}
		c *= mix(0.55, 1.0, smoothstep(0.0, 1.1, w.y));            // sombra na base da parede
		c = faixas(c, n, FRAGCOORD.xy);
		float lf = luz_face(w, n);                                  // tocha ilumina conforme o ângulo
		c = mix(c * luz_min, c * vec3(1.15, 1.0, 0.82), clamp(lf, 0.0, 1.2));
		if (lf < 0.3 && fract((FRAGCOORD.x + FRAGCOORD.y) / 4.0) < 0.25) c *= 0.75;
		ALBEDO = c;
	}
	if (n.y > 0.7) ALBEDO = mix(c * luz_min, c, max(smoothstep(luz_raio, luz_raio * 0.45, distance(w.xz, luz_pos.xz)) * 0.8, luz_min));
}
