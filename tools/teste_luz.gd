extends SceneTree
## Teste "luz de verdade" na sala 24, no renderizador Compatibility (o mesmo do navegador).
## Materiais PBR com textura pintada + mapa de normais (triplanar), tochas reais com sombra,
## preenchimento frio, brilho (glow), correção de cor ACES e faíscas.
## Uso: godot --path . --script tools/teste_luz.gd -- <pasta_saida>

const TAM := Vector2i(1280, 720)
const TESSA_POS := Vector3(11.5, 0, 6.0)
var vp: SubViewport
var cam: Camera3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var pasta: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(pasta)
	vp = SubViewport.new(); vp.size = TAM; vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	for contorno in [false, true]:
		var mundo := _montar(contorno)
		for v in [["a", Vector3(12.75, 0.6, 5.0), 11.0, -25.0, 55.0], ["b", Vector3(12.75, 1.2, 4.0), 9.0, 10.0, 30.0]]:
			var r := deg_to_rad(v[3]); var i := deg_to_rad(v[4])
			cam.position = v[1] + Vector3(sin(r) * cos(i), sin(i), cos(r) * cos(i)) * v[2]; cam.look_at(v[1])
			for _f in 20: await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGB8)
			var nome := "luz%s-%s.png" % ["-contorno" if contorno else "", v[0]]
			img.save_png(pasta.path_join(nome)); print("ok ", nome)
		mundo.queue_free(); await process_frame
	quit()

func _textura(caminho: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho)); img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _pbr(cor: String, normal: String, escala: float, tint := Color.WHITE, rugos := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _textura(cor); m.albedo_color = tint
	m.normal_enabled = true; m.normal_texture = _textura(normal); m.normal_scale = 1.3
	m.roughness = rugos; m.metallic = 0.0
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3.ONE / escala
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _contorno(m: Material, largura: float) -> void:
	var c := ShaderMaterial.new(); c.shader = load("res://shaders/contorno.gdshader"); c.set_shader_parameter("largura", largura)
	m.next_pass = c

func _tocha_parede(pai: Node3D, pos: Vector3, para_dentro: Vector3) -> void:
	var t := Node3D.new(); t.position = pos; pai.add_child(t)
	var cabo := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.05; cm.bottom_radius = 0.035; cm.height = 0.5; cabo.mesh = cm
	var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.25, 0.15, 0.08); cabo.material_override = mm
	cabo.rotation_degrees = Vector3(-25, 0, 0) if absf(para_dentro.z) > 0.5 else Vector3(0, 0, 25 * signf(-para_dentro.x))
	t.add_child(cabo)
	var chama := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.24; chama.mesh = sm
	var mc := StandardMaterial3D.new(); mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mc.albedo_color = Color(1.0, 0.7, 0.3)
	mc.emission_enabled = true; mc.emission = Color(1.0, 0.6, 0.2); mc.emission_energy_multiplier = 1.3
	chama.material_override = mc; chama.position = Vector3(0, 0.3, 0) + para_dentro * 0.1; t.add_child(chama)
	var luz := OmniLight3D.new(); luz.position = chama.position + para_dentro * 0.3; luz.light_color = Color(1.0, 0.68, 0.38)
	luz.light_energy = 2.1; luz.omni_range = 8.5; luz.omni_attenuation = 1.6; luz.shadow_enabled = true; t.add_child(luz)
	var faiscas := CPUParticles3D.new(); faiscas.position = chama.position; faiscas.amount = 18; faiscas.lifetime = 1.6
	faiscas.direction = Vector3.UP; faiscas.spread = 25; faiscas.initial_velocity_min = 0.3; faiscas.initial_velocity_max = 0.8
	faiscas.gravity = Vector3(0, 0.2, 0)
	var qm := QuadMesh.new(); qm.size = Vector2(0.035, 0.035); faiscas.mesh = qm
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.75, 0.35); fm.emission_enabled = true; fm.emission = Color(1, 0.6, 0.2); fm.emission_energy_multiplier = 1.2
	qm.material = fm; faiscas.preprocess = 2.0; t.add_child(faiscas)

