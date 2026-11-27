extends Node
## Iluminação "de verdade" da masmorra (renderizador Compatibility / WebGL):
## materiais pintados com relevo, tochas de parede com orçamento de sombras, tocha do grupo,
## preenchimento frio, ACES, brilho leve. Modo mestre acende tudo.

const SOMBRAS_MAX := 3          # só as tochas mais próximas do grupo projetam sombra
const CEL := 1.5

var tochas: Array[OmniLight3D] = []
var tochas_nos: Array[Node3D] = []
var tochas_cel: Array[Vector2i] = []
var materiais: Array[ShaderMaterial] = []
var pedra_mat: ShaderMaterial   # material das paredes (portas secretas usam para se disfarçar)
var luzes_tocha := {}           # ator -> OmniLight3D da tocha na mão dele
var _raiz: Node3D
var chao_mat: ShaderMaterial
var env: Environment
var preenchimento: DirectionalLight3D
var alvo: Node3D                 # quem carrega a tocha do grupo
var mestre := false

func configurar(raiz: Node3D, masmorra: Node3D, ambiente: WorldEnvironment, carregador: Node3D) -> void:
	alvo = carregador
	# Textura importada (com mipmaps): o PNG original não existe no jogo exportado (navegador).
	var tex := func(c: String) -> Texture2D: return load(c)
	var laje: Texture2D = tex.call("res://arte/texturas/laje_cor.png")
	var laje_n: Texture2D = tex.call("res://arte/texturas/laje_normal.png")
	var parede: Texture2D = tex.call("res://arte/texturas/parede_cor.png")
	var parede_n: Texture2D = tex.call("res://arte/texturas/parede_normal.png")
	chao_mat = ShaderMaterial.new(); chao_mat.shader = load("res://shaders/chao_luz.gdshader")
	chao_mat.set_shader_parameter("cor_tex", laje); chao_mat.set_shader_parameter("normal_tex", laje_n)
	_aplicar(masmorra.get_node("Chao"), chao_mat, false)
	pedra_mat = ShaderMaterial.new(); var pedra := pedra_mat; pedra.shader = load("res://shaders/pedra_luz.gdshader")
	pedra.set_shader_parameter("cor_tex", parede); pedra.set_shader_parameter("normal_tex", parede_n); pedra.set_shader_parameter("natural_tex", laje)
	_aplicar(masmorra.get_node("Rocha"), pedra, true)
	_aplicar(masmorra.get_node("Paredes"), pedra, true)
	materiais = [chao_mat, pedra]
	var madeira := _objeto(0.0, 0.8)
	for folha in masmorra.get_node("Portas").find_children("*", "MeshInstance3D", true, false):
		folha.material_override = madeira
	masmorra.get_node("Ferro").material_override = _objeto(0.8, 0.4)
	masmorra.get_node("Esteiras").material_override = _objeto(0.0, 0.9)
	masmorra.get_node("Cristais").material_override = _objeto(0.0, 0.2, Color(0.4, 0.7, 1.0), 0.8)
	if masmorra.has_node("Rotulos"): masmorra.get_node("Rotulos").visible = false

	_raiz = raiz
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
			tochas_cel.append(c)

## Luz fraca e fria espalhada numa área em penumbra (luz que vaza de fora, por grades ou frestas).
func penumbra(raiz: Node3D, celulas: Array) -> void:
	if celulas.is_empty(): return
	var soma := Vector2.ZERO
	for c in celulas: soma += Vector2(c.x + 0.5, c.y + 0.5)
	soma /= celulas.size()
	var l := OmniLight3D.new(); l.position = Vector3(soma.x * CEL, 2.4, soma.y * CEL)
	l.light_color = Color(0.62, 0.66, 0.8); l.light_energy = 0.55; l.omni_range = 6.0; l.omni_attenuation = 1.2
	raiz.add_child(l)

## Sombra de tocha lisa: cubo (mais preciso que o paraboloide), borda desfocada e viés contra o serrilhado.
func _sombra_suave(l: OmniLight3D) -> void:
	l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	l.shadow_blur = 2.5
	l.shadow_bias = 0.04; l.shadow_normal_bias = 1.2

## Caixa de todas as malhas de um modelo, no espaço da raiz dele (conta a escala dos nós do .glb).
static func caixa_local(raiz: Node3D) -> AABB:
	var caixa := AABB(); var primeiro := true
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var tr := Transform3D(); var p: Node = n
		while p != raiz and p != null:
			tr = (p as Node3D).transform * tr; p = p.get_parent()
		var bb: AABB = tr * (n as MeshInstance3D).get_aabb()
		caixa = bb if primeiro else caixa.merge(bb); primeiro = false
	return caixa

const TOCHA_GLB := "res://arte/final/3d/tocha-parede.glb"
const TOCHA_ALTURA := 0.9

