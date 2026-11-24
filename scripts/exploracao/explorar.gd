extends Node3D
## Cena principal: exploração e combate na Masmorra Base.
##
## Exploração: botão esquerdo num lugar já visto e a Tessa anda até lá. Portas começam fechadas:
## clique na porta para ela ir até lá e abrir. A distância andada vira tempo (turno de 10 min = o
## movimento de exploração dela, pela carga): cada turno gasta tocha e, a cada 2 turnos, há teste de
## monstros errantes (1 em d6). Errantes surgem fora da vista e vêm na direção do grupo; o combate
## começa quando um lado enxerga o outro (quem não viu nada fica surpreso).
## Visão: paredes, rocha e portas fechadas bloqueiam; só se vê o que está iluminado (tocha 9 m, tochas
## de parede) ou dentro da visão no escuro. Monstros só veem num cone à frente.
## Névoa de guerra: nunca visto = preto · já visto = lembrança apagada, sem criaturas · à vista = normal.
## Combate: na vez do personagem, o alcance fica destacado; clique para andar, num inimigo para atacar,
## numa porta para abrir. Espaço encerra a vez.
## Teclas: F foca · M modo mestre (vê tudo) · G grade · K força um encontro · R recomeça.
## Linha de comando: -- --captura=arquivo.png [--teste=andar|frente|longe|porta|errantes|combate|auto]

const Luz = preload("res://scripts/visual/luz.gd")
const Grade = preload("res://scripts/exploracao/grade.gd")
const Visao = preload("res://scripts/exploracao/visao.gd")
const Ator = preload("res://scripts/exploracao/ator.gd")
const Marcas = preload("res://scripts/visual/marcas.gd")
const Combate = preload("res://scripts/combate/combate.gd")
const Regras = preload("res://scripts/regras/regras.gd")
const Dados = preload("res://scripts/regras/dados.gd")

const LAYOUT := "res://data/masmorra/layout.json"
const TESSA_GLB := "res://arte/final/3d/tessa-biblioteca.glb"
const TESSA_ANIM := {"parado": "parado-espada-escudo", "andar": "andar", "golpe": "golpe", "dano": "levar-golpe", "morrer": "morrer", "vitoria": "vitoria"}
## Para onde o corpo aponta em cada animação (medido com tools/medir_frente.gd); o modelo gira o contrário.
const TESSA_GIRO := {"parado-espada-escudo": 30.0, "parado": 55.0, "andar": 90.0, "comecar-a-andar": 90.0, "golpe": 70.0,
	"levar-golpe": 30.0, "morrer": 90.0, "vitoria": 88.0, "magia": 60.0, "sacar-flecha": 30.0}
const INICIO := Vector2i(7, 5)
const TURNOS_POR_TOCHA := 6
const SEM_CELULA := Vector2i(-999, -999)
const VEL_ERRANTE := 2.0

@onready var camera: Camera3D = $Camera
var grade: RefCounted
var visao: RefCounted
var luz: Node
var combate: Node
var heroi: Node3D
var monstros: Array = []   # todos os monstros vivos em cena
var errantes: Array = []   # monstros vindo na direção do grupo, ainda sem combate
var marca_alcance: Node
var marca_caminho: Node
var marca_vez: Node
var MONSTROS := {}
var ENCONTROS := {}

var mestre := false
var grade_forte := false
var fim := false
var porta_alvo := {}       # porta que a Tessa vai abrir quando chegar

