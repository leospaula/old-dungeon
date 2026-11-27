extends RefCounted
## Ações de exploração nas portas (B/X): abrir, ouvir, forçar, abrir fechadura, procurar armadilha,
## desarmar e pregar. Quem age (o personagem selecionado pela carta; sem seleção, quem lidera) vai até
## a porta, anima, rola e gasta tempo do turno (a tocha queima e os errantes rolam junto).
## Rolagens escondidas: ouvir e procurar armadilha (o registro não diz se falhou ou se não havia nada).
## Forçar, fechadura e desarmar mostram o resultado.
## Estado inicial das portas: data/masmorra/estado-teste.json (até a aventura trazer o dela).

const Dados = preload("res://scripts/regras/dados.gd")
const Efeitos = preload("res://scripts/visual/efeitos.gd")
const Sons = preload("res://scripts/visual/sons.gd")
const ARQ := "res://data/masmorra/estado-teste.json"
const RODADA := 1.0 / 60.0   # turno de 10 min = 60 rodadas de 10 s
const BARRAM := ["trancada", "pregada", "secreta"]   # monstros não passam
const LIMITE_OUVIR_M := 18.0              # no corredor, até onde se ouve
## O que se ouve de cada criatura (mortos-vivos e o cubo não fazem barulho).
const SONS := {"goblin": "risadas agudas e metal batendo", "kobold": "latidos baixos e passos miúdos",
	"chefe_kobold": "latidos baixos e passos miúdos", "rato_gigante": "guinchos e unhas na pedra",
	"besouro_de_fogo": "estalos de carapaça", "estirge": "um zumbido de asas", "aranha_caranguejo": "patas raspando",
	"bandido": "vozes abafadas e passos de botas", "hobgoblin": "grunhidos e ferro batendo",
	"chefe_hobgoblin": "grunhidos e ferro batendo", "nao_combatente": "vozes"}

var ex: Node                 # explorar.gd
var est := {}                # id -> estado da porta (ver portas-teste.json) + o que o grupo descobriu
var por_id := {}             # id -> porta da planta
var ocupado := false

func _init(explorar: Node) -> void:
	ex = explorar
	for ch in ex.grade.portas: por_id[ex.grade.portas[ch].id] = ex.grade.portas[ch]
	var d: Dictionary = fonte()
	for id in d.portas:
		est[id] = (d.portas[id] as Dictionary).duplicate(true)
		if por_id.has(id) and str(est[id].estado) in BARRAM: ex.grade.barrar_porta(por_id[id], true)

## Estado inicial de portas e armadilhas: o da aventura carregada ou o de teste.
func fonte() -> Dictionary:
	if ex.get("aventura") != null: return ex.aventura.estado_portas()
	return JSON.parse_string(FileAccess.get_file_as_string(ARQ))

func de(pt: Dictionary) -> Dictionary:
	if not est.has(pt.id): est[pt.id] = {"estado": "fechada"}
	return est[pt.id]

# ---------- balão ----------

