extends Node
## Combate por turnos na grade, no padrão B/X:
## rodada de 10 s · iniciativa d6 por lado (o maior age primeiro) · cada um, na sua vez, anda até o
## seu movimento de combate (1/3 do de exploração) e/ou ataca quem está ao lado.
## Ataque: d20 + mods ≥ THAC0 − CA do alvo (20 natural sempre acerta, 1 sempre erra).
## Moral dos monstros: 2d6 > moral = fogem (testa na primeira baixa e quando metade cai).

const Dados = preload("res://scripts/regras/dados.gd")
const Efeitos = preload("res://scripts/visual/efeitos.gd")

signal registro(texto: String)
signal mudou
signal terminou(resultado: String, xp: int, rodadas: int)
signal _fim_de_turno

var grade: RefCounted
var camera: Camera3D        # para o tremor de impacto
var marca_alcance: Node    # marcas.gd
var marca_caminho: Node
var marca_vez: Node
var exploradas := {}       # o jogador só anda pelo que já viu (visao.gd)
var visivel: Callable      # (ator) -> bool: o jogador está vendo esse ator?
var abrir_porta: Callable  # (porta, de_celula) -> void
var proibidas: Callable    # () -> {casa: true}: armadilhas vistas (fosso), onde herói não para (atravessa pulando)
var no_fosso: Callable     # (ator) -> bool: caiu no fosso
var turno_no_fosso: Callable  # (ator) -> await: a vez de quem está no fosso (sair ou passar)

var ativo := false
var ocupado := false
var rodada := 0
var vez: Node = null       # ator da vez
var restante := 0.0        # metros de movimento que sobram na vez de um personagem
var previa_m := -1.0       # custo do caminho sob o mouse
var grupo: Array = []
var monstros: Array = []
var _alc := {}             # onde quem age pode parar (custo, anterior)
var _alc_todo := {}        # inclui as casas de aliados, que se atravessam mas onde não se para
var ordem_lados: Array = []   # ordem dos lados nesta rodada (para a tela de iniciativa)
var ini_grupo := 0            # d6 de iniciativa de cada lado nesta rodada (0 = rodada de surpresa)
var ini_monstros := 0
var alvo_pairado: Node = null # inimigo sob o mouse (a tela mostra o que precisa no d20)
var _mortos := 0
var _xp := 0
var _moral_primeira := false
var _moral_metade := false

## Marca de quem age: círculo no chão, embaixo do personagem (amarelo) ou da criatura (vermelho).
const COR_VEZ := Color(1.0, 0.8, 0.3, 0.9)
const RAIO_VEZ := 0.55

func iniciar(g: Array, m: Array, surpreso_grupo: bool, surpreso_monstros: bool) -> void:
	grupo = g; monstros = m; ativo = true; rodada = 0; _mortos = 0; _xp = 0
	_moral_primeira = false; _moral_metade = false
	for x in grupo + monstros: _entrar(x)
	var vistos := monstros.filter(func(x): return _ve(x))
	var nomes := ", ".join(vistos.map(func(x): return x.nome)) if not vistos.is_empty() else "algo no escuro"
	registro.emit("[b]Combate![/b] %s." % nomes)
	if surpreso_grupo and not surpreso_monstros: registro.emit("O grupo foi [color=#ff9a6a]surpreendido[/color]: os monstros agem primeiro, sozinhos.")
	elif surpreso_monstros and not surpreso_grupo: registro.emit("Os monstros foram [color=#9ad0ff]surpreendidos[/color]: o grupo tem uma rodada livre.")
	await _laco(surpreso_grupo != surpreso_monstros, surpreso_grupo)

func _laco(rodada_de_surpresa: bool, grupo_surpreso: bool) -> void:
	while ativo:
		rodada += 1
		var ordem: Array = []
		if rodada == 1 and rodada_de_surpresa:
			ordem = ["monstros"] if grupo_surpreso else ["grupo"]
			ini_grupo = 0; ini_monstros = 0
			registro.emit("[color=#c8b89a]— Rodada 1 (surpresa) —[/color]")
		else:
			var ig := Dados.d(6); var im := Dados.d(6)
			while ig == im:
				ig = Dados.d(6); im = Dados.d(6)
			ordem = ["grupo", "monstros"] if ig > im else ["monstros", "grupo"]
			ini_grupo = ig; ini_monstros = im
			registro.emit("[color=#c8b89a]— Rodada %d —[/color] iniciativa: grupo %d × monstros %d" % [rodada, ig, im])
		ordem_lados = ordem
		for lado in ordem:
			var lista: Array = grupo if lado == "grupo" else monstros
			for a in lista.duplicate():
				if not ativo: break
				if not is_instance_valid(a) or not a.vivo(): continue
				if lado == "grupo": await _turno_personagem(a)
				else: await _turno_monstro(a)
				if _checar_fim(): break
			if not ativo: break
	return

