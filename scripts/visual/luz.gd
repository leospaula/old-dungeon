extends Node
## Iluminação "de verdade" da masmorra (renderizador Compatibility / WebGL):
## materiais pintados com relevo, tochas de parede com orçamento de sombras, tocha do grupo,
## preenchimento frio, ACES, brilho leve. Modo mestre acende tudo.

const SOMBRAS_MAX := 3          # só as tochas mais próximas do grupo projetam sombra
const CEL := 1.5

var tochas: Array[OmniLight3D] = []
var luz_grupo: OmniLight3D
var chao_mat: ShaderMaterial
var env: Environment
var preenchimento: DirectionalLight3D
var alvo: Node3D                 # quem carrega a tocha do grupo
var mestre := false

func configurar(raiz: Node3D, masmorra: Node3D, ambiente: WorldEnvironment, carregador: Node3D) -> void:
	alvo = carregador
	var tex := func(c: String) -> Texture2D:
		var img := Image.load_from_file(ProjectSettings.globalize_path(c)); img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	var laje: Texture2D = tex.call("res://arte/texturas/laje_cor.png")
	var laje_n: Texture2D = tex.call("res://arte/texturas/laje_normal.png")
	var parede: Texture2D = tex.call("res://arte/texturas/parede_cor.png")
	var parede_n: Texture2D = tex.call("res://arte/texturas/parede_normal.png")
	chao_mat = ShaderMaterial.new(); chao_mat.shader = load("res://shaders/chao_luz.gdshader")
	chao_mat.set_shader_parameter("cor_tex", laje); chao_mat.set_shader_parameter("normal_tex", laje_n)
	_aplicar(masmorra.get_node("Chao"), chao_mat, false)
	var pedra := ShaderMaterial.new(); pedra.shader = load("res://shaders/pedra_luz.gdshader")
	pedra.set_shader_parameter("cor_tex", parede); pedra.set_shader_parameter("normal_tex", parede_n); pedra.set_shader_parameter("natural_tex", laje)
	_aplicar(masmorra.get_node("Rocha"), pedra, true)
	_aplicar(masmorra.get_node("Paredes"), pedra, true)
	var madeira := StandardMaterial3D.new(); madeira.vertex_color_use_as_albedo = true; madeira.roughness = 0.8
	masmorra.get_node("Portas").material_override = madeira
	var ferro := StandardMaterial3D.new(); ferro.vertex_color_use_as_albedo = true; ferro.metallic = 0.8; ferro.roughness = 0.4
	masmorra.get_node("Ferro").material_override = ferro
	var est := StandardMaterial3D.new(); est.vertex_color_use_as_albedo = true; est.roughness = 0.9
	masmorra.get_node("Esteiras").material_override = est
	var cr := StandardMaterial3D.new(); cr.vertex_color_use_as_albedo = true; cr.emission_enabled = true
	cr.emission = Color(0.4, 0.7, 1.0); cr.emission_energy_multiplier = 0.8; cr.roughness = 0.2
	masmorra.get_node("Cristais").material_override = cr
	if masmorra.has_node("Rotulos"): masmorra.get_node("Rotulos").visible = false

	luz_grupo = OmniLight3D.new(); luz_grupo.light_color = Color(1.0, 0.72, 0.42); luz_grupo.light_energy = 0.9
	luz_grupo.omni_range = 9.0; luz_grupo.omni_attenuation = 1.5; raiz.add_child(luz_grupo)
	preenchimento = DirectionalLight3D.new(); preenchimento.rotation_degrees = Vector3(-60, 30, 0)
	preenchimento.light_color = Color(0.55, 0.6, 0.85); preenchimento.light_energy = 0.35; raiz.add_child(preenchimento)

	env = ambiente.environment
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.32, 0.36, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 1.05
	env.glow_enabled = true; env.glow_intensity = 0.35; env.glow_bloom = 0.0; env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true; env.adjustment_contrast = 1.06; env.adjustment_saturation = 0.92
	env.fog_enabled = true; env.fog_light_color = Color(0.1, 0.08, 0.07); env.fog_density = 0.01
	set_mestre(false)

