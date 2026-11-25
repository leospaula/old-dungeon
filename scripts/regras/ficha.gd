extends RefCounted
## Ficha de um personagem: dados fixos (data/personagens), inventário por espaços (Regras B-X §11) e tudo
## que é calculado a partir deles: CA, carga, movimento, arma na mão, munição. Nada calculado é salvo.
##
## Item = {"id": <chave do catálogo>, "qtd": n}. Lugares: mão direita, mão esquerda, corpo, cinto (2) e mochila.

const Regras = preload("res://scripts/regras/regras.gd")
const CATALOGO_ARQ := "res://data/catalogos/itens.json"
const MOV_CARGA := {"leve": 36.0, "media": 27.0, "pesada": 18.0}

static var _catalogo := {}

var p: Dictionary            # dados da ficha (grupo-inicial.json)
var id := ""
var nome := ""
var mao_d = null             # item ou null
var mao_e = null
var corpo = null
var cinto: Array = [null, null]
var mochila: Array = []
var moedas := {"pl": 0, "po": 0, "pe": 0, "pp": 0, "pc": 0}
var pv := 1
var diario: Array = []       # [{tipo, texto, turno}]

static func catalogo() -> Dictionary:
	if _catalogo.is_empty():
		_catalogo = JSON.parse_string(FileAccess.get_file_as_string(CATALOGO_ARQ)).itens
	return _catalogo

static func info(it) -> Dictionary:
	if it == null: return {}
	return catalogo().get(it.id, {"nome": str(it.id), "tipo": "ferramenta", "espacos": 1, "icone": ""})

static func icone(it) -> Texture2D:
	var ic: String = str(info(it).get("icone", ""))
	var arq := "res://arte/final/interface/icones/%s.png" % ic
	if ic == "" or not ResourceLoader.exists(arq): return null   # ícone ainda não feito: mostra o nome
	return load(arq)

func _init(dados: Dictionary, arma_preferida := "") -> void:
	p = dados; id = str(p.id); nome = str(p.nome)
	pv = int(p.pv)
	moedas.po = int(p.get("po", 0))
	_distribuir(arma_preferida)

# ---------- montagem inicial ----------

## "tocha x6" → {"id": "tocha", "qtd": 6}
static func _ler(s: String) -> Dictionary:
	var m := RegEx.create_from_string("^(.*) x(\\d+)$").search(s)
	if m: return {"id": m.get_string(1), "qtd": int(m.get_string(2))}
	return {"id": s, "qtd": 1}

func _distribuir(arma_preferida: String) -> void:
	var todos: Array = []
	for s in p.get("equipamento", []):
		var it := _ler(str(s))
		if it.id == "mochila": continue
		var inf := info(it)
		# Itens que não empilham viram entradas separadas (machado de mão x2 = dois machados).
		if int(inf.get("pilha", 1)) <= 1 and it.qtd > 1:
			for _i in it.qtd: todos.append({"id": it.id, "qtd": 1})
		else:
			todos.append(it)
	for w in p.get("armas", []):
		if not todos.any(func(x): return x.id == w.nome): todos.append({"id": str(w.nome), "qtd": 1})
	var pega := func(cond: Callable):
		for x in todos:
			if cond.call(x):
				todos.erase(x); return x
		return null
	corpo = pega.call(func(x): return info(x).get("tipo") == "armadura")
	# Mão direita: a arma preferida (o arco da Lianne) ou a primeira arma da ficha.
	var pref := arma_preferida if arma_preferida != "" else (str(p.armas[0].nome) if not p.get("armas", []).is_empty() else "")
	mao_d = pega.call(func(x): return x.id == pref)
	if int(info(mao_d).get("maos", 1)) < 2:
		mao_e = pega.call(func(x): return info(x).get("tipo") == "escudo")
	# Cinto: a pilha de tochas e um frasco (óleo ou água benta), se houver.
	cinto[0] = pega.call(func(x): return x.id == "tocha")
	cinto[1] = pega.call(func(x): return x.id in ["óleo", "água benta"])
	mochila = todos

# ---------- calculado ----------

func mod(attr: String) -> int:
	return Regras.mod(int(p.atributos[attr]))

func classe() -> String:
	return {"guerreiro": "Guerreira" if id == "tessa" else "Guerreiro", "anao": "Anão", "ladrao": "Ladrão", "elfo": "Elfa" if id == "lianne" else "Elfo",
		"mago": "Maga" if id == "mirela" else "Mago", "clerigo": "Clérigo", "halfling": "Halfling"}.get(str(p.classe), str(p.classe))

