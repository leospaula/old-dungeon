extends SceneTree
## Monta um personagem com itens presos aos ossos e uma animação externa (FBX/glTF do Mixamo),
## e renderiza quadros da animação numa tira PNG.
## Uso: godot --path . --script tools/montar_personagem.gd -- <montagem.json> <animacao.fbx> <saida.png> [angulo] [exportar.glb]
## O JSON define o modelo e os itens: osso, comprimento (m), pega (ponto 0–1 da caixa do item que vai no osso),
## posicao (m, no espaço do osso) e rotacao (graus XYZ).

const TAM := Vector2i(360, 480)
const QUADROS := 6

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var angulo := float(a[3]) if a.size() > 3 else 35.0
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)

	var pers := _carregar(cfg.modelo); vp.add_child(pers)
	var sk := _achar(pers, "Skeleton3D") as Skeleton3D
	for it in cfg.itens:
		var ba := BoneAttachment3D.new(); ba.bone_name = it.osso; sk.add_child(ba)
		var item := _carregar(it.arquivo)
		var caixa := _aabb(item)
		var esc: float = it.comprimento / maxf(caixa.size.y, maxf(caixa.size.x, caixa.size.z))
		var pega: Vector3 = caixa.position + caixa.size * Vector3(it.pega[0], it.pega[1], it.pega[2])
		var piv := Node3D.new(); ba.add_child(piv)
		piv.position = Vector3(it.posicao[0], it.posicao[1], it.posicao[2])
		piv.rotation_degrees = Vector3(it.rotacao[0], it.rotacao[1], it.rotacao[2])
		piv.add_child(item); item.scale = Vector3.ONE * esc; item.position = -pega * esc

	# Animação externa: copia as trilhas para o AnimationPlayer do personagem, ajustando o caminho
	# do esqueleto e a altura do quadril.
	var fonte := _carregar(a[1])
	var ap_f := _achar(fonte, "AnimationPlayer") as AnimationPlayer
	var anim: Animation = ap_f.get_animation(ap_f.get_animation_list()[0]).duplicate()
	var sk_f := _achar(fonte, "Skeleton3D") as Skeleton3D
	var h := "mixamorig_Hips"
	var razao := sk.get_bone_rest(sk.find_bone(h)).origin.y / sk_f.get_bone_rest(sk_f.find_bone(h)).origin.y
	var caminho := str(pers.get_path_to(sk))
	for i in anim.get_track_count():
		var osso := anim.track_get_path(i).get_concatenated_subnames()
		anim.track_set_path(i, NodePath(caminho + ":" + osso))
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				anim.track_set_key_value(i, k, anim.track_get_key_value(i, k) * razao)
	var ap := AnimationPlayer.new(); pers.add_child(ap); ap.root_node = ap.get_path_to(pers)
	var lib := AnimationLibrary.new(); lib.add_animation("golpe", anim); ap.add_animation_library("", lib)
	ap.play("golpe"); ap.pause()

	if a.size() > 4:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		doc.image_format = "JPEG"; doc.lossy_quality = 0.85
		var err := doc.append_from_scene(pers, st)
		if err == OK: err = doc.write_to_filesystem(st, a[4])
		print("exportado=%s erro=%d" % [a[4], err])
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.88, 0.88, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 40; vp.add_child(cam); cam.current = true
	var centro := Vector3(0, 0.95, 0)
	var r := deg_to_rad(angulo)
	cam.position = centro + Vector3(sin(r), 0.2, cos(r)) * 3.6; cam.look_at(centro)

	var tira := Image.create(TAM.x * QUADROS, TAM.y, false, Image.FORMAT_RGBA8)
	for i in QUADROS:
		ap.seek(anim.length * i / (QUADROS - 1), true)
		for _f in 3: await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
		tira.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * i, 0))
	tira.save_png(a[2])
	print("ok duração=%.2f razão_quadril=%.3f salvo=%s" % [anim.length, razao, a[2]])
	quit()

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
