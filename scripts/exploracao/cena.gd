extends RefCounted
## Cenas da aventura: sequências de passos escritas no aventura.json ("cenas"), disparadas pelos eventos
## ("eventos": quando → faz [{cena: id}]). Enquanto a cena roda, o jogador não anda nem abre portas; um
## clique (ou espaço) só pula a fala da vez. Cada passo é um dicionário com "faz" e os parâmetros:
##
##   surgir   {quem, pdm, area, pos}        PdM entra em cena (modelo da criatura "base" do PdM)
##   andar    {quem, area, pos, correr, junto}   anda até a casa (a livre mais perto, se ocupada);
##                                          junto = não espera chegar
##   andar_grupo {quem: [ids], destinos: [{area,pos}...], correr}   anda em fila como o grupo do jogador:
##                                          o primeiro abre caminho, os outros seguem a casa de quem vai
##                                          à frente; ao chegar, cada um vai para o seu destino (na ordem)
##   guarda   {quem: id | [ids], para, mirar, ate}   saca a arma e fica em guarda (pose de combate do estilo
##                                          da arma); mirar = animação de mira segurada em `ate` s (besta-mirar)
##   esperar  {quem}                        espera quem está andando parar
##   olhar    {quem, para}                  para: "grupo", id de PdM ou {area, pos}
##   fala     {quem, texto}                 balão em cima da cabeça (e no registro)
##   mensagem {texto}                       só no registro
##   pausa    {s}
##   anim     {quem, anim, ate, ritmo}       animação da biblioteca (ate = segura nesse tempo)
##   abrir_porta / fechar_porta {porta, quem, fresta}   fresta = só entreabre (graus), sem liberar a passagem
##   trancar_porta {porta}
##   grupo    {acao: "deitar" | "levantar" | "recuar", porta}
##   pj       {quem: "agente" | "mais_forte", ir: "porta" | {area,pos}, porta, anim, correr}
##   ataque   {quem, alvo: "mais_perto", arma, dano}   ataque de verdade (d20 contra a CA); não derruba (PV mín. 1)
##   escolha  {quem, titulo, texto, opcoes: [{id, texto, dica, faz, fim}], limite, ao_limite}
##            repete até uma opção com fim; depois de `limite` escolhas sem fim, roda ao_limite e só
##            sobram as opções com fim
##   sumir    {quem}
##   cena     {id}                          roda outra cena
## "quem" é o id de um PdM da cena, "agente" (quem age no grupo) ou "mais_forte" (maior FOR).

const Dados = preload("res://scripts/regras/dados.gd")
const Ator = preload("res://scripts/exploracao/ator.gd")
const Sistema = preload("res://scripts/regras/sistema.gd")

var ex: Node
var ativa := false
var _feitos := {}          # id do evento -> true
var _alvo_pj: Node3D = null   # personagem que a última opção escolhida pôs em ação
var escolhas_auto: Array = []   # testes: respostas prontas para as escolhas, na ordem

func _init(explorar: Node) -> void:
	ex = explorar

func eventos() -> Array:
	return ex.aventura.d.get("eventos", []) if ex.aventura else []

## Dispara os eventos do gatilho "inicio" (segundos depois de a aventura começar).
func comecar() -> void:
	for ev in eventos():
		var q: Dictionary = ev.get("quando", {})
		if q.has("inicio"):
			ex.get_tree().create_timer(float(q.inicio)).timeout.connect(func(): disparar(ev))