# ---------- vez de um personagem (jogador) ----------

func _turno_personagem(h: Node) -> void:
	vez = h; restante = h.mov_combate_m
	h.set_meta("trocou", false)
	if no_fosso.is_valid() and no_fosso.call(h):
		marca_alcance.limpar(); marca_vez.limpar(); marca_vez.alvo(h.celula, COR_VEZ, RAIO_VEZ); marca_vez.seguir(h, h.celula)
		mudou.emit()
		ocupado = true
		await turno_no_fosso.call(h)
		ocupado = false
		return
	_mostrar_alcance()
	mudou.emit()
	await _fim_de_turno
	marca_alcance.limpar(); marca_caminho.limpar()

## Monstro que entra no meio do combate (age a partir da próxima vez do lado dos monstros).
func adicionar(m: Node) -> void:
	monstros.append(m); _entrar(m)
	mudou.emit()

## Botão "Atacar/Atirar": o inimigo à vista mais perto que dá para atingir nesta vez.
func atacar_mais_proximo() -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo": return
	var melhor: Node = null; var menor := INF
	for m in monstros:
		if not (is_instance_valid(m) and m.vivo() and _ve(m)): continue
		var ok: bool = _faixa(vez, m) >= 0 or grade.adjacentes(vez.celula, m.celula) or _melhor_vizinha(m) != Vector2i(-999, -999)
		var d: float = Vector2(m.celula - vez.celula).length()
		if ok and d < menor:
			menor = d; melhor = m
	if melhor: clicar(melhor.celula, melhor)
	else: registro.emit("Nenhum inimigo ao alcance nesta vez.")

func encerrar_turno() -> void:
	if ativo and vez and vez.lado == "grupo" and not ocupado:
		_fim_de_turno.emit()

func clicar(c: Vector2i, alvo: Node) -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo": return
	if alvo == null: alvo = _monstro_em(c)
	if alvo and _faixa(vez, alvo) >= 0:
		ocupado = true; await _atacar(vez, alvo, true); ocupado = false
		_fim_de_turno.emit()
		return
	if alvo:
		if grade.adjacentes(vez.celula, alvo.celula):
			ocupado = true; await _atacar(vez, alvo); ocupado = false
			_fim_de_turno.emit()
			return
		var lado := _melhor_vizinha(alvo)
		if lado == Vector2i(-999, -999):
			# Longe demais: anda o máximo que der na direção dele, sem atacar.
			var rumo := _rumo(_alc, vez, alvo)
			if rumo == vez.celula: return
			ocupado = true
			restante -= float(_alc[rumo][0])
			marca_caminho.limpar(); marca_alcance.limpar()
			await _andar(vez, grade.refazer(_alc_todo, rumo))
			ocupado = false
			_mostrar_alcance(); mudou.emit()
			if restante < 1.49: _fim_de_turno.emit()
			return
		ocupado = true
		restante -= float(_alc[lado][0])
		await _andar(vez, grade.refazer(_alc_todo, lado))
		await _atacar(vez, alvo)
		ocupado = false
		_fim_de_turno.emit()
		return
	if _alc.has(c) and c != vez.celula:
		ocupado = true
		restante -= float(_alc[c][0])
		marca_caminho.limpar(); marca_alcance.limpar()
		await _andar(vez, grade.refazer(_alc_todo, c))
		ocupado = false
		_mostrar_alcance(); mudou.emit()
		if restante < 1.49 and _inimigo_ao_lado(vez) == null:
			_fim_de_turno.emit()

const CURSOR_ESPADA := preload("res://arte/final/interface/cursores/espada.png")
const CURSOR_FLECHA := preload("res://arte/final/interface/cursores/flecha.png")
var _cursor := ""
## Cursor sobre um inimigo atacável: espada (corpo a corpo) ou flecha (à distância); fora disso, o normal.
func _por_cursor(tipo: String) -> void:
	if tipo == _cursor: return
	_cursor = tipo
	match tipo:
		"espada": Input.set_custom_mouse_cursor(CURSOR_ESPADA, Input.CURSOR_ARROW, Vector2(2, 2))
		"flecha": Input.set_custom_mouse_cursor(CURSOR_FLECHA, Input.CURSOR_ARROW, Vector2(2, 2))
		_: Input.set_custom_mouse_cursor(null)