## CA descendente do B/X: 9 sem armadura; a armadura dá a base; escudo e DES melhoram (diminuem).
func ca() -> int:
	var base := 9
	if corpo != null: base = int(info(corpo).get("ca", 9))
	for m in [mao_d, mao_e]:
		if m != null and info(m).get("tipo") == "escudo": base -= int(info(m).get("ca", 1))
	return base - mod("des")

func thac0() -> int:
	return int(p.thac0)

func pv_max() -> int:
	return int(p.pv)

func espacos_max() -> int:
	return maxi(10, 10 + mod("for"))

func _espacos(it) -> int:
	if it == null: return 0
	var inf := info(it)
	return int(ceil(float(it.qtd) / float(inf.get("pilha", 1)))) * int(inf.get("espacos", 1))

func espacos_usados() -> int:
	var n := 0
	for it in mochila: n += _espacos(it)
	var total := 0
	for k in moedas: total += int(moedas[k])
	return n + int(ceil(total / 200.0))

func carga() -> String:
	var peso: String = str(info(corpo).get("peso", "leve")) if corpo != null else "leve"
	var usados := espacos_usados()
	if peso == "pesada" or usados >= espacos_max(): return "pesada"
	if peso == "media" or usados > 5: return "media"
	return "leve"

func movimento_m() -> float:
	return MOV_CARGA[carga()]

## Arma usada no ataque: a da mão direita (ou da esquerda, se a direita estiver vazia).
func arma():
	for m in [mao_d, mao_e]:
		if m != null and info(m).get("tipo") == "arma": return m
	return null

func municao_de(a) -> int:
	var tipo: String = str(info(a).get("municao", ""))
	if tipo == "": return 0
	var n := 0
	for it in cinto + mochila:
		if it != null and it.id == tipo: n += int(it.qtd)
	return n

func gastar_municao(a) -> void:
	var tipo: String = str(info(a).get("municao", ""))
	for lista in [cinto, mochila]:
		for i in lista.size():
			var it = lista[i]
			if it != null and it.id == tipo:
				it.qtd -= 1
				if it.qtd <= 0:
					if lista == cinto: cinto[i] = null
					else: mochila.remove_at(i)
				return

func contar(item_id: String) -> int:
	var n := 0
	for it in [mao_d, mao_e, corpo] + cinto + mochila:
		if it != null and it.id == item_id: n += int(it.qtd)
	return n

## Tira 1 unidade de um item (do cinto primeiro). Devolve false se não tinha.
func gastar(item_id: String) -> bool:
	for i in cinto.size():
		if cinto[i] != null and cinto[i].id == item_id:
			cinto[i].qtd -= 1
			if cinto[i].qtd <= 0: cinto[i] = null
			return true
	for i in mochila.size():
		if mochila[i].id == item_id:
			mochila[i].qtd -= 1
			if mochila[i].qtd <= 0: mochila.remove_at(i)
			return true
	return false

## Armas que dá para empunhar no lugar da atual (cinto e mochila).
func armas_guardadas() -> Array:
	return (cinto + mochila).filter(func(x): return x != null and info(x).get("tipo") == "arma")

## Troca a arma da mão direita por `nova` (que estava no cinto ou na mochila). Arma de 2 mãos
## manda o que estiver na esquerda (escudo) para a mochila; voltar a 1 mão traz o escudo de volta.
func empunhar(nova) -> void:
	var de_cinto := cinto.find(nova)
	if de_cinto >= 0: cinto[de_cinto] = null
	else: mochila.erase(nova)
	var antiga = mao_d
	mao_d = nova
	if antiga != null:
		if de_cinto >= 0 and bool(info(antiga).get("cinto", false)): cinto[de_cinto] = antiga
		else: mochila.append(antiga)
	if int(info(nova).get("maos", 1)) >= 2 and mao_e != null:
		mochila.append(mao_e); mao_e = null
	elif mao_e == null:
		for x in mochila:
			if info(x).get("tipo") == "escudo":
				mochila.erase(x); mao_e = x; break

