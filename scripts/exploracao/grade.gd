extends RefCounted
## Grade mecânica da masmorra, lida da planta (data/masmorra/layout.json).
## 1 célula = 1,5 m = 1 personagem. Paredes ficam ENTRE células de áreas diferentes, exceto nas
## aberturas. Portas de madeira começam FECHADAS: o personagem do jogador só passa depois de abrir
## (clicando nela); monstros abrem ao passar. Grades e celas não deixam passar (mas deixam ver).
## Passo reto custa 1,5 m; passo diagonal 2,12 m, e não corta quina de parede nem porta.

const CEL := 1.5
const DIAG := 1.5 * 1.41421356

var W := 0
var H := 0
var area := {}        # Vector2i -> id da área
var tipo := {}        # id da área -> tipo
var nomes := {}       # id da área -> nome
var abertas := {}     # "a|b" -> "hv"
var grades_fixas := {}   # "a|b" -> true: borda de barras fixas (vê através, não passa)
var portas := {}      # "v:x:y" / "h:x:y" -> porta (Dictionary)
var bloqueadas := {}  # células com obstáculo fixo (esteiras)
var porta_aberta := {} # id da porta -> true
var porta_barrada := {} # id -> true: trancada ou pregada (monstros também não passam)
var astar := AStar2D.new()        # jogador: só portas abertas e só células já exploradas
var astar_livre := AStar2D.new()  # monstros: atravessam portas de madeira (abrindo)

func carregar(caminho: String) -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(caminho))
	W = int(L.grade.largura); H = int(L.grade.altura)
	for ar in L.areas:
		tipo[ar.id] = ar.tipo; nomes[ar.id] = ar.nome
		for r in ar.retangulos:
			for y in range(int(r[1]), int(r[3])):
				for x in range(int(r[0]), int(r[2])):
					area[Vector2i(x, y)] = ar.id
	for p in L.aberturas:
		var par: Array = p if p is Array else p.entre
		abertas[_par(par[0], par[1])] = "hv" if p is Array else str(p.get("bordas", "hv"))
	for pt in L.portas:
		for k in int(pt.largura):
			var chave := "v:%d:%d" % [pt.x, pt.y + k] if pt.orient == "v" else "h:%d:%d" % [pt.x + k, pt.y]
			portas[chave] = pt
	for g in L.get("grades_fixas", []):
		grades_fixas[_par(str(g.entre[0]), str(g.entre[1]))] = true
	for e in L.get("esteiras", []):
		for y in range(int(e.de_y), int(e.ate_y)):
			bloqueadas[Vector2i(int(e.coluna), y)] = true
	_montar_astar()

func chao(c: Vector2i) -> bool:
	return area.has(c) and not bloqueadas.has(c)

func centro(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CEL, 0.0, (c.y + 0.5) * CEL)

func celula(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CEL), floori(p.z / CEL))

func area_de(c: Vector2i) -> String:
	return str(area.get(c, ""))

## Porta na borda entre duas células vizinhas (reto), ou {}.
func porta_entre(a: Vector2i, b: Vector2i) -> Dictionary:
	return portas.get(_borda(a, b), {})

## Passo reto (vizinhos de lado). `abre_portas`: porta de madeira fechada conta como passagem.
func passa_reto(a: Vector2i, b: Vector2i, abre_portas := false) -> bool:
	if not chao(a) or not chao(b): return false
	var ia: String = area[a]; var ib: String = area[b]
	var ch := _borda(a, b)
	if portas.has(ch):
		var pt: Dictionary = portas[ch]
		if porta_aberta.has(pt.id): return true   # porta, dupla ou grade aberta
		return pt.tipo in ["porta", "dupla"] and abre_portas and not porta_barrada.has(pt.id)
	if ia == ib: return true
	var par := _par(ia, ib)
	return abertas.has(par) and (abertas[par] as String).contains(ch.left(1))

## Passo para qualquer uma das 8 vizinhas.
func passa(a: Vector2i, b: Vector2i, abre_portas := false) -> bool:
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO: return false
	if d.x == 0 or d.y == 0: return passa_reto(a, b, abre_portas)
	var h := a + Vector2i(d.x, 0); var v := a + Vector2i(0, d.y)
	for par in [[a, h], [h, b], [a, v], [v, b]]:
		if not passa_reto(par[0], par[1]) or not porta_entre(par[0], par[1]).is_empty(): return false
	return true