func pairar(c: Vector2i, alvo: Node) -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo":
		_por_cursor(""); return
	marca_caminho.limpar(); previa_m = -1.0
	if alvo == null: alvo = _monstro_em(c)
	alvo_pairado = alvo if alvo and _ve(alvo) else null
	if alvo_pairado == null: _por_cursor("")
	elif _faixa(vez, alvo) >= 0 and not grade.adjacentes(vez.celula, alvo.celula): _por_cursor("flecha")
	elif grade.adjacentes(vez.celula, alvo.celula) or _melhor_vizinha(alvo) != Vector2i(-999, -999): _por_cursor("espada")
	else: _por_cursor("")
	if alvo and _faixa(vez, alvo) >= 0:
		# Disparo: sem caminho; a cor diz a faixa (curta +1 · média · longa −1).
		var fx := _faixa(vez, alvo)
		marca_caminho.alvo(alvo.celula, [Color(0.95, 0.3, 0.1, 0.85), Color(0.95, 0.55, 0.1, 0.8), Color(0.95, 0.8, 0.2, 0.75)][fx], 0.55)
		mudou.emit()
		return
	if alvo:
		if not grade.adjacentes(vez.celula, alvo.celula):
			var lado := _melhor_vizinha(alvo)
			if lado == Vector2i(-999, -999): lado = _rumo(_alc, vez, alvo)
			if lado != vez.celula:
				marca_caminho.pontos(grade.refazer(_alc_todo, lado), Color(1, 0.95, 0.8, 0.7))
				previa_m = float(_alc[lado][0])
		marca_caminho.alvo(alvo.celula, Color(0.9, 0.2, 0.12, 0.85), 0.55)
	elif _alc.has(c) and c != vez.celula:
		var cam: Array[Vector2i] = grade.refazer(_alc_todo, c)
		marca_caminho.pontos(cam.slice(0, cam.size() - 1), Color(1, 0.95, 0.8, 0.7))
		marca_caminho.alvo(c, Color(1, 0.92, 0.7, 0.8))
		previa_m = float(_alc[c][0])
	mudou.emit()

func _mostrar_alcance() -> void:
	# Heróis atravessam os companheiros (só não param na casa deles); monstros barram.
	_alc_todo = grade.alcance(vez.celula, restante, _barram(vez), false, exploradas)
	_alc = _alc_todo.duplicate()
	for x in grupo:
		if is_instance_valid(x) and x != vez and x.vivo(): _alc.erase(x.celula); _alc.erase(x.proxima_celula())
	if vez.lado == "grupo" and proibidas.is_valid():
		for c in proibidas.call(): _alc.erase(c)
	marca_alcance.limpar()
	var cels: Array = _alc.keys().filter(func(k): return k != vez.celula)
	marca_alcance.por(cels, Color(0.35, 0.65, 1.0, 0.28))
	var alvos: Array = []
	for m in monstros:
		if is_instance_valid(m) and m.vivo() and _ve(m) and (_faixa(vez, m) >= 0 or grade.adjacentes(vez.celula, m.celula) or _melhor_vizinha(m) != Vector2i(-999, -999)):
			alvos.append(m.celula)
	for c in alvos: marca_alcance.alvo(c, Color(0.95, 0.25, 0.15, 0.75), RAIO_VEZ)
	marca_vez.limpar(); marca_vez.alvo(vez.celula, COR_VEZ, RAIO_VEZ); marca_vez.seguir(vez, vez.celula)

## Célula mais adiantada, dentro do alcance, no caminho de `quem` até `alvo`.
func _rumo(alc: Dictionary, quem: Node, alvo: Node) -> Vector2i:
	var destino: Vector2i = quem.celula
	for c in grade.caminho(quem.celula, alvo.celula, _barram(quem), quem.lado == "monstros"):
		if alc.has(c): destino = c
		elif quem.lado != "grupo" or not _alc_todo.has(c): break   # casa de aliado: atravessa e segue
	return destino

func _melhor_vizinha(alvo: Node) -> Vector2i:
	var melhor := Vector2i(-999, -999); var menor := INF
	for c in _alc:
		if grade.adjacentes(c, alvo.celula) and float(_alc[c][0]) < menor:
			menor = float(_alc[c][0]); melhor = c
	return melhor

