extends RefCounted
## Procurar (B/X) adaptado: portas secretas e armadilhas de sala.
## - Procurar na sala (medalhão Procurar): todos da área vasculham. Cada pessoa cobre 36 m² de chão
##   (com as paredes em volta) por turno; mínimo 1 turno. Sala 24 (110 m²): 3 pessoas 2 turnos, 5–6 → 1. Cada um rola em segredo, uma vez por
##   área: porta secreta 1 em 6 (elfo 2 em 6); armadilha de sala 1 em 6 (anão 2 em 6).
## - Elfo nota porta secreta de passagem (1 em 6, até 2 casas), uma vez por turno, se não estiver correndo.
## - Modo Cauteloso: quem lidera procura armadilhas nas casas à frente enquanto anda (rolagem secreta).
## - Armadilha de sala não achada: passar por cima dispara 2 em 6. Achada: marcada em vermelho e o
##   caminho desvia; se for o único caminho, pula por cima.
## Dados de teste: data/masmorra/estado-teste.json ("portas" com estado "secreta" e "armadilhas").

const Dados = preload("res://scripts/regras/dados.gd")
const ESP := 0.3     # espessura da parede (tools/gerar_masmorra.gd)
const ALT_VAO := 2.4 # altura do vão da porta (a verga de pedra fica por cima)

var ex: Node
var armadilhas := {}   # Vector2i -> {tipo, dano, efeito, achada (texto), visto: bool, fora: bool}
var procurou := {}     # área -> {nome: true}
var _tampas := {}      # id da porta secreta -> parede falsa
var _elfo := {}        # "porta:nome" -> turno da última chance de passagem
var ocupado := false

func _init(explorar: Node) -> void:
	ex = explorar
	var d = JSON.parse_string(FileAccess.get_file_as_string(ex.portas.ARQ))
	for t in d.get("armadilhas", []):
		var a: Dictionary = (t as Dictionary).duplicate(true); a.visto = false; a.fora = false
		armadilhas[Vector2i(int(t.cel[0]), int(t.cel[1]))] = a
	for id in ex.portas.est:
		if str(ex.portas.est[id].estado) == "secreta" and ex.portas.por_id.has(id): _disfarcar(ex.portas.por_id[id])

func secreta(pt: Dictionary) -> bool:
	return ex.portas.est.has(pt.id) and str(ex.portas.est[pt.id].estado) == "secreta"

# ---------- porta secreta ----------

## Some com a porta e tapa o vão com parede (mesmo material): de fora é só pedra.
func _disfarcar(pt: Dictionary) -> void:
	var no: Node3D = ex.get_node_or_null("Masmorra/Portas/" + str(pt.id))
	if no: no.visible = false
	var comp: float = float(pt.largura) * 1.5
	var caixa := BoxMesh.new()
	var mi := MeshInstance3D.new(); mi.mesh = caixa; mi.material_override = ex.luz.pedra_mat
	if pt.orient == "v":
		caixa.size = Vector3(ESP, ALT_VAO, comp); mi.position = Vector3(pt.x * 1.5, ALT_VAO / 2, pt.y * 1.5 + comp / 2)
	else:
		caixa.size = Vector3(comp, ALT_VAO, ESP); mi.position = Vector3(pt.x * 1.5 + comp / 2, ALT_VAO / 2, pt.y * 1.5)
	ex.get_node("Masmorra").add_child(mi)
	_tampas[pt.id] = mi

## Achou: a parede falsa sai, a porta aparece (fechada, comum) e entra no diário.
func revelar(pt: Dictionary, quem: String) -> void:
	if not secreta(pt): return
	ex.portas.est[pt.id].estado = "fechada"
	ex.grade.barrar_porta(pt, false)
	if _tampas.has(pt.id): _tampas[pt.id].queue_free(); _tampas.erase(pt.id)
	var no: Node3D = ex.get_node_or_null("Masmorra/Portas/" + str(pt.id))
	if no: no.visible = true
	ex._registrar("[color=#ffcf6a]%s encontra uma porta secreta[/color] (%s)!" % [quem, pt.id])
	ex._diario("evento", "%s achou uma porta secreta (%s)." % [quem, pt.id])
	ex._desenhar_portas()

## Portas secretas ainda escondidas nas paredes da área.
func _secretas_da_area(area: String) -> Array:
	var out: Array = []
	for id in ex.portas.est:
		if not ex.portas.por_id.has(id): continue
		var pt: Dictionary = ex.portas.por_id[id]
		if not secreta(pt): continue
		for par in ex.grade.lados_da_porta(pt):
			if ex.grade.area_de(par[0]) == area or ex.grade.area_de(par[1]) == area: out.append(pt); break
	return out