func _tocha(raiz: Node3D, pos: Vector3, dentro: Vector3) -> void:
	var t := Node3D.new(); t.position = pos; raiz.add_child(t); tochas_nos.append(t)
	var pos_chama := Vector3(0, 0.3, 0) + dentro * 0.1
	if ResourceLoader.exists(TOCHA_GLB):
		# Modelo: placa no +z (contra a parede), tocha avançando para -z, altura em y.
		var mod: Node3D = load(TOCHA_GLB).instantiate()
		var caixa := caixa_local(mod)
		var s := TOCHA_ALTURA / caixa.size.y
		var zm := -dentro; var xm := Vector3.UP.cross(zm).normalized()
		var b := Basis(xm * s, Vector3.UP * s, zm * s)
		var placa := Vector3(caixa.get_center().x, caixa.get_center().y, caixa.end.z)
		mod.transform = Transform3D(b, -dentro * 0.2 - b * placa)
		t.add_child(mod)
		for mi in mod.find_children("*", "MeshInstance3D", true, false):   # a própria chama não faz sombra da tocha
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cabeca := Vector3(caixa.get_center().x, caixa.end.y, caixa.position.z + caixa.size.z * 0.3)
		pos_chama = mod.transform * cabeca + Vector3(0, 0.06, 0)
	else:
		var cabo := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.05; cm.bottom_radius = 0.035; cm.height = 0.5; cabo.mesh = cm
		var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.25, 0.15, 0.08); cabo.material_override = mm
		cabo.rotation_degrees = Vector3(-25, 0, 0) if absf(dentro.z) > 0.5 else Vector3(0, 0, -25)
		t.add_child(cabo)
	var chama := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.055; sm.height = 0.17; chama.mesh = sm
	chama.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mc := StandardMaterial3D.new(); mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mc.albedo_color = Color(1.0, 0.7, 0.3)
	mc.emission_enabled = true; mc.emission = Color(1.0, 0.6, 0.2); mc.emission_energy_multiplier = 1.3
	chama.material_override = mc; chama.position = pos_chama; t.add_child(chama)
	var luz := OmniLight3D.new(); luz.position = chama.position + dentro * 0.3; luz.light_color = Color(1.0, 0.68, 0.38)
	luz.light_energy = 2.1; luz.omni_range = 8.5; luz.omni_attenuation = 1.6; t.add_child(luz)
	_sombra_suave(luz)
	tochas.append(luz)
	var f := CPUParticles3D.new(); f.position = chama.position; f.amount = 14; f.lifetime = 1.6; f.direction = Vector3.UP; f.spread = 25
	f.initial_velocity_min = 0.3; f.initial_velocity_max = 0.8; f.gravity = Vector3(0, 0.2, 0); f.preprocess = 2.0
	var qm := QuadMesh.new(); qm.size = Vector2(0.035, 0.035)
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.75, 0.35); fm.emission_enabled = true; fm.emission = Color(1, 0.6, 0.2); fm.emission_energy_multiplier = 1.2
	qm.material = fm; f.mesh = qm; f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; t.add_child(f)

func _objeto(metalico: float, rugosidade: float, emissao := Color.BLACK, forca := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/objeto_luz.gdshader")
	m.set_shader_parameter("metalico", metalico); m.set_shader_parameter("rugosidade", rugosidade)
	m.set_shader_parameter("emissao", Vector3(emissao.r, emissao.g, emissao.b)); m.set_shader_parameter("emissao_forca", forca)
	materiais.append(m)
	return m

## Liga a névoa de guerra em todos os materiais da masmorra.
func set_nevoa(tex: Texture2D, tam: Vector2) -> void:
	for m in materiais:
		m.set_shader_parameter("nevoa_tex", tex); m.set_shader_parameter("nevoa_tam", tam)

## Tochas de parede: a luz delas sempre aparece, mesmo onde ninguém do grupo viu ainda (a claridade
## vaza por portas, grades e corredores, como numa masmorra de verdade).
## O objeto da tocha (cabo, chama e faíscas) só aparece depois de visto, para não flutuar no escuro.
func atualizar_tochas(exploradas: Dictionary, mestre_: bool) -> void:
	for i in tochas_nos.size():
		var visto: bool = mestre_ or exploradas.has(tochas_cel[i])
		for c in tochas_nos[i].get_children():
			if not c is Light3D: c.visible = visto

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

## Tocha na mão de um personagem: luz quente de 9 m que o acompanha.
func set_tocha(a: Node3D, acesa: bool) -> void:
	if not luzes_tocha.has(a):
		var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.72, 0.42); l.light_energy = 0.9
		l.omni_range = 9.0; l.omni_attenuation = 1.5; _raiz.add_child(l); _sombra_suave(l)
		luzes_tocha[a] = l
	luzes_tocha[a].visible = acesa
	if acesa: luzes_tocha[a].global_position = a.global_position + Vector3(0.4, 1.6, 0.3)

func set_grade(combate: bool) -> void:
	chao_mat.set_shader_parameter("grade_forca", 0.6 if combate else 0.12)

func _process(_dt: float) -> void:
	if alvo == null: return
	var p := alvo.global_position
	for a in luzes_tocha:
		if is_instance_valid(a): luzes_tocha[a].global_position = a.global_position + Vector3(0.4, 1.6, 0.3)
	# Orçamento de sombras: só as tochas mais próximas
	var ordem := tochas.filter(func(l): return l.is_visible_in_tree())
	ordem.sort_custom(func(a, b): return a.global_position.distance_squared_to(p) < b.global_position.distance_squared_to(p))
	for i in ordem.size():
		ordem[i].shadow_enabled = i < SOMBRAS_MAX
	for l in tochas:
		if not l.is_visible_in_tree(): l.shadow_enabled = false
