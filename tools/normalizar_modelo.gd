extends SceneTree
## Normaliza um personagem (rig Mixamo do Tripo) para o repouso de um esqueleto de referência, para que
## uma biblioteca de animações única sirva para todos da mesma categoria (scripts/visual/bibliotecas.gd).
##
## 1. Converte o repouso da referência para o modelo (tools/retarget.gd, pela direção dos ossos) e
##    aplica essa pose: os ossos do modelo passam a apontar como os da referência.
## 2. Fixa a malha nessa pose (bake) e grava o novo repouso de cada osso com a orientação da referência
##    (a posição continua a do modelo). A pele (bind) é refeita, então a malha não muda.
## 3. Exporta o .glb sem animações. As animações da referência servem direto; a diferença de altura vai
##    em Skeleton3D.motion_scale (quadril do modelo ÷ quadril da referência).
##
## Uso: godot --headless --path . --script tools/normalizar_modelo.gd -- <ref.glb> <modelo.glb> <saida.glb>

const Retarget = preload("res://tools/retarget.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var ref := _carregar(a[0]); root.add_child(ref)
	var mod := _carregar(a[1]); root.add_child(mod)
	for _f in 3: await process_frame
	var sk_r := _achar(ref, "Skeleton3D") as Skeleton3D
	var sk := _achar(mod, "Skeleton3D") as Skeleton3D
	var base_r := Retarget.base_personagem(sk_r); var base_m := Retarget.base_personagem(sk)
	print("frente ref=", base_r.z, " modelo=", base_m.z)

	# 1. Repouso da referência como animação de 1 quadro, convertido para o modelo.
	var repouso := Animation.new(); repouso.length = 1.0 / Retarget.FPS
	for i in sk_r.get_bone_count():
		var t := repouso.add_track(Animation.TYPE_ROTATION_3D)
		repouso.track_set_path(t, NodePath("Skeleton3D:" + sk_r.get_bone_name(i)))
		repouso.track_insert_key(t, 0.0, sk_r.get_bone_rest(i).basis.get_rotation_quaternion())
		repouso.track_insert_key(t, repouso.length, sk_r.get_bone_rest(i).basis.get_rotation_quaternion())
	var hips_r := sk_r.find_bone("mixamorig_Hips")
	var tp := repouso.add_track(Animation.TYPE_POSITION_3D)
	repouso.track_set_path(tp, NodePath("Skeleton3D:mixamorig_Hips"))
	repouso.track_insert_key(tp, 0.0, sk_r.get_bone_rest(hips_r).origin)
	repouso.track_insert_key(tp, repouso.length, sk_r.get_bone_rest(hips_r).origin)
	var conv: Animation = Retarget.converter(repouso, sk_r, sk, "Skeleton3D", false)
	for t in conv.get_track_count():
		var osso := sk.find_bone(conv.track_get_path(t).get_concatenated_subnames())
		if osso < 0: continue
		if conv.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(osso, conv.rotation_track_interpolate(t, 0.0))
	sk.force_update_all_bone_transforms()
	for _f in 2: await process_frame

	# Transformação malha -> espaço do esqueleto (igual para todos os ossos no bind antigo).
	var malhas: Array = []
	for n in mod.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null: malhas.append(n)

	# 2. Bake da malha na pose e novo repouso com a orientação da referência.
	var novo_global := {}
	for i in sk.get_bone_count():
		var j := sk_r.find_bone(sk.get_bone_name(i))
		var b: Basis = (base_m * base_r.inverse()) * sk_r.get_bone_global_rest(j).basis if j >= 0 else sk.get_bone_global_pose(i).basis
		novo_global[i] = Transform3D(b.orthonormalized(), sk.get_bone_global_pose(i).origin)
	for mi in malhas:
		var skin: Skin = mi.skin
		var binds := []   # índice do bind -> índice do osso
		for k in skin.get_bind_count():
			var nome := skin.get_bind_name(k)
			binds.append(sk.find_bone(nome) if nome != "" else skin.get_bind_bone(k))
		mi.mesh = _bake(mi.mesh, skin, binds, sk)
		var nova := Skin.new()
		for k in binds.size():
			nova.add_named_bind(sk.get_bone_name(binds[k]), (novo_global[binds[k]] as Transform3D).affine_inverse())
		mi.skin = nova
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var local: Transform3D = (novo_global[p] as Transform3D).affine_inverse() * novo_global[i] if p >= 0 else novo_global[i]
		sk.set_bone_rest(i, local)
	sk.reset_bone_poses(); sk.force_update_all_bone_transforms()
	var hips := sk.find_bone("mixamorig_Hips")
	print("quadril: modelo=%.3f ref=%.3f escala=%.3f" % [sk.get_bone_global_rest(hips).origin.y, sk_r.get_bone_global_rest(hips_r).origin.y,
		sk.get_bone_global_rest(hips).origin.y / sk_r.get_bone_global_rest(hips_r).origin.y])

	# 3. Exporta.
	root.remove_child(mod)
	for ap in mod.find_children("*", "AnimationPlayer", true, false): ap.free()
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.image_format = "JPEG"; doc.lossy_quality = 0.85
	var err := doc.append_from_scene(mod, st)
	if err == OK: err = doc.write_to_filesystem(st, a[2])
	print("normalizado=%s erro=%d" % [a[2], err])
	quit()

## Skinning feito à mão (o bake do Godot precisa do servidor de render): cada vértice vai para a pose
## atual do esqueleto, no espaço do esqueleto. Os pesos e ossos continuam na malha.
func _bake(m: Mesh, skin: Skin, binds: Array, sk: Skeleton3D) -> ArrayMesh:
	var M := []
	for k in binds.size(): M.append(sk.get_bone_global_pose(binds[k]) * skin.get_bind_pose(k))
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var fmt: int = m.surface_get_format(s)
		var n_pesos := 8 if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var TG: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]; var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for v in V.size():
			var t := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
			for q in n_pesos:
				var w := W[v * n_pesos + q]
				if w <= 0.0: continue
				var mk: Transform3D = M[B[v * n_pesos + q]]
				t.basis.x += mk.basis.x * w; t.basis.y += mk.basis.y * w; t.basis.z += mk.basis.z * w; t.origin += mk.origin * w
			V[v] = t * V[v]
			if not N.is_empty(): N[v] = (t.basis * N[v]).normalized()
			if not TG.is_empty():
				var tv := (t.basis * Vector3(TG[v * 4], TG[v * 4 + 1], TG[v * 4 + 2])).normalized()
				TG[v * 4] = tv.x; TG[v * 4 + 1] = tv.y; TG[v * 4 + 2] = tv.z
		arr[Mesh.ARRAY_VERTEX] = V
		if not N.is_empty(): arr[Mesh.ARRAY_NORMAL] = N
		if not TG.is_empty(): arr[Mesh.ARRAY_TANGENT] = TG
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(s, m.surface_get_material(s))
	return out

func _carregar(c: String) -> Node3D:
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	if doc.append_from_file(c, st) != OK: push_error("falha ao abrir " + c); quit(1)
	return doc.generate_scene(st)

func _achar(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _achar(c, cls)
		if r: return r
	return null