func _montar(contorno: bool) -> Node3D:
	var mundo := Node3D.new(); vp.add_child(mundo)
	var masm: Node3D = load("res://scenes/masmorra/masmorra_base.scn").instantiate(); mundo.add_child(masm)
	masm.get_node("Rotulos").visible = false
	var chao := _pbr("res://arte/texturas/laje_cor.png", "res://arte/texturas/laje_normal.png", 3.0)
	var parede := _pbr("res://arte/texturas/parede_cor.png", "res://arte/texturas/parede_normal.png", 2.4)
	var rocha := _pbr("res://arte/texturas/parede_cor.png", "res://arte/texturas/parede_normal.png", 2.4, Color(0.75, 0.72, 0.7))
	if contorno: _contorno(parede, 0.05); _contorno(rocha, 0.06)
	masm.get_node("Chao").material_override = chao
	masm.get_node("Paredes").material_override = parede
	masm.get_node("Rocha").material_override = rocha
	var madeira := StandardMaterial3D.new(); madeira.vertex_color_use_as_albedo = true; madeira.roughness = 0.8
	masm.get_node("Portas").material_override = madeira
	var ferro := StandardMaterial3D.new(); ferro.vertex_color_use_as_albedo = true; ferro.metallic = 0.8; ferro.roughness = 0.4
	masm.get_node("Ferro").material_override = ferro

	var tessa: Node3D = load("res://arte/final/3d/tessa-biblioteca.glb").instantiate()
	tessa.position = TESSA_POS; tessa.rotation_degrees = Vector3(0, -60, 0); mundo.add_child(tessa)
	var ap := _achar(tessa, "AnimationPlayer") as AnimationPlayer
	ap.play("parado-espada-escudo"); ap.seek(0.6, true); ap.pause()
	if contorno:
		for mi in _malhas(tessa):
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s).duplicate(); _contorno(m, 0.012); mi.set_surface_override_material(s, m)

	# Tochas na sala 24 (x 7,5–18 m; z 0–10,5 m): parede norte (z = 0) e parede oeste (x = 7,5)
	_tocha_parede(mundo, Vector3(10.0, 2.0, 0.2), Vector3(0, 0, 1))
	_tocha_parede(mundo, Vector3(15.5, 2.0, 0.2), Vector3(0, 0, 1))
	_tocha_parede(mundo, Vector3(7.7, 2.0, 6.0), Vector3(1, 0, 0))
	# Luz da tocha que a Tessa carrega (sem sombra, para ficar leve)
	var mao := OmniLight3D.new(); mao.position = TESSA_POS + Vector3(0.4, 1.6, 0.3); mao.light_color = Color(1.0, 0.72, 0.42)
	mao.light_energy = 0.7; mao.omni_range = 9.0; mundo.add_child(mao)
	# Preenchimento frio vindo de cima
	var lua := DirectionalLight3D.new(); lua.rotation_degrees = Vector3(-60, 30, 0); lua.light_color = Color(0.55, 0.6, 0.85)
	lua.light_energy = 0.35; mundo.add_child(lua)

	var env := WorldEnvironment.new(); var e := Environment.new(); env.environment = e; mundo.add_child(env)
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.32, 0.36, 0.55); e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; e.tonemap_exposure = 1.05
	e.glow_enabled = true; e.glow_intensity = 0.35; e.glow_bloom = 0.0; e.glow_hdr_threshold = 1.2
	e.adjustment_enabled = true; e.adjustment_contrast = 1.06; e.adjustment_saturation = 0.92
	e.fog_enabled = true; e.fog_light_color = Color(0.1, 0.08, 0.07); e.fog_density = 0.01
	cam = Camera3D.new(); cam.fov = 45; mundo.add_child(cam); cam.current = true
	return mundo

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
