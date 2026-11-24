extends SceneTree
## Teste de estilos visuais: renderiza a mesma cena em 4 versões e monta uma folha de comparação.
## Uso: godot --path . --script tools/teste_estilos.gd -- <pasta_saida>
## Versões: atual · 1 tinta e aquarela · 2 diorama na mesa · 1+2 juntos.
## Tudo compatível com o renderizador Compatibility (WebGL2): shaders sem luz (unshaded),
## contorno por casca invertida e papel por cima em multiplicação.

const TAM := Vector2i(960, 540)
const TESSA_POS := Vector3(10.5, 0, 7.5)

const SH_TINTA := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool usa_tex = false;
uniform float satura = 0.7;
uniform float mistura = 0.3;
uniform vec3 sol = vec3(0.45, 0.8, 0.35);
uniform vec3 papel = vec3(0.93, 0.86, 0.72);
varying vec3 n_mundo;
void vertex() { n_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; }
void fragment() {
	vec3 base = usa_tex ? texture(tex, UV).rgb : COLOR.rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(vec3(lum), base, satura);           // aquarela: menos saturação
	base = mix(base, papel * (0.35 + lum), mistura); // puxa para o tom do pergaminho
	float d = dot(normalize(n_mundo), normalize(sol));
	float banda = d > 0.45 ? 1.0 : (d > -0.05 ? 0.8 : 0.6);
	vec3 c = base * banda * 1.12;
	if (banda < 0.95) {
		float h = fract((FRAGCOORD.x - FRAGCOORD.y) / 5.0);
		if (h < 0.2) c *= banda < 0.7 ? 0.55 : 0.8;    // hachura a pena nas sombras
	}
	ALBEDO = c;
}
"""

const SH_CONTORNO := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float largura = 0.04;
uniform vec3 tinta = vec3(0.10, 0.07, 0.05);
void vertex() { VERTEX += NORMAL * largura; }
void fragment() { ALBEDO = tinta; }
"""

const SH_PERGAMINHO := """
shader_type spatial;
render_mode cull_disabled%s;
uniform float cel = 1.5;
varying vec3 w;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 papel = vec3(0.88, 0.79, 0.60);
	float n = ruido(w.xz * 0.6) * 0.55 + ruido(w.xz * 2.7) * 0.25 + ruido(w.xz * 11.0) * 0.1;
	vec3 c = papel * (0.82 + n * 0.25);
	vec2 g = abs(fract(w.xz / cel + 0.5) - 0.5) * cel;
	float linha = 1.0 - smoothstep(0.0, 0.03, min(g.x, g.y));
	c = mix(c, vec3(0.30, 0.22, 0.15), linha * 0.6);
	ALBEDO = c;%s
}
"""

const SH_MADEIRA := """
shader_type spatial;
render_mode cull_disabled%s;
varying vec3 w;
float hash(float p) { return fract(sin(p * 91.7) * 43758.5453); }
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float tabua = floor(w.z / 2.2);
	float veio = sin(w.x * 1.7 + sin(w.z * 0.9 + tabua) * 2.0 + hash(tabua) * 6.0) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.24, 0.14, 0.07), vec3(0.36, 0.22, 0.11), veio * 0.6 + hash(tabua) * 0.4);
	if (fract(w.z / 2.2) < 0.02) c *= 0.5;
	ALBEDO = c;%s
}
"""

const SH_PAPEL_TELA := """
shader_type canvas_item;
render_mode blend_mul;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float n = ruido(uv * vec2(480.0, 270.0)) * 0.07 + ruido(uv * vec2(36.0, 20.0)) * 0.08;
	float v = smoothstep(0.85, 0.3, distance(uv, vec2(0.5)));
	COLOR = vec4(vec3(0.9 + n) * mix(0.72, 1.0, v) * vec3(1.0, 0.95, 0.86), 1.0);
}
"""

var vp: SubViewport
var cam: Camera3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var pasta: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(pasta)
	vp = SubViewport.new(); vp.size = TAM; vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var tiras := []
	for v in ["atual", "tinta", "diorama", "tinta-diorama"]:
		var mundo := await _montar(v)
		var imgs := []
		for vista in [[TESSA_POS + Vector3(0, 0.8, 0), 6.5, -40.0, 52.0], [Vector3(54, 0, 27), 34.0, -25.0, 48.0], [Vector3(46, 0, 29), 95.0, -15.0, 55.0]]:
			_camera(vista[0], vista[1], vista[2], vista[3])
			for _f in 6: await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGB8)
			img.save_png(pasta.path_join("%s-%d.png" % [v, imgs.size() + 1]))
			imgs.append(img)
		tiras.append(imgs)
		mundo.queue_free()
		await process_frame
		print("ok ", v)
	quit()

func _camera(alvo: Vector3, dist: float, guinada: float, inclin: float) -> void:
	var r := deg_to_rad(guinada); var i := deg_to_rad(inclin)
	cam.position = alvo + Vector3(sin(r) * cos(i), sin(i), cos(r) * cos(i)) * dist
	cam.look_at(alvo)

