extends RefCounted
## Procurar (B/X) adaptado: portas secretas e armadilhas de sala.
## - Procurar na sala (medalhão Procurar): todos da área vasculham. Cada pessoa cobre 25 m² de chão
##   (com as paredes em volta) por turno, × mobília (pouca 1,5 · mobiliada 2 · abarrotada 3); mínimo 1 turno. Cada um rola em segredo, uma vez por
##   área: porta secreta 1 em 6 (elfo 2 em 6); armadilha de sala 1 em 6 (anão 2 em 6).
## - Elfo nota porta secreta de passagem (1 em 6, até 2 casas), uma vez por turno, se não estiver correndo.
## - Modo Cauteloso: quem lidera procura armadilhas nas casas à frente enquanto anda (rolagem secreta).
## - Armadilha de sala não achada: passar por cima dispara 2 em 6. Achada: marcada em vermelho e o
##   caminho desvia; se for o único caminho, pula por cima.
## Dados de teste: data/masmorra/estado-teste.json ("portas" com estado "secreta" e "armadilhas").

const Sistema = preload("res://scripts/regras/sistema.gd")
const Sons = preload("res://scripts/visual/sons.gd")
const Dados = preload("res://scripts/regras/dados.gd")
const Fosso = preload("res://scripts/visual/fosso.gd")
const COR_CHAO := {"sala": Color(0.47, 0.44, 0.39), "corredor": Color(0.42, 0.40, 0.36), "cela": Color(0.36, 0.34, 0.31),
	"prisao": Color(0.40, 0.38, 0.34), "caverna": Color(0.38, 0.32, 0.25), "mina": Color(0.42, 0.35, 0.27)}   # tools/gerar_masmorra.gd
const ESP := 0.3     # espessura da parede (tools/gerar_masmorra.gd)
const ALT_VAO := 2.4 # altura do vão da porta (a verga de pedra fica por cima)

var ex: Node
var armadilhas := {}   # Vector2i -> {tipo, dano, efeito, achada (texto), visto: bool, fora: bool}
var procurou := {}     # área -> {nome: true}
var _tampas := {}      # id da porta secreta -> parede falsa
var _elfo := {}        # "porta:nome" -> turno da última chance de passagem
var ocupado := false
var fossos := {}       # Vector2i -> Fosso (buraco com alçapão)
var no_fosso := {}     # personagem -> casa do fosso onde está (caiu e ainda não saiu)

func _init(explorar: Node) -> void:
	ex = explorar
	var d: Dictionary = ex.portas.fonte()
	for t in d.get("armadilhas", []):
		var a: Dictionary = (t as Dictionary).duplicate(true); a.visto = false; a.fora = false
		armadilhas[Vector2i(int(t.cel[0]), int(t.cel[1]))] = a
	_montar_fossos()
	var lay = JSON.parse_string(FileAccess.get_file_as_string(ex.LAYOUT))
	for ar in lay.areas:
		if ar.has("mobilia"): mobilia[str(ar.id)] = str(ar.mobilia)
	for k in d.get("mobilia", {}): mobilia[str(k)] = str(d.mobilia[k])
	for id in ex.portas.est:
		if str(ex.portas.est[id].estado) == "secreta" and ex.portas.por_id.has(id): _disfarcar(ex.portas.por_id[id])

## Cada armadilha "fosso" vira um buraco de verdade, tapado por um alçapão igual ao chão.
func _montar_fossos() -> void:
	var rects: Array = []
	var tampa: ShaderMaterial = ex.luz.chao_mat.duplicate()
	tampa.set_shader_parameter("n_buracos", 0)
	for c in armadilhas:
		if str(armadilhas[c].tipo) != "fosso" or rects.size() >= 8: continue
		var f := Fosso.new()
		ex.get_node("Masmorra").add_child(f)
		var tipo: String = str(ex.grade.tipo.get(ex.grade.area_de(c), "sala"))
		f.montar(c, ex.luz.chao_mat, tampa, ex.luz.pedra_mat, COR_CHAO.get(tipo, Color(0.45, 0.42, 0.38)))
		fossos[c] = f
		rects.append(Vector4(c.x * 1.5, c.y * 1.5, (c.x + 1) * 1.5, (c.y + 1) * 1.5))
	while rects.size() < 8: rects.append(Vector4.ZERO)
	ex.luz.chao_mat.set_shader_parameter("buracos", rects)
	ex.luz.chao_mat.set_shader_parameter("n_buracos", fossos.size())

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

