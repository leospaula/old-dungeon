extends Node3D
## Cena principal: exploração e combate na Masmorra Base.
##
## Exploração: botão esquerdo num lugar do mapa e a Tessa anda até lá. A distância andada vira tempo
## (turno de 10 min = o movimento de exploração dela, pela carga): cada turno gasta tocha e, a cada
## 2 turnos, há teste de monstros errantes (1 em d6). Encontro: distância 2d6 × 3 m e surpresa.
## Combate: na vez do personagem, o alcance do movimento fica destacado; clique para andar ou clique
## num inimigo para atacar (ele anda até o lado, se der). Espaço encerra a vez.
## Teclas: F foca · M modo mestre · G grade · K força um encontro · R recomeça.
## Linha de comando: -- --captura=arquivo.png [--teste=andar|combate|auto]

const Luz = preload("res://scripts/visual/luz.gd")
const Grade = preload("res://scripts/exploracao/grade.gd")
const Ator = preload("res://scripts/exploracao/ator.gd")
const Marcas = preload("res://scripts/visual/marcas.gd")
const Combate = preload("res://scripts/combate/combate.gd")
const Regras = preload("res://scripts/regras/regras.gd")
const Dados = preload("res://scripts/regras/dados.gd")

const LAYOUT := "res://data/masmorra/layout.json"
const TESSA_GLB := "res://arte/final/3d/tessa-biblioteca.glb"
const TESSA_ANIM := {"parado": "parado-espada-escudo", "andar": "andar", "golpe": "golpe", "dano": "levar-golpe", "morrer": "morrer", "vitoria": "vitoria"}
const TESSA_FRENTE := 0.0
const INICIO := Vector2i(7, 5)
const TURNOS_POR_TOCHA := 6
const SEM_CELULA := Vector2i(-999, -999)

@onready var camera: Camera3D = $Camera
var grade: RefCounted
var luz: Node
var combate: Node
var heroi: Node3D
var monstros: Array = []
var marca_alcance: Node
var marca_caminho: Node
var marca_vez: Node
var MONSTROS := {}
var ENCONTROS := {}

var mestre := false
var grade_forte := false
var fim := false
var auto := false

# Relógio da exploração
var taxa_m := 36.0
var turno := 0
var metros_no_turno := 0.0
var tocha_turnos := TURNOS_POR_TOCHA
var tochas_reserva := 0
var encontro_pendente := false
var xp_total := 0

# Tela
var hud_relogio: Label
var hud_combate: Label
var hud_centro: Label
var hud_log: RichTextLabel
var _linhas: Array[String] = []

func _ready() -> void:
	$Sol.visible = false
	grade = Grade.new(); grade.carregar(LAYOUT)
	MONSTROS = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/monstros.json"))
	ENCONTROS = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/encontros.json"))
	heroi = _criar_tessa()
	luz = Luz.new(); add_child(luz)
	luz.configurar(self, $Masmorra, $Ambiente, heroi)
	luz.tochas_automaticas(self, LAYOUT, ["24", "23", "21", "22", "15", "20", "14", "10", "12"], 2)
	for n in ["marca_alcance", "marca_caminho", "marca_vez"]:
		var m := MeshInstance3D.new(); m.set_script(Marcas); add_child(m); set(n, m)
	combate = Combate.new(); add_child(combate)
	combate.grade = grade; combate.marca_alcance = marca_alcance; combate.marca_caminho = marca_caminho; combate.marca_vez = marca_vez
	combate.registro.connect(_registrar)
	combate.terminou.connect(_fim_do_combate)
	_montar_hud()
	camera.alvo = heroi.position; camera.distancia = 15.0; camera.inclinacao = 55.0; camera.guinada = -30.0
	_registrar("A Tessa desce a escada para a [b]%s[/b]. Clique no chão para andar." % grade.nomes.get(grade.area_de(heroi.celula), ""))
	_linha_de_comando()

# ---------- personagens ----------

