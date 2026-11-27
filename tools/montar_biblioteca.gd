extends SceneTree
## Extrai a biblioteca de animações de um personagem de referência (já convertida para o esqueleto dele
## por tools/montar_personagem.gd) e grava como AnimationLibrary única da categoria. As trilhas passam a
## apontar para "Skeleton3D:<osso>", e o jogo põe o AnimationPlayer no pai do esqueleto.
## Uso: godot --headless --path . --script tools/montar_biblioteca.gd -- <ref-biblioteca.glb> <saida.res> [anim,anim,...]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n: Node = load(a[0]).instantiate()
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	var so: Array = a[2].split(",") if a.size() > 2 and a[2] != "" else []
	var lib := AnimationLibrary.new()
	for nome in ap.get_animation_list():
		if not so.is_empty() and not so.has(nome): continue
		var an: Animation = ap.get_animation(nome).duplicate(true)
		for t in an.get_track_count():
			var osso := an.track_get_path(t).get_concatenated_subnames()
			an.track_set_path(t, NodePath("Skeleton3D:" + osso))
		lib.add_animation(nome, an)
	var err := ResourceSaver.save(lib, a[1], ResourceSaver.FLAG_COMPRESS)
	print("biblioteca=%s animações=%d erro=%d" % [a[1], lib.get_animation_list().size(), err])
	quit()