const M2_POR_TURNO := 25.0   # chão (e paredes em volta) que uma pessoa vasculha num turno (sala vazia)
## Mobília multiplica o trabalho (móveis, gavetas, livros nas prateleiras): "mobilia" da área no
## layout (ou em estado-teste.json), padrão vazia.
const MOBILIA := {"vazia": 1.0, "pouca": 1.5, "mobiliada": 2.0, "abarrotada": 3.0}
var mobilia := {}   # área -> nível

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
	return maxi(1, ceili(metros2(area) * fator_mobilia(area) / (M2_POR_TURNO * n))) if n > 0 else 0

func fator_mobilia(area: String) -> float:
	return float(MOBILIA.get(str(mobilia.get(area, "vazia")), 1.0))

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
	ex._registrar("%s procura%s aqui, %s (%d m² de chão e paredes%s): %d turno%s." % [", ".join(quem.map(func(h): return h.nome)),
		"m" if quem.size() > 1 else "", nome_area, roundi(metros2(area)), "" if fator_mobilia(area) == 1.0 else ", " + str(mobilia[area]), turnos, "s" if turnos > 1 else ""])
	await _vasculhar(quem, area)
	if not procurou.has(area): procurou[area] = {}
	for h in quem: procurou[area][h.nome] = true
	var achou := false
	# Portas secretas: cada um rola em segredo (1 em 6; elfo 2 em 6).
	for pt in _secretas_da_area(area):
		for h in quem:
			var n := Sistema.em6("porta_secreta_em6", str(h.ficha.p.classe)); var r := Dados.d(6)
			ex._secreto("Porta secreta %s · %s: d6 %d contra %d → %s" % [pt.id, h.nome, r, n, "acha" if r <= n else "falha"])
			if r <= n: revelar(pt, h.nome); achou = true; break
	# Armadilhas de sala no chão da área (1 em 6; anão 2 em 6).
	for c in armadilhas:
		var a: Dictionary = armadilhas[c]
		if a.visto or a.fora or ex.grade.area_de(c) != area: continue
		for h in quem:
			var n := Sistema.em6("armadilha_sala_em6", str(h.ficha.p.classe)); var r := Dados.d(6)
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

## Encenação da busca: cada um vira para um lado e olha em volta; depois cada um anda até ~2 casas
## (para uma casa livre da mesma área, nunca numa armadilha), vira para outro lado e olha de novo.
var vasculhando := false   # explorar: andar aqui não puxa a fila nem conta tempo (o tempo é o da busca)
func _vasculhar(quem: Array, area: String) -> void:
	vasculhando = true
	await _olhar_todos(quem)
	var reservadas: Dictionary = ex._ocupadas_por(quem)
	for h in quem: reservadas[h.celula] = true
	for h in quem:
		var cam := _passeio(h, area, reservadas)
		if cam.is_empty(): continue
		reservadas[cam[-1]] = true
		h.seguir(cam)
	for h in quem:
		if h.andando(): await h.parou
	await _olhar_todos(quem)
	vasculhando = false

## Vira cada um para um lado diferente (leque com início sorteado) e toca "olhar-em-volta".
func _olhar_todos(quem: Array) -> void:
	var base := randf() * TAU
	var dur := 0.0
	for i in quem.size():
		var h: Node3D = quem[i]
		var ang := base + TAU * i / quem.size() + randf_range(-0.4, 0.4)
		var de: float = h.rotation.y; var para: float = ang + h.frente
		h.create_tween().tween_method(func(t: float): h.rotation.y = lerp_angle(de, para, t), 0.0, 1.0, 0.35)
		var d: float = h.tocar_anim("olhar-em-volta", 0.3) if h.player and h.player.has_animation("olhar-em-volta") else 4.0
		dur = maxf(dur, d)
	await ex.get_tree().create_timer(dur + 0.35).timeout