## Título e opções do balão da porta para quem vai agir: [{id, texto, dica, ativo}].
func opcoes(pt: Dictionary, q: Node) -> Array:
	var e := de(pt); var f = q.ficha
	var sabe: String = str(e.get("sabe", ""))
	var out: Array = []
	var abrir := {"id": "abrir", "texto": "Abrir", "dica": "Empurra a porta.", "ativo": true}
	if sabe != "": abrir.texto = "Abrir (%s)" % sabe
	out.append(abrir)
	var ouv := {"id": "ouvir", "texto": "Ouvir · %d em 6 · 1 rodada" % f.chance_ouvir(), "dica": "Encosta o ouvido na porta e ouve a sala inteira do outro lado. Ninguém sabe se falhou ou se não há nada.", "ativo": true}
	var tod := {"id": "ouvir_todos", "texto": "Todos que couberem ouvem · 1 rodada", "dica": "Quem estiver perto da porta encosta o ouvido também; vale o melhor.", "ativo": true}
	if ex.modo == "rapido":
		for o in [ouv, tod]: o.ativo = false; o.dica = "Correndo não dá para ouvir: mude para Normal ou Devagar."
	elif int(e.get("ouviu", {}).get(q.nome, -99)) >= ex.turno:
		for o in [ouv, tod]: o.ativo = false; o.dica = "%s já ouviu nesta porta; tente de novo no próximo turno." % q.nome
	out.append(ouv); out.append(tod)
	if sabe in ["emperrada", "trancada", "pregada"]:
		var fo := {"id": "forcar", "texto": "Forçar · %d em 6 · 1 rodada" % _chance_forcar(e, f), "dica": "No ombro e no chute. Faz barulho: pode atrair monstros errantes.", "ativo": true}
		if bool(e.get("inquebravel", false)):
			fo.ativo = false; fo.texto = "Forçar · impossível"; fo.dica = "Barras grossas de ferro: não cedem. Só com a chave."
		out.append(fo)
	if sabe == "trancada":
		var o := {"id": "fechadura", "texto": "Abrir fechadura · %d%% · 1 turno" % f.pct_fechadura(), "dica": "Ferramentas de ladrão. Se falhar, só no próximo nível.", "ativo": true}
		if not f.ladrao(): o.ativo = false; o.dica = "Só o ladrão abre fechaduras."; o.texto = "Abrir fechadura · só ladrão"
		elif f.contar("ferramentas de ladrão") <= 0: o.ativo = false; o.dica = "Precisa das ferramentas de ladrão."
		elif int(e.get("fechadura_falhou", {}).get(q.nome, -1)) >= int(f.p.nivel): o.ativo = false; o.dica = "%s já falhou nesta fechadura; só no próximo nível." % q.nome
		out.append(o)
	var ca: Array = f.chance_armadilha()
	var proc := {"id": "armadilha", "texto": "Procurar armadilha · %s · 1 turno" % (("%d%%" % ca[1]) if ca[0] == "%" else ("%d em 6" % ca[1])), "dica": "Examina a porta com cuidado. Ninguém sabe se falhou ou se não há nada.", "ativo": true}
	if e.get("procurou", {}).has(q.nome): proc.ativo = false; proc.dica = "%s já procurou nesta porta." % q.nome
	out.append(proc)
	if bool(e.get("armadilha_achada", false)) and not bool(e.get("armadilha_fora", false)):
		var o := {"id": "desarmar", "texto": "Desarmar armadilha · %d%% · 1 turno" % (int(f.p.habilidades_ladrao.armadilhas) if f.ladrao() else 0), "dica": "Se falhar, a armadilha dispara.", "ativo": f.ladrao()}
		if not f.ladrao(): o.texto = "Desarmar armadilha · só ladrão"; o.dica = "Só o ladrão desarma armadilhas."
		else: o.dica = "Se falhar, a armadilha dispara."
		out.append(o)
	var pr := {"id": "pregar", "texto": "Pregar · 1 turno", "dica": "Martelo e pregos: ninguém abre sem forçar, e os monstros não passam.", "ativo": true}
	if f.contar("martelo e pregos") <= 0: pr.ativo = false; pr.dica = "%s não tem martelo e pregos." % q.nome
	elif str(e.estado) == "pregada": pr.ativo = false; pr.dica = "Já está pregada."
	out.append(pr)
	return out

func _chance_forcar(e: Dictionary, f) -> int:
	if e.has("dificuldade"): return clampi(int(e.dificuldade) + f.mod("for"), 1, 5)
	return f.chance_forcar()

# ---------- agir ----------

