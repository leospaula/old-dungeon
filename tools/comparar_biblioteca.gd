extends SceneTree
## Compara, quadro a quadro, um personagem com a biblioteca própria (antiga) e o mesmo personagem
## normalizado usando a biblioteca compartilhada. Tira PNG: linha de cima antigo, de baixo novo.
## Uso: godot --path . --script tools/comparar_biblioteca.gd -- <antigo-biblioteca.glb> <norm.glb> <lib.res> <escala_mov> <saida.png> anim,anim
const TAM := Vector2i(240, 320)
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var anims: PackedStringArray = a[5].split(",")
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.85, 0.85); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.7; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 40; vp.add_child(cam); cam.position = Vector3(3.2, 1.2, 1.6); cam.look_at(Vector3(0, 0.7, 0))
	var velho: Node3D = load(a[0]).instantiate(); var ap_v: AnimationPlayer = velho.find_children("*", "AnimationPlayer", true, false)[0]
	var novo: Node3D = load(a[1]).instantiate()
	var sk: Skeleton3D = novo.find_children("*", "Skeleton3D", true, false)[0]
	sk.motion_scale = float(a[3])
	var ap_n := AnimationPlayer.new(); sk.get_parent().add_child(ap_n); ap_n.add_animation_library("", load(a[2]))
	var tiras := Image.create(TAM.x * anims.size() * 3, TAM.y * 2, false, Image.FORMAT_RGBA8)
	for linha in 2:
		var pers: Node3D = velho if linha == 0 else novo
		var ap: AnimationPlayer = ap_v if linha == 0 else ap_n
		vp.add_child(pers)
		for i in anims.size():
			var an: Animation = ap.get_animation(anims[i])
			ap.play(anims[i]); ap.pause()
			for q in 3:
				ap.seek(an.length * (q + 0.5) / 3.0, true)
				for _f in 3: await process_frame
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
				tiras.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * (i * 3 + q), TAM.y * linha))
		vp.remove_child(pers)
	tiras.save_png(a[4]); print("ok ", a[4]); quit()