# ---------- vez de um monstro ----------

func _turno_monstro(m: Node) -> void:
	vez = m; mudou.emit()
	marca_vez.limpar(); marca_vez.alvo(m.celula, Color(0.95, 0.3, 0.2, 0.9), RAIO_VEZ); marca_vez.seguir(m, m.celula)
	await get_tree().create_timer(0.35).timeout
	var alvo := _mais_proximo(m, grupo)
	if alvo == null: return
	if not grade.adjacentes(m.celula, alvo.celula):
		var ocup := _ocupadas(m)
		var alc: Dictionary = grade.alcance(m.celula, m.mov_combate_m, ocup, true)
		var destino := Vector2i(-999, -999); var menor := INF
		for c in alc:
			if grade.adjacentes(c, alvo.celula) and float(alc[c][0]) < menor:
				menor = float(alc[c][0]); destino = c
		if destino == Vector2i(-999, -999): destino = _rumo(alc, m, alvo)
		if destino != Vector2i(-999, -999) and destino != m.celula:
			await _andar(m, grade.refazer(alc, destino))
	if grade.adjacentes(m.celula, alvo.celula):
		await _atacar(m, alvo)
	else:
		await get_tree().create_timer(0.2).timeout

# ---------- ataque, baixas e moral ----------

## Faixa de distância do disparo de `a` em `alvo`: 0 curta (+1), 1 média, 2 longa (−1); −1 = não dá
## (sem arma à distância, sem munição, longe demais ou sem linha de visada).
func _faixa(a: Node, alvo: Node) -> int:
	if a.dist_faixas.is_empty() or a.municao <= 0 or not _ve(alvo): return -1
	if not grade.linha(a.celula, alvo.celula): return -1
	var d: float = Vector2(alvo.celula - a.celula).length() * 1.5
	for i in 3:
		if d <= float(a.dist_faixas[i]): return i
	return -1

## O que `a` precisa tirar no d20 para acertar `alvo` (já com os bônus), a chance e o dano.
## 20 sempre acerta e 1 sempre erra, então o número fica entre 2 e 20.
func previsao(a: Node, alvo: Node) -> Dictionary:
	var faixa := _faixa(a, alvo)
	var dist: bool = faixa >= 0 and not grade.adjacentes(a.celula, alvo.celula)
	var mod: int = (a.dist_mod + [1, 0, -1][faixa]) if dist else a.mod_acerto
	var n: int = clampi(a.thac0 - alvo.ca - mod, 2, 20)
	var dano: String = a.dist_dano if dist else ("%s%s" % [a.dano, ("%+d" % a.mod_dano) if a.mod_dano != 0 else ""])
	return {"n": n, "chance": (21 - n) * 5, "dano": dano, "distancia": dist, "mod": mod}