## Caminho curto até uma casa sorteada da mesma área (de preferência a 2 casas).
func _passeio(h: Node3D, area: String, reservadas: Dictionary) -> Array[Vector2i]:
	var de: Vector2i = h.celula
	var opcoes := {1: [], 2: []}
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var c := de + Vector2i(dx, dy)
			var dist: int = maxi(absi(dx), absi(dy))
			if dist == 0 or reservadas.has(c) or armadilhas.has(c) or not ex.grade.chao(c): continue
			if ex.grade.area_de(c) != area or not ex.visao.exploradas.has(c): continue
			opcoes[dist].append(c)
	for dist in [2, 1]:
		var lista: Array = opcoes[dist]
		lista.shuffle()
		for c in lista:
			var cam: Array[Vector2i] = ex.grade.caminho(de, c, reservadas)
			if not cam.is_empty() and cam.size() <= 3 and not cam.any(func(x): return armadilhas.has(x)): return cam
	return []

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
	var cs: Array = vistas().keys().filter(func(c): return not (fossos.has(c) and fossos[c].aberto))   # fosso aberto já se vê
	if not cs.is_empty(): ex.marca_armadilhas.por(cs, Color(0.85, 0.15, 0.08, 0.45), 0.08)

## Alguém do grupo chegou numa casa: armadilha escondida dispara 2 em 6; vista, pula por cima.
func pisou(h: Node3D, c: Vector2i) -> void:
	if not armadilhas.has(c): return
	var a: Dictionary = armadilhas[c]
	if a.fora: return
	if a.visto: return   # vista: o caminho desvia ou pula (explorar._pulo)
	var r := Dados.d(6)
	ex._secreto("%s pisa na armadilha escondida %s: d6 %d contra 2 → %s" % [h.nome, c, r, "dispara" if r <= 2 else "não dispara"])
	if r > 2: return
	a.visto = true; a.fora = str(a.tipo) != "fosso"   # o fosso continua lá, aberto
	if fossos.has(c):
		await cair(h, c, a); return
	Sons.tocar("armadilha", h)
	var dd := Dados.detalhar(str(a.get("dano", "1d6"))); var dano := maxi(1, int(dd.total))
	h.pv -= dano
	Sons.criatura(h, "dor")
	var txt := "[color=#ff7a5a]Armadilha![/color] %s %s sofre %s = [b]%d[/b] de dano." % [str(a.get("efeito", "")), h.nome, dd.texto, dano]
	h.piscar(Color(1, 0.25, 0.2, 0.6))
	if h.pv <= 0: h.animar_morte(); txt += " [color=#ff7a5a]%s cai.[/color]" % h.nome
	else: h.animar_dano()
	ex._registrar(txt)
	ex._diario("evento", "%s caiu numa armadilha (%s)." % [h.nome, str(a.tipo)])
	desenhar()
	if not h.vivo(): ex._heroi_caiu_fora(h)
	ex._ficha_mudou(h)

# ---------- fosso: queda e saída ----------

## Caiu no fosso: o alçapão abre, cai, sofre o dano, levanta lá no fundo e o jogador escolhe o que fazer.
signal escolheu(id: String)