func _criar_tessa() -> Node3D:
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/personagens/grupo-inicial.json"))
	var p: Dictionary = {}
	for x in G.personagens:
		if x.id == "tessa": p = x
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "grupo"
	a.nome = str(p.nome).get_slice(" ", 0)
	a.pv = int(p.pv); a.pv_max = a.pv; a.ca = int(p.ca); a.thac0 = int(p.thac0)
	var mfor := Regras.mod(int(p.atributos["for"]))
	a.mod_acerto = mfor; a.mod_dano = mfor
	a.dano = str(p.armas[0].dano); a.arma = str(p.armas[0].nome)
	taxa_m = Regras.taxa_exploracao_m(p.equipamento)
	a.mov_combate_m = Regras.taxa_combate_m(taxa_m)
	for it in p.equipamento:
		var s := str(it)
		if s.begins_with("tocha x"): tochas_reserva = int(s.get_slice("x", 1)) - 1
	add_child(a); a.colocar(INICIO)
	a.montar_modelo(load(TESSA_GLB).instantiate(), TESSA_ANIM, TESSA_FRENTE)
	a.rotulo.visible = false
	a.passo_iniciado.connect(_ao_iniciar_passo)
	a.chegou.connect(_ao_chegar)
	a.parou.connect(_ao_parar)
	return a

func _criar_monstro(id: String, nome: String, c: Vector2i) -> Node3D:
	var d: Dictionary = MONSTROS[id]
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "monstros"; a.nome = nome
	a.ca = int(d.ca); a.thac0 = Regras.thac0_monstro(str(d.dv)); a.pv = Regras.pv_monstro(str(d.dv)); a.pv_max = a.pv
	a.dano = str(d.ataques[0].dano); a.arma = str(d.ataques[0].nome)
	a.moral = int(d.moral); a.xp = int(d.xp)
	a.mov_combate_m = Regras.taxa_combate_m(float(d.mov_m))
	add_child(a); a.colocar(c)
	a.montar_modelo(Ator.goblin_provisorio(), {}, 0.0)
	a.olhar_para(heroi.position)
	a.passo_iniciado.connect(_ao_iniciar_passo)
	a.scale = Vector3(0.01, 0.01, 0.01)
	create_tween().tween_property(a, "scale", Vector3.ONE, 0.35)
	return a

# ---------- entrada ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_R: get_tree().reload_current_scene(); return
			KEY_F: camera.alvo = heroi.global_position; camera.distancia = 14.0
			KEY_M: mestre = not mestre; luz.set_mestre(mestre)
			KEY_G: grade_forte = not grade_forte; luz.set_grade(grade_forte or combate.ativo)
			KEY_K: if not combate.ativo and not fim: _iniciar_encontro(true)
			KEY_SPACE, KEY_ENTER: combate.encerrar_turno()
	if fim: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var mira := _mira(e.position)
		if combate.ativo: combate.clicar(mira[0], mira[1])
		else: _andar_para(mira[0])
	elif e is InputEventMouseMotion:
		var mira := _mira(e.position)
		if combate.ativo: combate.pairar(mira[0], mira[1])
		else: _previa(mira[0])

## Célula do chão sob o mouse e, se houver, o monstro sob o mouse.
func _mira(tela: Vector2) -> Array:
	var o := camera.project_ray_origin(tela); var d := camera.project_ray_normal(tela)
	var alvo: Node = null; var perto := INF
	for m in monstros:
		if not is_instance_valid(m) or not m.vivo(): continue
		var c: Vector3 = m.global_position + Vector3(0, 0.7, 0)
		var t := (c - o).dot(d)
		if t > 0 and (o + d * t - c).length() < 0.55 and t < perto: perto = t; alvo = m
	if d.y > -0.001: return [SEM_CELULA, alvo]
	return [grade.celula(o + d * (-o.y / d.y)), alvo]

# ---------- exploração ----------

func _andar_para(c: Vector2i) -> void:
	if not grade.chao(c) or encontro_pendente: return
	var de: Vector2i = heroi.proxima_celula()
	var cam: Array[Vector2i] = grade.caminho(de, c)
	if cam.is_empty() and de == c and not heroi.andando(): return
	if heroi.andando(): cam.push_front(de)
	marca_caminho.limpar(); marca_caminho.por([c], Color(1, 0.9, 0.6, 0.35), 0.15)
	heroi.seguir(cam)