func _atacar(a: Node, alvo: Node, distancia := false) -> void:
	marca_caminho.limpar()
	_por_cursor(""); alvo_pairado = null
	# Rola antes: o d20 aparece girando sobre o atacante enquanto ele arma o golpe.
	var r := Dados.d(20)
	var precisa: int = a.thac0 - alvo.ca
	var faixa := _faixa(a, alvo) if distancia else -1
	var mod: int = (a.dist_mod + [1, 0, -1][faixa]) if distancia else a.mod_acerto
	var total: int = r + mod
	var acerta: bool = r == 20 or (r != 1 and total >= precisa)
	# Erro com motivo: escudo bloqueia, arma de duas mãos apara, o resto esquiva; 1 natural = golpe em falso.
	var defesa: String = "" if acerta or r == 1 else alvo.defesa()
	if distancia:
		a.gastar_municao()
		var de: Vector3 = a.global_position + Vector3(0, a.altura_texto() * 0.95, 0)
		var para: Vector3 = alvo.global_position + Vector3(0, alvo.altura_texto() * 0.8, 0)
		var voo := maxf(de.distance_to(para) / 24.0, 0.12)
		if defesa != "": alvo.defender(defesa, a.global_position, a.tempo_tiro() + voo)
		await a.animar_tiro(alvo)
		if not is_instance_valid(alvo): return
		await Efeitos.flecha(a.get_parent(), de, para)
	else:
		var golpe: String = a.escolher_golpe(r == 20)
		if defesa != "": alvo.defender(defesa, a.global_position, a.tempo_impacto(golpe))
		await a.animar_golpe(alvo, golpe)
	if not is_instance_valid(alvo): return
	var mod_txt := (" %+d = %d" % [mod, total]) if mod != 0 else ""
	var acao := ("atira (%s, %s) em" % [a.dist_arma, ["curta", "média", "longa"][faixa]]) if distancia else "ataca"
	var txt := "%s %s %s: d20 [b]%d[/b]%s (precisa %d) → " % [_nome(a), acao, _nome(alvo), r, mod_txt, precisa]
	var topo: Vector3 = alvo.global_position + Vector3(0, alvo.altura_texto(), 0)
	var no_grupo: bool = alvo.lado == "grupo"
	if acerta:
		var expr: String = a.dist_dano if distancia else a.dano + (("%+d" % a.mod_dano) if a.mod_dano != 0 else "")
		var dd := Dados.detalhar(expr)
		var dano := maxi(1, int(dd.total))
		alvo.pv -= dano
		txt += "[color=#ffcf6a]acerta[/color]! %s: %s = [b]%d[/b] de dano." % [expr, dd.texto, dano]
		registro.emit(txt)
		# Impacto: quanto maior o dano (e no 20 natural), mais forte. Mais forte quando a Tessa apanha.
		var critico := r == 20
		var forca := clampf(0.35 + dano * 0.1, 0.4, 1.0) * (1.5 if critico else 1.0)
		alvo.piscar(Color(1, 0.25, 0.2, 0.6) if no_grupo else Color(1, 0.95, 0.85, 0.7))
		alvo.recuar(a.global_position, 0.18 + 0.12 * forca)
		if camera: camera.tremer((0.09 if no_grupo else 0.06) * forca)
		Efeitos.texto(alvo.get_parent(), topo, ("CRÍTICO!  %d" % dano) if critico else str(dano),
			Color(1, 0.35, 0.25) if no_grupo else Color(1, 0.85, 0.35), minf(0.9 + 0.1 * minf(dano, 6) + (0.15 if critico else 0.0), 1.4))
		if alvo.pv <= 0:
			alvo.animar_morte()
			registro.emit("[color=#ff7a5a]%s cai.[/color]" % _nome(alvo))
			_baixa(alvo)
		else:
			alvo.animar_dano()
		await Efeitos.congelar(self, 0.06 + 0.05 * forca)
	else:
		var o_que: String = "Golpe em falso!" if r == 1 else {"bloquear": "Bloqueou!", "aparar": "Aparou!"}.get(defesa, "Esquivou!")
		if r == 1:
			a.recuar(alvo.global_position, 0.25)
		elif defesa == "bloquear" or defesa == "aparar":
			alvo.recuar(a.global_position, 0.08 if alvo._tem(defesa) else 0.12)
			alvo.piscar(Color(0.75, 0.85, 1.0, 0.45), 0.1)
			if camera: camera.tremer(0.025)
		elif not alvo._tem("esquivar"):
			alvo.recuar(a.global_position, 0.35, true)
		Efeitos.texto(alvo.get_parent(), topo, o_que, Color(0.78, 0.8, 0.85), 0.75, 0.6, 0.85)
		registro.emit(txt + "[color=#9aa4b0]erra (%s).[/color]" % o_que.trim_suffix("!").to_lower())
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(a) and a.vivo(): a.tocar("parado")
	mudou.emit()

func _baixa(x: Node) -> void:
	if x.lado != "monstros": return
	_mortos += 1; _xp += x.xp
	var total := monstros.size()
	if not _moral_primeira:
		_moral_primeira = true; _testar_moral()
	elif not _moral_metade and _mortos * 2 >= total:
		_moral_metade = true; _testar_moral()

func _testar_moral() -> void:
	var vivos := monstros.filter(func(m): return is_instance_valid(m) and m.vivo())
	if vivos.is_empty(): return
	var moral: int = vivos[0].moral
	if moral >= 12: return
	var r := Dados.d(6) + Dados.d(6)
	if r > moral:
		registro.emit("Moral dos monstros: 2d6 = %d contra %d → [color=#9ad0ff]fogem![/color]" % [r, moral])
		for m in vivos:
			_fugir(m)
	else:
		registro.emit("Moral dos monstros: 2d6 = %d contra %d → continuam lutando." % [r, moral])