## Habilidades de exploração (B/X): chances em d6 ou porcentagem, para a carta e a ficha.
func habilidades_exploracao() -> Array:
	var out: Array = []
	var anao := str(p.classe) == "anao"
	var elfo := str(p.classe) == "elfo"
	out.append(["Forçar porta", "%d em 6" % clampi(2 + mod("for"), 1, 5)])
	out.append(["Ouvir", "%s em 6" % (str(p.habilidades_ladrao.ouvir) if p.has("habilidades_ladrao") else ("1–2" if anao or elfo or str(p.classe) == "halfling" else "1"))])
	out.append(["Achar porta secreta", "2 em 6" if elfo else "1 em 6"])
	out.append(["Achar armadilha", "%d%%" % int(p.habilidades_ladrao.armadilhas) if p.has("habilidades_ladrao") else ("2 em 6" if anao else "1 em 6")])
	if p.has("habilidades_ladrao"):
		var h: Dictionary = p.habilidades_ladrao
		out.append(["Abrir fechaduras", "%d%%" % int(h.abrir_fechaduras)])
		out.append(["Mover em silêncio", "%d%%" % int(h.silencio)])
		out.append(["Esconder-se", "%d%%" % int(h.esconder)])
		out.append(["Escalar", "%d%%" % int(h.escalar)])
	if anao or elfo: out.append(["Infravisão", "18 m"])
	return out

# ---------- para a ficha completa ----------

var xp := 0

## XP para o 2º nível (B/X).
func xp_proximo() -> int:
	return {"guerreiro": 2000, "anao": 2200, "ladrao": 1200, "elfo": 4000, "mago": 2500, "clerigo": 1500, "halfling": 2000}.get(str(p.classe), 2000)

## Requisito principal e bônus de XP (B/X: 13–15 → +5%, 16–18 → +10%; elfo e halfling têm regras próprias).
func bonus_xp() -> Array:
	var c := str(p.classe)
	var at := func(k): return int(p.atributos[k])
	match c:
		"elfo":
			var b := 10 if at.call("for") >= 13 and at.call("int") >= 16 else (5 if at.call("for") >= 13 and at.call("int") >= 13 else 0)
			return ["FOR e INT", b]
		"halfling":
			var b := 10 if at.call("for") >= 13 and at.call("des") >= 13 else (5 if at.call("for") >= 13 or at.call("des") >= 13 else 0)
			return ["FOR e DES", b]
	var req: String = {"guerreiro": "for", "anao": "for", "ladrao": "des", "mago": "int", "clerigo": "sab"}.get(c, "for")
	var v: int = at.call(req)
	return [req.to_upper(), 10 if v >= 16 else (5 if v >= 13 else (0 if v >= 9 else -10))]

func alinhamento() -> String:
	return {"ordeiro": "Ordeiro", "neutro": "Neutro", "caotico": "Caótico"}.get(str(p.get("alinhamento", "neutro")), str(p.get("alinhamento", "")))

func idiomas() -> Array:
	var out := ["Comum", "a língua do alinhamento (%s)" % alinhamento().to_lower()]
	match str(p.classe):
		"anao": out.append_array(["anão", "gnomo", "goblin", "kobold"])
		"elfo": out.append_array(["élfico", "gnoll", "hobgoblin", "orc"])
		"halfling": out.append("halfling")
	var extra := 2 if int(p.atributos.int) >= 16 else (1 if int(p.atributos.int) >= 13 else 0)
	if extra > 0: out.append("+%d à escolha (INT)" % extra)
	return out

func habilidades_especiais() -> Array:
	match str(p.classe):
		"ladrao": return ["Ataque furtivo: +4 no acerto e dano ×2 pelas costas", "Ler idiomas (a partir do 4º nível)"]
		"elfo": return ["Infravisão 18 m", "Acha portas secretas 2 em 6", "Imune à paralisia de carniçais", "Usa armadura e magia arcana (1 magia de 1º círculo por dia)"]
		"anao": return ["Infravisão 18 m", "Acha armadilhas, paredes falsas e salas escondidas 2 em 6", "Proteções altas contra magia e veneno"]
		"halfling": return ["Esconde-se no mato 90%, na masmorra 2 em 6", "−2 na CA contra criaturas grandes", "+1 no acerto com projéteis", "+1 na iniciativa individual"]
		"clerigo": return ["Afastar mortos-vivos", "Magias divinas a partir do 2º nível"]
		"mago": return ["Magia arcana: 1 magia de 1º círculo por dia", "Grimório"]
	return ["Usa qualquer arma e armadura"]