func disparar(ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	if bool(ev.get("uma_vez", true)) and _feitos.has(id): return
	_feitos[id] = true
	for f in ev.get("faz", []):
		if (f as Dictionary).has("cena"): await rodar_cena(str(f.cena))
		elif (f as Dictionary).has("mensagem"): ex._registrar(str(f.mensagem))

func rodar_cena(id: String) -> void:
	var passos: Array = ex.aventura.d.get("cenas", {}).get(id, [])
	if passos.is_empty(): push_warning("cena %s não existe" % id); return
	while ativa: await ex.get_tree().process_frame   # uma cena de cada vez
	while ex.combate.ativo or ex.portas.ocupado or ex.heroi.andando(): await ex.get_tree().process_frame
	ativa = true
	ex.marca_caminho.limpar(); ex.porta_alvo = {}
	for h in ex.vivos(): h.parar()
	var cam := [ex.camera.distancia, ex.camera.inclinacao, ex.camera.guinada]
	await rodar(passos)
	# A câmera volta ao ângulo do jogador (o alvo fica onde a cena terminou).
	for i in 3:
		ex.create_tween().tween_property(ex.camera, ["distancia", "inclinacao", "guinada"][i], cam[i], 1.0).set_trans(Tween.TRANS_SINE)
	ativa = false
	ex.hud_ui.refazer()

func rodar(passos: Array) -> void:
	for p in passos: await passo(p)

func passo(p: Dictionary) -> void:
	match str(p.get("faz", "")):
		"surgir":
			var c: Vector2i = ex.aventura.cel(str(p.area), str(p.pos))
			ex._criar_pdm(str(p.quem), str(p.get("pdm", p.quem)), _livre_perto(c, null))
		"andar":
			var q := quem(p); if q == null: return
			await _andar(q, ex.aventura.cel(str(p.area), str(p.pos)), bool(p.get("correr", false)), bool(p.get("junto", false)))
		"andar_grupo":
			await _andar_grupo(p)
		"guarda":
			for id in (p.quem if p.quem is Array else [p.quem]):
				var g: Node3D = ex.pdms.get(str(id), null)
				if g == null: continue
				if p.has("para"): g.olhar_para(_ponto(p.para, g))
				g.empunhar(true)
				if p.has("mirar"): _anim(g, str(p.mirar), float(p.get("ate", 0.9)), 1.0)   # segura a pose de mira
				await ex.get_tree().create_timer(0.12).timeout
		"esperar":
			var q := quem(p)
			if q and q.andando(): await q.parou
		"olhar":
			var q := quem(p); if q == null: return
			q.olhar_para(_ponto(p.get("para", "grupo"), q))
		"fala":
			var q := quem(p)
			var nome: String = q.nome if q else ""
			ex._registrar("[b]%s:[/b] “%s”" % [nome, str(p.texto)])
			if q: await ex.hud_ui.fala(q, ex.camera, nome, str(q.get_meta("retrato", "")), str(p.texto), q.altura_texto() + 0.5)
		"mensagem":
			ex._registrar("[i]%s[/i]" % str(p.texto))
		"camera":
			if ex._args().has("--camera-fixa"): return   # capturas: a câmera fica onde a linha de comando pôs
			# Leva a câmera até o ponto da cena (só desliza; o jogador continua podendo girar e afastar).
			var alvo: Vector3 = ex.grade.centro(ex.aventura.cel(str(p.area), str(p.pos))) + Vector3(float(p.get("dx", 0.0)), 0, float(p.get("dz", 0.0)))
			var tw: Tween = ex.create_tween(); tw.tween_property(ex.camera, "alvo", alvo, 1.0).set_trans(Tween.TRANS_SINE)
			for k in ["distancia", "inclinacao", "guinada"]:
				if p.has(k): ex.create_tween().tween_property(ex.camera, k, float(p[k]), 1.2).set_trans(Tween.TRANS_SINE)
		"pausa":
			await ex.get_tree().create_timer(float(p.get("s", 1.0))).timeout
		"anim":
			var q := quem(p); if q == null: return
			await _anim(q, str(p.anim), float(p.get("ate", 0.0)), float(p.get("ritmo", 1.0)))
		"abrir_porta":
			var pt: Dictionary = ex.portas.por_id[str(p.porta)]
			var q := quem(p)
			if p.has("fresta"): await ex._entreabrir_porta(pt, float(p.fresta), q)
			else: ex._abrir_porta(pt, q.celula if q else pt_lado(pt, 0), "")
			await ex.get_tree().create_timer(0.5).timeout
		"fechar_porta":
			ex._fechar_porta(ex.portas.por_id[str(p.porta)])
			await ex.get_tree().create_timer(0.45).timeout
		"trancar_porta":
			ex._trancar_porta(ex.portas.por_id[str(p.porta)])
		"grupo":
			await _grupo(p)
		"pj":
			await _pj(p)
		"ataque":
			await _ataque(p)
		"escolha":
			await _escolha(p)
		"sumir":
			var q := quem(p); if q == null: return
			ex._remover_pdm(str(p.quem))
		"cena":
			await rodar(ex.aventura.d.get("cenas", {}).get(str(p.id), []))
		_:
			push_warning("passo de cena desconhecido: %s" % p)

func pt_lado(pt: Dictionary, i: int) -> Vector2i:
	return ex.grade.lados_da_porta(pt)[0][i]

## Ator de um passo: PdM pelo id, ou alguém do grupo.
func quem(p: Dictionary) -> Node3D:
	var id := str(p.get("quem", ""))
	match id:
		"agente": return _alvo_pj if is_instance_valid(_alvo_pj) else ex.agente()
		"mais_forte": return _mais_forte()
		"pj": return _alvo_pj if is_instance_valid(_alvo_pj) else ex.agente()
	return ex.pdms.get(id, null)

func _mais_forte() -> Node3D:
	var m: Node3D = null
	for h in ex.vivos():
		if m == null or int(h.ficha.p.atributos.for) > int(m.ficha.p.atributos.for): m = h
	return m

func _ponto(para, q: Node3D) -> Vector3:
	if para is Dictionary: return ex.grade.centro(ex.aventura.cel(str(para.area), str(para.pos)))
	if str(para) == "grupo":
		var s := Vector3.ZERO; var n := 0
		for h in ex.vivos(): s += h.global_position; n += 1
		return s / maxf(n, 1)
	var o: Node3D = ex.pdms.get(str(para), null)
	return o.global_position if o else q.global_position + q.frente_vetor()

## Casa livre mais perto de `c` (a própria, se livre), do mesmo lado das paredes.
func _livre_perto(c: Vector2i, q: Node3D) -> Vector2i:
	var ocup: Dictionary = ex._ocupadas_por([q] if q else [])
	if not ocup.has(c): return c
	var alc: Dictionary = ex.grade.alcance(c, 6.0, {}, false)
	var melhor := c; var dist := INF
	for x in alc:
		if ocup.has(x) or ex.grade.area_de(x) != ex.grade.area_de(c): continue
		if float(alc[x][0]) < dist: dist = float(alc[x][0]); melhor = x
	return melhor

func _andar(q: Node3D, c: Vector2i, correr: bool, junto: bool) -> void:
	var destino := _livre_perto(c, q)
	if destino == q.celula: return
	var cam: Array[Vector2i] = ex.grade.caminho(q.proxima_celula(), destino, ex._ocupadas_por([q]), true)
	if cam.is_empty(): cam = ex.grade.caminho(q.proxima_celula(), destino, {}, true)
	if cam.is_empty(): return
	q.papel_andar = "correr" if correr else "andar"
	q.velocidade = Ator.VEL_BASE * (1.8 if correr else 1.0)
	q.seguir(cam)
	if not junto: await q.parou
	if not junto: q.papel_andar = "andar"; q.velocidade = Ator.VEL_BASE

## Grupo de PdMs andando junto: a mesma fila do grupo do jogador (explorar._puxar_fila). Quem lidera
## vai até o primeiro destino; a cada passo dele, cada um anda até a casa que o da frente acabou de deixar
## (no máximo 3 casas, sem atravessar ninguém). Quando quem lidera chega, os outros vão para os seus
## destinos, um de cada vez, com um pequeno intervalo, e ninguém fica em cima de ninguém.
func _andar_grupo(p: Dictionary) -> void:
	var membros: Array = []
	for id in p.get("quem", []):
		var m: Node3D = ex.pdms.get(str(id), null)
		if m and m.vivo(): membros.append(m)
	if membros.is_empty(): return
	var destinos: Array = p.get("destinos", []).duplicate()
	var correr := bool(p.get("correr", false))
	# Ordem da fila: lidera quem está mais perto dos destinos; o destino mais fundo (mais longe de onde
	# o grupo está) fica para quem lidera, e os mais rasos para quem vem atrás. Assim ninguém precisa
	# passar por cima de ninguém, nem para sair nem para chegar.
	if not destinos.is_empty():
		var cels: Array = destinos.map(func(x): return ex.aventura.cel(str(x.area), str(x.pos)))
		var cd := Vector2.ZERO
		for c in cels: cd += Vector2(c)
		cd /= cels.size()
		var cm := Vector2.ZERO
		for m in membros: cm += Vector2(m.celula)
		cm /= membros.size()
		var dist_cam := func(a: Vector2i, b: Vector2i) -> float:
			var cam: Array[Vector2i] = ex.grade.caminho(a, b, {}, true)
			return float(cam.size()) if not cam.is_empty() else Vector2(a - b).length()
		var alvo_c := Vector2i(roundi(cd.x), roundi(cd.y))
		if not ex.grade.chao(alvo_c): alvo_c = cels[0]
		membros.sort_custom(func(a, b): return dist_cam.call(a.celula, alvo_c) < dist_cam.call(b.celula, alvo_c))
		var orig := Vector2i(roundi(cm.x), roundi(cm.y))
		if not ex.grade.chao(orig): orig = membros[0].celula
		destinos.sort_custom(func(a, b):
			return dist_cam.call(orig, ex.aventura.cel(str(a.area), str(a.pos))) > dist_cam.call(orig, ex.aventura.cel(str(b.area), str(b.pos))))
	for m in membros:
		m.papel_andar = "correr" if correr else "andar"; m.velocidade = Ator.VEL_BASE * (1.8 if correr else 1.0)
	_menor_dist = INF
	var lider: Node3D = membros[0]
	var puxar := func(de: Vector2i, _para: Vector2i):
		var alvo := de
		for f in membros.slice(1):
			var atual: Vector2i = f.proxima_celula()
			if atual != alvo:
				var cam: Array[Vector2i] = ex.grade.caminho(atual, alvo, ex._ocupadas_por([f]), true)
				f.seguir(cam.slice(0, mini(3, cam.size())))
			alvo = atual
	lider.passo_iniciado.connect(puxar)
	var d0: Dictionary = destinos[0] if not destinos.is_empty() else {}
	if not d0.is_empty(): await _andar(lider, ex.aventura.cel(str(d0.area), str(d0.pos)), correr, false)
	lider.passo_iniciado.disconnect(puxar)
	for i in range(1, membros.size()):
		if i < destinos.size():
			var d: Dictionary = destinos[i]
			_andar(membros[i], ex.aventura.cel(str(d.area), str(d.pos)), correr, true)
			await ex.get_tree().create_timer(0.25).timeout
	for m in membros:
		if m.andando(): await m.parou
		m.papel_andar = "andar"; m.velocidade = Ator.VEL_BASE
	if ex._args().has("--medir-grupo"): print("GRUPO %s: menor distância entre dois = %.2f m" % [p.quem, _menor_dist])

## Testes (--medir-grupo): menor distância entre quaisquer dois PdMs em cena, medida a cada quadro.
var _menor_dist := INF
func medir_grupo() -> void:
	while true:
		await ex.get_tree().process_frame
		var l: Array = ex.pdms.values().filter(func(x): return is_instance_valid(x))
		for i in l.size():
			for j in range(i + 1, l.size()):
				_menor_dist = minf(_menor_dist, Vector2(l[i].global_position.x - l[j].global_position.x, l[i].global_position.z - l[j].global_position.z).length())

## Anima e espera; `ate` > 0 segura a pose nesse tempo da animação.
func _anim(q: Node3D, nome: String, ate: float, ritmo: float) -> void:
	var t: float = q.tocar_anim(nome, 0.2)
	if q.player == null: return
	q.player.speed_scale = ritmo
	if ate > 0.0:
		await ex.get_tree().create_timer(ate / ritmo).timeout
		q.player.pause()
	else:
		await ex.get_tree().create_timer(t / ritmo).timeout
		if q.vivo(): q.tocar("parado", 0.3)

# ---------- grupo ----------

## Deitar de cara no chão: o "levantar" (de bruços no chão até ficar de pé) de trás para a frente.
const LEVANTAR := "levantar"
const DEITADO_T := 0.0   # tempo do "levantar" em que o corpo está estendido no chão
func _grupo(p: Dictionary) -> void:
	match str(p.get("acao", "")):
		"deitar":
			for h in ex.vivos():
				if bool(h.get_meta("deitado", false)): continue
				h.set_meta("deitado", true)
				_deitar(h)
				await ex.get_tree().create_timer(0.25).timeout
			await ex.get_tree().create_timer(1.6).timeout
		"levantar":
			for h in ex.vivos():
				if not bool(h.get_meta("deitado", false)): continue
				h.set_meta("deitado", false)
				_levantar(h)
				await ex.get_tree().create_timer(0.2).timeout
			await ex.get_tree().create_timer(1.8).timeout
		"recuar":
			# Quem está encostado na porta (do lado de dentro) recua uma ou duas casas.
			var pt: Dictionary = ex.portas.por_id[str(p.porta)]
			var perto := {}
			for par in ex.grade.lados_da_porta(pt):
				for c in par: perto[c] = true
			for h in ex.vivos():
				if not perto.has(h.celula): continue
				var alc: Dictionary = ex.grade.alcance(h.celula, 4.5, ex._ocupadas_por([h]), false)
				var melhor: Vector2i = h.celula; var nota := -INF
				for c in alc:
					if ex.grade.area_de(c) != ex.grade.area_de(h.celula) or ex._ocupadas_por([h]).has(c): continue
					var longe := 99.0
					for x in perto: longe = minf(longe, Vector2(c - x).length())
					var n := minf(longe, 2.0) * 10.0 - float(alc[c][0])
					if n > nota: nota = n; melhor = c
				if melhor != h.celula: await _andar(h, melhor, false, true)
			for h in ex.vivos():
				if h.andando(): await h.parou

func _deitar(h: Node3D) -> void:
	if h.player == null or not h.player.has_animation(LEVANTAR):
		h.tocar_anim("ajoelhar"); return
	var dur: float = h.player.get_animation(LEVANTAR).length
	h.tocar_anim(LEVANTAR, 0.3)
	h.player.seek(dur * 0.55, true)
	h.player.play_backwards(LEVANTAR, 0.3)
	h.player.speed_scale = 1.0
	await ex.get_tree().create_timer(dur * 0.55).timeout
	if bool(h.get_meta("deitado", false)):
		h.player.seek(DEITADO_T, true); h.player.pause()

func _levantar(h: Node3D) -> void:
	if h.player == null or not h.player.has_animation(LEVANTAR):
		h.tocar("parado", 0.4); return
	h.player.play(LEVANTAR, 0.1); h.player.seek(0.0, true); h.player.speed_scale = 1.2
	await ex.get_tree().create_timer(h.player.get_animation(LEVANTAR).length / 1.2).timeout
	if not bool(h.get_meta("deitado", false)): h.tocar("parado", 0.4)

## Um personagem age sozinho: vai até a porta (ou a uma casa) e anima.
func _pj(p: Dictionary) -> void:
	var h := quem(p); if h == null: return
	_alvo_pj = h
	if p.has("ir"):
		var c: Vector2i
		if str(p.ir) == "porta":
			var pt: Dictionary = ex.portas.por_id[str(p.porta)]
			var dentro: Array = []
			for par in ex.grade.lados_da_porta(pt):
				for x in par:
					if ex.grade.area_de(x) == ex.grade.area_de(h.celula): dentro.append(x)
			dentro.sort_custom(func(a, b): return Vector2(a - h.celula).length() < Vector2(b - h.celula).length())
			c = dentro[0] if not dentro.is_empty() else h.celula
			if p.has("casa"): c = dentro[clampi(int(p.casa), 0, dentro.size() - 1)]
		else: c = ex.aventura.cel(str(p.ir.area), str(p.ir.pos))
		if p.get("modo", "") == "rastejar": h.papel_andar = "andar_furtivo"; h.velocidade = Ator.VEL_BASE * 0.5
		await _andar(h, c, bool(p.get("correr", false)), false)
		h.papel_andar = "andar"; h.velocidade = Ator.VEL_BASE
		var pt2: Dictionary = ex.portas.por_id.get(str(p.get("porta", "")), {})
		if not pt2.is_empty():
			for par in ex.grade.lados_da_porta(pt2):
				if h.celula in par: h.olhar_para(ex.grade.centro(par[1] if par[0] == h.celula else par[0]))
	if p.has("anim"): await _anim(h, str(p.anim), float(p.get("ate", 0.0)), float(p.get("ritmo", 1.0)))
	if p.has("mensagem"): ex._registrar("[i]%s[/i]" % str(p.mensagem).replace("{nome}", h.nome))

## Ataque de verdade (d20 contra THAC0 − CA), sem derrubar: a cena não mata ninguém (PV mínimo 1).
func _ataque(p: Dictionary) -> void:
	var a := quem(p); if a == null: return
	var alvo: Node3D = null
	for h in ex.vivos():
		if alvo == null or h.global_position.distance_to(a.global_position) < alvo.global_position.distance_to(a.global_position): alvo = h
	if alvo == null: return
	a.olhar_para(alvo.global_position)
	var arma := str(p.get("arma", a.arma))
	var at: Dictionary = Sistema.atacar(a.thac0, alvo.ca, 0)
	var precisa: int = at.precisa
	var r: int = at.r
	var papel := "golpe"
	if p.has("anim"): a.tocar_anim(str(p.anim), 0.15)
	else:
		papel = a.escolher_golpe(false); a.tocar(papel, 0.15)   # golpe do estilo da arma (chicote: de cima)
	await ex.get_tree().create_timer(a.tempo_impacto(papel)).timeout
	if at.acerta:
		var dano := Dados.rolar(str(p.get("dano", a.dano)))
		alvo.pv = maxi(1, alvo.pv - dano)
		alvo.olhar_para(a.global_position); alvo.animar_dano(); alvo.piscar(Color(1, 0.3, 0.2))
		ex._registrar("%s acerta %s com o %s pelas barras (d20 %d, precisa %d): [color=#ff9a6a]%d de dano[/color]." % [a.nome, alvo.nome, arma, r, precisa, dano])
		ex._ficha_mudou(alvo)
	else:
		alvo.defender("esquivar", a.global_position, 0.0)
		ex._registrar("%s estala o %s pelas barras, mas %s se esquiva (d20 %d, precisa %d)." % [a.nome, arma, alvo.nome, r, precisa])
	await ex.get_tree().create_timer(0.9).timeout
	if a.vivo(): a.tocar("parado", 0.3)

# ---------- escolha ----------

signal _escolheu(id: String)
func _escolha(p: Dictionary) -> void:
	var sem_fim := 0
	var limite := int(p.get("limite", 0))
	var so_fim := false
	var q := quem(p)
	while true:
		var ops: Array = []
		for o in p.get("opcoes", []):
			if so_fim and not bool(o.get("fim", false)): continue
			ops.append({"id": str(o.id), "texto": _trocar(str(o.texto)), "dica": _trocar(str(o.get("dica", "")))})
		var texto := _trocar(str(p.get("texto_depois" if sem_fim > 0 and p.has("texto_depois") else "texto", "")))
		var id: String
		if not escolhas_auto.is_empty():
			id = str(escolhas_auto.pop_front())
			if not ops.any(func(o): return o.id == id): id = str(ops[0].id)
			ex._registrar("[color=#b9a3e3](teste) escolha: %s[/color]" % id)
		else:
			ex.hud_ui.dialogo(_trocar(str(p.get("titulo", ""))), texto, ops, func(x): _escolheu.emit(x),
				str(q.get_meta("retrato", "")) if q else "")
			id = await _escolheu
		var o: Dictionary = {}
		for x in p.get("opcoes", []):
			if str(x.id) == id: o = x
		ex._diario("evento", "Escolha: %s" % _trocar(str(o.get("texto", id))))
		_alvo_pj = null
		await rodar(o.get("faz", []))
		if bool(o.get("fim", false)): return
		sem_fim += 1
		if limite > 0 and sem_fim >= limite and not so_fim:
			await rodar(p.get("ao_limite", []))
			so_fim = true

## {agente} e {mais_forte} viram nomes.
func _trocar(t: String) -> String:
	var mf := _mais_forte()
	return t.replace("{agente}", ex.agente().nome).replace("{mais_forte}", mf.nome if mf else "")
