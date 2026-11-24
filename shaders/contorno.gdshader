// Contorno de tinta por casca invertida (barato e compatível com WebGL).
shader_type spatial;
render_mode unshaded, cull_front;
uniform float largura = 0.05;
uniform vec3 tinta = vec3(0.09, 0.06, 0.04);
void vertex() { VERTEX += NORMAL * largura; }
void fragment() { ALBEDO = tinta; }
