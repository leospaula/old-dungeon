extends SceneTree
## Teste de estilo (rodada 2): masmorra de pedra em tinta e aquarela, diorama na mesa, luz da tocha.
## Uso: godot --path . --script tools/teste_estilos2.gd -- <pasta_saida>
## Usa os shaders de res://shaders/ (os mesmos que o jogo vai usar).

const TAM := Vector2i(960, 540)
const TESSA_POS := Vector3(10.5, 0, 7.5)
var vp: SubViewport
var cam: Camera3D
var materiais := []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var pasta: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(pasta)
	vp = SubViewport.new(); vp.size = TAM; vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	await _montar()
	var vistas := [
		["1-perto-tocha", TESSA_POS + Vector3(0, 0.8, 0), 6.5, -40.0, 52.0, 9.0],
		["2-perto-tocha-baixa", TESSA_POS + Vector3(0, 1.0, 0), 5.0, -130.0, 28.0, 9.0],
		["3-bloco-mestre", Vector3(54, 0, 27), 34.0, -25.0, 48.0, 9999.0],
		["4-mapa-mestre", Vector3(46, 0, 29), 95.0, -15.0, 55.0, 9999.0],
		["5-mapa-tocha", Vector3(46, 0, 29), 95.0, -15.0, 55.0, 9.0],
	]
	for v in vistas:
		for m in materiais: m.set_shader_parameter("luz_raio", v[5])
		var r := deg_to_rad(v[3]); var i := deg_to_rad(v[4])
		cam.position = v[1] + Vector3(sin(r) * cos(i), sin(i), cos(r) * cos(i)) * v[2]; cam.look_at(v[1])
		for _f in 6: await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGB8)
		img.save_png(pasta.path_join(v[0] + ".png"))
		print("ok ", v[0])
	quit()

func _mat(caminho: String) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load(caminho)
	m.set_shader_parameter("luz_pos", TESSA_POS + Vector3(0, 1.5, 0))
	materiais.append(m)
	return m

func _contorno(m: ShaderMaterial, largura: float) -> ShaderMaterial:
	var c := ShaderMaterial.new(); c.shader = load("res://shaders/contorno.gdshader"); c.set_shader_parameter("largura", largura)
	m.next_pass = c
	return m

func _montar() -> void:
	var mundo := Node3D.new(); vp.add_child(mundo)
	var masm: Node3D = load("res://scenes/masmorra/masmorra_base.scn").instantiate(); mundo.add_child(masm)
	masm.get_node("Rotulos").visible = false
	masm.get_node("Chao").material_override = _mat("res://shaders/chao.gdshader")
	masm.get_node("Rocha").material_override = _contorno(_mat("res://shaders/pedra.gdshader"), 0.06)
	masm.get_node("Paredes").material_override = _contorno(_mat("res://shaders/pedra.gdshader"), 0.05)
	for nome in ["Portas", "Ferro", "Esteiras"]:
		masm.get_node(nome).material_override = _contorno(_mat("res://shaders/objeto.gdshader"), 0.03)
	var cr := _mat("res://shaders/objeto.gdshader"); cr.set_shader_parameter("brilho", 0.6); cr.set_shader_parameter("satura", 1.0)
	masm.get_node("Cristais").material_override = cr

	var tessa: Node3D = load("res://arte/final/3d/tessa-biblioteca.glb").instantiate()
	tessa.position = TESSA_POS; tessa.rotation_degrees = Vector3(0, -90, 0); mundo.add_child(tessa)
	var ap := _achar(tessa, "AnimationPlayer") as AnimationPlayer
	ap.play("parado-espada-escudo"); ap.seek(0.6, true); ap.pause()
	for mi in _malhas(tessa):
		for s in mi.mesh.get_surface_count():
			var orig: Material = mi.get_active_material(s)
			var m := _mat("res://shaders/objeto.gdshader")
			if orig is StandardMaterial3D and orig.albedo_texture:
				m.set_shader_parameter("tex", orig.albedo_texture); m.set_shader_parameter("usa_tex", true)
			mi.set_surface_override_material(s, _contorno(m, 0.012))
	# Base de miniatura
	var base := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.5; cm.bottom_radius = 0.55; cm.height = 0.08
	var mb := StandardMaterial3D.new(); mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mb.albedo_color = Color(0.10, 0.12, 0.08)
	base.mesh = cm; base.material_override = mb; base.position = TESSA_POS + Vector3(0, 0.04, 0); mundo.add_child(base)
	# Mesa
	var mesa := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(260, 180); mesa.mesh = pm
	var sm := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 w;
float h(float p) { return fract(sin(p * 91.7) * 43758.5453); }
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = floor(w.z / 2.2);
	float veio = sin(w.x * 1.7 + sin(w.z * 0.9 + t) * 2.0 + h(t) * 6.0) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.20, 0.12, 0.06), vec3(0.32, 0.20, 0.10), veio * 0.6 + h(t) * 0.4);
	if (fract(w.z / 2.2) < 0.02) c *= 0.5;
	float d = distance(w.xz, vec2(46.0, 29.0));
	ALBEDO = c * mix(1.0, 0.35, smoothstep(40.0, 110.0, d));
}"""
	sm.shader = sh; mesa.material_override = sm; mesa.position = Vector3(46, -0.3, 28); mundo.add_child(mesa)

	var env := WorldEnvironment.new(); env.environment = Environment.new(); mundo.add_child(env)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.04, 0.03, 0.02)
	cam = Camera3D.new(); cam.fov = 45; mundo.add_child(cam); cam.current = true
	var tela := CanvasLayer.new(); mundo.add_child(tela)
	var papel := ColorRect.new(); papel.size = Vector2(TAM)
	var pm2 := ShaderMaterial.new(); pm2.shader = load("res://shaders/papel_tela.gdshader"); papel.material = pm2
	tela.add_child(papel)
	await process_frame

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