func _previa(c: Vector2i) -> void:
	if heroi.andando(): return
	marca_caminho.limpar()
	if not grade.chao(c) or c == heroi.celula: return
	var cam: Array[Vector2i] = grade.caminho(heroi.celula, c)
	if cam.is_empty(): return
	marca_caminho.por(cam.slice(0, cam.size() - 1), Color(1, 0.95, 0.8, 0.18), 0.55)
	marca_caminho.por([c], Color(1, 0.95, 0.8, 0.3), 0.15)

func _ao_iniciar_passo(de: Vector2i, para: Vector2i) -> void:
	var pt: Dictionary = grade.porta_entre(de, para)
	if pt.is_empty(): return
	var no := $Masmorra.get_node_or_null("Portas/" + str(pt.id))
	if no == null or no.has_meta("aberta"): return
	no.set_meta("aberta", true)
	var sentido: Vector3 = grade.centro(para) - grade.centro(de)
	var eixo := Vector3(0, 0, 1) if pt.orient == "v" else Vector3(1, 0, 0)
	for folha in no.get_children():
		var dir := eixo if folha.name == "Folha0" else -eixo
		var ang := deg_to_rad(95.0)
		if dir.rotated(Vector3.UP, ang).dot(sentido) < 0: ang = -ang
		create_tween().tween_property(folha, "rotation:y", ang, 0.4).set_trans(Tween.TRANS_SINE)

func _ao_chegar(_c: Vector2i, metros: float) -> void:
	if combate.ativo: return
	metros_no_turno += metros
	while metros_no_turno >= taxa_m:
		metros_no_turno -= taxa_m
		_passar_turno()

func _ao_parar() -> void:
	if not combate.ativo: marca_caminho.limpar()
	if encontro_pendente and not combate.ativo: _iniciar_encontro(false)

func _passar_turno() -> void:
	turno += 1
	tocha_turnos -= 1
	var txt := "Passa o turno %d (%s de exploração)." % [turno, _hora()]
	if tocha_turnos == 1: txt += " A tocha está no fim."
	if tocha_turnos <= 0:
		if tochas_reserva > 0:
			tochas_reserva -= 1; tocha_turnos = TURNOS_POR_TOCHA
			txt += " A tocha apaga e a Tessa acende outra (restam %d)." % tochas_reserva
		else:
			tocha_turnos = 0; luz.luz_grupo.visible = false
			txt += " [color=#ff7a5a]A última tocha apagou.[/color]"
	_registrar(txt)
	if turno % 2 == 0:
		var r := Dados.d(6)
		if r == 1:
			_registrar("Monstros errantes: d6 = [b]1[/b] → [color=#ff9a6a]algo se aproxima![/color]")
			encontro_pendente = true
			heroi.parar()
		else:
			_registrar("Monstros errantes: d6 = %d → nada." % r)

func _hora() -> String:
	var min := turno * 10
	return "%d min" % min if min < 60 else "%dh%02d" % [min / 60, min % 60]

# ---------- encontros ----------

func _iniciar_encontro(forcado: bool) -> void:
	encontro_pendente = false
	if forcado: _registrar("[i](encontro forçado com K)[/i]")
	var tab: Array = ENCONTROS.nivel_1
	var e: Dictionary = tab[randi() % tab.size()]
	var dm: Dictionary = MONSTROS[e.monstro]
	var n := maxi(1, Dados.rolar(str(e.quantidade)))
	var dist := Dados.rolar("2d6") * 3.0
	var alc: Dictionary = grade.alcance(heroi.celula, dist + 6.0, {})
	# Lugar do encontro: o mais perto da distância rolada, longe o bastante para não começar colado.
	var centro := SEM_CELULA; var melhor := INF
	for c in alc:
		var custo: float = alc[c][0]
		if custo < 3.0: continue
		if absf(custo - dist) < melhor: melhor = absf(custo - dist); centro = c
	if centro == SEM_CELULA:
		_registrar("Barulhos ao longe, mas nada aparece.")
		return
	var lugares: Array = alc.keys().filter(func(c): return float(alc[c][0]) >= 3.0)
	lugares.sort_custom(func(a, b): return Vector2(a - centro).length() < Vector2(b - centro).length())
	monstros.clear()
	for i in mini(n, lugares.size()):
		var nome: String = dm.nome if n == 1 else "%s %d" % [dm.nome, i + 1]
		monstros.append(_criar_monstro(str(e.monstro), nome, lugares[i]))
	heroi.parar()
	_registrar("[b]%d %s[/b] a uns %d m!" % [monstros.size(), str(dm.nome).to_lower() + ("s" if monstros.size() > 1 else ""), int(dist)])
	var sg := Dados.d(6) <= 2; var sm := Dados.d(6) <= 2
	_registrar("Surpresa (1–2 em d6): grupo %s · monstros %s" % ["surpreendido" if sg else "atento", "surpreendidos" if sm else "atentos"])
	await get_tree().create_timer(0.5).timeout
	if heroi.andando(): await heroi.parou
	camera.distancia = clampf(camera.distancia, 12.0, 18.0)
	heroi.rotulo.visible = true
	luz.set_grade(true)
	combate.iniciar([heroi], monstros, sg, sm)