## Coloca tochas nas paredes das áreas indicadas: procura células da área com parede ao norte
## (ou a oeste) e espaça `por_area` tochas ao longo delas.
func tochas_automaticas(raiz: Node3D, layout_path: String, areas: Array, por_area := 2) -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	var W := int(L.grade.largura); var H := int(L.grade.altura)
	var cel := {}
	for ar in L.areas:
		for r in ar.retangulos:
			for y in range(int(r[1]), int(r[3])):
				for x in range(int(r[0]), int(r[2])):
					cel[Vector2i(x, y)] = ar.id
	for area in areas:
		var norte := []; var oeste := []
		for k in cel:
			if cel[k] != area: continue
			if not cel.has(k + Vector2i(0, -1)): norte.append(k)
			elif not cel.has(k + Vector2i(-1, 0)): oeste.append(k)
		norte.sort(); oeste.sort()
		var lista := norte if norte.size() >= 2 else norte + oeste
		for i in mini(por_area, lista.size()):
			var c: Vector2i = lista[int((i + 0.5) * lista.size() / por_area)]
			var na_norte := not cel.has(c + Vector2i(0, -1))
			var pos := Vector3((c.x + 0.5) * CEL, 2.0, c.y * CEL + 0.2) if na_norte else Vector3(c.x * CEL + 0.2, 2.0, (c.y + 0.5) * CEL)
			_tocha(raiz, pos, Vector3(0, 0, 1) if na_norte else Vector3(1, 0, 0))

func _tocha(raiz: Node3D, pos: Vector3, dentro: Vector3) -> void:
	var t := Node3D.new(); t.position = pos; raiz.add_child(t)
	var cabo := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.05; cm.bottom_radius = 0.035; cm.height = 0.5; cabo.mesh = cm
	var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.25, 0.15, 0.08); cabo.material_override = mm
	cabo.rotation_degrees = Vector3(-25, 0, 0) if absf(dentro.z) > 0.5 else Vector3(0, 0, -25)
	t.add_child(cabo)
	var chama := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.24; chama.mesh = sm
	var mc := StandardMaterial3D.new(); mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mc.albedo_color = Color(1.0, 0.7, 0.3)
	mc.emission_enabled = true; mc.emission = Color(1.0, 0.6, 0.2); mc.emission_energy_multiplier = 1.3
	chama.material_override = mc; chama.position = Vector3(0, 0.3, 0) + dentro * 0.1; t.add_child(chama)
	var luz := OmniLight3D.new(); luz.position = chama.position + dentro * 0.3; luz.light_color = Color(1.0, 0.68, 0.38)
	luz.light_energy = 2.1; luz.omni_range = 8.5; luz.omni_attenuation = 1.6; t.add_child(luz)
	tochas.append(luz)
	var f := CPUParticles3D.new(); f.position = chama.position; f.amount = 14; f.lifetime = 1.6; f.direction = Vector3.UP; f.spread = 25
	f.initial_velocity_min = 0.3; f.initial_velocity_max = 0.8; f.gravity = Vector3(0, 0.2, 0); f.preprocess = 2.0
	var qm := QuadMesh.new(); qm.size = Vector2(0.035, 0.035)
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.75, 0.35); fm.emission_enabled = true; fm.emission = Color(1, 0.6, 0.2); fm.emission_energy_multiplier = 1.2
	qm.material = fm; f.mesh = qm; t.add_child(f)

## Aplica o material em todos os blocos (malhas filhas) de um grupo da masmorra.
func _aplicar(grupo: Node, mat: Material, sombra: bool) -> void:
	for c in grupo.get_children():
		if c is MeshInstance3D:
			c.material_override = mat
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func set_mestre(v: bool) -> void:
	mestre = v
	env.ambient_light_energy = 2.6 if v else 0.6
	preenchimento.light_energy = 1.6 if v else 0.35
	env.fog_enabled = not v

func set_grade(combate: bool) -> void:
	chao_mat.set_shader_parameter("grade_forca", 0.6 if combate else 0.12)

func _process(_dt: float) -> void:
	if alvo == null: return
	var p := alvo.global_position
	luz_grupo.global_position = p + Vector3(0.4, 1.6, 0.3)
	# Orçamento de sombras: só as tochas mais próximas
	var ordem := tochas.duplicate()
	ordem.sort_custom(func(a, b): return a.global_position.distance_squared_to(p) < b.global_position.distance_squared_to(p))
	for i in ordem.size():
		ordem[i].shadow_enabled = i < SOMBRAS_MAX
