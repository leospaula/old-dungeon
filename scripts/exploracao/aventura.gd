extends RefCounted
## Aventura carregada por cima da planta base (data/aventuras/<id>/aventura.json, formato em
## data/esquemas/aventura.schema.json): início do grupo, estado das portas, luz e props de cada área,
## leituras ao entrar nas áreas. O resto (PDMs, eventos, monstros) entra aos poucos, sala a sala.

const PROPS_ARQ := "res://data/catalogos/props.json"
const CEL := 1.5

var id := ""
var d: Dictionary = {}
var grade: RefCounted
var props_cat: Dictionary = {}
var equipamento_guardado := {}   # id do personagem -> {armas, equipamento, po} tirados no início
var leituras_feitas := {}        # área -> true
var props_em_cena: Array = []    # [{tipo, area, celulas, no}]
var parte_atual := ""            # id da parte em que o grupo está (pacote de download)
var escolhidos: Array = []       # ids escolhidos na tela de escolha, na ordem de marcha

func _init(g: RefCounted, aventura_id: String) -> void:
	grade = g; id = aventura_id
	d = JSON.parse_string(FileAccess.get_file_as_string("res://data/aventuras/%s/aventura.json" % id))
	props_cat = JSON.parse_string(FileAccess.get_file_as_string(PROPS_ARQ)).props

static func existe(aventura_id: String) -> bool:
	return FileAccess.file_exists("res://data/aventuras/%s/aventura.json" % aventura_id)

## Coordenada local "C3" da área -> célula da grade (A1 = canto superior esquerdo da caixa da área).
func cel(area: String, pos: String) -> Vector2i:
	var mn := Vector2i(1 << 20, 1 << 20)
	for c in grade.area:
		if grade.area[c] == area: mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
	return mn + Vector2i(pos.unicode_at(0) - 65, int(pos.substr(1)) - 1)

func inicio() -> Dictionary: return d.get("inicio", {})
func celula_inicio() -> Vector2i: return cel(str(inicio().area), str(inicio().pos))
func grupo_ids() -> Array: return d.get("grupo", [])
## Parte da aventura que contém a área (cada parte vira um pacote de download).
func parte_de_area(area: String) -> String:
	for p in d.get("partes", []):
		if area in p.get("areas", []): return str(p.id)
	return ""

func nome_parte(id: String) -> String:
	for p in d.get("partes", []):
		if str(p.id) == id: return str(p.get("nome", id))
	return id

func tamanho_grupo() -> int: return int(d.get("tamanho_grupo", 0))

## Ficha do personagem como começa a aventura. Capturados sem equipamento: armas, mochila e moedas
## ficam guardados (inicio.equipamento_em diz onde o grupo vai achá-los).
func ficha_inicial(p: Dictionary) -> Dictionary:
	if not bool(inicio().get("sem_equipamento", false)): return p
	var q := p.duplicate(true)
	equipamento_guardado[str(p.id)] = {"armas": q.get("armas", []), "equipamento": q.get("equipamento", []), "po": q.get("po", 0)}
	q.armas = []; q.equipamento = []; q.po = 0
	return q

## Portas e armadilhas no mesmo formato de data/masmorra/estado-teste.json.
func estado_portas() -> Dictionary:
	return {"portas": d.get("portas", {}), "armadilhas": []}

## Áreas iluminadas por tochas na parede.
func areas_iluminadas() -> Array:
	var out: Array = []
	var A: Dictionary = d.get("areas", {})
	for a in A:
		if str(A[a].get("luz", "")) == "iluminado": out.append(a)
	return out

## Células das áreas em penumbra (sempre visíveis, com luz fraca).
func celulas_penumbra() -> Array:
	var out: Array = []
	var A: Dictionary = d.get("areas", {})
	for c in grade.area:
		var a: String = grade.area[c]
		if A.has(a) and str(A[a].get("luz", "")) == "penumbra": out.append(c)
	return out

func leitura(area: String) -> String:
	if leituras_feitas.has(area): return ""
	var t: String = str(d.get("areas", {}).get(area, {}).get("leitura", ""))
	if t != "": leituras_feitas[area] = true
	return t

## Coloca os props das áreas na cena. Props que bloqueiam ocupam as células do tamanho (girado).
func colocar_props(raiz: Node3D) -> void:
	var A: Dictionary = d.get("areas", {})
	for a in A:
		for pr in A[a].get("props", []):
			var info: Dictionary = props_cat.get(str(pr.tipo), {})
			if info.is_empty():
				push_warning("prop sem catálogo: %s" % pr.tipo); continue
			var giro := int(pr.get("giro", 0))
			var tam: Array = info.get("tamanho", [1, 1])
			var w := int(tam[0]); var h := int(tam[1])
			if giro in [90, 270]: var t := w; w = h; h = t
			var c0 := cel(str(a), str(pr.pos))
			var cels: Array = []
			for y in h:
				for x in w: cels.append(c0 + Vector2i(x, y))
			if bool(info.get("bloqueia", false)):
				for c in cels: grade.bloqueadas[c] = true
			var no: Node3D = null
			var m: Dictionary = info.get("modelo3d", {})
			if m.has("arquivo") and ResourceLoader.exists(str(m.arquivo)):
				no = load(str(m.arquivo)).instantiate()
				no.scale = Vector3.ONE * float(m.get("escala", 1.0))
				no.rotation_degrees.y = float(m.get("giro_modelo", 0.0)) - giro
				no.position = Vector3((c0.x + w * 0.5) * CEL, 0.0, (c0.y + h * 0.5) * CEL)
				no.name = "Prop_%s_%s" % [pr.tipo, pr.pos]
				raiz.add_child(no)
			props_em_cena.append({"tipo": pr.tipo, "area": a, "celulas": cels, "no": no, "nome": str(pr.get("nome", info.get("nome", pr.tipo)))})
	grade._montar_astar()