func agir(pt: Dictionary, q: Node3D, acao: String) -> void:
	if ocupado or not q.vivo() or str(de(pt).estado) == "secreta": return
	if not opcoes(pt, q).any(func(o): return o.id == acao and o.ativo): return   # só o que o balão oferece
	ocupado = true
	if await _ir_ate(pt, q):
		match acao:
			"abrir": tentar_abrir(pt, q)
			"ouvir": await _ouvir(pt, q, false)
			"ouvir_todos": await _ouvir(pt, q, true)
			"forcar": await _forcar(pt, q)
			"fechadura": await _fechadura(pt, q)
			"armadilha": await _procurar(pt, q)
			"desarmar": await _desarmar(pt, q)
			"pregar": await _pregar(pt, q)
		if is_instance_valid(q) and q.vivo() and not q.andando(): q.tocar("parado", 0.4)
	ocupado = false
	ex._checar_avistamento()

## Leva quem age até o lado da porta do grupo. Se a casa estiver com um companheiro, eles trocam.
func _ir_ate(pt: Dictionary, q: Node3D) -> bool:
	var de: Vector2i = q.proxima_celula()
	var melhor: Array[Vector2i] = []; var alvo := Vector2i(-999, -999); var menor := INF
	for par in ex.grade.lados_da_porta(pt):
		for c in par:
			if not ex.visao.exploradas.has(c): continue
			if c == de: alvo = c; melhor = []; menor = 0.0; continue
			var cam: Array[Vector2i] = ex.grade.caminho(de, c, ex._ocupadas_por(ex.grupo))   # só monstros barram
			if cam.is_empty(): continue
			var l: float = ex.grade.comprimento(de, cam)
			if l < menor: menor = l; melhor = cam; alvo = c
	if alvo == Vector2i(-999, -999):
		ex._registrar("Não há como chegar até essa porta por aqui.")
		return false
	if q.andando(): await q.parou
	if not melhor.is_empty():
		for h in ex.vivos():
			if h != q and h.celula == alvo:   # companheiro dá passagem: vai para onde quem age estava
				var volta: Array[Vector2i] = ex.grade.caminho(h.celula, q.celula, ex._ocupadas_por(ex.grupo))
				if not volta.is_empty(): h.seguir(volta)
		q.seguir(melhor)
		await q.parou
	for par in ex.grade.lados_da_porta(pt):
		if q.celula in par: q.olhar_para(ex.grade.centro(par[1] if par[0] == q.celula else par[0]))
	return q.celula == alvo

## Abrir: se estiver só fechada, abre (e dispara a armadilha, se houver). Senão, o grupo descobre por quê.
## Também usado no combate (clique na porta na vez do personagem).
func tentar_abrir(pt: Dictionary, q: Node3D) -> bool:
	var e := de(pt)
	match str(e.estado):
		"emperrada", "trancada", "pregada":
			e.sabe = str(e.estado)
			var dica: String = {"emperrada": "dá para forçar", "trancada": "um ladrão pode abrir a fechadura, ou dá para forçar", "pregada": "só forçando"}[e.estado]
			if bool(e.get("inquebravel", false)): dica = "barras grossas de ferro; só com a chave"
			var oque := "a grade" if str(pt.get("tipo", "")) in ["grade", "cela"] else "a porta %s" % pt.id
			ex._registrar("%s empurra %s: está [b]%s[/b] (%s)." % [q.nome, oque, e.estado, dica])
			return false
	_disparar(pt, q)   # a armadilha dispara quando a porta abre de fato
	if not q.vivo(): return false
	ex._abrir_porta(pt, q.celula, q.nome)
	return true

