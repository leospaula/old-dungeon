extends SceneTree
## Monta um personagem com itens presos aos ossos e uma biblioteca de animações do Mixamo
## (retarget pela direção dos ossos, ver tools/retarget.gd). Renderiza uma tira de quadros por
## animação e, opcionalmente, exporta tudo num único GLB (texturas JPEG).
##
## Uso: godot --path . --script tools/montar_personagem.gd -- <montagem.json> <pasta_quadros> [exportar.glb]
##
## O JSON define:
##   modelo      caminho do .glb do personagem (com esqueleto Mixamo)
##   itens       [{arquivo, osso, modo: "arma"|"escudo", comprimento (m), pega [0–1]×3,
##                 ao_longo (fração do osso), afastar (m), rotacao [graus]}]
##   animacoes   {"nome": "arquivo.fbx", ...}
##   no_lugar    [nomes] animações cujo avanço horizontal é removido (andar, correr…)
##   angulo      ângulo da câmera nos quadros (graus, opcional)

const Retarget = preload("res://tools/retarget.gd")
const TAM := Vector2i(360, 480)
const QUADROS := 6

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var pasta: String = a[1]
	DirAccess.make_dir_recursive_absolute(pasta)
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)

	var pers := _carregar(cfg.modelo); vp.add_child(pers)
	var sk := _achar(pers, "Skeleton3D") as Skeleton3D
	_montar_itens(sk, cfg.itens)

	var ap := AnimationPlayer.new(); pers.add_child(ap); ap.root_node = ap.get_path_to(pers)
	var lib := AnimationLibrary.new(); ap.add_animation_library("", lib)
	var caminho_sk := str(pers.get_path_to(sk))
	var nomes: Array = cfg.animacoes.keys()
	for nome in nomes:
		var fonte := _carregar(cfg.animacoes[nome])
		var ap_f := _achar(fonte, "AnimationPlayer") as AnimationPlayer
		var anim_f: Animation = ap_f.get_animation(ap_f.get_animation_list()[0])
		var sk_f := _achar(fonte, "Skeleton3D") as Skeleton3D
		var anim: Animation = Retarget.converter(anim_f, sk_f, sk, caminho_sk, nome in cfg.get("no_lugar", []))
		anim.loop_mode = Animation.LOOP_LINEAR if (nome as String).begins_with("parado") or nome == "andar" else Animation.LOOP_NONE
		lib.add_animation(nome, anim)
		fonte.free()

	if a.size() > 2:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		doc.image_format = "JPEG"; doc.lossy_quality = 0.85
		var err := doc.append_from_scene(pers, st)
		if err == OK: err = doc.write_to_filesystem(st, a[2])
		print("exportado=%s erro=%d" % [a[2], err])

	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.88, 0.88, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 40; vp.add_child(cam); cam.current = true

	# Câmera em 3/4 pela frente da personagem.
	var base := Retarget.base_personagem(sk)
	var r := deg_to_rad(float(cfg.get("angulo", 35.0)))
	var dir: Vector3 = (base.z * cos(r) + base.x * sin(r)).normalized()
	var centro := Vector3(0, 0.95, 0)
	cam.position = centro + dir * 3.8 + Vector3(0, 0.6, 0); cam.look_at(centro)

	for nome in nomes:
		var anim := lib.get_animation(nome)
		ap.play(nome); ap.pause()
		var tira := Image.create(TAM.x * QUADROS, TAM.y, false, Image.FORMAT_RGBA8)
		for i in QUADROS:
			ap.seek(anim.length * i / (QUADROS - 1), true)
			for _f in 3: await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			tira.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * i, 0))
		tira.save_png(pasta.path_join(nome + ".png"))
		print("ok %s duração=%.2f" % [nome, anim.length])
	quit()

func _montar_itens(sk: Skeleton3D, itens: Array) -> void:
	var base := Retarget.base_personagem(sk)   # X = esquerda, Y = cima, Z = frente
	for it in itens:
		var i_osso := sk.find_bone(it.osso)
		var g_osso := sk.get_bone_global_rest(i_osso)
		var f := Retarget.filho_preferido(sk, i_osso)
		var dir := sk.get_bone_global_rest(f).origin - g_osso.origin
		var ba := BoneAttachment3D.new(); ba.bone_name = it.osso; sk.add_child(ba)
		var item := _carregar(it.arquivo)
		var caixa := _aabb(item)
		var esc: float = it.comprimento / maxf(caixa.size.y, maxf(caixa.size.x, caixa.size.z))
		var pega: Vector3 = caixa.position + caixa.size * Vector3(it.pega[0], it.pega[1], it.pega[2])
		var lado: float = 1.0 if (it.osso as String).contains("Left") else -1.0
		var y_alvo: Vector3; var x_alvo: Vector3
		if it.modo == "escudo":
			# Plano do escudo paralelo ao antebraço, face para fora do corpo.
			y_alvo = dir.normalized()
			x_alvo = (base.x * lado - y_alvo * y_alvo.dot(base.x * lado)).normalized()
		else:
			# Arma na mão: lâmina para a frente da personagem.
			y_alvo = base.z
			x_alvo = base.x * lado
		var ponto: Vector3 = g_osso.origin + dir * float(it.ao_longo) + x_alvo * float(it.afastar)
		var z_alvo := x_alvo.cross(y_alvo).normalized(); x_alvo = y_alvo.cross(z_alvo).normalized()
		var piv := Node3D.new(); ba.add_child(piv)
		piv.transform = g_osso.affine_inverse() * Transform3D(Basis(x_alvo, y_alvo, z_alvo), ponto)
		var giro := Node3D.new(); piv.add_child(giro)
		giro.rotation_degrees = Vector3(it.rotacao[0], it.rotacao[1], it.rotacao[2])
		giro.add_child(item); item.scale = Vector3.ONE * esc; item.position = -pega * esc

func _carregar(c: String) -> Node3D:
	var fbx := c.ends_with(".fbx")
	var doc = FBXDocument.new() if fbx else GLTFDocument.new()
	var st = FBXState.new() if fbx else GLTFState.new()
	if doc.append_from_file(c, st) != OK: push_error("falha ao abrir " + c); quit(1)
	return doc.generate_scene(st)

func _achar(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _achar(c, cls)
		if r: return r
	return null

func _aabb(n: Node) -> AABB:
	var caixa := AABB(); var primeiro := true
	var pilha := [[n, Transform3D.IDENTITY]]
	while pilha:
		var par = pilha.pop_back(); var no: Node = par[0]; var t: Transform3D = par[1]
		if no is Node3D: t = t * (no as Node3D).transform
		if no is MeshInstance3D and no.mesh:
			var b: AABB = t * no.mesh.get_aabb()
			caixa = b if primeiro else caixa.merge(b); primeiro = false
		for c in no.get_children(): pilha.append([c, t])
	return caixa
