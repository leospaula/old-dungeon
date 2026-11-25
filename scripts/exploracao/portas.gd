extends RefCounted
## Ações de exploração nas portas (B/X): abrir, ouvir, forçar, abrir fechadura, procurar armadilha,
## desarmar e pregar. Quem age (o personagem selecionado pela carta; sem seleção, quem lidera) vai até
## a porta, anima, rola e gasta tempo do turno (a tocha queima e os errantes rolam junto).
## Rolagens escondidas: ouvir e procurar armadilha (o registro não diz se falhou ou se não havia nada).
## Forçar, fechadura e desarmar mostram o resultado.
## Estado inicial das portas: data/masmorra/portas-teste.json (até a aventura trazer o dela).

const Dados = preload("res://scripts/regras/dados.gd")
const ARQ := "res://data/masmorra/portas-teste.json"
const RODADA := 1.0 / 60.0   # turno de 10 min = 60 rodadas de 10 s
const BARRAM := ["trancada", "pregada"]   # monstros não passam

var ex: Node                 # explorar.gd
var est := {}                # id -> estado da porta (ver portas-teste.json) + o que o grupo descobriu
var por_id := {}             # id -> porta da planta
var ocupado := false

func _init(explorar: Node) -> void:
	ex = explorar
	for ch in ex.grade.portas: por_id[ex.grade.portas[ch].id] = ex.grade.portas[ch]
	var d = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	for id in d.portas:
		est[id] = (d.portas[id] as Dictionary).duplicate(true)
		if por_id.has(id) and str(est[id].estado) in BARRAM: ex.grade.barrar_porta(por_id[id], true)

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
	out.append({"id": "ouvir", "texto": "Ouvir · %d em 6 · 1 rodada" % f.chance_ouvir(), "dica": "Encosta o ouvido na porta. Ninguém sabe se falhou ou se não há nada.", "ativo": true})
	if sabe in ["emperrada", "trancada", "pregada"]:
		out.append({"id": "forcar", "texto": "Forçar · %d em 6 · 1 rodada" % _chance_forcar(e, f), "dica": "No ombro e no chute. Faz barulho: pode atrair monstros errantes.", "ativo": true})
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
		var o := {"id": "desarmar", "texto": "Desarmar armadilha · %d%% · 1 turno" % (int(f.p.habilidades_ladrao.armadilhas) if f.ladrao() else 0), "dica": "Se falhar, só no próximo nível.", "ativo": f.ladrao()}
		if not f.ladrao(): o.texto = "Desarmar armadilha · só ladrão"; o.dica = "Só o ladrão desarma armadilhas."
		elif int(e.get("desarmar_falhou", {}).get(q.nome, -1)) >= int(f.p.nivel): o.ativo = false; o.dica = "%s já falhou; só no próximo nível." % q.nome
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
	if ocupado or not q.vivo(): return
	if not opcoes(pt, q).any(func(o): return o.id == acao and o.ativo): return   # só o que o balão oferece
	ocupado = true
	if await _ir_ate(pt, q):
		match acao:
			"abrir": tentar_abrir(pt, q)
			"ouvir": await _ouvir(pt, q)
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
			ex._registrar("%s empurra a porta %s: está [b]%s[/b] (%s)." % [q.nome, pt.id, e.estado, dica])
			return false
	_disparar(pt, q)   # a armadilha dispara quando a porta abre de fato
	if not q.vivo(): return false
	ex._abrir_porta(pt, q.celula, q.nome)
	return true

func _ouvir(pt: Dictionary, q: Node3D) -> void:
	await _animar(q, "ajoelhar")
	ex._gastar_tempo(RODADA)
	var n: int = q.ficha.chance_ouvir(); var r := Dados.d(6)
	var ha := _ha_algo_atras(pt, q)
	print("(ouvir %s: d6 %d contra %d; há algo: %s)" % [q.nome, r, n, ha])
	if r <= n and ha: ex._registrar("%s encosta o ouvido na porta %s: [color=#ff9a6a]passos e respiração do outro lado.[/color]" % [q.nome, pt.id])
	else: ex._registrar("%s encosta o ouvido na porta %s e não ouve nada." % [q.nome, pt.id])