## Linhas da aba Habilidades do livro: {nome, desc, valor, chance (0–100), quando: ex | co | am}.
func habilidades() -> Array:
	var out: Array = []
	if p.has("habilidades_ladrao"):
		var h: Dictionary = p.habilidades_ladrao
		out.append(_hab("Mover em silêncio", "Você não sabe se falhou: o jogo rola escondido.", "%d%%" % int(h.silencio), int(h.silencio), "am"))
		out.append(_hab("Esconder-se nas sombras", "Parado, na sombra. Atacar revela.", "%d%%" % int(h.esconder), int(h.esconder), "am"))
		out.append(_hab("Abrir fechaduras", "Uma tentativa por fechadura; precisa das ferramentas.", "%d%%" % int(h.abrir_fechaduras), int(h.abrir_fechaduras), "ex"))
		out.append(_hab("Achar e desarmar armadilhas", "1 turno por área; substitui o 1 em 6 comum.", "%d%%" % int(h.armadilhas), int(h.armadilhas), "ex"))
		out.append(_hab("Escalar paredes", "Um teste por subida; cair causa dano.", "%d%%" % int(h.escalar), int(h.escalar), "ex"))
		out.append(_hab("Bater carteira", "Falha grande: a vítima percebe.", "%d%%" % int(h.bater_carteira), int(h.bater_carteira), "ex"))
		out.append(_hab("Ouvir atrás de portas", "Um teste por porta, em silêncio.", "%s em 6" % str(h.ouvir), 33, "ex"))
	match str(p.classe):
		"elfo":
			out.append(_hab("Infravisão", "Vê calor no escuro.", "18 m", -1, "am"))
			out.append(_hab("Achar porta secreta", "1 turno procurando a área.", "2 em 6", 33, "ex"))
			out.append(_hab("Imune à paralisia", "O toque do carniçal não a prende.", "sempre", -1, "co"))
		"anao":
			out.append(_hab("Infravisão", "Vê calor no escuro.", "18 m", -1, "am"))
			out.append(_hab("Achar construções e armadilhas", "Paredes falsas, salas escondidas, armadilhas.", "2 em 6", 33, "ex"))
		"halfling":
			out.append(_hab("Esconder-se", "No mato 90%; na masmorra, parado e quieto.", "2 em 6", 33, "am"))
			out.append(_hab("Pontaria", "+1 no acerto com projéteis.", "+1", -1, "co"))
			out.append(_hab("Pequeno", "−2 na CA contra criaturas grandes.", "−2 CA", -1, "co"))
	return out

func _hab(nome: String, desc: String, valor: String, chance: int, quando: String) -> Dictionary:
	return {"nome": nome, "desc": desc, "valor": valor, "chance": chance, "quando": quando}

## Testes de masmorra que todos fazem (o que a classe já cobre não se repete).
func testes_masmorra() -> Array:
	var c := str(p.classe)
	var out: Array = []
	var fp := clampi(2 + mod("for"), 1, 5)
	out.append(_hab("Forçar porta", "Uma tentativa por rodada; o barulho chama errantes.", "%d em 6" % fp, int(fp * 100 / 6.0), "ex"))
	if not p.has("habilidades_ladrao"):
		var ouv := c in ["anao", "elfo", "halfling"]
		out.append(_hab("Ouvir atrás de portas", "Um teste por porta.", "1–2 em 6" if ouv else "1 em 6", 33 if ouv else 17, "ex"))
	if c != "elfo": out.append(_hab("Achar porta secreta", "1 turno procurando a área.", "1 em 6", 17, "ex"))
	if not p.has("habilidades_ladrao") and c != "anao": out.append(_hab("Achar armadilha", "1 turno por área.", "1 em 6", 17, "ex"))
	return out

## Quadro de destaque da classe na aba Habilidades ({} = nenhum).
func destaque() -> Dictionary:
	match str(p.classe):
		"ladrao": return {"tipo": "furtivo", "acerto": 4, "dano": 2}
		"clerigo":
			var t: Dictionary = p.get("afastar_mortos_vivos", {})
			return {"tipo": "afastar", "tabela": [["Esqueleto", int(t.get("esqueleto", 7))], ["Zumbi", int(t.get("zumbi", 9))], ["Carniçal", int(t.get("carnical", 11))]]}
	return {}

## Chance (%) de tirar `alvo` ou mais em 2d6.
static func chance_2d6(alvo: int) -> int:
	var n := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b >= alvo: n += 1
	return int(round(n * 100.0 / 36.0))

