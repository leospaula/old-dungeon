extends SceneTree
## Confere as armas na mão: para cada item com modelo3d e estilo, monta na personagem (como no jogo) e
## renderiza a guarda e o instante do golpe (ou da soltura), de frente e de lado.
## Uso: godot --path . --script tools/ver_armas.gd -- <biblioteca.glb> <escala> <saida.png> [item1,item2,...]

const Armas3D = preload("res://scripts/visual/armas3d.gd")
const TAM := Vector2i(240, 300)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var esc := float(a[1])
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalogos/itens.json")).itens
	var est: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/estilos.json"))
	var ids: Array = a[3].split(",") if a.size() > 3 else cat.keys().filter(func(k): return cat[k].has("estilo") and cat[k].has("modelo3d"))
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.86, 0.86, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 38; vp.add_child(cam); cam.current = true
	var colunas := 4
	var folha := Image.create(TAM.x * colunas, TAM.y * ids.size(), false, Image.FORMAT_RGBA8)
	for li in ids.size():
		var id: String = ids[li]
		var t: Node3D = load(a[0]).instantiate(); t.scale = Vector3.ONE * esc; vp.add_child(t)
		var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
		var e: Dictionary = est.estilos.get(cat[id].estilo, {})
		Armas3D.montar(sk, ap, cat[id].modelo3d, esc)
		var golpe: String = e.get("atirar", e.get("golpe", "golpe"))
		var tg: float = float(est.solta.get(golpe, est.impactos.get(golpe, 0.8)))
		var casos := [[e.get("parado_combate", "parado"), 0.5, 0.0], [e.get("parado_combate", "parado"), 0.5, 90.0], [golpe, tg, 0.0], [golpe, tg, 90.0]]
		for ci in casos.size():
			var c: Array = casos[ci]
			ap.play(c[0]); ap.seek(minf(float(c[1]), ap.get_animation(c[0]).length), true); ap.pause()
			var r := deg_to_rad(float(c[2]) + 35.0)
			cam.position = Vector3(sin(r), 0.3, cos(r)) * 3.4 * esc / 1.5 + Vector3(0, 0.85 * esc / 1.5, 0)
			cam.look_at(Vector3(0, 0.8 * esc / 1.5, 0))
			for _f in 4: await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			folha.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * ci, TAM.y * li))
		print("ok ", id)
		t.queue_free(); await process_frame
	folha.save_png(a[2]); print("salvo ", a[2])
	quit()
