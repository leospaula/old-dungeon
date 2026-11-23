extends SceneTree
## Renderiza um .glb em 4 ângulos (0°, 90°, 180°, 270°) numa tira PNG.
## Uso:
##   godot --path . --script tools/render_glb.gd -- <entrada.glb> <saida.png>
## Precisa de janela (não funciona com --headless, que não renderiza).

const TAM := Vector2i(400, 560)
const ANGULOS := [0.0, 90.0, 180.0, 270.0]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("uso: -- <entrada.glb> <saida.png>")
		quit(1)
		return
	var vp := SubViewport.new()
	vp.size = TAM
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(args[0], st)
	if err != OK:
		push_error("falha ao abrir %s: %s" % [args[0], err])
		quit(1)
		return
	var modelo: Node3D = doc.generate_scene(st)
	vp.add_child(modelo)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.88, 0.88, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(luz)

	await process_frame
	var caixa := _aabb(modelo)
	var centro := caixa.get_center()
	var dist := maxf(caixa.size.y, maxf(caixa.size.x, caixa.size.z)) * 1.7
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.current = true

	var tira := Image.create(TAM.x * ANGULOS.size(), TAM.y, false, Image.FORMAT_RGBA8)
	for i in ANGULOS.size():
		var a := deg_to_rad(ANGULOS[i])
		cam.position = centro + Vector3(sin(a), 0.15, cos(a)) * dist
		cam.look_at(centro)
		for _f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		tira.blit_rect(img, Rect2i(Vector2i.ZERO, TAM), Vector2i(TAM.x * i, 0))

	tira.save_png(args[1])
	print("tris=%d altura=%.2f salvo=%s" % [_tris(modelo), caixa.size.y, args[1]])
	quit()


func _aabb(n: Node) -> AABB:
	var caixa := AABB()
	var primeiro := true
	# Malha com esqueleto: a AABB da malha vem no espaço de bind; usar os ossos.
	for sk in _esqueletos(n):
		for i in sk.get_bone_count():
			var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
			caixa = AABB(p, Vector3.ZERO) if primeiro else caixa.expand(p)
			primeiro = false
	if not primeiro:
		return caixa.grow(caixa.size.y * 0.12)
	for m in _malhas(n):
		var b: AABB = m.global_transform * m.get_aabb()
		caixa = b if primeiro else caixa.merge(b)
		primeiro = false
	return caixa


func _tris(n: Node) -> int:
	var total := 0
	for m in _malhas(n):
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			total += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return total


func _malhas(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_malhas(c))
	return out


func _esqueletos(n: Node) -> Array:
	var out := []
	if n is Skeleton3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_esqueletos(c))
	return out
