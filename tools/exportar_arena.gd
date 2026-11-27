extends SceneTree
## Exporta para a Arena do ateliê (atelie/arena/dados.json) como cada arma/escudo fica preso em cada
## personagem, com a mesma conta do jogo (scripts/visual/armas3d.gd). Matrizes em coluna (three.js).
## Os modelos são os normalizados (arte/final/3d/norm/, sem animações) e as animações vêm da biblioteca
## da categoria (data/regras/animacoes.json), como no jogo. Também exporta os .glb dos modelos e das
## bibliotecas para atelie/arena/ (convertidos depois por tools/glb_para_gltf_json.py).
## Uso: godot --headless --path . --script tools/exportar_arena.gd -- atelie/arena/dados.json

const Armas3D = preload("res://scripts/visual/armas3d.gd")
const Bibliotecas = preload("res://scripts/visual/bibliotecas.gd")
const PERS := {
	"tessa": {"nome": "Tessa (guerreira)", "glb": "tessa-heroica", "escala": 1.5, "categoria": "pj", "grupo": "Personagens"},
	"durgo": {"nome": "Durgo (anão)", "glb": "anao", "escala": 0.9, "categoria": "pj", "grupo": "Personagens"},
	"caco": {"nome": "Caco (ladrão)", "glb": "caco", "escala": 0.9, "categoria": "pj", "grupo": "Personagens"},
	"lianne": {"nome": "Lianne (elfa)", "glb": "lianne", "escala": 0.86, "categoria": "pj", "grupo": "Personagens"},
	"mirela": {"nome": "Mirela (maga)", "glb": "maga", "escala": 0.9, "categoria": "pj", "grupo": "Personagens"},
	"anselmo": {"nome": "Anselmo (clérigo)", "glb": "clerigo", "escala": 0.9, "categoria": "pj", "grupo": "Personagens"},
	"bento": {"nome": "Bento (halfling)", "glb": "halfling", "escala": 0.9, "categoria": "pj", "grupo": "Personagens"},
	"hobgoblin": {"nome": "Hobgoblin", "glb": "hobgoblin", "escala": 0.9, "categoria": "humanoide_armado", "grupo": "Monstros e PNJ"},
	"goblin": {"nome": "Goblin", "glb": "goblin", "escala": 0.95, "categoria": "humanoide_armado", "grupo": "Monstros e PNJ"},
	"guarda": {"nome": "Guarda", "glb": "guarda", "escala": 0.9, "categoria": "humanoide_armado", "grupo": "Monstros e PNJ"},
	"prisioneiro": {"nome": "Prisioneiro", "glb": "prisioneiro", "escala": 0.9, "categoria": "humanoide_armado", "grupo": "Monstros e PNJ"},
}

func _init() -> void:
	_run.call_deferred()

## Exporta um nó como .glb (texturas JPEG).
func _glb(n: Node3D, arq: String) -> void:
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.image_format = "JPEG"; doc.lossy_quality = 0.8
	var err := doc.append_from_scene(n, st)
	if err == OK: err = doc.write_to_filesystem(st, arq)
	print("glb ", arq, " erro=", err)

func _m(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, 0, b.y.x, b.y.y, b.y.z, 0, b.z.x, b.z.y, b.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]

func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _run() -> void:
	var saida: String = OS.get_cmdline_user_args()[0]
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalogos/itens.json")).itens
	var est: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/estilos.json"))
	var anim: Dictionary = Bibliotecas.dados()
	var out := {"personagens": {}, "itens": {}, "montagens": {}, "estilos": est, "modelos_itens": {}, "bibliotecas": {}, "categorias": anim.categorias}
	var pasta := saida.get_base_dir()
	DirAccess.make_dir_recursive_absolute(pasta + "/modelos"); DirAccess.make_dir_recursive_absolute(pasta + "/bibliotecas")
	# Bibliotecas: o modelo de referência com a biblioteca (o three.js liga as trilhas pelo nome do osso).
	for b in anim.bibliotecas:
		var ref: Node3D = load(str(anim.bibliotecas[b].referencia).replace("res://arte/final/3d/", "res://arte/final/3d/norm/")).instantiate()
		root.add_child(ref)
		var cat_b := ""
		for c in anim.categorias:
			if str(anim.categorias[c].biblioteca) == b: cat_b = c; break
		Bibliotecas.preparar(ref, cat_b)
		_glb(ref, pasta + "/bibliotecas/%s.glb" % b)
		out.bibliotecas[b] = "arena/bibliotecas/%s.gltf.json" % b
		ref.free()
	for id in cat:
		var it: Dictionary = cat[id]
		if not it.has("modelo3d"): continue
		var arq := str(it.modelo3d.get("arquivo", "")).get_file().get_basename()
		out.itens[id] = {"nome": it.nome, "tipo": it.tipo, "estilo": it.get("estilo", ""), "maos": int(it.get("maos", 1)),
			"icone": it.get("icone", ""), "modelo": arq, "escudos": it.get("escudos", [])}
		if arq != "": out.modelos_itens[arq] = "arena/itens/%s.gltf.json" % arq
	for p in PERS:
		var cfg: Dictionary = PERS[p]
		var t: Node3D = load("res://arte/final/3d/norm/%s.glb" % cfg.glb).instantiate(); root.add_child(t)
		_glb(t, pasta + "/modelos/%s.glb" % p)
		var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = Bibliotecas.preparar(t, str(cfg.categoria))
		var cab := sk.find_bone("mixamorig_Head")
		var frente: Vector3 = Armas3D._frente(sk)
		var catg: Dictionary = anim.categorias[cfg.categoria]
		out.personagens[p] = {"nome": cfg.nome, "modelo": "arena/modelos/%s.gltf.json" % p, "escala": cfg.escala, "frente": _v(frente),
			"olhar_local": _v(sk.get_bone_global_rest(cab).basis.inverse() * frente), "animacoes": catg.animacoes,
			"categoria": cfg.categoria, "grupo": cfg.grupo, "biblioteca": catg.biblioteca, "escala_quadril": sk.motion_scale}
		out.montagens[p] = {}
		for id in out.itens:
			var m: Dictionary = cat[id].modelo3d
			if m.has("procedural"):
				out.montagens[p][id] = {"procedural": str(m.procedural), "comprimento": float(m.get("comprimento", 0.5))}
				continue
			var ba: Node3D = Armas3D.montar(sk, ap, m, float(cfg.escala))
			if ba == null: continue
			var piv: Node3D = ba.get_child(0)
			var item: Node3D = Armas3D.item_de(ba)
			var d := {"osso": str(ba.bone_name), "piv": _m(piv.transform), "resto": _m(Armas3D.resto_de(ba)),
				"duas_maos": bool(m.get("duas_maos", false)), "ponta": str(m.get("ponta", "olhar")), "prumo": bool(m.get("prumo", false))}
			if piv.get("eixo_item") != null: d["eixo_item"] = _v(piv.eixo_item)
			if piv.get("alinhada") != null:   # PoseAlinhada: natural fora da animação, alinhada dentro
				d["alinhada"] = _m(Transform3D(piv.alinhada, piv.transform.origin)); d["anim_alinhada"] = str(piv.anim)
			if m.has("erguer"): d["erguer"] = m.erguer
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
