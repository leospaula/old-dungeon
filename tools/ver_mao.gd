extends SceneTree
## Close da mão direita (arma) em várias animações e ângulos, para conferir a empunhadura.
## Uso: godot --path . --script tools/ver_mao.gd -- <biblioteca.glb> <saida.png> [anim1,anim2,...] [distancia]
const TAM := Vector2i(320, 320)
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var anims: Array = (a[2] if a.size() > 2 else "parado-espada-escudo,golpe,andar").split(",")
	var dist: float = float(a[3]) if a.size() > 3 else 0.6
	var vp := SubViewport.new(); vp.size = TAM; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var t: Node3D = load(a[0]).instantiate(); vp.add_child(t)
	var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7; vp.add_child(env)
	var luz := DirectionalLight3D.new(); luz.rotation_degrees = Vector3(-40, 30, 0); vp.add_child(luz)
	var cam := Camera3D.new(); cam.fov = 40; vp.add_child(cam); cam.current = true
	var mao := sk.find_bone("mixamorig_RightHand")
	var angs := [0.0, 90.0, 180.0, 270.0]
	var folha := Image.create(TAM.x * angs.size(), TAM.y * anims.size(), false, Image.FORMAT_RGBA8)
	for li in anims.size():
		var nome: String = anims[li]
		var A := ap.get_animation(nome)
		ap.play(nome); ap.seek(A.length * 0.3, true); ap.pause()
		for _f in 3: await process_frame
		var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(mao)).origin
		for ci in angs.size():
			var r := deg_to_rad(angs[ci])
			cam.position = p + Vector3(sin(r), 0.25, cos(r)).normalized() * dist; cam.look_at(p)
			for _f in 2: await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			folha.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * ci, TAM.y * li))
	folha.save_png(a[1]); print("ok ", a[1])
	quit()