## Ouvir na porta: o sucesso vale para a sala inteira do outro lado (diz se há monstros).
## Falha e sala vazia dão o mesmo texto. Quem ouviu marca os monstros: o grupo não é surpreendido
## por eles e, se eles não ouviram o grupo, são surpreendidos ao abrir a porta.
func _ouvir(pt: Dictionary, q: Node3D, todos: bool) -> void:
	var e := de(pt)
	if not e.has("ouviu"): e.ouviu = {}
	var ouvintes: Array = [q]
	if todos:
		for h in ex.vivos():
			if h != q and Vector2(h.celula - q.celula).length() <= 2.5 and int(e.ouviu.get(h.nome, -99)) < ex.turno: ouvintes.append(h)
	for h in ouvintes: e.ouviu[h.nome] = ex.turno
	await _encostar_ouvido(pt, ouvintes)
	ex._gastar_tempo(RODADA)
	var outro: Array[Vector2i] = []
	for par in ex.grade.lados_da_porta(pt): outro.append(par[1] if par[0] == q.celula else par[0])
	var area: String = ex.grade.area_de(outro[0])
	var la: Array = ex.monstros_vivos().filter(func(m): return ex.grade.area_de(m.celula) == area or ex.grade.alcance(outro[0], 9.0, {}, false).has(m.celula))
	var nomes := ", ".join(ouvintes.map(func(h): return h.nome))
	var ouviu := ouvir(ouvintes, la)
	if ouviu.is_empty():
		ex._registrar("%s encosta%s o ouvido na porta %s e não ouve%s nada." % [nomes, "m" if ouvintes.size() > 1 else "", pt.id, "m" if ouvintes.size() > 1 else ""])
	else:
		ex._registrar("%s ouve%s do outro lado da porta %s: [color=#ff9a6a]%s[/color] (%s)." % [nomes, "m" if ouvintes.size() > 1 else "", pt.id, _descrever(ouviu), ex.grade.nomes.get(area, "do outro lado")])
		ex._diario("evento", "Ouviram %s atrás da porta %s." % [_descrever(ouviu), pt.id])

## Encenação do ouvir: quem está colado na porta chega rente a ela, vira a orelha para a madeira e
## inclina o corpo (animação "ouvir", curvada e cautelosa, mais lenta); os outros só viram para a porta.
## Sem a animação, ajoelha como antes.
const OUVIR_DUR := 4.0
func _encostar_ouvido(pt: Dictionary, ouvintes: Array) -> void:
	var lados: Array = ex.grade.lados_da_porta(pt)
	var voltar := []
	for h in ouvintes:
		var porta := Vector3.INF
		for par in lados:
			if h.celula in par: porta = (ex.grade.centro(par[0]) + ex.grade.centro(par[1])) * 0.5
		if porta == Vector3.INF:   # companheiro perto: olha para a porta
			var c0: Vector2i = lados[0][0]; var c1: Vector2i = lados[0][1]
			h.olhar_para((ex.grade.centro(c0) + ex.grade.centro(c1)) * 0.5)
			if h.player and h.player.has_animation("ouvir"):
				h.tocar_anim("ouvir", 0.3); h.player.speed_scale = 0.7
			else: h.tocar_anim("ajoelhar")
			continue
		if h.player == null or not h.player.has_animation("ouvir"):
			h.olhar_para(porta); h.tocar_anim("ajoelhar"); continue
		var antes: Transform3D = h.transform
		var d: Vector3 = porta - h.position; d.y = 0; d = d.normalized()
		h.olhar_para(porta)
		var giro: float = h.rotation.y + PI * 0.5   # orelha direita para a porta
		var t := Transform3D(Basis(Vector3.UP, giro), antes.origin + d * 0.3)
		t.basis = Basis(Vector3.UP.cross(d).normalized(), deg_to_rad(9.0)) * t.basis   # inclina para a porta
		h.create_tween().tween_property(h, "transform", t, 0.45).set_trans(Tween.TRANS_SINE)
		h.tocar_anim("ouvir", 0.3); h.player.speed_scale = 0.6
		voltar.append([h, antes])
	await ex.get_tree().create_timer(OUVIR_DUR).timeout
	for v in voltar:
		v[0].create_tween().tween_property(v[0], "transform", v[1], 0.4).set_trans(Tween.TRANS_SINE)
	for h in ouvintes:
		if h.vivo(): h.tocar("parado", 0.4)
	if not voltar.is_empty(): await ex.get_tree().create_timer(0.4).timeout