# Relógio da exploração
var taxa_m := 36.0
var turno := 0
var metros_no_turno := 0.0
var tocha_turnos := TURNOS_POR_TOCHA
var tochas_reserva := 0
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
	visao = Visao.new(grade)
	visao.tochas_parede = luz.tochas_cel.duplicate()
	visao.recalcular_luz_fixa()
	luz.set_nevoa(visao.textura(), Vector2(grade.W, grade.H))
	for n in ["marca_alcance", "marca_caminho", "marca_vez"]:
		var m := MeshInstance3D.new(); m.set_script(Marcas); add_child(m); set(n, m)
	combate = Combate.new(); add_child(combate)
	combate.grade = grade; combate.marca_alcance = marca_alcance; combate.marca_caminho = marca_caminho; combate.marca_vez = marca_vez
	combate.exploradas = visao.exploradas
	combate.visivel = func(a): return mestre or visao.visiveis.has(a.celula)
	combate.abrir_porta = _abrir_porta
	combate.registro.connect(_registrar)
	combate.terminou.connect(_fim_do_combate)
	_montar_hud()
	camera.alvo = heroi.position; camera.distancia = 15.0; camera.inclinacao = 55.0; camera.guinada = -30.0
	_atualizar_visao()
	_registrar("A Tessa desce a escada para a [b]%s[/b]. Clique no chão para andar; clique numa porta para abri-la." % grade.nomes.get(grade.area_de(heroi.celula), ""))
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
	a.giro_anim = TESSA_GIRO
	a.montar_modelo(load(TESSA_GLB).instantiate(), TESSA_ANIM, 0.0)
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
	a.moral = int(d.moral); a.xp = int(d.xp); a.infravisao_m = float(d.get("infravisao_m", 0.0))
	a.mov_combate_m = Regras.taxa_combate_m(float(d.mov_m))
	add_child(a); a.colocar(c)
	a.montar_modelo(Ator.goblin_provisorio(), {}, 0.0)
	a.olhar_para(heroi.position)
	a.passo_iniciado.connect(_ao_iniciar_passo)
	a.chegou.connect(_ao_monstro_chegar.bind(a))
	a.visible = false
	return a

# ---------- entrada ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_R: get_tree().reload_current_scene(); return
			KEY_F: camera.alvo = heroi.global_position; camera.distancia = 14.0
			KEY_M: mestre = not mestre; luz.set_mestre(mestre); _atualizar_visao()
			KEY_G: grade_forte = not grade_forte; luz.set_grade(grade_forte or combate.ativo)
			KEY_K: if not combate.ativo and not fim: _surgir_errantes(true)
			KEY_SPACE, KEY_ENTER: combate.encerrar_turno()
	if fim: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var mira := _mira(e.position)
		if not mira[2].is_empty():
			if combate.ativo: combate.clicar_porta(mira[2])
			else: _ir_abrir_porta(mira[2])
		elif combate.ativo: combate.clicar(mira[0], mira[1])
		else: _andar_para(mira[0])
	elif e is InputEventMouseMotion:
		var mira := _mira(e.position)
		if combate.ativo: combate.pairar(mira[0], mira[1])
		else: _previa(mira[0], mira[2])

## [célula do chão sob o mouse, monstro visível sob o mouse, porta fechada sob o mouse]
func _mira(tela: Vector2) -> Array:
	var o := camera.project_ray_origin(tela); var d := camera.project_ray_normal(tela)
	var alvo: Node = null; var perto := INF
	for m in monstros:
		if not is_instance_valid(m) or not m.vivo() or not m.visible: continue
		var c: Vector3 = m.global_position + Vector3(0, 0.7, 0)
		var t := (c - o).dot(d)
		if t > 0 and (o + d * t - c).length() < 0.55 and t < perto: perto = t; alvo = m
	var cel := SEM_CELULA
	var t_chao := INF
	if d.y < -0.001:
		t_chao = -o.y / d.y
		cel = grade.celula(o + d * t_chao)
	var porta := _porta_no_raio(o, d, minf(t_chao, perto))
	return [cel, alvo, porta]