func _fugir(m: Node) -> void:
	m.fugindo = true; _xp += m.xp
	var alc: Dictionary = grade.alcance(m.celula, m.mov_combate_m * 2.0, _ocupadas(m), true)
	var melhor: Vector2i = m.celula; var maior := -1.0
	for c in alc:
		var perto := INF
		for h in grupo:
			if is_instance_valid(h) and h.vivo(): perto = minf(perto, Vector2(c - h.celula).length())
		if perto > maior: maior = perto; melhor = c
	if melhor != m.celula:
		m.seguir(grade.refazer(alc, melhor))
		await m.parou
	m.sumir()

func _checar_fim() -> bool:
	if not ativo: return true
	var g := grupo.any(func(h): return is_instance_valid(h) and h.vivo())
	var m := monstros.any(func(x): return is_instance_valid(x) and x.vivo())
	if g and m: return false
	ativo = false; vez = null; _por_cursor("")
	for x in grupo + monstros:
		if is_instance_valid(x): x.no_combate = false
	marca_alcance.limpar(); marca_caminho.limpar(); marca_vez.limpar()
	terminou.emit("vitoria" if g else "derrota", _xp, rodada)
	return true

# ---------- utilidades ----------

func _ve(a: Node) -> bool:
	return a.lado == "grupo" or not visivel.is_valid() or visivel.call(a)

func _nome(a: Node) -> String:
	return a.nome if _ve(a) else "Algo no escuro"

## Clique numa porta fechada durante a vez do personagem: abre se estiver ao lado (gasta a ação);
## senão anda até o lado dela (se der) e abre.
func clicar_porta(pt: Dictionary) -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo": return
	var lado := Vector2i(-999, -999); var menor := INF
	for par in grade.lados_da_porta(pt):
		for c in par:
			if _alc.has(c) and float(_alc[c][0]) < menor: menor = float(_alc[c][0]); lado = c
	if lado == Vector2i(-999, -999):
		registro.emit("A porta está longe demais para abrir nesta rodada.")
		return
	ocupado = true
	if lado != vez.celula:
		restante -= menor
		marca_alcance.limpar(); marca_caminho.limpar()
		await _andar(vez, grade.refazer(_alc_todo, lado))
	abrir_porta.call(pt, vez.celula)
	await get_tree().create_timer(0.4).timeout
	ocupado = false
	_fim_de_turno.emit()

func _andar(a: Node, cam: Array[Vector2i]) -> void:
	if cam.is_empty(): return
	a.seguir(cam)
	await a.parou

## No combate: longe (mais de 3 casas) do inimigo vivo mais próximo corre; perto, anda em guarda.
const PERTO_CASAS := 3
func _entrar(x: Node) -> void:
	x.no_combate = true; x.perto_de_inimigo = _perto_de_inimigo

func _perto_de_inimigo(a: Node) -> bool:
	var c: Vector2i = a.grade.celula(a.position)
	for x in (monstros if a.lado == "grupo" else grupo):
		if is_instance_valid(x) and x.vivo():
			var d: Vector2i = (x.celula as Vector2i) - c
			if maxi(absi(d.x), absi(d.y)) <= PERTO_CASAS: return true
	return false

## Casas que barram o caminho de `quem`: para heróis, só os monstros; para monstros, todos.
func _barram(quem: Node) -> Dictionary:
	if quem.lado != "grupo": return _ocupadas(quem)
	var d := {}
	for x in monstros:
		if is_instance_valid(x) and x.vivo(): d[x.celula] = true; d[x.proxima_celula()] = true
	return d

func _ocupadas(exceto: Node) -> Dictionary:
	var d := {}
	for x in grupo + monstros:
		if is_instance_valid(x) and x != exceto and x.vivo(): d[x.celula] = true; d[x.proxima_celula()] = true
	return d

func _monstro_em(c: Vector2i) -> Node:
	for m in monstros:
		if is_instance_valid(m) and m.vivo() and m.celula == c and _ve(m): return m
	return null

func _inimigo_ao_lado(h: Node) -> Node:
	for m in monstros:
		if is_instance_valid(m) and m.vivo() and grade.adjacentes(h.celula, m.celula): return m
	return null

func _mais_proximo(a: Node, lista: Array) -> Node:
	var melhor: Node = null; var menor := INF
	for x in lista:
		if not is_instance_valid(x) or not x.vivo(): continue
		var d: int = grade.caminho(a.celula, x.celula, {}, true).size()
		if d > 0 and d < menor: menor = d; melhor = x
	return melhor