## A luz e o olhar atravessam a borda entre duas vizinhas de lado? Rocha, parede e porta fechada
## bloqueiam; abertura, porta aberta, grade e cela deixam ver.
func transparente(a: Vector2i, b: Vector2i) -> bool:
	if not area.has(a) or not area.has(b): return false
	var ch := _borda(a, b)
	if portas.has(ch):
		var pt: Dictionary = portas[ch]
		return pt.tipo in ["grade", "cela"] or porta_aberta.has(pt.id)
	var ia: String = area[a]; var ib: String = area[b]
	if ia == ib: return true
	var cela: bool = (tipo[ia] == "cela" and ib == "19") or (tipo[ib] == "cela" and ia == "19")
	if cela: return true
	var par := _par(ia, ib)
	if grades_fixas.has(par): return true   # barras fixas: deixam ver, não deixam passar
	return abertas.has(par) and (abertas[par] as String).contains(ch.left(1))

## Linha de visada entre os centros de duas células (percorre as células cruzadas pela reta).
## Passando exatamente por uma quina, basta um dos dois lados estar livre.
func linha(a: Vector2i, b: Vector2i) -> bool:
	if a == b: return true
	var dx := b.x - a.x; var dy := b.y - a.y
	var sx := signi(dx); var sy := signi(dy)
	var tdx := INF if dx == 0 else 1.0 / absf(dx)
	var tdy := INF if dy == 0 else 1.0 / absf(dy)
	var tx := tdx * 0.5; var ty := tdy * 0.5
	var c := a
	while c != b:
		if absf(tx - ty) < 1e-6:
			var hx := c + Vector2i(sx, 0); var vy := c + Vector2i(0, sy); var n := c + Vector2i(sx, sy)
			if not ((transparente(c, hx) and transparente(hx, n)) or (transparente(c, vy) and transparente(vy, n))): return false
			c = n; tx += tdx; ty += tdy
		elif tx < ty:
			var n := c + Vector2i(sx, 0)
			if not transparente(c, n): return false
			c = n; tx += tdx
		else:
			var n := c + Vector2i(0, sy)
			if not transparente(c, n): return false
			c = n; ty += tdy
	return true

## Células de cada lado da porta: [[lado_a, lado_b], ...] (uma dupla por célula de largura).
func lados_da_porta(pt: Dictionary) -> Array:
	var out := []
	for k in int(pt.largura):
		if pt.orient == "v": out.append([Vector2i(int(pt.x) - 1, int(pt.y) + k), Vector2i(int(pt.x), int(pt.y) + k)])
		else: out.append([Vector2i(int(pt.x) + k, int(pt.y) - 1), Vector2i(int(pt.x) + k, int(pt.y))])
	return out

func abrir_porta(pt: Dictionary) -> void:
	if porta_aberta.has(pt.id): return
	porta_aberta[pt.id] = true
	for par in lados_da_porta(pt):
		for ag in [astar, astar_livre]:
			if ag.has_point(_id(par[0])) and ag.has_point(_id(par[1])):
				ag.connect_points(_id(par[0]), _id(par[1]))

## Fecha de novo (evento da aventura: o carcereiro bate a grade). Monstros continuam abrindo porta de
## madeira ao passar, a não ser que esteja barrada; grade e cela fechadas ninguém atravessa.
func fechar_porta(pt: Dictionary) -> void:
	if not porta_aberta.has(pt.id): return
	porta_aberta.erase(pt.id)
	for par in lados_da_porta(pt):
		var a := _id(par[0]); var b := _id(par[1])
		if astar.has_point(a) and astar.has_point(b): astar.disconnect_points(a, b)
		var madeira: bool = pt.tipo in ["porta", "dupla"] and not porta_barrada.has(pt.id)
		if not madeira and astar_livre.has_point(a) and astar_livre.has_point(b): astar_livre.disconnect_points(a, b)

## Trancada ou pregada: monstros não abrem ao passar. Liga/desliga a passagem no grafo deles.
func barrar_porta(pt: Dictionary, sim: bool) -> void:
	if sim: porta_barrada[pt.id] = true
	else: porta_barrada.erase(pt.id)
	for par in lados_da_porta(pt):
		var a := _id(par[0]); var b := _id(par[1])
		if not (astar_livre.has_point(a) and astar_livre.has_point(b)): continue
		if sim and not porta_aberta.has(pt.id): astar_livre.disconnect_points(a, b)
		elif not sim: astar_livre.connect_points(a, b)

## O jogador só planeja caminho por onde já esteve (ou já viu).
func marcar_explorada(c: Vector2i) -> void:
	if astar.has_point(_id(c)): astar.set_point_disabled(_id(c), false)

