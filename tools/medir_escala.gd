extends SceneTree
const Luz = preload("res://scripts/visual/luz.gd")
func _init() -> void:
	var cfg := {"tessa": ["res://arte/final/3d/norm/tessa-heroica.glb", 1.5], "caco": ["res://arte/final/3d/norm/caco.glb", 0.9], "lianne": ["res://arte/final/3d/norm/lianne.glb", 0.86],
		"durgo (anão)": ["res://arte/final/3d/norm/anao.glb", 0.9], "mirela": ["res://arte/final/3d/norm/maga.glb", 0.9], "anselmo": ["res://arte/final/3d/norm/clerigo.glb", 0.9],
		"bento (halfling)": ["res://arte/final/3d/norm/halfling.glb", 0.9], "prisioneiro": ["res://arte/final/3d/norm/prisioneiro.glb", 0.9], "hobgoblin": ["res://arte/final/3d/norm/hobgoblin.glb", 0.9],
		"goblin": ["res://arte/final/3d/norm/goblin.glb", 0.9], "guarda": ["res://arte/final/3d/norm/guarda.glb", 0.9]}
	var cri: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/animacoes.json")).get("criaturas", {})
	for k in cri:
		if cri[k] is Dictionary and cri[k].has("modelo"):
			for n in cfg:
				if cfg[n][0] == str(cri[k].modelo): cfg[n][1] = float(cri[k].get("escala", 0.9))
	for n in cfg:
		var m: Node3D = load(cfg[n][0]).instantiate()
		var c: AABB = Luz.caixa_local(m)
		print("%-18s altura %.2f m (modelo %.2f × escala %.2f)" % [n, c.size.y * cfg[n][1], c.size.y, cfg[n][1]])
	for f in ["res://arte/final/3d/porta.glb", "res://arte/final/3d/porta-dupla.glb", "res://arte/final/3d/tocha-parede.glb"]:
		var m2: Node3D = load(f).instantiate(); var c2: AABB = Luz.caixa_local(m2)
		print(f.get_file(), " caixa original ", c2.size)
	# Masmorra: paredes e caixas das portas/grades.
	var mz: Node3D = load("res://scenes/masmorra/masmorra_base.scn").instantiate()
	for g in mz.get_children():
		var ms := g.find_children("*", "MeshInstance3D", true, false)
		if ms.is_empty(): continue
		var tot := AABB(); var pri := true
		for mi in ms:
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb() if mi.is_inside_tree() else _glob(mi) * (mi as MeshInstance3D).get_aabb()
			tot = b if pri else tot.merge(b); pri = false
		print("%-12s %d malhas · altura de %.2f a %.2f m" % [g.name, ms.size(), tot.position.y, tot.end.y])
	var portas := mz.get_node_or_null("Portas")
	if portas:
		for no in portas.get_children():
			if str(no.name) in ["P17", "P01", "P03"]:
				for p in no.get_children():
					var m: MeshInstance3D = p.get_node_or_null("Malha")
					if m: print(no.name, "/", p.name, " tipo=", no.get_meta("tipo", "?"), " caixa ", m.get_aabb().size)
	quit()

func _glob(n: Node3D) -> Transform3D:
	var t := n.transform; var p := n.get_parent()
	while p is Node3D: t = (p as Node3D).transform * t; p = p.get_parent()
	return t