func cair(h: Node3D, c: Vector2i, a: Dictionary) -> void:
	var andava: bool = h.andando()
	h._caminho.clear()
	if andava: h.parou.emit()   # quem esperava o passo (combate) segue
	h.position = ex.grade.centro(c)
	no_fosso[h] = c; h.set_meta("no_fosso", true)
	h.separado = true
	var f: Node3D = fossos[c]
	f.abrir()
	ex._registrar("[color=#ff7a5a]O chão cede![/color] %s cai num fosso." % h.nome)
	h.get_tree().create_timer(0.45).timeout.connect(func(): Sons.tocar("queda_fosso", h))
	if h.player: h.tocar("dano", 0.05)
	var t := h.create_tween()
	t.tween_property(h, "position:y", f.fundo_y(), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	var dd := Dados.detalhar(str(a.get("dano", "1d6"))); var dano := maxi(1, int(dd.total))
	h.pv -= dano
	h.piscar(Color(1, 0.25, 0.2, 0.6))
	var txt := "%s %s sofre %s = [b]%d[/b] de dano." % [str(a.get("efeito", "")), h.nome, dd.texto, dano]
	ex._diario("evento", "%s caiu num fosso." % h.nome)
	desenhar()
	if h.pv <= 0:
		h.animar_morte(); ex._registrar(txt + " [color=#ff7a5a]%s morre no fundo do fosso.[/color]" % h.nome)
		ex._heroi_caiu_fora(h)
		ex._ficha_mudou(h)
		if not ex.fim: await h.get_tree().create_timer(2.5).timeout
	else:
		ex._registrar(txt)
		h.animar_dano(); ex._ficha_mudou(h)
		await h.get_tree().create_timer(0.9).timeout
		# caído no fundo, levanta ("levantar": do chão até em pé em ~4,3 s)
		if h.player and h.player.has_animation("levantar"):
			h.tocar_anim("levantar", 0.3)
			await h.get_tree().create_timer(4.3).timeout
			h.tocar("parado", 0.4)
		else:
			await _levantar(h)
	if h == ex.heroi and h.vivo(): _liderar_quem_esta_fora()
	if not ex.combate.ativo and not ex.fim: dialogo_fosso(h)

## Abaixa na beirada ("ajoelhar" inteiro: termina agachado, quadril a 0,36 m) e segura a pose.
func _agachar(q: Node3D, ritmo := 1.2) -> void:
	var t: float = q.tocar_anim("ajoelhar", 0.2)
	if q.player == null: return
	q.player.speed_scale = ritmo
	await q.get_tree().create_timer(t / ritmo).timeout
	q.player.pause()

## Levanta: o "ajoelhar" de trás para a frente (a parte em pé do começo fica de fora).
func _levantar(q: Node3D) -> void:
	if q.player == null or not q.player.has_animation("ajoelhar"):
		q.tocar("parado", 0.4); return
	q.player.play_backwards("ajoelhar", 0.1); q.player.speed_scale = 1.3
	await q.get_tree().create_timer(2.0 / 1.3).timeout   # de 2,77 s até ~0,8 s: o quadril já subiu
	q.tocar("parado", 0.4)

## Combate: na vez de quem está no fosso, tentar sair (teste; passou, sai e a vez acaba) ou passar a vez.
func turno_no_fosso(h: Node3D) -> void:
	if not h.vivo(): return
	var ch := chance_sair(h)
	ex.hud_ui.dialogo("Fosso · vez de %s" % h.nome, "%s está no fundo do fosso, no meio do combate." % h.nome, [
		{"id": "sair", "texto": "Tentar sair do fosso", "dica": "Precisa de %s. Passou: sai e a vez acaba. Falhou: a vez acaba e tenta de novo na próxima." % ch[0]},
		{"id": "passar", "texto": "Passar a vez", "dica": "Fica no fundo do fosso até a próxima vez."}],
		func(id): escolheu.emit(id))
	var id: String = await escolheu
	if id != "sair":
		ex._registrar("%s espera no fundo do fosso." % h.nome); return
	var r := Dados.d(100) if ch[1] == "%" else Dados.d(6)
	var ok := r <= int(ch[2])
	await ex.portas._animar(h, "ajoelhar", 0.8, 0.9)
	ex._registrar("%s tenta escalar a parede do fosso (%s): [b]%d[/b] → %s" % [h.nome, ch[0], r, "[color=#ffcf6a]consegue![/color]" if ok else "escorrega de volta."])
	if ok: await _subir(h, _casa_ao_lado(no_fosso[h], []))
	else: h.tocar("parado", 0.4)

## Quem está no fosso não leva a fila: a liderança (e a tocha) passa para o primeiro que está fora.
func _liderar_quem_esta_fora() -> void:
	for x in ex.vivos():
		if not no_fosso.has(x): ex._passar_lideranca(x); return

func esta_no_fosso(h: Node3D) -> bool:
	return no_fosso.has(h)

## Chance de sair sozinho: ladrão escala (d%); os outros d6 contra 2 + mod FOR. [texto, tipo, alvo]
func chance_sair(h: Node3D) -> Array:
	var f = h.ficha
	if f.ladrao(): return ["escalar %d%% (d%%)" % int(f.p.habilidades_ladrao.escalar), "%", int(f.p.habilidades_ladrao.escalar)]
	var n: int = f.chance_forcar()
	return ["%s em 6 (d6, Força)" % ("1" if n == 1 else "1–%d" % n), "d6", n]

func _ajudantes(h: Node3D) -> Array:
	return ex.vivos().filter(func(x): return x != h and not no_fosso.has(x))

func _ladrao_fora() -> Node3D:
	for x in _ajudantes(null):
		if x.ficha.ladrao(): return x
	return null

## A caixa de escolhas de quem está no fosso (vivo: sair, ajudar, ficar; morto: resgatar o corpo, deixar).
func dialogo_fosso(h: Node3D) -> void:
	if not no_fosso.has(h): return
	var ops: Array = []
	var txt: String
	if h.vivo():
		var ch := chance_sair(h)
		txt = "%s está no fundo de um fosso de 3 m (PV %d/%d). O que fazer?" % [h.nome, h.pv, h.pv_max]
		ops.append({"id": "sair", "texto": "%s tenta sair sozinho · 1 turno" % h.nome, "dica": "Precisa de %s. Se falhar, o turno passa e pode tentar de novo." % ch[0]})
		var aj := _ajudantes(h)
		ops.append({"id": "ajudar", "texto": "O grupo ajuda a sair · ½ turno", "dica": "Sem teste: alguém vai até a borda e puxa." if not aj.is_empty() else "Não há ninguém fora do fosso para ajudar.", "ativo": not aj.is_empty()})
		ops.append({"id": "ficar", "texto": "Deixar %s no fosso" % h.nome, "dica": "O grupo segue; clique na carta para voltar a esta escolha."})
	else:
		var l := _ladrao_fora()
		txt = "O corpo de %s está no fundo do fosso." % h.nome
		ops.append({"id": "resgatar", "texto": ("%s desce e traz o corpo · 1 turno" % l.nome) if l else "Resgatar o corpo · precisa do ladrão", "dica": "O corpo fica numa casa ao lado do fosso." if l else "Só o ladrão desce e sobe as paredes do fosso.", "ativo": l != null})
		ops.append({"id": "ficar", "texto": "Deixar o corpo no fosso", "dica": "Clique na carta para voltar a esta escolha."})
	ex.hud_ui.dialogo("Fosso", txt, ops, func(id): _escolha_fosso(h, id))

func _escolha_fosso(h: Node3D, id: String) -> void:
	if ocupado: return
	match id:
		"sair": await _sair_sozinho(h)
		"ajudar": await _ajudar(h)
		"resgatar": await _resgatar(h)
		"ficar":
			ex._registrar("%s fica no fosso." % h.nome if h.vivo() else "O corpo de %s fica no fosso." % h.nome)

func _sair_sozinho(h: Node3D) -> void:
	ocupado = true
	var ch := chance_sair(h)
	var r := Dados.d(100) if ch[1] == "%" else Dados.d(6)
	var ok := r <= int(ch[2])
	await ex.portas._animar(h, "ajoelhar", 1.0, 0.8)
	ex._gastar_tempo(1.0)
	ex._registrar("%s tenta escalar a parede do fosso (%s): [b]%d[/b] → %s" % [h.nome, ch[0], r, "[color=#ffcf6a]consegue![/color]" if ok else "escorrega de volta."])
	if ok:
		var saida := _casa_ao_lado(no_fosso[h], [])
		await _subir(h, saida)
	ocupado = false
	if not ok and h.vivo() and not ex.fim: dialogo_fosso(h)

func _ajudar(h: Node3D) -> void:
	ocupado = true
	var c: Vector2i = no_fosso[h]
	var aj: Array = _ajudantes(h)
	aj.sort_custom(func(a, b): return ex.grade.centro(a.celula).distance_to(ex.grade.centro(c)) < ex.grade.centro(b.celula).distance_to(ex.grade.centro(c)))
	var quem: Node3D = aj[0]
	var borda := await _ir_para_borda(quem, c)
	if borda == ex.SEM_CELULA:
		ex._registrar("%s não consegue chegar à borda do fosso." % quem.nome); ocupado = false; return
	quem.olhar_para(ex.grade.centro(c))
	var perto: Vector3 = ex.grade.centro(borda).lerp(ex.grade.centro(c), 0.3)   # abaixa na beirada
	var tb := quem.create_tween(); tb.tween_property(quem, "position", perto, 0.3)
	await _agachar(quem)   # a saída só começa com quem ajuda já agachado na beirada
	ex._gastar_tempo(0.5)
	ex._registrar("%s se debruça na borda e puxa %s para fora do fosso." % [quem.nome, h.nome])
	await _subir(h, _saida_perto(c, borda))
	await _levantar(quem)   # fica agachado até ela sair de todo
	quem.create_tween().tween_property(quem, "position", ex.grade.centro(borda), 0.3)
	ocupado = false

func _resgatar(h: Node3D) -> void:
	ocupado = true
	var c: Vector2i = no_fosso[h]
	var l := _ladrao_fora()
	var borda := await _ir_para_borda(l, c)
	if borda == ex.SEM_CELULA:
		ex._registrar("%s não consegue chegar à borda do fosso." % l.nome); ocupado = false; return
	l.olhar_para(ex.grade.centro(c))
	var tb := l.create_tween(); tb.tween_property(l, "position", ex.grade.centro(borda).lerp(ex.grade.centro(c), 0.3), 0.3)
	await _agachar(l)
	ex._gastar_tempo(1.0)
	var destino := _casa_ao_lado(c, [borda])
	no_fosso.erase(h); h.set_meta("no_fosso", false)
	h.celula = destino; h._de = destino
	var t := h.create_tween()
	t.tween_property(h, "position", ex.grade.centro(destino), 0.8).set_trans(Tween.TRANS_SINE)
	await t.finished
	await _levantar(l)
	l.create_tween().tween_property(l, "position", ex.grade.centro(borda), 0.3)
	ex._registrar("%s desce no fosso, amarra o corpo de %s e o traz para cima." % [l.nome, h.nome])
	ex._diario("evento", "%s resgatou o corpo de %s do fosso." % [l.nome, h.nome])
	ocupado = false

## Quanto uma animação desloca o quadril no mundo (do começo ao fim), medido no próprio modelo.
func _desloc_anim(h: Node3D, nome: String) -> Vector3:
	var sks: Array = h.modelo.find_children("*", "Skeleton3D", true, false) if h.modelo else []
	if sks.is_empty() or h.player == null: return Vector3.ZERO
	var sk: Skeleton3D = sks[0]; var i := sk.find_bone("mixamorig_Hips")
	if i < 0: return Vector3.ZERO
	h.player.play(nome, 0.0); h.player.seek(0.0, true); h.player.advance(0)
	var a: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
	h.player.seek(h.player.get_animation(nome).length, true); h.player.advance(0)
	var b: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
	h.player.seek(0.0, true); h.player.advance(0)
	return b - a

## Sobe do fundo para uma casa ao lado. Com "sair-do-buraco": mede quanto a animação sobe e avança
## neste modelo; o ator sobe o que falta durante a pegada e, no fim, passa para a pose em pé na beirada.
func _subir(h: Node3D, destino: Vector2i) -> void:
	var c: Vector2i = no_fosso.get(h, h.celula)
	var centro: Vector3 = ex.grade.centro(c)
	h.olhar_para(ex.grade.centro(destino))
	var t: Tween
	if h.player and h.player.has_animation("sair-do-buraco"):
		h.tocar_anim("sair-do-buraco", 0.0)   # já com o giro da animação
		var d := _desloc_anim(h, "sair-do-buraco")
		var sobe := d.y; var dh := Vector3(d.x, 0, d.z)
		var dur: float = h.tocar_anim("sair-do-buraco", 0.2)
		var tw := h.create_tween()
		tw.tween_property(h, "position:y", minf(-sobe, 0.0), dur * 0.4).set_trans(Tween.TRANS_SINE)
		await h.get_tree().create_timer(dur).timeout
		h.position = centro + dh; h.position.y = 0.0   # a pose final em pé fica na beirada
		h.tocar("andar", 0.1)
		t = h.create_tween()
		t.tween_property(h, "position", ex.grade.centro(destino), maxf(0.2, ex.grade.centro(destino).distance_to(h.position) / 1.5))
	else:
		var dur := 2.2   # sem a animação de subida: escala devagar
		h.tocar_anim("ajoelhar")
		t = h.create_tween()
		t.tween_property(h, "position:y", 0.0, dur * 0.6).set_trans(Tween.TRANS_SINE)
		t.tween_property(h, "position", ex.grade.centro(destino), dur * 0.4)
	await t.finished
	h.celula = destino; h._de = destino
	no_fosso.erase(h); h.set_meta("no_fosso", false)
	h.tocar("parado", 0.3)
	ex._registrar("%s sai do fosso." % h.nome)
	if ex.agrupado: h.separado = false
	ex._atualizar_visao(); ex.hud_ui.refazer()

## Leva quem ajuda até uma casa ao lado do fosso (devolve a casa, ou SEM_CELULA).
func _ir_para_borda(q: Node3D, c: Vector2i) -> Vector2i:
	var melhor: Array[Vector2i] = []; var alvo: Vector2i = ex.SEM_CELULA; var menor := INF
	for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + v
		if not ex.grade.chao(n) or not ex.grade.passa_reto(c, n) or not ex.visao.exploradas.has(n): continue
		if n == q.celula: return n
		var cam: Array[Vector2i] = ex._caminho_lider(q.proxima_celula(), n, q)
		if cam.is_empty(): continue
		var l: float = ex.grade.comprimento(q.proxima_celula(), cam)
		if l < menor: menor = l; melhor = cam; alvo = n
	if alvo == ex.SEM_CELULA: return alvo
	if q.andando(): await q.parou
	q.seguir(melhor); await q.parou
	return alvo

## Saída do lado de quem puxa: casa ao lado do fosso, livre, a mais perto de quem está na borda.
func _saida_perto(c: Vector2i, borda: Vector2i) -> Vector2i:
	var ocup: Dictionary = ex._ocupadas_por(no_fosso.keys())
	var melhor := Vector2i(-999, -999); var menor := INF
	for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + v
		if n == borda or ocup.has(n) or armadilhas.has(n) or not ex.grade.chao(n) or not ex.grade.passa_reto(c, n): continue
		var d := Vector2(n - borda).length()
		if d < menor: menor = d; melhor = n
	return melhor if melhor.x > -999 else _casa_ao_lado(c, [borda])

## Casa do chão ao lado do fosso, livre (sem ninguém), sem parede no meio.
func _casa_ao_lado(c: Vector2i, evitar: Array) -> Vector2i:
	var ocup: Dictionary = ex._ocupadas_por(no_fosso.keys())
	for v in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + v
		if n in evitar or ocup.has(n) or armadilhas.has(n): continue
		if ex.grade.chao(n) and ex.grade.adjacentes(c, n): return n
	return c + Vector2i(1, 0)

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
		var n := Sistema.em6("armadilha_sala_em6", str(h.ficha.p.classe)); var r := Dados.d(6)
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
		var r := Dados.d(6); var n := Sistema.em6("elfo_passando_em6", "padrao")
		ex._secreto("%s passa perto da porta secreta %s: d6 %d contra %d → %s" % [h.nome, id, r, n, "nota" if r <= n else "não nota"])
		if r <= n: revelar(pt, h.nome)