func _fim_do_combate(resultado: String, xp: int, rodadas: int) -> void:
	luz.set_grade(grade_forte)
	if resultado == "vitoria":
		xp_total += xp
		_registrar("[color=#ffcf6a][b]Vitória![/b][/color] %d rodada(s) (%d s). XP: +%d (total %d)." % [rodadas, rodadas * 10, xp, xp_total])
		heroi.tocar("vitoria")
		await get_tree().create_timer(2.5).timeout
		if not combate.ativo and not heroi.andando(): heroi.tocar("parado")
		heroi.rotulo.visible = false
		monstros = monstros.filter(func(m): return is_instance_valid(m) and m.vivo())
	else:
		fim = true
		_registrar("[color=#ff7a5a][b]A Tessa caiu.[/b][/color]")
		hud_centro.text = "A Tessa caiu na masmorra.\nR para recomeçar"

# ---------- tela ----------

func _montar_hud() -> void:
	var hud: CanvasLayer = $HUD
	$HUD/Legenda.text = "Botão esquerdo: andar / atacar · Espaço: encerrar a vez · botão direito, Q/E: girar · roda: zoom · WASD: mover · F: focar · M: mestre · G: grade · K: encontro · R: recomeçar"
	$HUD/Legenda.label_settings = $HUD/Legenda.label_settings.duplicate()
	$HUD/Legenda.label_settings.font_size = 13
	var estilo := LabelSettings.new(); estilo.font_size = 16; estilo.outline_size = 5; estilo.outline_color = Color.BLACK
	hud_relogio = Label.new(); hud_relogio.label_settings = estilo
	hud_relogio.set_anchors_preset(Control.PRESET_TOP_RIGHT); hud_relogio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_relogio.offset_left = -520; hud_relogio.offset_right = -16; hud_relogio.offset_top = 12
	hud.add_child(hud_relogio)
	var grande := estilo.duplicate(); grande.font_size = 20; grande.font_color = Color(1, 0.9, 0.7)
	hud_combate = Label.new(); hud_combate.label_settings = grande
	hud_combate.set_anchors_preset(Control.PRESET_CENTER_TOP); hud_combate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_combate.offset_left = -400; hud_combate.offset_right = 400; hud_combate.offset_top = 118
	hud.add_child(hud_combate)
	var enorme := estilo.duplicate(); enorme.font_size = 40; enorme.font_color = Color(1, 0.6, 0.45); enorme.outline_size = 10
	hud_centro = Label.new(); hud_centro.label_settings = enorme
	hud_centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_centro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hud_centro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_centro)
	var fundo := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.04, 0.03, 0.02, 0.62); sb.set_corner_radius_all(6); sb.set_content_margin_all(10)
	fundo.add_theme_stylebox_override("panel", sb)
	fundo.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fundo.offset_left = 12; fundo.offset_right = 640; fundo.offset_top = -210; fundo.offset_bottom = -12
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fundo)
	hud_log = RichTextLabel.new(); hud_log.bbcode_enabled = true; hud_log.scroll_following = true
	hud_log.add_theme_font_size_override("normal_font_size", 14); hud_log.add_theme_font_size_override("bold_font_size", 14)
	hud_log.add_theme_font_size_override("italics_font_size", 14)
	hud_log.add_theme_color_override("default_color", Color(0.92, 0.88, 0.8))
	hud_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_child(hud_log)