## Há monstro vivo até 9 m do outro lado da porta?
func _ha_algo_atras(pt: Dictionary, q: Node3D) -> bool:
	var outro: Array[Vector2i] = []
	for par in ex.grade.lados_da_porta(pt): outro.append(par[1] if par[0] == q.celula else par[0])
	for m in ex.monstros + ex.errantes:
		if not is_instance_valid(m) or not m.vivo(): continue
		for c in outro:
			if ex.grade.area_de(m.celula) == ex.grade.area_de(c) or Vector2(m.celula - c).length() <= 6.0: return true
	return false

func _forcar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	var n := _chance_forcar(e, f); var r := Dados.d(6)
	var ok := r <= n
	await _animar(q, "chutar-porta" if ok else "levar-golpe")
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
	if Dados.d(6) <= 2: ex._surgir_errantes(false, true)   # o barulho atrai quem estiver perto

func _fechadura(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	await _animar(q, "ajoelhar", 1.6)
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
	await _animar(q, "ajoelhar", 1.6)
	ex._gastar_tempo(1.0)
	if not e.has("procurou"): e.procurou = {}
	e.procurou[q.nome] = true
	var ca: Array = f.chance_armadilha()
	var r := Dados.d(100) if ca[0] == "%" else Dados.d(6)
	var ok := r <= int(ca[1])
	var tem := e.has("armadilha") and not bool(e.get("armadilha_fora", false))
	print("(armadilha %s: %s %d contra %d; há: %s)" % [q.nome, ca[0], r, ca[1], tem])
	if ok and tem:
		e.armadilha_achada = true
		ex._registrar("%s examina a porta %s e [color=#ff9a6a]encontra uma armadilha[/color]: %s" % [q.nome, pt.id, str(e.armadilha.get("achada", e.armadilha.get("efeito", "")))])
		ex._diario("evento", "Armadilha na porta %s: %s" % [pt.id, str(e.armadilha.get("achada", ""))])
	else:
		ex._registrar("%s examina a porta %s com cuidado e não encontra nada." % [q.nome, pt.id])

func _desarmar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt); var f = q.ficha
	await _animar(q, "ajoelhar", 1.6)
	ex._gastar_tempo(1.0)
	var pct := int(f.p.habilidades_ladrao.armadilhas); var r := Dados.d(100)
	if r <= pct:
		e.armadilha_fora = true
		ex._registrar("%s desarma a armadilha da porta %s (d%% [b]%d[/b] contra %d)." % [q.nome, pt.id, r, pct])
	else:
		if not e.has("desarmar_falhou"): e.desarmar_falhou = {}
		e.desarmar_falhou[q.nome] = int(f.p.nivel)
		ex._registrar("%s não consegue desarmar a armadilha da porta %s (d%% [b]%d[/b] contra %d); só no próximo nível." % [q.nome, pt.id, r, pct])

func _pregar(pt: Dictionary, q: Node3D) -> void:
	var e := de(pt)
	await _animar(q, "ajoelhar", 1.6)
	ex._gastar_tempo(1.0)
	e.estado = "pregada"; e.sabe = "pregada"; ex.grade.barrar_porta(pt, true)
	ex._registrar("%s prega a porta %s: ninguém passa por ela sem forçar." % [q.nome, pt.id])
	ex._registrar("[i]As marteladas ecoam.[/i]")
	if Dados.d(6) == 1: ex._surgir_errantes(false, true)

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

func _animar(q: Node3D, nome: String, ate := 0.0) -> void:
	var t: float = q.tocar_anim(nome)
	await q.get_tree().create_timer(ate if ate > 0.0 else t).timeout
