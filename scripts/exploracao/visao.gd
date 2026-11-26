extends RefCounted
## Visão, luz e névoa de guerra na grade.
##
## Luz: a tocha do grupo ilumina 9 m (B/X); cada tocha de parede ilumina o que ela "vê" até 7,5 m.
## Ninguém enxerga através de parede, rocha ou porta fechada (grades e celas deixam ver).
## Jogador: olha em volta (360°) e vê o que está iluminado e na linha de visada.
## Monstros: só um cone à frente (120°); veem o que está iluminado ou dentro da visão no escuro deles.
## Névoa: nunca visto = preto · já visto e fora da vista = lembrança apagada, sem criaturas · à vista = normal.

const CEL := 1.5
const RAIO_TOCHA := 9.0
const RAIO_TOCHA_PAREDE := 7.5
const ALCANCE_MAX := 36.0
const MEIO_CONE := 60.0
const LEMBRADO := 110         # valor da névoa para "já visto" (0–255)

var grade: RefCounted
var tochas_parede: Array = []   # Vector2i da célula de cada tocha de parede
var exploradas := {}            # já vistas alguma vez
var visiveis := {}              # à vista agora
var _iluminadas := {}           # iluminadas pelas tochas de parede
var _img: Image
var _tex: ImageTexture

func _init(g: RefCounted) -> void:
	grade = g
	_img = Image.create(grade.W, grade.H, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_img)

func textura() -> ImageTexture:
	return _tex

## Recalcula a luz fixa (tochas de parede). Chamar ao abrir porta.
func recalcular_luz_fixa() -> void:
	_iluminadas.clear()
	for t in tochas_parede:
		for c in _perto(t, RAIO_TOCHA_PAREDE):
			if grade.linha(t, c): _iluminadas[c] = true

func iluminada_fixa(c: Vector2i) -> bool:
	return _iluminadas.has(c)

func atualizar_jogador(origem: Vector2i, tocha_acesa: bool, infra_m := 0.0) -> void:
	atualizar_grupo([[origem, infra_m]], [origem] if tocha_acesa else [])

## Visão do grupo: cada um vê, da própria casa, o que está iluminado (tochas de parede ou as tochas
## acesas na mão de alguém, cuja luz também precisa alcançar a casa) ou dentro da visão no escuro dada.
## olhos: [[célula, infravisão_m], ...]; tochas: células de quem está com tocha acesa.
var _luz_tochas := {}
func atualizar_grupo(olhos: Array, tochas: Array) -> void:
	visiveis.clear()
	_luz_tochas.clear()
	var luz_tocha := _luz_tochas
	for tocha in tochas:
		for c in _perto(tocha, RAIO_TOCHA):
			if grade.linha(tocha, c): luz_tocha[c] = true
	for o in olhos:
		var origem: Vector2i = o[0]; var infra: float = o[1]
		visiveis[origem] = true
		for c in _perto(origem, ALCANCE_MAX):
			if visiveis.has(c): continue
			var d := Vector2(c - origem).length() * CEL
			var luz := _iluminadas.has(c) or luz_tocha.has(c) or d <= infra
			if luz and grade.linha(origem, c): visiveis[c] = true
	for c in visiveis:
		if not exploradas.has(c):
			exploradas[c] = true
			grade.marcar_explorada(c)

## O monstro em `de`, olhando para `frente`, vê a célula `alvo`?
func monstro_ve(de: Vector2i, frente: Vector3, infra_m: float, alvo: Vector2i, alvo_com_tocha: bool) -> bool:
	var dv := Vector2(alvo - de) * CEL
	var d := dv.length()
	if d > ALCANCE_MAX: return false
	if d > 1.6:
		var f := Vector2(frente.x, frente.z)
		if f.length() > 0.01 and rad_to_deg(absf(f.angle_to(dv))) > MEIO_CONE: return false
	var luz := alvo_com_tocha or _iluminadas.has(alvo) or _luz_tochas.has(alvo) or d <= infra_m
	return luz and grade.linha(de, alvo)

func atualizar_textura(mestre: bool) -> void:
	for y in grade.H:
		for x in grade.W:
			var c := Vector2i(x, y)
			var v := 0
			if grade.area.has(c):
				v = 255 if (mestre or visiveis.has(c)) else (LEMBRADO if exploradas.has(c) else 0)
			else:
				# Rocha: assume o valor da vizinha mais "vista" (o topo da rocha acompanha a sala)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var n := c + Vector2i(dx, dy)
						if grade.area.has(n):
							v = maxi(v, 255 if (mestre or visiveis.has(n)) else (LEMBRADO if exploradas.has(n) else 0))
			_img.set_pixel(x, y, Color8(v, 0, 0))
	_tex.update(_img)

func _perto(o: Vector2i, raio_m: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := ceili(raio_m / CEL)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := o + Vector2i(dx, dy)
			if grade.area.has(c) and Vector2(dx, dy).length() * CEL <= raio_m: out.append(c)
	return out