## Modo mestre: a parede falsa fica translúcida e lilás (dá para ver a porta atrás).
var _mat_mestre: StandardMaterial3D
func mostrar_tampas(v: bool) -> void:
	if v and _mat_mestre == null:
		_mat_mestre = StandardMaterial3D.new(); _mat_mestre.albedo_color = Color(0.75, 0.55, 1.0, 0.35)
		_mat_mestre.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; _mat_mestre.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for id in _tampas:
		_tampas[id].material_override = _mat_mestre if v else ex.luz.pedra_mat
		var no: Node3D = ex.get_node_or_null("Masmorra/Portas/" + str(id))
		if no: no.visible = v

# ---------- procurar na sala ----------

const M2_POR_TURNO := 36.0   # chão (e paredes em volta) que uma pessoa vasculha num turno: 4 quadrados de 3 m

## Chão da área em m² (casas de 1,5 m).
func metros2(area: String) -> float:
	var n := 0
	for c in ex.grade.area:
		if ex.grade.area_de(c) == area and ex.grade.chao(c): n += 1
	return n * 2.25

## Quem procuraria agora na área de quem age (vivos na mesma área que ainda não procuraram nela).
func procuradores(area: String) -> Array:
	var ja: Dictionary = procurou.get(area, {})
	return ex.vivos().filter(func(h): return ex.grade.area_de(h.celula) == area and not ja.has(h.nome))

func turnos_para(area: String) -> int:
	var n := procuradores(area).size()
	return maxi(1, ceili(metros2(area) / (M2_POR_TURNO * n))) if n > 0 else 0

func procurar_sala() -> void:
	if ocupado or ex.combate.ativo: return
	var area: String = ex.grade.area_de(ex.agente().celula)
	var quem := procuradores(area)
	var nome_area: String = ex.grade.nomes.get(area, area)
	if quem.is_empty():
		ex._registrar("Todos aqui já procuraram (%s)." % nome_area); return
	ocupado = true
	var turnos := turnos_para(area)
	for h in ex.vivos(): h.parar()
	for h in quem:
		if h.andando(): await h.parou
	ex._registrar("%s procura%s aqui, %s (%d m² de chão e paredes): %d turno%s." % [", ".join(quem.map(func(h): return h.nome)),
		"m" if quem.size() > 1 else "", nome_area, roundi(metros2(area)), turnos, "s" if turnos > 1 else ""])
	for h in quem: h.tocar_anim("ajoelhar"); h.player.speed_scale = 0.6
	await ex.get_tree().create_timer(4.0).timeout
	if not procurou.has(area): procurou[area] = {}
	for h in quem: procurou[area][h.nome] = true
	var achou := false
	# Portas secretas: cada um rola em segredo (1 em 6; elfo 2 em 6).
	for pt in _secretas_da_area(area):
		for h in quem:
			var n := 2 if str(h.ficha.p.classe) == "elfo" else 1; var r := Dados.d(6)
			ex._secreto("Porta secreta %s · %s: d6 %d contra %d → %s" % [pt.id, h.nome, r, n, "acha" if r <= n else "falha"])
			if r <= n: revelar(pt, h.nome); achou = true; break
	# Armadilhas de sala no chão da área (1 em 6; anão 2 em 6).
	for c in armadilhas:
		var a: Dictionary = armadilhas[c]
		if a.visto or a.fora or ex.grade.area_de(c) != area: continue
		for h in quem:
			var n := 2 if str(h.ficha.p.classe) == "anao" else 1; var r := Dados.d(6)
			ex._secreto("Armadilha de sala %s · %s: d6 %d contra %d → %s" % [c, h.nome, r, n, "acha" if r <= n else "falha"])
			if r <= n: _achar(c, h.nome); achou = true; break
	ex._gastar_tempo(float(turnos))
	if not achou:
		ex._secreto("Nesta área: %d porta(s) secreta(s) e %d armadilha(s) escondidas." % [_secretas_da_area(area).size(),
			armadilhas.keys().filter(func(c): return ex.grade.area_de(c) == area and not armadilhas[c].visto and not armadilhas[c].fora).size()])
		ex._registrar("Vasculham cada canto e não encontram nada.")
	for h in quem:
		if h.vivo(): h.tocar("parado", 0.4)
	ocupado = false
	ex.hud_ui.refazer()
	ex._checar_avistamento()

# ---------- armadilhas de sala ----------

