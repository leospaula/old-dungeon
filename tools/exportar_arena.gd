extends SceneTree
## Exporta para a Arena do ateliê (atelie/arena/dados.json) como cada arma/escudo fica preso em cada
## personagem, com a mesma conta do jogo (scripts/visual/armas3d.gd). Matrizes em coluna (three.js).
## Uso: godot --headless --path . --script tools/exportar_arena.gd -- atelie/arena/dados.json

const Armas3D = preload("res://scripts/visual/armas3d.gd")
const PERS := {
	"tessa": {"nome": "Tessa (guerreira)", "glb": "res://arte/final/3d/tessa-heroica-biblioteca.glb", "escala": 1.5, "modelo": "arena/tessa.gltf.json"},
	"caco": {"nome": "Caco (ladrão)", "glb": "res://arte/final/3d/caco-biblioteca.glb", "escala": 0.9, "modelo": "arena/caco.gltf.json"},
	"lianne": {"nome": "Lianne (elfa)", "glb": "res://arte/final/3d/lianne-biblioteca.glb", "escala": 0.86, "modelo": "arena/lianne.gltf.json"},
}

func _init() -> void:
	_run.call_deferred()

func _m(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, 0, b.y.x, b.y.y, b.y.z, 0, b.z.x, b.z.y, b.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]

func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _run() -> void:
	var saida: String = OS.get_cmdline_user_args()[0]
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalogos/itens.json")).itens
	var est: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/estilos.json"))
	var out := {"personagens": {}, "itens": {}, "montagens": {}, "estilos": est, "modelos_itens": {}}
	for id in cat:
		var it: Dictionary = cat[id]
		if not it.has("modelo3d"): continue
		var arq := str(it.modelo3d.arquivo).get_file().get_basename()
		out.itens[id] = {"nome": it.nome, "tipo": it.tipo, "estilo": it.get("estilo", ""), "maos": int(it.get("maos", 1)),
			"icone": it.get("icone", ""), "modelo": arq}
		out.modelos_itens[arq] = "arena/itens/%s.gltf.json" % arq
	for p in PERS:
		var cfg: Dictionary = PERS[p]
		var t: Node3D = load(cfg.glb).instantiate(); root.add_child(t)
		var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
		var cab := sk.find_bone("mixamorig_Head")
		var frente: Vector3 = Armas3D._frente(sk)
		out.personagens[p] = {"nome": cfg.nome, "modelo": cfg.modelo, "escala": cfg.escala, "frente": _v(frente),
			"olhar_local": _v(sk.get_bone_global_rest(cab).basis.inverse() * frente), "animacoes": Array(ap.get_animation_list())}
		out.montagens[p] = {}
		for id in out.itens:
			var m: Dictionary = cat[id].modelo3d
			var ba: Node3D = Armas3D.montar(sk, ap, m, float(cfg.escala))
			if ba == null: continue
			var piv: Node3D = ba.get_child(0)
			var giro: Node3D = piv.get_child(0)
			var item: Node3D = giro.get_child(0)
			var d := {"osso": str(ba.bone_name), "piv": _m(piv.transform), "resto": _m(giro.transform * item.transform),
				"duas_maos": bool(m.get("duas_maos", false)), "ponta": str(m.get("ponta", "olhar")), "prumo": bool(m.get("prumo", false))}
			if piv.get("eixo_item") != null: d["eixo_item"] = _v(piv.eixo_item)
			for c in item.get_children():
				if c.get_script() != null and str(c.get_script().resource_path).contains("corda"):
					d["corda"] = {"a": _v(c._ponta_a), "b": _v(c._ponta_b)}
			out.montagens[p][id] = d
			ba.free()
		t.free()
		print("ok ", p)
	var f := FileAccess.open(saida, FileAccess.WRITE); f.store_string(JSON.stringify(out)); f.close()
	print("salvo ", saida)
	quit()
