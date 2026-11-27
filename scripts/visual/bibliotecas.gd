extends RefCounted
## Bibliotecas de animação por categoria (data/regras/animacoes.json). Um modelo normalizado
## (tools/normalizar_modelo.gd) recebe um AnimationPlayer com a biblioteca da sua categoria; a
## diferença de altura em relação à referência vai em Skeleton3D.motion_scale.

const ARQ := "res://data/regras/animacoes.json"
static var _dados := {}
static var _libs := {}

static func dados() -> Dictionary:
	if _dados.is_empty(): _dados = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	return _dados

static func criatura(id: String) -> Dictionary:
	return dados().criaturas.get(id, {})

## Põe no modelo o AnimationPlayer com a biblioteca da categoria. Devolve o player (ou null).
static func preparar(modelo: Node3D, categoria: String) -> AnimationPlayer:
	var cat: Dictionary = dados().categorias.get(categoria, {})
	var bib: Dictionary = dados().bibliotecas.get(str(cat.get("biblioteca", "")), {})
	if bib.is_empty():
		push_warning("categoria de animação sem biblioteca: %s" % categoria); return null
	var sks := modelo.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty(): return null
	var sk: Skeleton3D = sks[0]
	var arq: String = bib.arquivo
	if not _libs.has(arq): _libs[arq] = load(arq)
	var quadril := sk.find_bone("mixamorig_Hips")
	if quadril >= 0: sk.motion_scale = sk.get_bone_global_rest(quadril).origin.y / float(bib.quadril_ref)
	var ap := AnimationPlayer.new(); ap.name = "Animacoes"
	sk.get_parent().add_child(ap)
	ap.add_animation_library("", _libs[arq])
	return ap
