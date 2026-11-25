extends SceneTree
## Quadros de uma animação num intervalo de tempo (para achar soltura, auge, impacto).
## Uso: godot --path . --script tools/quadros_tempo.gd -- <glb> <anim> <t0> <t1> <passo> <saida.png> [angulo] [escala]
const TAM := Vector2i(260, 340)
func _init(): _run.call_deferred()
func _run():
	var a := OS.get_cmdline_user_args()
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var t: Node3D = load(a[0]).instantiate(); vp.add_child(t)
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.86, 0.86); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.7; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 35; vp.add_child(cam); cam.current = true
	var ang := deg_to_rad(float(a[6]) if a.size() > 6 else 60.0)
	cam.position = Vector3(sin(ang), 0.35, cos(ang)) * 3.0 + Vector3(0, 0.75, 0); cam.look_at(Vector3(0, 0.75, 0))
	var t0 := float(a[2]); var t1 := float(a[3]); var p := float(a[4])
	var n := int((t1 - t0) / p) + 1
	var folha := Image.create(TAM.x * n, TAM.y, false, Image.FORMAT_RGBA8)
	ap.play(a[1]); ap.pause()
	for i in n:
		ap.seek(t0 + i * p, true)
		for _f in 3: await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
		folha.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * i, 0))
	folha.save_png(a[5]); quit()