func custo(a: Vector2i, b: Vector2i) -> float:
	return CEL if (a.x == b.x or a.y == b.y) else DIAG

func vizinhas(c: Vector2i, abre_portas := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := c + Vector2i(dx, dy)
			if n != c and passa(c, n, abre_portas): out.append(n)
	return out

## Lado a lado (inclui diagonal) e sem parede no meio: alcance de corpo a corpo.
## Na diagonal basta um dos dois lados da quina estar livre (porta aberta conta): dá para golpear
## quem está do outro lado do vão da porta, mesmo sem poder andar cortando a quina.
func adjacentes(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO: return false
	if d.x == 0 or d.y == 0: return passa_reto(a, b)
	var h := a + Vector2i(d.x, 0); var v := a + Vector2i(0, d.y)
	return (passa_reto(a, h) and passa_reto(h, b)) or (passa_reto(a, v) and passa_reto(v, b))

## Caminho mais curto (sem a célula de saída). `ocupadas` bloqueia células; o destino pode estar ocupado
## se `ate_vizinho` for verdadeiro (para chegar ao lado de alguém).
## `livre`: caminho de monstro (atravessa portas fechadas e lugares não explorados).
func caminho(de: Vector2i, para: Vector2i, ocupadas := {}, livre := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not chao(de) or not chao(para): return out
	var ag: AStar2D = astar_livre if livre else astar
	var reativar: Array[int] = []
	if not livre:
		for c in [de, para]:
			if ag.is_point_disabled(_id(c)): ag.set_point_disabled(_id(c), false); reativar.append(_id(c))
	var desligar: Array[int] = []
	for c in ocupadas:
		if c != de and c != para and ag.has_point(_id(c)) and not ag.is_point_disabled(_id(c)):
			ag.set_point_disabled(_id(c), true); desligar.append(_id(c))
	var ids := ag.get_id_path(_id(de), _id(para))
	for i in desligar: ag.set_point_disabled(i, false)
	for i in reativar: ag.set_point_disabled(i, true)
	for k in range(1, ids.size()):
		out.append(Vector2i(ids[k] % W, ids[k] / W))
	return out

func comprimento(de: Vector2i, cam: Array[Vector2i]) -> float:
	var t := 0.0; var a := de
	for c in cam:
		t += custo(a, c); a = c
	return t

## Células alcançáveis com até `max_m` metros (Dijkstra). Devolve {célula: [custo, anterior]}.
## `permitidas` vazio = todas; senão só essas células (o jogador só anda pelo que já viu).
func alcance(de: Vector2i, max_m: float, ocupadas := {}, abre_portas := false, permitidas := {}) -> Dictionary:
	var dist := {de: [0.0, de]}
	var aberto: Array[Vector2i] = [de]
	while not aberto.is_empty():
		var mi := 0
		for i in aberto.size():
			if dist[aberto[i]][0] < dist[aberto[mi]][0]: mi = i
		var c: Vector2i = aberto[mi]; aberto.remove_at(mi)
		var dc: float = dist[c][0]
		for n in vizinhas(c, abre_portas):
			if ocupadas.has(n) or (not permitidas.is_empty() and not permitidas.has(n)): continue
			var nd := dc + custo(c, n)
			if nd > max_m + 0.01: continue
			if not dist.has(n) or nd < dist[n][0] - 0.001:
				dist[n] = [nd, c]
				if not aberto.has(n): aberto.append(n)
	return dist

func refazer(alc: Dictionary, para: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := para
	while alc.has(c) and alc[c][1] != c:
		out.push_front(c); c = alc[c][1]
	return out

func _montar_astar() -> void:
	astar.clear(); astar_livre.clear()   # refeito quando a aventura põe obstáculos (props)
	for c in area:
		if not chao(c): continue
		astar.add_point(_id(c), Vector2(c.x, c.y)); astar.set_point_disabled(_id(c), true)
		astar_livre.add_point(_id(c), Vector2(c.x, c.y))
	for c in area:
		if not chao(c): continue
		for n in vizinhas(c, false):
			if _id(n) > _id(c): astar.connect_points(_id(c), _id(n))
		for n in vizinhas(c, true):
			if _id(n) > _id(c): astar_livre.connect_points(_id(c), _id(n))

func _id(c: Vector2i) -> int:
	return c.y * W + c.x

func _borda(a: Vector2i, b: Vector2i) -> String:
	if a.y == b.y: return "v:%d:%d" % [maxi(a.x, b.x), a.y]
	return "h:%d:%d" % [a.x, maxi(a.y, b.y)]

func _par(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
