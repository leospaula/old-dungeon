// Chama de tocha: quad virado para a câmera (só em torno do eixo vertical), com língua de fogo feita de
// ruído que sobe e tremula. Núcleo quase branco, corpo amarelo-laranja, pontas vermelhas que somem.
// Misturado (não aditivo, para não estourar em branco sobre a parede iluminada) e sem luz própria (a luz é a OmniLight da tocha).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float semente = 0.0;
uniform float intensidade = 1.25;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int k = 0; k < 4; k++) { v += a * ruido(p); p *= 2.03; a *= 0.5; } return v; }

void vertex() {
	// Billboard cilíndrico: gira só em Y para encarar a câmera (a chama continua em pé).
	vec3 cam = (INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz); cam.y = 0.0; cam = normalize(cam);
	vec3 dir = normalize(cross(vec3(0.0, 1.0, 0.0), cam));
	vec3 esc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 mundo = MODEL_MATRIX[3].xyz + dir * VERTEX.x * esc.x + vec3(0.0, 1.0, 0.0) * VERTEX.y * esc.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(mundo, 1.0);
}

void fragment() {
	vec2 uv = UV; uv.y = 1.0 - uv.y;            // 0 = base, 1 = ponta
	float t = TIME * 1.7 + semente * 7.0;
	// O corpo da chama balança de lado, mais na ponta.
	float lado = (fbm(vec2(uv.y * 2.0 - t * 1.1, semente)) - 0.5) * 0.5 * uv.y;
	float x = (uv.x - 0.5 - lado) * 2.0;
	// Largura irregular: gota larga embaixo que afina, com bordas mordidas pelo ruído.
	float borda = fbm(vec2(uv.x * 5.0 + semente, uv.y * 3.0 - t * 2.6));
	float larg = mix(0.85, 0.08, pow(uv.y, 0.7)) * (0.75 + 0.5 * borda);
	float forma = 1.0 - smoothstep(larg * 0.35, larg, abs(x));
	// Línguas: o ruído que sobe corta o topo em pedaços.
	float n = fbm(vec2(uv.x * 4.0, uv.y * 2.6 - t * 3.0));
	float chama = forma * smoothstep(0.05, 0.55, (1.0 - uv.y) * 1.35 + (n - 0.5) * 0.9 - 0.12);
	chama *= smoothstep(0.0, 0.18, uv.y + 0.04);  // base escondida no pano
	chama = clamp(chama, 0.0, 1.0);
	vec3 vermelho = vec3(0.75, 0.12, 0.02), laranja = vec3(1.0, 0.42, 0.05), amarelo = vec3(1.0, 0.75, 0.25), miolo = vec3(1.0, 0.93, 0.7);
	vec3 c = mix(vermelho, laranja, smoothstep(0.05, 0.35, chama));
	c = mix(c, amarelo, smoothstep(0.45, 0.8, chama));
	c = mix(c, miolo, smoothstep(0.85, 1.0, chama) * (1.0 - uv.y * 1.4));
	ALBEDO = c * intensidade;
	ALPHA = smoothstep(0.02, 0.35, chama) * 0.95;
}
