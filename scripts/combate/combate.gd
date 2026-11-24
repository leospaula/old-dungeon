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

var ativo := false
var ocupado := false
var rodada := 0
var vez: Node = null       # ator da vez
var restante := 0.0        # metros de movimento que sobram na vez de um personagem
var previa_m := -1.0       # custo do caminho sob o mouse
var grupo: Array = []
var monstros: Array = []
var _alc := {}
var _mortos := 0
var _xp := 0
var _moral_primeira := false
var _moral_metade := false

func iniciar(g: Array, m: Array, surpreso_grupo: bool, surpreso_monstros: bool) -> void:
	grupo = g; monstros = m; ativo = true; rodada = 0; _mortos = 0; _xp = 0
	_moral_primeira = false; _moral_metade = false
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
			registro.emit("[color=#c8b89a]— Rodada 1 (surpresa) —[/color]")
		else:
			var ig := Dados.d(6); var im := Dados.d(6)
			while ig == im:
				ig = Dados.d(6); im = Dados.d(6)
			ordem = ["grupo", "monstros"] if ig > im else ["monstros", "grupo"]
			registro.emit("[color=#c8b89a]— Rodada %d —[/color] iniciativa: grupo %d × monstros %d" % [rodada, ig, im])
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
	_mostrar_alcance()
	mudou.emit()
	await _fim_de_turno
	marca_alcance.limpar(); marca_caminho.limpar()

## Monstro que entra no meio do combate (age a partir da próxima vez do lado dos monstros).
func adicionar(m: Node) -> void:
	monstros.append(m)
	mudou.emit()

func encerrar_turno() -> void:
	if ativo and vez and vez.lado == "grupo" and not ocupado:
		_fim_de_turno.emit()

func clicar(c: Vector2i, alvo: Node) -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo": return
	if alvo == null: alvo = _monstro_em(c)
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
			await _andar(vez, grade.refazer(_alc, rumo))
			ocupado = false
			_mostrar_alcance(); mudou.emit()
			if restante < 1.49: _fim_de_turno.emit()
			return
		ocupado = true
		restante -= float(_alc[lado][0])
		await _andar(vez, grade.refazer(_alc, lado))
		await _atacar(vez, alvo)
		ocupado = false
		_fim_de_turno.emit()
		return
	if _alc.has(c) and c != vez.celula:
		ocupado = true
		restante -= float(_alc[c][0])
		marca_caminho.limpar(); marca_alcance.limpar()
		await _andar(vez, grade.refazer(_alc, c))
		ocupado = false
		_mostrar_alcance(); mudou.emit()
		if restante < 1.49 and _inimigo_ao_lado(vez) == null:
			_fim_de_turno.emit()

func pairar(c: Vector2i, alvo: Node) -> void:
	if not ativo or ocupado or vez == null or vez.lado != "grupo": return
	marca_caminho.limpar(); previa_m = -1.0
	if alvo == null: alvo = _monstro_em(c)
	if alvo:
		if not grade.adjacentes(vez.celula, alvo.celula):
			var lado := _melhor_vizinha(alvo)
			if lado == Vector2i(-999, -999): lado = _rumo(_alc, vez, alvo)
			if lado != vez.celula:
				marca_caminho.por(grade.refazer(_alc, lado), Color(1, 0.95, 0.8, 0.45), 0.5)
				previa_m = float(_alc[lado][0])
		marca_caminho.por([alvo.celula], Color(0.9, 0.15, 0.1, 0.55), 0.05)
	elif _alc.has(c) and c != vez.celula:
		var cam: Array[Vector2i] = grade.refazer(_alc, c)
		marca_caminho.por(cam.slice(0, cam.size() - 1), Color(1, 0.95, 0.8, 0.45), 0.5)
		marca_caminho.por([c], Color(1, 0.95, 0.8, 0.5), 0.1)
		previa_m = float(_alc[c][0])
	mudou.emit()

func _mostrar_alcance() -> void:
	_alc = grade.alcance(vez.celula, restante, _ocupadas(vez), false, exploradas)
	marca_alcance.limpar()
	var cels: Array = _alc.keys().filter(func(k): return k != vez.celula)
	marca_alcance.por(cels, Color(0.35, 0.65, 1.0, 0.28))
	var alvos: Array = []
	for m in monstros:
		if is_instance_valid(m) and m.vivo() and _ve(m) and (grade.adjacentes(vez.celula, m.celula) or _melhor_vizinha(m) != Vector2i(-999, -999)):
			alvos.append(m.celula)
	marca_alcance.por(alvos, Color(0.95, 0.25, 0.15, 0.3))
	marca_vez.limpar(); marca_vez.por([vez.celula], Color(1.0, 0.8, 0.3, 0.45), 0.02)

## Célula mais adiantada, dentro do alcance, no caminho de `quem` até `alvo`.
func _rumo(alc: Dictionary, quem: Node, alvo: Node) -> Vector2i:
	var destino: Vector2i = quem.celula
	for c in grade.caminho(quem.celula, alvo.celula, _ocupadas(quem), quem.lado == "monstros"):
		if alc.has(c): destino = c
		else: break
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
	marca_vez.limpar(); marca_vez.por([m.celula], Color(0.95, 0.3, 0.2, 0.45), 0.02)
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

func _atacar(a: Node, alvo: Node) -> void:
	marca_caminho.limpar()
	# Rola antes: o d20 aparece girando sobre o atacante enquanto ele arma o golpe.
	var r := Dados.d(20)
	var precisa: int = a.thac0 - alvo.ca
	var total: int = r + a.mod_acerto
	var acerta: bool = r == 20 or (r != 1 and total >= precisa)
	Efeitos.dado(a, r, acerta, 0.6)
	await a.animar_golpe(alvo)
	if not is_instance_valid(alvo): return
	var mod_txt := (" %+d = %d" % [a.mod_acerto, total]) if a.mod_acerto != 0 else ""
	var txt := "%s ataca %s: d20 [b]%d[/b]%s (precisa %d) → " % [_nome(a), _nome(alvo), r, mod_txt, precisa]
	var topo: Vector3 = alvo.global_position + Vector3(0, alvo.altura_texto(), 0)
	var no_grupo: bool = alvo.lado == "grupo"
	if acerta:
		var expr: String = a.dano + (("%+d" % a.mod_dano) if a.mod_dano != 0 else "")
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
		# Erro com motivo: passou perto = bloqueou (escudo/arma); longe = esquivou; 1 natural = golpe em falso.
		var quase := total >= precisa - 3
		var tem_escudo: bool = alvo.lado == "grupo"
		var o_que := "Golpe em falso!" if r == 1 else ("Bloqueou!" if quase else "Esquivou!")
		if r == 1:
			a.recuar(alvo.global_position, 0.25)
		elif quase:
			alvo.recuar(a.global_position, 0.12)
			alvo.piscar(Color(0.75, 0.85, 1.0, 0.45), 0.1)
			if camera: camera.tremer(0.025)
			if not tem_escudo: o_que = "Aparou!"
		else:
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
	ativo = false; vez = null
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
		await _andar(vez, grade.refazer(_alc, lado))
	abrir_porta.call(pt, vez.celula)
	await get_tree().create_timer(0.4).timeout
	ocupado = false
	_fim_de_turno.emit()

func _andar(a: Node, cam: Array[Vector2i]) -> void:
	if cam.is_empty(): return
	a.seguir(cam)
	await a.parou

func _ocupadas(exceto: Node) -> Dictionary:
	var d := {}
	for x in grupo + monstros:
		if is_instance_valid(x) and x != exceto and x.vivo(): d[x.celula] = true
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