## Rolagens escondidas de quem ouve; devolve os monstros ouvidos (já marcados) ou [].
func ouvir(ouvintes: Array, candidatos: Array) -> Array:
	var ok := false
	for h in ouvintes:
		var n: int = h.ficha.chance_ouvir(); var r := Dados.d(6)
		ex._secreto("Ouvir · %s: d6 %d contra %d → %s" % [h.nome, r, n, "ouve" if r <= n else "falha"])
		ok = ok or r <= n
	var ruidosos := candidatos.filter(func(m): return SONS.has(str(m.get_meta("id", ""))))
	ex._secreto("Ao alcance: %d criatura(s), %d fazem barulho" % [candidatos.size(), ruidosos.size()])
	if not ok or ruidosos.is_empty(): return []
	for m in ruidosos: m.set_meta("ouvido", ex.turno)
	return ruidosos

func _descrever(ms: Array) -> String:
	var sons := {}
	for m in ms: sons[SONS[str(m.get_meta("id"))]] = true
	return " e ".join(sons.keys())

func _forcar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	var n := _chance_forcar(e, f); var r := Dados.d(6)
	var ok := r <= n
	Efeitos.dado_opcional(q, r, ok, 0.5, 6)
	q.get_tree().create_timer(0.55).timeout.connect(func(): Sons.tocar("porta_forcar", q.global_position + q.frente_vetor() * 0.7 + Vector3(0, 1, 0)))
	await _animar(q, "chutar-porta")   # chuta, abrindo ou não
	ex._gastar_tempo(RODADA)
	var faixa := "1" if n == 1 else "1–%d" % n
	if ok:
		ex._registrar("%s força a porta %s (%s em d6): [b]%d[/b] → [color=#ffcf6a]a porta cede![/color]" % [q.nome, pt.id, faixa, r])
		_disparar(pt, q)
		e.estado = "fechada"; e.erase("sabe"); ex.grade.barrar_porta(pt, false)
		if q.vivo(): ex._abrir_porta(pt, q.celula, q.nome)
	else:
		ex._registrar("%s força a porta %s (%s em d6): [b]%d[/b] → não cede." % [q.nome, pt.id, faixa, r])
	ex._registrar("[i]O estrondo ecoa pelos corredores.[/i]")
	var rb := Dados.d(6)
	ex._secreto("Barulho atrai errantes: d6 %d contra 2 → %s" % [rb, "sim" if rb <= 2 else "não"])
	if rb <= 2: ex._surgir_errantes(false, true)   # o barulho atrai quem estiver perto