func _achar(c: Vector2i, quem: String) -> void:
	var a: Dictionary = armadilhas[c]
	a.visto = true
	ex._registrar("%s encontra uma armadilha no chão: [color=#ff9a6a]%s[/color]." % [quem, str(a.get("achada", a.tipo))])
	ex._diario("evento", "Armadilha de %s em %s." % [str(a.tipo), ex.grade.nomes.get(ex.grade.area_de(c), "")])
	desenhar()

## Casas com armadilha já vista (o caminho desvia delas).
func vistas() -> Dictionary:
	var d := {}
	for c in armadilhas:
		if armadilhas[c].visto and not armadilhas[c].fora: d[c] = true
	return d

func desenhar() -> void:
	ex.marca_armadilhas.limpar()
	var cs: Array = vistas().keys()
	if not cs.is_empty(): ex.marca_armadilhas.por(cs, Color(0.85, 0.15, 0.08, 0.45), 0.08)

## Alguém do grupo chegou numa casa: armadilha escondida dispara 2 em 6; vista, pula por cima.
func pisou(h: Node3D, c: Vector2i) -> void:
	if not armadilhas.has(c): return
	var a: Dictionary = armadilhas[c]
	if a.fora: return
	if a.visto:
		ex._registrar("%s pula por cima do %s." % [h.nome, str(a.tipo)]); return
	var r := Dados.d(6)
	ex._secreto("%s pisa na armadilha escondida %s: d6 %d contra 2 → %s" % [h.nome, c, r, "dispara" if r <= 2 else "não dispara"])
	if r > 2: return
	a.visto = true; a.fora = str(a.tipo) != "fosso"   # o fosso continua lá, aberto
	var dd := Dados.detalhar(str(a.get("dano", "1d6"))); var dano := maxi(1, int(dd.total))
	h.pv -= dano
	var txt := "[color=#ff7a5a]Armadilha![/color] %s %s sofre %s = [b]%d[/b] de dano." % [str(a.get("efeito", "")), h.nome, dd.texto, dano]
	h.piscar(Color(1, 0.25, 0.2, 0.6))
	if h.pv <= 0: h.animar_morte(); txt += " [color=#ff7a5a]%s cai.[/color]" % h.nome
	else: h.animar_dano()
	ex._registrar(txt)
	ex._diario("evento", "%s caiu numa armadilha (%s)." % [h.nome, str(a.tipo)])
	desenhar()
	if not h.vivo(): ex._heroi_caiu_fora(h)
	ex._ficha_mudou(h)

## Modo Cauteloso: quem lidera olha as casas logo à frente (até 2) ao chegar numa casa.
func cauteloso(h: Node3D, c: Vector2i) -> void:
	var f: Vector3 = h.frente_vetor()
	var dir := Vector2i(roundi(f.x), roundi(f.z))
	for k in [1, 2]:
		var alvo: Vector2i = c + dir * int(k)
		if not armadilhas.has(alvo): continue
		var a: Dictionary = armadilhas[alvo]
		if a.visto or a.fora or a.has("cauteloso_" + h.nome): continue
		a["cauteloso_" + h.nome] = true   # uma chance por pessoa
		var n := 2 if str(h.ficha.p.classe) == "anao" else 1; var r := Dados.d(6)
		ex._secreto("Cauteloso %s · %s: d6 %d contra %d → %s" % [alvo, h.nome, r, n, "acha" if r <= n else "falha"])
		if r <= n: _achar(alvo, h.nome)

## Elfo de passagem: 1 em 6 para cada porta secreta a até 2 casas, uma vez por turno (não correndo).
func elfo_passando(h: Node3D) -> void:
	if str(h.ficha.p.classe) != "elfo" or ex.modo == "rapido": return
	for id in ex.portas.est:
		if not ex.portas.por_id.has(id): continue
		var pt: Dictionary = ex.portas.por_id[id]
		if not secreta(pt): continue
		var perto := false
		for par in ex.grade.lados_da_porta(pt):
			for c in par:
				var d: Vector2i = c - h.celula
				if maxi(absi(d.x), absi(d.y)) <= 2 and ex.visao.exploradas.has(c): perto = true
		if not perto: continue
		var chave := "%s:%s" % [id, h.nome]
		if int(_elfo.get(chave, -99)) >= ex.turno: continue
		_elfo[chave] = ex.turno
		var r := Dados.d(6)
		ex._secreto("%s passa perto da porta secreta %s: d6 %d contra 1 → %s" % [h.nome, id, r, "nota" if r <= 1 else "não nota"])
		if r <= 1: revelar(pt, h.nome)