## Porta fechada (e já vista) atingida pelo raio do mouse antes de `limite`.
func _porta_no_raio(o: Vector3, d: Vector3, limite: float) -> Dictionary:
	var melhor := {}; var tmin := limite
	var vistas := {}
	for ch in grade.portas:
		var pt: Dictionary = grade.portas[ch]
		if vistas.has(pt.id) or grade.porta_aberta.has(pt.id) or not (pt.tipo in ["porta", "dupla"]): continue
		vistas[pt.id] = true
		var conhecida := false
		for par in grade.lados_da_porta(pt):
			if visao.exploradas.has(par[0]) or visao.exploradas.has(par[1]): conhecida = true
		if not conhecida and not mestre: continue
		var comp: float = float(pt.largura) * 1.5
		var a: Vector3; var b: Vector3
		if pt.orient == "v":
			a = Vector3(pt.x * 1.5 - 0.2, 0, pt.y * 1.5); b = Vector3(pt.x * 1.5 + 0.2, 2.4, pt.y * 1.5 + comp)
		else:
			a = Vector3(pt.x * 1.5, 0, pt.y * 1.5 - 0.2); b = Vector3(pt.x * 1.5 + comp, 2.4, pt.y * 1.5 + 0.2)
		var t := _raio_caixa(o, d, a, b)
		if t >= 0.0 and t < tmin: tmin = t; melhor = pt
	return melhor

