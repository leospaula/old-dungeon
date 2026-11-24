// Grão de papel e vinheta por cima da tela (multiplicação).
shader_type canvas_item;
render_mode blend_mul;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float n = ruido(uv * vec2(480.0, 270.0)) * 0.07 + ruido(uv * vec2(36.0, 20.0)) * 0.08;
	float v = smoothstep(0.85, 0.3, distance(uv, vec2(0.5)));
	COLOR = vec4(vec3(0.9 + n) * mix(0.7, 1.0, v) * vec3(1.0, 0.95, 0.86), 1.0);
}
