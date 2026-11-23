extends SceneTree
## Compara o esqueleto de um modelo com as trilhas de uma animação (FBX ou glTF).
## Uso: godot --headless --path . --script tools/inspecionar_anim.gd -- <modelo.glb> <animacao.fbx>

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var modelo := _carregar(a[0])
	var anim := _carregar(a[1])
	var sk := _achar(modelo, "Skeleton3D") as Skeleton3D
	print("MODELO esqueleto=", modelo.get_path_to(sk), " ossos=", sk.get_bone_count())
	var h := sk.find_bone("mixamorig_Hips")
	print("  Hips rest=", sk.get_bone_rest(h).origin, " cadeia=", _cadeia(sk))
	var sk2 := _achar(anim, "Skeleton3D") as Skeleton3D
	if sk2:
		var h2 := sk2.find_bone("mixamorig_Hips")
		print("ANIM esqueleto=", anim.get_path_to(sk2), " ossos=", sk2.get_bone_count(), " Hips rest=", sk2.get_bone_rest(h2).origin, " cadeia=", _cadeia(sk2))
	var ap := _achar(anim, "AnimationPlayer") as AnimationPlayer
	for n in ap.get_animation_list():
		var an := ap.get_animation(n)
		print("ANIM '", n, "' duração=", an.length, " trilhas=", an.get_track_count())
		var faltando := []
		for i in an.get_track_count():
			var p := an.track_get_path(i)
			if i < 4: print("  trilha ", i, " tipo=", an.track_get_type(i), " ", p, " 1º valor=", an.track_get_key_value(i, 0))
			var osso := p.get_concatenated_subnames()
			if osso != "" and sk.find_bone(osso) < 0: faltando.append(osso)
		print("  ossos da animação ausentes no modelo: ", faltando.size(), " ", faltando.slice(0, 8))
	quit()

func _carregar(c: String) -> Node:
	var doc = FBXDocument.new() if c.ends_with(".fbx") else GLTFDocument.new()
	var st = FBXState.new() if c.ends_with(".fbx") else GLTFState.new()
	var err = doc.append_from_file(c, st)
	assert(err == OK, "falha ao abrir " + c)
	var n: Node = doc.generate_scene(st)
	root.add_child(n)
	return n

func _achar(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _achar(c, cls)
		if r: return r
	return null

func _cadeia(n: Node) -> String:
	var out := []
	while n:
		if n is Node3D: out.append("%s%s" % [n.name, (n as Node3D).scale])
		n = n.get_parent()
	return " < ".join(out)