## Magia: quem lança, que lista, quantas por dia no 1º círculo e o que está memorizado.
func lanca_magia() -> bool:
	return str(p.classe) in ["mago", "elfo", "clerigo"]

func lista_magia() -> String:
	return "divina" if str(p.classe) == "clerigo" else "arcana"

func magias_por_dia() -> int:
	return int(p.get("magias_por_dia", {}).get("1", 0))

## Memorizadas hoje (ids). Por enquanto: as do grimório, até o limite por dia.
func memorizadas() -> Array:
	return p.get("grimorio", []).slice(0, magias_por_dia())

var magias_gastas := 0

static var _magias := {}
static func magias_catalogo() -> Dictionary:
	if _magias.is_empty():
		_magias = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/magias.json"))
	return _magias

func magias() -> Array:
	var nomes := {"missil_magico": "Míssil Mágico", "sono": "Sono", "luz": "Luz", "escudo": "Escudo"}
	return p.get("grimorio", []).map(func(x): return nomes.get(x, str(x)))

# ---------- mexer no inventário (livro) ----------
## Lugares: "mao_d", "mao_e", "corpo", "cinto0", "cinto1", "mochila".

func pegar(lugar: String):
	match lugar:
		"mao_d": return mao_d
		"mao_e": return mao_e
		"corpo": return corpo
		"cinto0": return cinto[0]
		"cinto1": return cinto[1]
	return null

func _por(lugar: String, it) -> void:
	match lugar:
		"mao_d": mao_d = it
		"mao_e": mao_e = it
		"corpo": corpo = it
		"cinto0": cinto[0] = it
		"cinto1": cinto[1] = it
		"mochila": if it != null: mochila.append(it)

func lugar_de(it) -> String:
	for l in ["mao_d", "mao_e", "corpo", "cinto0", "cinto1"]:
		if pegar(l) == it: return l
	return "mochila" if mochila.has(it) else ""

func tirar(it) -> void:
	var l := lugar_de(it)
	if l == "mochila": mochila.erase(it)
	elif l != "": _por(l, null)

func cabe_na_mochila(it, sem = null) -> bool:
	var usados := espacos_usados() - (_espacos(sem) if sem != null and mochila.has(sem) else 0)
	return usados + _espacos(it) <= espacos_max()

## "" se `it` pode ir para `lugar`; senão, o motivo.
func motivo_para_nao(it, lugar: String) -> String:
	var inf := info(it); var tipo := str(inf.get("tipo", ""))
	var duas := int(inf.get("maos", 1)) >= 2
	match lugar:
		"mao_d":
			if not tipo in ["arma", "luz", "escudo"]: return "só armas, escudo ou luz na mão"
		"mao_e":
			if duas: return "arma de duas mãos vai na mão direita"
			if not tipo in ["arma", "luz", "escudo"]: return "só armas, escudo ou luz na mão"
			if mao_d != null and mao_d != it and int(info(mao_d).get("maos", 1)) >= 2: return "a mão direita segura uma arma de duas mãos"
		"corpo":
			if tipo != "armadura": return "só armadura no corpo"
		"cinto0", "cinto1":
			if not bool(inf.get("cinto", false)): return "não cabe no cinto"
		"mochila":
			if not cabe_na_mochila(it, it): return "a mochila está cheia"
	return ""

## Move `it` para `lugar`. Quem estava lá vai para onde `it` estava (se puder) ou para a mochila.
func mover(it, lugar: String) -> String:
	var origem := lugar_de(it)
	if origem == lugar: return ""
	var m := motivo_para_nao(it, lugar)
	if m != "": return m
	var antes = pegar(lugar)
	tirar(it)
	if antes != null:
		_por(lugar, null)
		if origem != "mochila" and origem != "" and motivo_para_nao(antes, origem) == "": _por(origem, antes)
		else: mochila.append(antes)
	_por(lugar, it)
	# Arma de duas mãos: a esquerda vai para a mochila.
	if lugar == "mao_d" and int(info(it).get("maos", 1)) >= 2 and mao_e != null:
		mochila.append(mao_e); mao_e = null
	return ""

## Dá o item a outra ficha (vai para a mochila dela).
func dar(it, outra) -> String:
	if not outra.cabe_na_mochila(it): return "a mochila de %s está cheia" % str(outra.nome).get_slice(" ", 0)
	tirar(it); outra.mochila.append(it)
	return ""
