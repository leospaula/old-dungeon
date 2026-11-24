extends SceneTree
## Tira de quadros da sequência golpe -> queda, em tempo real, como no jogo.
## Uso: godot --path . --script tools/ver_morte.gd -- <glb> <saida.png> [inicio_morrer] [dano_antes]
const TAM := Vector2i(240, 320)
const N := 10
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var ini := float(a[2]) if a.size() > 2 else 0.85
	var antes := float(a[3]) if a.size() > 3 else 0.28
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var t: Node3D = load(a[0]).instantiate(); vp.add_child(t)
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7; vp.add_child(env)
	var cam := Camera3D.new(); cam.fov = 40; vp.add_child(cam); cam.current = true
	cam.position = Vector3(2.6, 1.0, 0.4); cam.look_at(Vector3(0, 0.4, 0))
	ap.play("parado-espada-escudo"); for _f in 10: await process_frame
	var folha := Image.create(TAM.x * N, TAM.y, false, Image.FORMAT_RGBA8)
	ap.play("levar-golpe", 0.05)
	var t0 := Time.get_ticks_msec(); var trocou := false; var i := 0
	while i < N:
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		if not trocou and dt >= antes:
			ap.play("morrer", 0.3); ap.seek(ini, false); trocou = true
		if dt >= i * 0.18:
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			folha.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * i, 0)); i += 1
		await process_frame
	folha.save_png(a[1]); print("ok"); quit()