func _registrar(txt: String) -> void:
	_linhas.append(txt)
	if _linhas.size() > 60: _linhas.pop_front()
	hud_log.text = "\n".join(_linhas)
	print(txt)

func _process(dt: float) -> void:
	# A câmera acompanha quem está andando.
	var quem: Node3D = null
	if combate.ativo and combate.vez and is_instance_valid(combate.vez): quem = combate.vez
	elif not combate.ativo and heroi.andando(): quem = heroi
	if quem: camera.alvo = camera.alvo.lerp(quem.global_position, 1.0 - exp(-2.5 * dt))
	_atualizar_hud()

func _atualizar_hud() -> void:
	var area: String = grade.nomes.get(grade.area_de(heroi.celula), "")
	var tocha := "tocha: %d de %d turnos (+%d de reserva)" % [tocha_turnos, TURNOS_POR_TOCHA, tochas_reserva] if tocha_turnos > 0 else "sem luz"
	var prox := turno + (2 - turno % 2)
	hud_relogio.text = "%s\nTurno %d · %s · andado no turno: %.1f de %d m\n%s · teste de errantes no turno %d\nTessa: PV %d/%d · CA %d · XP %d" % [
		area, turno, _hora(), metros_no_turno, int(taxa_m), tocha, prox, maxi(heroi.pv, 0), heroi.pv_max, heroi.ca, xp_total]
	if combate.ativo and combate.vez and is_instance_valid(combate.vez):
		var v: Node = combate.vez
		if v.lado == "grupo":
			var previa := "  →  este caminho: %.1f m" % combate.previa_m if combate.previa_m >= 0 else ""
			hud_combate.text = "Rodada %d · vez da %s · movimento: %.1f de %.0f m%s\nclique para andar · clique num inimigo para atacar · Espaço encerra a vez" % [
				combate.rodada, v.nome, combate.restante, v.mov_combate_m, previa]
		else:
			hud_combate.text = "Rodada %d · vez do %s" % [combate.rodada, v.nome]
	else:
		hud_combate.text = ""

# ---------- testes por linha de comando ----------

func _linha_de_comando() -> void:
	var captura := ""; var teste := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--captura="): captura = a.trim_prefix("--captura=")
		if a.begins_with("--teste="): teste = a.trim_prefix("--teste=")
	if captura == "" and teste == "": return
	if teste == "frente":
		camera.alvo = heroi.position + Vector3(0, 1, 0); camera.distancia = 4.0; camera.inclinacao = 15.0; camera.guinada = 180.0
		heroi.olhar_para(heroi.position + Vector3(0, 0, -5))
		for _f in 20: await get_tree().process_frame
	elif teste == "longe":
		_andar_para(Vector2i(45, 30))
		await get_tree().create_timer(30.0).timeout
	elif teste == "andar":
		camera.distancia = 8.0; camera.inclinacao = 40.0
		_andar_para(Vector2i(17, 1))
		for _f in 150: await get_tree().process_frame
	elif teste == "combate" or teste == "auto":
		_iniciar_encontro(true)
		await get_tree().create_timer(2.0).timeout
		if teste == "auto":
			auto = true
			var limite := 0
			while combate.ativo and limite < 60:
				limite += 1
				if combate.vez and combate.vez.lado == "grupo" and not combate.ocupado:
					var alvo: Node = null
					for m in monstros:
						if is_instance_valid(m) and m.vivo(): alvo = m
					if alvo: combate.clicar(alvo.celula, alvo)
					await get_tree().create_timer(0.2).timeout
					if combate.vez == heroi and not combate.ocupado: combate.encerrar_turno()
				await get_tree().create_timer(0.3).timeout
		else:
			var alvo: Node = monstros[0]
			combate.pairar(alvo.celula, alvo)
	for _f in 30: await get_tree().process_frame
	if captura != "":
		get_viewport().get_texture().get_image().save_png(captura)
	get_tree().quit()