func _fechadura(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	await _animar(q, "ajoelhar", 0.0, 0.7)
	ex._gastar_tempo(1.0)
	var pct: int = f.pct_fechadura(); var r := Dados.d(100)
	_disparar(pt, q)   # mexer na fechadura dispara a agulha, se ninguém desarmou
	if not q.vivo(): return
	if r <= pct:
		e.estado = "fechada"; e.erase("sabe"); ex.grade.barrar_porta(pt, false)
		ex._registrar("%s abre a fechadura da porta %s (d%% [b]%d[/b] contra %d) → [color=#ffcf6a]clique![/color]" % [q.nome, pt.id, r, pct])
	else:
		if not e.has("fechadura_falhou"): e.fechadura_falhou = {}
		e.fechadura_falhou[q.nome] = int(f.p.nivel)
		ex._registrar("%s tenta a fechadura da porta %s (d%% [b]%d[/b] contra %d) → não consegue; só no próximo nível." % [q.nome, pt.id, r, pct])

func _procurar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	await _examinar(q)
	ex._gastar_tempo(1.0)
	if not e.has("procurou"): e.procurou = {}
	e.procurou[q.nome] = true
	var ca: Array = f.chance_armadilha()
	var r := Dados.d(100) if ca[0] == "%" else Dados.d(6)
	var ok := r <= int(ca[1])
	var tem := e.has("armadilha") and not bool(e.get("armadilha_fora", false))
	ex._secreto("Armadilha na porta %s · %s: %s %d contra %d → %s; armadilha: %s" % [pt.id, q.nome, "d%" if ca[0] == "%" else "d6", r, ca[1], "acha" if ok else "falha", "sim" if tem else "não"])
	if ok and tem:
		e.armadilha_achada = true
		ex._registrar("%s examina a porta %s e [color=#ff9a6a]encontra uma armadilha[/color]: %s" % [q.nome, pt.id, str(e.armadilha.get("achada", e.armadilha.get("efeito", "")))])
		ex._diario("evento", "Armadilha na porta %s: %s" % [pt.id, str(e.armadilha.get("achada", ""))])
	else:
		ex._registrar("%s examina a porta %s com cuidado e não encontra nada." % [q.nome, pt.id])

func _desarmar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	await _examinar(q)
	ex._gastar_tempo(1.0)
	var pct := int(f.p.habilidades_ladrao.armadilhas); var r := Dados.d(100)
	if r <= pct:
		e.armadilha_fora = true
		ex._registrar("%s desarma a armadilha da porta %s (d%% [b]%d[/b] contra %d)." % [q.nome, pt.id, r, pct])
	else:
		ex._registrar("%s erra ao desarmar a armadilha da porta %s (d%% [b]%d[/b] contra %d) e ela dispara!" % [q.nome, pt.id, r, pct])
		_disparar(pt, q)

func _pregar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt)
	await _animar(q, "ajoelhar", 0.0, 0.7)
	ex._gastar_tempo(1.0)
	e.estado = "pregada"; e.sabe = "pregada"; ex.grade.barrar_porta(pt, true)
	ex._registrar("%s prega a porta %s: ninguém passa por ela sem forçar." % [q.nome, pt.id])
	ex._registrar("[i]As marteladas ecoam.[/i]")
	var rb := Dados.d(6)
	ex._secreto("Marteladas atraem errantes: d6 %d contra 1 → %s" % [rb, "sim" if rb == 1 else "não"])
	if rb == 1: ex._surgir_errantes(false, true)

## Armadilha da porta (uma vez): dano em quem mexeu ou alarme.
func _disparar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt)
	if not e.has("armadilha") or bool(e.get("armadilha_fora", false)): return
	e.armadilha_fora = true
	var a: Dictionary = e.armadilha
	var txt := "[color=#ff7a5a]Armadilha![/color] %s" % str(a.get("efeito", ""))
	if a.has("dano"):
		var dd := Dados.detalhar(str(a.dano)); var dano := maxi(1, int(dd.total))
		q.pv -= dano
		txt += " %s sofre %s = [b]%d[/b] de dano." % [q.nome, dd.texto, dano]
		q.piscar(Color(1, 0.25, 0.2, 0.6))
		if q.pv <= 0: q.animar_morte(); txt += " [color=#ff7a5a]%s cai.[/color]" % q.nome
		else: q.animar_dano()
	ex._registrar(txt)
	ex._diario("evento", "%s disparou a armadilha da porta %s." % [q.nome, pt.id])
	if str(a.get("tipo", "")) == "alarme": ex._surgir_errantes(false, true)
	if not q.vivo(): ex._heroi_caiu_fora(q)
	ex._ficha_mudou(q)

## Toca a animação inteira (ritmo < 1 = mais lenta, para o trabalho demorado não ficar truncado).
## Examinar de perto (armadilha na porta, desarmar): ajoelha, examina ajoelhado e levanta.
func _examinar(q: Node3D) -> void:
	if q.player == null or not q.player.has_animation("examinar-ajoelhado"):
		await _animar(q, "ajoelhar", 0.0, 0.7); return
	await ex.procurar._agachar(q)
	var t: float = q.tocar_anim("examinar-ajoelhado", 0.3)
	await q.get_tree().create_timer(t).timeout
	await ex.procurar._levantar(q)

func _animar(q: Node3D, nome: String, ate := 0.0, ritmo := 1.0) -> void:
	var t: float = q.tocar_anim(nome)
	if q.player: q.player.speed_scale = ritmo
	await q.get_tree().create_timer(ate if ate > 0.0 else t / ritmo).timeout
