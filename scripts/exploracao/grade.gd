extends RefCounted
## Grade mecânica da masmorra, lida da planta (data/masmorra/layout.json).
## 1 célula = 1,5 m = 1 personagem. Paredes ficam ENTRE células de áreas diferentes, exceto nas
## aberturas; portas de madeira deixam passar (o jogo abre a porta); grades e celas, não.
## Passo reto custa 1,5 m; passo diagonal 2,12 m, e não corta quina de parede nem porta.

const CEL := 1.5
const DIAG := 1.5 * 1.41421356

var W := 0
var H := 0
var area := {}        # Vector2i -> id da área
var tipo := {}        # id da área -> tipo
var nomes := {}       # id da área -> nome
var abertas := {}     # "a|b" -> "hv"
var portas := {}      # "v:x:y" / "h:x:y" -> porta (Dictionary)
var bloqueadas := {}  # células com obstáculo fixo (esteiras)
var astar := AStar2D.new()

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

## Passo reto (vizinhos de lado).
func passa_reto(a: Vector2i, b: Vector2i) -> bool:
	if not chao(a) or not chao(b): return false
	var ia: String = area[a]; var ib: String = area[b]
	var ch := _borda(a, b)
	if portas.has(ch): return portas[ch].tipo in ["porta", "dupla"]
	if ia == ib: return true
	var par := _par(ia, ib)
	return abertas.has(par) and (abertas[par] as String).contains(ch.left(1))

## Passo para qualquer uma das 8 vizinhas.
func passa(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO: return false
	if d.x == 0 or d.y == 0: return passa_reto(a, b)
	var h := a + Vector2i(d.x, 0); var v := a + Vector2i(0, d.y)
	for par in [[a, h], [h, b], [a, v], [v, b]]:
		if not passa_reto(par[0], par[1]) or not porta_entre(par[0], par[1]).is_empty(): return false
	return true

func custo(a: Vector2i, b: Vector2i) -> float:
	return CEL if (a.x == b.x or a.y == b.y) else DIAG

func vizinhas(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := c + Vector2i(dx, dy)
			if n != c and passa(c, n): out.append(n)
	return out

## Lado a lado (inclui diagonal) e sem parede no meio: alcance de corpo a corpo.
func adjacentes(a: Vector2i, b: Vector2i) -> bool:
	return passa(a, b)

## Caminho mais curto (sem a célula de saída). `ocupadas` bloqueia células; o destino pode estar ocupado
## se `ate_vizinho` for verdadeiro (para chegar ao lado de alguém).
func caminho(de: Vector2i, para: Vector2i, ocupadas := {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not chao(de) or not chao(para): return out
	var desligar: Array[int] = []
	for c in ocupadas:
		if c != de and c != para and astar.has_point(_id(c)):
			astar.set_point_disabled(_id(c), true); desligar.append(_id(c))
	var ids := astar.get_id_path(_id(de), _id(para))
	for i in desligar: astar.set_point_disabled(i, false)
	for k in range(1, ids.size()):
		out.append(Vector2i(ids[k] % W, ids[k] / W))
	return out

func comprimento(de: Vector2i, cam: Array[Vector2i]) -> float:
	var t := 0.0; var a := de
	for c in cam:
		t += custo(a, c); a = c
	return t

## Células alcançáveis com até `max_m` metros (Dijkstra). Devolve {célula: [custo, anterior]}.
func alcance(de: Vector2i, max_m: float, ocupadas := {}) -> Dictionary:
	var dist := {de: [0.0, de]}
	var aberto: Array[Vector2i] = [de]
	while not aberto.is_empty():
		var mi := 0
		for i in aberto.size():
			if dist[aberto[i]][0] < dist[aberto[mi]][0]: mi = i
		var c: Vector2i = aberto[mi]; aberto.remove_at(mi)
		var dc: float = dist[c][0]
		for n in vizinhas(c):
			if ocupadas.has(n): continue
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
	for c in area:
		if chao(c): astar.add_point(_id(c), Vector2(c.x, c.y))
	for c in area:
		if not chao(c): continue
		for n in vizinhas(c):
			if _id(n) > _id(c): astar.connect_points(_id(c), _id(n))

func _id(c: Vector2i) -> int:
	return c.y * W + c.x

func _borda(a: Vector2i, b: Vector2i) -> String:
	if a.y == b.y: return "v:%d:%d" % [maxi(a.x, b.x), a.y]
	return "h:%d:%d" % [a.x, maxi(a.y, b.y)]

func _par(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