func _montar(v: String) -> Node3D:
	var tinta := v.begins_with("tinta")
	var diorama := v.ends_with("diorama")
	var mundo := Node3D.new(); vp.add_child(mundo)
	var masm: Node3D = load("res://scenes/masmorra/masmorra_base.scn").instantiate(); mundo.add_child(masm)
	masm.get_node("Rotulos").visible = false
	var tessa: Node3D = load("res://arte/final/3d/tessa-biblioteca.glb").instantiate()
	tessa.position = TESSA_POS; tessa.rotation_degrees = Vector3(0, -90, 0); mundo.add_child(tessa)
	var ap := _achar(tessa, "AnimationPlayer") as AnimationPlayer
	ap.play("parado-espada-escudo"); ap.seek(0.6, true); ap.pause()

	var env := WorldEnvironment.new(); env.environment = Environment.new(); mundo.add_child(env)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cam = Camera3D.new(); cam.fov = 45; mundo.add_child(cam); cam.current = true

	if diorama:
		# Mesa de madeira por baixo, base de miniatura, luz de vela
		var mesa := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(260, 180); mesa.mesh = pm
		mesa.position = Vector3(46, -0.3, 28); mesa.material_override = _shader(SH_MADEIRA % ([", unshaded", ""] if tinta else ["", "\n\tROUGHNESS = 0.7;"]))
		mundo.add_child(mesa)
		var base := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.5; cm.bottom_radius = 0.55; cm.height = 0.08; base.mesh = cm
		var mb := StandardMaterial3D.new(); mb.albedo_color = Color(0.12, 0.16, 0.10); base.material_override = mb
		base.position = TESSA_POS + Vector3(0, 0.04, 0); mundo.add_child(base)
		masm.get_node("Chao").material_override = _shader(SH_PERGAMINHO % ([", unshaded", ""] if tinta else ["", "\n\tROUGHNESS = 1.0;"]))
		env.environment.background_color = Color(0.05, 0.04, 0.03)
		env.environment.ambient_light_color = Color(0.55, 0.45, 0.35); env.environment.ambient_light_energy = 0.35
		var vela := OmniLight3D.new(); vela.position = TESSA_POS + Vector3(3, 4, 3); vela.omni_range = 40; vela.light_energy = 2.2
		vela.light_color = Color(1.0, 0.78, 0.5); vela.shadow_enabled = true; mundo.add_child(vela)
		var vela2 := OmniLight3D.new(); vela2.position = Vector3(55, 6, 30); vela2.omni_range = 45; vela2.light_energy = 1.6
		vela2.light_color = Color(1.0, 0.8, 0.55); mundo.add_child(vela2)
	else:
		env.environment.background_color = Color(0.06, 0.07, 0.09)
		env.environment.ambient_light_color = Color(0.85, 0.85, 0.95); env.environment.ambient_light_energy = 0.35
		var sol := DirectionalLight3D.new(); sol.rotation_degrees = Vector3(-55, -35, 0); sol.light_energy = 1.1; sol.shadow_enabled = true
		mundo.add_child(sol)

	if tinta:
		for nome in ["Rocha", "Paredes", "Portas", "Ferro", "Esteiras", "Cristais"] + ([] if diorama else ["Chao"]):
			var mi := masm.get_node_or_null(nome) as MeshInstance3D
			if mi: mi.material_override = _tinta(null, 0.05)
		for mi in _malhas(tessa):
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				var t: Texture2D = m.albedo_texture if m is StandardMaterial3D else null
				mi.set_surface_override_material(s, _tinta(t, 0.012))
		var tela := CanvasLayer.new(); mundo.add_child(tela)
		var papel := ColorRect.new(); papel.size = Vector2(TAM); papel.material = _shader_canvas(SH_PAPEL_TELA)
		tela.add_child(papel)
		if not diorama: env.environment.background_color = Color(0.16, 0.12, 0.09)
	await process_frame
	return mundo

func _tinta(t: Texture2D, largura: float) -> ShaderMaterial:
	var m := _shader(SH_TINTA)
	if t:
		m.set_shader_parameter("tex", t); m.set_shader_parameter("usa_tex", true)
		m.set_shader_parameter("satura", 0.95); m.set_shader_parameter("mistura", 0.1)
	var c := _shader(SH_CONTORNO); c.set_shader_parameter("largura", largura)
	m.next_pass = c
	return m

func _shader(codigo: String) -> ShaderMaterial:
	var s := Shader.new(); s.code = codigo
	var m := ShaderMaterial.new(); m.shader = s
	return m

func _shader_canvas(codigo: String) -> ShaderMaterial:
	return _shader(codigo)

func _achar(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _achar(c, cls)
		if r: return r
	return null

func _malhas(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh: out.append(n)
	for c in n.get_children(): out.append_array(_malhas(c))
	return out