func _raio_caixa(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> float:
	var t0 := -INF; var t1 := INF
	for i in 3:
		if absf(d[i]) < 1e-6:
			if o[i] < a[i] or o[i] > b[i]: return -1.0
		else:
			var u := (a[i] - o[i]) / d[i]; var v := (b[i] - o[i]) / d[i]
			t0 = maxf(t0, minf(u, v)); t1 = minf(t1, maxf(u, v))
	return t0 if t1 >= t0 and t1 > 0 else -1.0

# ---------- exploração ----------

func _andar_para(c: Vector2i) -> void:
	if not grade.chao(c) or not visao.exploradas.has(c): return
	porta_alvo = {}
	var de: Vector2i = heroi.proxima_celula()
	var cam: Array[Vector2i] = grade.caminho(de, c)
	if cam.is_empty() and de == c and not heroi.andando(): return
	if cam.is_empty() and de != c: return
	if heroi.andando(): cam.push_front(de)
	marca_caminho.limpar(); marca_caminho.por([c], Color(1, 0.9, 0.6, 0.35), 0.15)
	heroi.seguir(cam)

func _ir_abrir_porta(pt: Dictionary) -> void:
	var de: Vector2i = heroi.proxima_celula()
	var melhor: Array[Vector2i] = []; var achou := false; var menor := INF
	for par in grade.lados_da_porta(pt):
		for c in par:
			if not visao.exploradas.has(c): continue
			if c == de:
				melhor = []; menor = 0.0; achou = true
			else:
				var cam: Array[Vector2i] = grade.caminho(de, c)
				if cam.is_empty(): continue
				var l: float = grade.comprimento(de, cam)
				if l < menor: menor = l; melhor = cam; achou = true
	if not achou:
		_registrar("Não há como chegar até essa porta por aqui.")
		return
	porta_alvo = pt
	if melhor.is_empty() and not heroi.andando():
		_ao_parar()
		return
	if heroi.andando(): melhor.push_front(de)
	marca_caminho.limpar()
	heroi.seguir(melhor)

## Abre a porta para o lado oposto de quem abre; a luz e a visão passam a atravessar.
func _abrir_porta(pt: Dictionary, de: Vector2i) -> void:
	if grade.porta_aberta.has(pt.id): return
	var outro := de
	for par in grade.lados_da_porta(pt):
		if par[0] == de: outro = par[1]
		elif par[1] == de: outro = par[0]
	grade.abrir_porta(pt)
	var no := $Masmorra.get_node_or_null("Portas/" + str(pt.id))
	if no:
		var sentido: Vector3 = grade.centro(outro) - grade.centro(de)
		var eixo := Vector3(0, 0, 1) if pt.orient == "v" else Vector3(1, 0, 0)
		for folha in no.get_children():
			var dir := eixo if folha.name == "Folha0" else -eixo
			var ang := deg_to_rad(95.0)
			if dir.rotated(Vector3.UP, ang).dot(sentido) < 0: ang = -ang
			create_tween().tween_property(folha, "rotation:y", ang, 0.45).set_trans(Tween.TRANS_SINE)
	visao.recalcular_luz_fixa()
	_atualizar_visao()
	if visao.visiveis.has(de) or de == heroi.celula:
		_registrar("A Tessa abre a porta %s." % pt.id if de == heroi.celula else "[color=#ff9a6a]Uma porta se abre (%s).[/color]" % pt.id)
	_checar_avistamento()

func _previa(c: Vector2i, porta: Dictionary) -> void:
	if heroi.andando(): return
	marca_caminho.limpar()
	if not porta.is_empty():
		var cels: Array = []
		for par in grade.lados_da_porta(porta):
			for x in par:
				if visao.exploradas.has(x): cels.append(x)
		marca_caminho.por(cels, Color(1, 0.8, 0.3, 0.4), 0.1)
		return
	if not grade.chao(c) or c == heroi.celula or not visao.exploradas.has(c): return
	var cam: Array[Vector2i] = grade.caminho(heroi.celula, c)
	if cam.is_empty(): return
	marca_caminho.por(cam.slice(0, cam.size() - 1), Color(1, 0.95, 0.8, 0.18), 0.55)
	marca_caminho.por([c], Color(1, 0.95, 0.8, 0.3), 0.15)

## Monstros (que não estão na vista de ninguém) abrem portas ao passar.
func _ao_iniciar_passo(de: Vector2i, para: Vector2i) -> void:
	var pt: Dictionary = grade.porta_entre(de, para)
	if not pt.is_empty() and not grade.porta_aberta.has(pt.id): _abrir_porta(pt, de)

func _ao_chegar(_c: Vector2i, metros: float) -> void:
	_atualizar_visao()
	if combate.ativo: return
	metros_no_turno += metros
	while metros_no_turno >= taxa_m:
		metros_no_turno -= taxa_m
		_passar_turno()
	_checar_avistamento()

func _ao_parar() -> void:
	if combate.ativo: return
	marca_caminho.limpar()
	if not porta_alvo.is_empty():
		var pt := porta_alvo; porta_alvo = {}
		for par in grade.lados_da_porta(pt):
			if heroi.celula in par:
				heroi.olhar_para(grade.centro(par[1] if par[0] == heroi.celula else par[0]))
				_abrir_porta(pt, heroi.celula)
				return

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
			_atualizar_visao()
	_registrar(txt)
	if turno % 2 == 0:
		var r := Dados.d(6)
		if r == 1:
			_registrar("Monstros errantes: d6 = [b]1[/b] → [color=#ff9a6a]passos ao longe…[/color]")
			_surgir_errantes(false)
		else:
			_registrar("Monstros errantes: d6 = %d → nada." % r)

func _hora() -> String:
	var minutos := turno * 10
	return "%d min" % minutos if minutos < 60 else "%dh%02d" % [minutos / 60, minutos % 60]

# ---------- visão ----------

func _atualizar_visao() -> void:
	visao.atualizar_jogador(heroi.celula, tocha_turnos > 0)
	visao.atualizar_textura(mestre)
	luz.atualizar_tochas(visao.exploradas, mestre)
	_atualizar_monstros_visiveis()

func _atualizar_monstros_visiveis() -> void:
	for m in monstros:
		if is_instance_valid(m) and m.vivo():
			m.visible = mestre or visao.visiveis.has(m.celula)

# ---------- encontros ----------

## Monstros errantes surgem fora da vista, a 2d6 × 3 m pelo caminho, e vêm na direção do grupo.
func _surgir_errantes(forcado: bool) -> void:
	if not errantes.is_empty(): return
	if forcado: _registrar("[i](K: monstros errantes por perto)[/i]")
	var tab: Array = ENCONTROS.nivel_1
	var e: Dictionary = tab[randi() % tab.size()]
	var dm: Dictionary = MONSTROS[e.monstro]
	var n := maxi(1, Dados.rolar(str(e.quantidade)))
	var dist := Dados.rolar("2d6") * 3.0
	var alc: Dictionary = grade.alcance(heroi.celula, dist + 9.0, {}, true)
	var centro := SEM_CELULA; var melhor := INF
	for c in alc:
		var custo: float = alc[c][0]
		if custo < 4.5 or visao.visiveis.has(c): continue
		if absf(custo - dist) < melhor: melhor = absf(custo - dist); centro = c
	if centro == SEM_CELULA: return
	var lugares: Array = alc.keys().filter(func(c): return float(alc[c][0]) >= 4.5 and not visao.visiveis.has(c))
	lugares.sort_custom(func(a, b): return Vector2(a - centro).length() < Vector2(b - centro).length())
	for i in mini(n, lugares.size()):
		var nome: String = dm.nome if n == 1 else "%s %d" % [dm.nome, i + 1]
		var m := _criar_monstro(str(e.monstro), nome, lugares[i])
		m.velocidade = VEL_ERRANTE
		monstros.append(m); errantes.append(m)
		_errante_rumo(m)
	print("(errantes: %d %s a %d m)" % [errantes.size(), dm.nome, int(dist)])
	_atualizar_monstros_visiveis()
	_checar_avistamento()

func _errante_rumo(m: Node3D) -> void:
	if combate.ativo or not errantes.has(m): return
	var ocup := {}
	for o in errantes:
		if o != m: ocup[o.proxima_celula()] = true
	var cam: Array[Vector2i] = grade.caminho(m.celula, heroi.proxima_celula(), ocup, true)
	if cam.size() > 1:
		cam.resize(cam.size() - 1)   # para ao lado, não em cima
		m.seguir(cam)

func _ao_monstro_chegar(_c: Vector2i, _metros: float, m: Node3D) -> void:
	_atualizar_monstros_visiveis()
	if combate.ativo: return
	_checar_avistamento()
	if errantes.has(m) and not combate.ativo: _errante_rumo(m)

## O combate começa quando um lado vê o outro. Quem não viu nada fica surpreso;
## quem viu rola surpresa normal (1–2 em d6).
func _checar_avistamento() -> void:
	if combate.ativo or errantes.is_empty() or fim: return
	var grupo_ve := false; var monstros_veem := false
	for m in errantes:
		if not is_instance_valid(m) or not m.vivo(): continue
		if visao.visiveis.has(m.celula): grupo_ve = true
		if visao.monstro_ve(m.celula, m.frente_vetor(), m.infravisao_m, heroi.celula, tocha_turnos > 0): monstros_veem = true
	if grupo_ve or monstros_veem: _comecar_combate(grupo_ve, monstros_veem)

func _comecar_combate(grupo_ve: bool, monstros_veem: bool) -> void:
	var lista := errantes.duplicate(); errantes.clear()
	porta_alvo = {}
	heroi.parar()
	for m in lista:
		m.parar(); m.velocidade = 3.2
	for a in [heroi] + lista:
		if a.andando(): await a.parou
	var sg := (not grupo_ve) or Dados.d(6) <= 2
	var sm := (not monstros_veem) or Dados.d(6) <= 2
	if grupo_ve and not monstros_veem: _registrar("A Tessa avista os monstros antes de ser vista.")
	elif monstros_veem and not grupo_ve: _registrar("[color=#ff9a6a]Algo a viu primeiro, do escuro.[/color]")
	_registrar("Surpresa: grupo %s · monstros %s" % ["surpreendido" if sg else "atento", "surpreendidos" if sm else "atentos"])
	camera.distancia = clampf(camera.distancia, 12.0, 18.0)
	heroi.rotulo.visible = true
	luz.set_grade(true)
	_atualizar_visao()
	combate.iniciar([heroi], lista, sg, sm)

func _fim_do_combate(resultado: String, xp: int, rodadas: int) -> void:
	luz.set_grade(grade_forte)
	if resultado == "vitoria":
		xp_total += xp
		_registrar("[color=#ffcf6a][b]Vitória![/b][/color] %d rodada(s) (%d s). XP: +%d (total %d)." % [rodadas, rodadas * 10, xp, xp_total])
		heroi.tocar("vitoria")
		monstros = monstros.filter(func(m): return is_instance_valid(m) and m.vivo())
		await get_tree().create_timer(2.5).timeout
		if not combate.ativo and not heroi.andando(): heroi.tocar("parado")
		heroi.rotulo.visible = false
	else:
		fim = true
		_registrar("[color=#ff7a5a][b]A Tessa caiu.[/b][/color]")
		hud_centro.text = "A Tessa caiu na masmorra.\nR para recomeçar"

# ---------- tela ----------

func _montar_hud() -> void:
	var hud: CanvasLayer = $HUD
	$HUD/Legenda.text = "Botão esquerdo: andar / atacar / abrir porta · Espaço: encerrar a vez · botão direito, Q/E: girar · roda: zoom · WASD: mover · F: focar · M: mestre · G: grade · K: encontro · R: recomeçar"
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
	# A câmera acompanha quem está agindo (se o jogador puder vê-lo).
	var quem: Node3D = null
	if combate.ativo and combate.vez and is_instance_valid(combate.vez) and combate.vez.visible: quem = combate.vez
	elif not combate.ativo and heroi.andando(): quem = heroi
	if quem: camera.alvo = camera.alvo.lerp(quem.global_position, 1.0 - exp(-2.5 * dt))
	_atualizar_monstros_visiveis()
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
			hud_combate.text = "Rodada %d · vez da %s · movimento: %.1f de %.0f m%s\nclique para andar · num inimigo para atacar · numa porta para abrir · Espaço encerra a vez" % [
				combate.rodada, v.nome, combate.restante, v.mov_combate_m, previa]
		else:
			hud_combate.text = "Rodada %d · vez %s" % [combate.rodada, ("do " + v.nome) if v.visible else "de algo no escuro"]
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
		heroi.tocar("andar")
		for _f in 40: await get_tree().process_frame
	elif teste == "golpe":
		camera.alvo = heroi.position + Vector3(0, 1, 0); camera.distancia = 4.0; camera.inclinacao = 15.0; camera.guinada = 90.0
		heroi.olhar_para(heroi.position + Vector3(0, 0, -5))
		heroi.tocar("golpe", 0.0)
		for _f in 25: await get_tree().process_frame
	elif teste == "andar":
		camera.distancia = 8.0; camera.inclinacao = 40.0
		_andar_para(Vector2i(10, 2))
		for _f in 70: await get_tree().process_frame
	elif teste == "porta":
		camera.distancia = 18.0; camera.inclinacao = 60.0
		var pt: Dictionary = grade.portas["v:12:5"]
		_ir_abrir_porta(pt)
		await get_tree().create_timer(4.0).timeout
		_andar_para(Vector2i(14, 5))
		await get_tree().create_timer(2.5).timeout
	elif teste == "longe":
		_andar_para(Vector2i(10, 6))
		await get_tree().create_timer(3.0).timeout
	elif teste == "errantes" or teste == "auto":
		_ir_abrir_porta(grade.portas["v:12:5"])
		await get_tree().create_timer(3.0).timeout
		_surgir_errantes(true)
		var limite := 0
		while not combate.ativo and limite < 40:
			limite += 1
			await get_tree().create_timer(0.5).timeout
		if teste == "auto":
			limite = 0
			while combate.ativo and limite < 80:
				limite += 1
				if combate.vez == heroi and not combate.ocupado:
					var alvo: Node = null
					for m in monstros:
						if is_instance_valid(m) and m.vivo() and m.visible: alvo = m
					if alvo: combate.clicar(alvo.celula, alvo)
					await get_tree().create_timer(0.2).timeout
					if combate.vez == heroi and not combate.ocupado: combate.encerrar_turno()
				await get_tree().create_timer(0.3).timeout
	elif teste == "combate":
		_surgir_errantes(true)
		await get_tree().create_timer(3.0).timeout
	for _f in 30: await get_tree().process_frame
	if captura != "":
		get_viewport().get_texture().get_image().save_png(captura)
	get_tree().quit()
