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
const TESSA_GLB := "res://arte/final/3d/tessa-heroica-biblioteca.glb"
const TESSA_ANIM := {"parado": "parado", "parado_combate": "parado-espada-escudo", "andar": "andar", "correr": "correr", "andar_furtivo": "andar-furtivo", "parado_furtivo": "parado-agachado", "andar_combate": "andar-combate", "golpe": "golpe", "dano": "levar-golpe", "morrer": "morrer", "vitoria": "vitoria", "bloquear": "bloquear", "esquivar": "esquivar"}
## Para onde o corpo aponta em cada animação (tools/medir_frente.gd); o modelo gira o contrário. Nas posturas
## de lado (guarda, dano, bloqueio, esquiva) vale para onde a cabeça olha (--teste=mirar), não o quadril.
const TESSA_GIRO := {"parado-espada-escudo": 76.0, "parado": 45.0, "andar": 90.0, "comecar-a-andar": 90.0, "correr": 90.0, "andar-furtivo": 90.0, "parado-agachado": 75.0, "andar-combate": 90.0, "golpe": 70.0,
	"levar-golpe": 85.0, "morrer": 90.0, "vitoria": 88.0, "magia": 60.0, "sacar-flecha": 30.0, "bloquear": 85.0, "esquivar": 130.0}
const GOBLIN_GLB := "res://arte/final/3d/goblin-biblioteca.glb"
const GOBLIN_ESCALA := 0.95
## Velocidade natural de cada animação de deslocamento já na escala do jogo (tools/medir_passada.gd).
const PASSADA_TESSA := {"andar": 1.25, "correr": 2.11, "andar_furtivo": 0.97, "andar_combate": 0.70}
const PASSADA_GOBLIN := {"andar": 0.88, "correr": 1.47, "andar_furtivo": 0.67, "andar_combate": 0.50}
## Animação de deslocamento de cada modo de movimento (em combate é sempre "andar").
const PAPEL_DO_MODO := {"devagar": "andar_furtivo", "normal": "andar", "rapido": "correr"}
const TESSA_ESCALA := 1.5   # o modelo heroico veio com ~1,03 m; no jogo ela tem ~1,55 m
const INICIO := Vector2i(7, 5)
const TURNOS_POR_TOCHA := 6
const SEM_CELULA := Vector2i(-999, -999)
const VEL_ERRANTE := 1.0

@onready var camera: Camera3D = $Camera
var grade: RefCounted
var visao: RefCounted
var luz: Node
var combate: Node
var heroi: Node3D          # quem lidera a fila (leva a tocha)
var grupo: Array = []      # personagens em jogo, na ordem da fila
var monstros: Array = []   # todos os monstros vivos em cena
var errantes: Array = []   # monstros vindo na direção do grupo, ainda sem combate
var marca_alcance: Node
var marca_caminho: Node
var marca_vez: Node
var marca_portas: Node
var porta_mat := {}        # id da porta -> material (para acender no mouse)
var _porta_acesa := ""
var MONSTROS := {}
var ENCONTROS := {}

var mestre := false
var MOV := {}               # data/regras/movimento.json
var modo := "normal"       # devagar · normal · rapido
var fichas: Array = []     # fichas (dicionários) do grupo em jogo
var botoes_modo := {}
var _goblins_brotados := 0
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
	MOV = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/movimento.json"))
	_criar_grupo()
	luz = Luz.new(); add_child(luz)
	luz.configurar(self, $Masmorra, $Ambiente, heroi)
	luz.tochas_automaticas(self, LAYOUT, ["24", "23", "21", "22", "15", "20", "14", "10", "12"], 2)
	visao = Visao.new(grade)
	visao.tochas_parede = luz.tochas_cel.duplicate()
	visao.recalcular_luz_fixa()
	_materiais_das_portas()
	luz.set_nevoa(visao.textura(), Vector2(grade.W, grade.H))
	for n in ["marca_alcance", "marca_caminho", "marca_vez", "marca_portas"]:
		var m := MeshInstance3D.new(); m.set_script(Marcas); add_child(m); set(n, m)
	combate = Combate.new(); add_child(combate)
	combate.grade = grade; combate.marca_alcance = marca_alcance; combate.marca_caminho = marca_caminho; combate.marca_vez = marca_vez
	combate.exploradas = visao.exploradas
	combate.camera = camera
	combate.visivel = func(a): return mestre or visao.visiveis.has(a.celula)
	combate.abrir_porta = _abrir_porta
	combate.registro.connect(_registrar)
	combate.terminou.connect(_fim_do_combate)
	_montar_hud()
	_mudar_modo("normal", false)
	camera.alvo = heroi.position; camera.distancia = 15.0; camera.inclinacao = 55.0; camera.guinada = -30.0
	_atualizar_visao()
	_registrar("A Tessa desce a escada para a [b]%s[/b]. Clique no chão para andar; clique numa porta para abri-la." % grade.nomes.get(grade.area_de(heroi.celula), ""))
	_linha_de_comando()

# ---------- personagens ----------

## Personagens em jogo (fichas em data/personagens/grupo-inicial.json). Todos usam as animações da Tessa
## (mesmo esqueleto Mixamo e o mesmo giro); `passo` ajusta a passada ao tamanho de cada um.
const HEROIS := {
	"tessa": {"glb": "res://arte/final/3d/tessa-heroica-biblioteca.glb", "escala": 1.5, "passo": 1.0, "mao": "mixamorig_RightHand"},
	"caco": {"glb": "res://arte/final/3d/caco-biblioteca.glb", "escala": 0.9, "passo": 1.08, "mao": "mixamorig_RightHand"},
	"lianne": {"glb": "res://arte/final/3d/lianne-biblioteca.glb", "escala": 0.86, "passo": 1.0, "mao": "mixamorig_LeftHand",
		"distancia": "arco curto", "papeis": {"atirar": "sacar-flecha"}},
}
const GRUPO_EM_JOGO := ["tessa", "caco", "lianne"]
## Armas de projétil de B/X: alcance curto/médio/longo (pés × 0,3 = metros).
const ALCANCES := {"arco curto": [15.0, 30.0, 45.0], "arco longo": [21.0, 42.0, 63.0], "funda": [12.0, 24.0, 48.0]}

func _criar_grupo() -> void:
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/personagens/grupo-inicial.json"))
	var lugares: Array[Vector2i] = [INICIO]
	var alc: Dictionary = grade.alcance(INICIO, 6.0, {}, true)
	var perto: Array = alc.keys().filter(func(c): return c != INICIO)
	perto.sort_custom(func(a, b): return float(alc[a][0]) < float(alc[b][0]))
	lugares.append_array(perto)
	var reserva := 0
	taxa_m = 999.0
	for k in GRUPO_EM_JOGO.size():
		var id: String = GRUPO_EM_JOGO[k]
		for x in G.personagens:
			if x.id == id: grupo.append(_criar_heroi(x, HEROIS[id], lugares[k]))
		for it in fichas[-1].equipamento:
			if str(it).begins_with("tocha x"): reserva += int(str(it).get_slice("x", 1))
	tochas_reserva = reserva - 1
	heroi = grupo[0]

func _criar_heroi(p: Dictionary, cfg: Dictionary, onde: Vector2i) -> Node3D:
	fichas.append(p)
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "grupo"
	a.nome = str(p.nome).get_slice(" ", 0)
	a.pv = int(p.pv); a.pv_max = a.pv; a.ca = int(p.ca); a.thac0 = int(p.thac0)
	var mfor := Regras.mod(int(p.atributos["for"]))
	a.mod_acerto = mfor; a.mod_dano = mfor
	a.dano = str(p.armas[0].dano); a.arma = str(p.armas[0].nome)
	a.infravisao_m = float(p.get("infravisao_m", 0.0))
	# O grupo anda no passo do mais lento (B/X).
	var t := Regras.taxa_exploracao_m(p.equipamento)
	taxa_m = minf(taxa_m, t)
	a.mov_combate_m = Regras.taxa_combate_m(t)
	for it in p.equipamento:
		if str(it).begins_with("escudo"): a.tem_escudo = true
	if cfg.has("distancia"):
		for w in p.armas:
			if str(w.nome) == cfg.distancia:
				a.dist_arma = str(w.nome); a.dist_dano = str(w.dano); a.dist_faixas = ALCANCES[w.nome]
				a.dist_mod = Regras.mod(int(p.atributos["des"]))
		for it in p.equipamento:
			if str(it).begins_with("flechas x") or str(it).begins_with("pedras de funda x"): a.municao = int(str(it).get_slice("x", 1))
	add_child(a); a.colocar(onde)
	a.giro_anim = TESSA_GIRO
	var modelo: Node3D = load(cfg.glb).instantiate()
	modelo.scale = Vector3.ONE * float(cfg.escala)
	var pas := {}
	for k in PASSADA_TESSA: pas[k] = PASSADA_TESSA[k] * float(cfg.passo)
	a.passadas = pas
	var papeis := TESSA_ANIM.duplicate()
	papeis.merge(cfg.get("papeis", {}), true)
	var mao := modelo.find_child(cfg.mao, true, false)
	a.montar_modelo(modelo, papeis, 0.0)
	if mao: a.armas_na_mao.assign(mao.get_children())
	a.empunhar(false)   # fora do combate a arma fica guardada
	a.rotulo.visible = false
	a.passo_iniciado.connect(_ao_iniciar_passo.bind(a))
	a.chegou.connect(_ao_chegar.bind(a))
	a.parou.connect(_ao_parar.bind(a))
	return a

## Fila: quando quem lidera dá um passo, cada um vai para onde estava o da frente.
func _puxar_fila(de: Vector2i) -> void:
	var alvo := de
	for f in grupo:
		if f == heroi or not f.vivo(): continue
		var atual: Vector2i = f.proxima_celula()
		if atual != alvo:
			var cam: Array[Vector2i] = grade.caminho(atual, alvo)
			if cam.size() > 3: cam = cam.slice(0, 3)
			f.seguir(cam)
		alvo = atual

func vivos() -> Array:
	return grupo.filter(func(h): return is_instance_valid(h) and h.vivo())

func _criar_monstro(id: String, nome: String, c: Vector2i) -> Node3D:
	var d: Dictionary = MONSTROS[id]
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "monstros"; a.nome = nome
	a.ca = int(d.ca); a.thac0 = Regras.thac0_monstro(str(d.dv)); a.pv = Regras.pv_monstro(str(d.dv)); a.pv_max = a.pv
	a.dano = str(d.ataques[0].dano); a.arma = str(d.ataques[0].nome)
	a.moral = int(d.moral); a.xp = int(d.xp); a.infravisao_m = float(d.get("infravisao_m", 0.0))
	a.tem_escudo = bool(d.get("escudo", false))
	a.mov_combate_m = Regras.taxa_combate_m(float(d.mov_m))
	add_child(a); a.colocar(c)
	if id == "goblin":
		# Modelo de verdade, com as mesmas animações (e o mesmo giro) dos personagens; espada curta sempre na mão.
		var modelo: Node3D = load(GOBLIN_GLB).instantiate()
		modelo.scale = Vector3.ONE * GOBLIN_ESCALA
		a.passadas = PASSADA_GOBLIN
		a.giro_anim = TESSA_GIRO
		a.montar_modelo(modelo, TESSA_ANIM, 0.0)
		a.empunhar(true)
	else:
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
			KEY_B: if not fim: _brotar_goblin()
			KEY_1: _mudar_modo("devagar")
			KEY_2: _mudar_modo("normal")
			KEY_3: _mudar_modo("rapido")
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
		var id_porta: String = str(mira[2].id) if not mira[2].is_empty() else ""
		if id_porta != _porta_acesa:
			_acender_porta(id_porta); _desenhar_portas()
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
	if porta.is_empty() and grade.chao(cel):
		# Perto da borda de uma célula com porta fechada também conta como clicar na porta.
		porta = _porta_perto(o + d * t_chao)
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

func _porta_perto(p: Vector3) -> Dictionary:
	var c: Vector2i = grade.celula(p)
	var fx: float = p.x / 1.5 - c.x; var fz: float = p.z / 1.5 - c.y
	for viz in [[Vector2i(-1, 0), fx], [Vector2i(1, 0), 1.0 - fx], [Vector2i(0, -1), fz], [Vector2i(0, 1), 1.0 - fz]]:
		if float(viz[1]) > 0.22: continue
		var pt: Dictionary = grade.porta_entre(c, c + viz[0])
		if not pt.is_empty() and not grade.porta_aberta.has(pt.id) and pt.tipo in ["porta", "dupla"]: return pt
	return {}

## Cada porta ganha o próprio material (contorno quente enquanto fechada, acende com o mouse).
func _materiais_das_portas() -> void:
	for no in $Masmorra.get_node("Portas").get_children():
		var folhas := no.find_children("*", "MeshInstance3D", true, false)
		if folhas.is_empty(): continue
		var m: ShaderMaterial = folhas[0].material_override.duplicate()
		m.set_shader_parameter("fechada", 1.0)
		for f in folhas: f.material_override = m
		porta_mat[str(no.name)] = m
		luz.materiais.append(m)

func _acender_porta(id: String) -> void:
	if id == _porta_acesa: return
	if porta_mat.has(_porta_acesa): porta_mat[_porta_acesa].set_shader_parameter("destaque", 0.0)
	_porta_acesa = id
	if porta_mat.has(id): porta_mat[id].set_shader_parameter("destaque", 1.0)

## Soleiras âmbar no chão dos dois lados de cada porta fechada já vista (o símbolo de porta do mapa).
func _desenhar_portas() -> void:
	marca_portas.limpar()
	var feitas := {}
	for ch in grade.portas:
		var pt: Dictionary = grade.portas[ch]
		if feitas.has(pt.id) or grade.porta_aberta.has(pt.id) or not (pt.tipo in ["porta", "dupla"]): continue
		feitas[pt.id] = true
		var conhecida := mestre
		for par in grade.lados_da_porta(pt):
			if visao.exploradas.has(par[0]) or visao.exploradas.has(par[1]): conhecida = true
		if not conhecida: continue
		var cor := Color(1.0, 0.72, 0.3, 0.75) if str(pt.id) == _porta_acesa else Color(1.0, 0.72, 0.3, 0.38)
		var comp: float = float(pt.largura) * 1.5
		var x: float = pt.x * 1.5; var z: float = pt.y * 1.5
		for lado: float in [-1.0, 1.0]:
			if pt.orient == "v":
				var x0: float = x + lado * 0.14; var x1: float = x + lado * 0.42
				marca_portas.retangulo(Vector2(minf(x0, x1), z + 0.1), Vector2(maxf(x0, x1), z + comp - 0.1), cor)
			else:
				var z0: float = z + lado * 0.14; var z1: float = z + lado * 0.42
				marca_portas.retangulo(Vector2(x + 0.1, minf(z0, z1)), Vector2(x + comp - 0.1, maxf(z0, z1)), cor)

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
		_ao_parar(heroi)
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
	if porta_mat.has(str(pt.id)):
		porta_mat[str(pt.id)].set_shader_parameter("fechada", 0.0); porta_mat[str(pt.id)].set_shader_parameter("destaque", 0.0)
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
	if not porta.is_empty(): return
	if not grade.chao(c) or c == heroi.celula or not visao.exploradas.has(c): return
	var cam: Array[Vector2i] = grade.caminho(heroi.celula, c)
	if cam.is_empty(): return
	marca_caminho.por(cam.slice(0, cam.size() - 1), Color(1, 0.95, 0.8, 0.18), 0.55)
	marca_caminho.por([c], Color(1, 0.95, 0.8, 0.3), 0.15)

## Monstros (que não estão na vista de ninguém) abrem portas ao passar.
func _ao_iniciar_passo(de: Vector2i, para: Vector2i, quem: Node3D) -> void:
	var pt: Dictionary = grade.porta_entre(de, para)
	if not pt.is_empty() and not grade.porta_aberta.has(pt.id): _abrir_porta(pt, de)
	if quem == heroi and not combate.ativo: _puxar_fila(de)

func _ao_chegar(_c: Vector2i, metros: float, quem: Node3D) -> void:
	_atualizar_visao()
	if combate.ativo or quem != heroi: return
	metros_no_turno += metros
	while metros_no_turno >= _taxa_turno():
		metros_no_turno -= _taxa_turno()
		_passar_turno()
	_checar_avistamento()

func _ao_parar(quem: Node3D) -> void:
	if combate.ativo or quem != heroi: return
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
		var m: Dictionary = MOV.modos[modo]
		var chance := int(m.errantes_em_6)
		var r := Dados.d(6)
		var faixa := "1" if chance == 1 else "1–%d" % chance
		if r > chance:
			_registrar("Monstros errantes (%s, %s em d6): %d → nada." % [str(m.nome).to_lower(), faixa, r])
			return
		_registrar("Monstros errantes (%s, %s em d6): [b]%d[/b] → [color=#ff9a6a]passos ao longe…[/color]" % [str(m.nome).to_lower(), faixa, r])
		var ciente := true
		if bool(m.furtivo):
			var f := _rolar_furtividade()
			ciente = not f
		_surgir_errantes(false, ciente)

# ---------- teste: brotar goblin ----------

## Teste: põe 1 goblin ao lado da Tessa. Fora de combate, começa o combate (sem surpresa);
## em combate, o goblin entra na luta. Cada clique (ou tecla B) gera mais um.
func _brotar_goblin() -> void:
	var ocup := {heroi.celula: true}
	for m in monstros:
		if is_instance_valid(m) and m.vivo(): ocup[m.proxima_celula()] = true
	var alc: Dictionary = grade.alcance(heroi.celula, 9.0, {}, true)
	var lugares: Array = alc.keys().filter(func(c): return not ocup.has(c))
	if lugares.is_empty():
		_registrar("Não há lugar livre perto da Tessa para brotar um goblin.")
		return
	var frente: Vector3 = heroi.frente_vetor()
	lugares.sort_custom(func(a, b):
		var da := float(alc[a][0]) - 0.3 * Vector2(a - heroi.celula).normalized().dot(Vector2(frente.x, frente.z))
		var db := float(alc[b][0]) - 0.3 * Vector2(b - heroi.celula).normalized().dot(Vector2(frente.x, frente.z))
		return da < db)
	_goblins_brotados += 1
	var m := _criar_monstro("goblin", "Goblin %d" % _goblins_brotados, lugares[0])
	m.visible = true
	monstros.append(m)
	m.scale = Vector3(0.01, 0.01, 0.01)
	create_tween().tween_property(m, "scale", Vector3.ONE, 0.3)
	_registrar("[i](teste)[/i] %s brota ao lado da Tessa." % m.nome)
	if combate.ativo:
		combate.adicionar(m)
		return
	for e in errantes.duplicate():
		errantes.erase(e); monstros.erase(e); e.queue_free()
	porta_alvo = {}
	await _grupo_em_guarda()
	luz.set_grade(true)
	_atualizar_visao()
	combate.iniciar(vivos(), [m], false, false)

# ---------- modos de movimento ----------

## Metros andados que fazem passar 1 turno de 10 min no modo atual.
func _taxa_turno() -> float:
	return taxa_m * float(MOV.modos[modo].velocidade)

func _mudar_modo(novo: String, avisar := true) -> void:
	modo = novo
	var m: Dictionary = MOV.modos[modo]
	if not combate.ativo:
		for h in vivos():
			h.velocidade = Ator.VEL_BASE * float(m.velocidade)
			h.papel_andar = PAPEL_DO_MODO.get(modo, "andar")
			if not h.andando(): h.tocar("parado")   # devagar: ficam agachados
	for k in botoes_modo: botoes_modo[k].button_pressed = (k == modo)
	if avisar: _registrar("Movimento: [b]%s[/b] (%s)." % [m.nome, m.dica])
	# Correndo, os errantes que ainda não tinham notado o grupo passam a ouvir.
	if modo == "rapido":
		for e in errantes: e.set_meta("ciente", true)

## Cada um do grupo rola; basta um falhar para o grupo ser ouvido.
func _rolar_furtividade() -> bool:
	var partes: Array[String] = []
	var ok := true
	for p in fichas:
		var chance := Regras.furtividade(p, MOV.furtividade)
		var r := randf()
		var passou := r < chance
		ok = ok and passou
		partes.append("%s %d%%: %s" % [str(p.nome).get_slice(" ", 0), roundi(chance * 100), "passou" if passou else "falhou"])
	_registrar("Furtividade do grupo (%s) → %s" % [", ".join(partes), "[color=#9ad0ff]ninguém os ouviu[/color]" if ok else "[color=#ff9a6a]vocês foram ouvidos[/color]"])
	return ok

func _hora() -> String:
	var minutos := turno * 10
	return "%d min" % minutos if minutos < 60 else "%dh%02d" % [minutos / 60, minutos % 60]

# ---------- visão ----------

func _atualizar_visao() -> void:
	visao.atualizar_jogador(heroi.celula, tocha_turnos > 0)
	visao.atualizar_textura(mestre)
	luz.atualizar_tochas(visao.exploradas, mestre)
	_atualizar_monstros_visiveis()
	_desenhar_portas()

func _atualizar_monstros_visiveis() -> void:
	for m in monstros:
		if is_instance_valid(m) and m.vivo():
			m.visible = mestre or visao.visiveis.has(m.celula)

# ---------- encontros ----------

## Monstros errantes surgem fora da vista, a 2d6 × 3 m pelo caminho, e vêm na direção do grupo.
func _surgir_errantes(forcado: bool, ciente := true) -> void:
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
		m.set_meta("ciente", ciente or modo == "rapido"); m.set_meta("turno", turno)
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
	if not bool(m.get_meta("ciente", true)):
		_errante_rondar(m, ocup)
		return
	var cam: Array[Vector2i] = grade.caminho(m.celula, heroi.proxima_celula(), ocup, true)
	if cam.size() > 1:
		cam.resize(cam.size() - 1)   # para ao lado, não em cima
		m.seguir(cam)

## Errante que não ouviu o grupo: anda à toa e, passados 3 turnos sem ser visto, vai embora.
func _errante_rondar(m: Node3D, ocup: Dictionary) -> void:
	if m.andando(): return
	if turno - int(m.get_meta("turno", turno)) >= 3 and not visao.visiveis.has(m.celula):
		errantes.erase(m); monstros.erase(m); m.queue_free()
		return
	var alc: Dictionary = grade.alcance(m.celula, 15.0, ocup, true)
	var opcoes: Array = alc.keys().filter(func(c): return float(alc[c][0]) >= 6.0)
	if opcoes.is_empty(): return
	m.seguir(grade.refazer(alc, opcoes[randi() % opcoes.size()]))

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
	var furtivos := lista.any(func(x): return not bool(x.get_meta("ciente", true)))
	porta_alvo = {}
	for m in lista:
		m.parar(); m.velocidade = Ator.VEL_BASE
	await _grupo_em_guarda()
	for a in lista:
		if a.andando(): await a.parou
	var mm: Dictionary = MOV.modos[modo]
	# Surpresa (normal 1–2 em d6). Devagar e sem ter sido ouvido: +1 para surpreender.
	# Correndo: impossível surpreender os monstros, e +1 na chance de ser surpreendido.
	var sg := (not grupo_ve) or Dados.d(6) <= 2 + int(mm.ser_surpreendido)
	var sm := false
	if mm.surpreender != null:
		sm = (not monstros_veem) or Dados.d(6) <= 2 + (int(mm.surpreender) if furtivos else 0)
	if grupo_ve and not monstros_veem: _registrar("A Tessa avista os monstros antes de ser vista.")
	elif monstros_veem and not grupo_ve: _registrar("[color=#ff9a6a]Algo a viu primeiro, do escuro.[/color]")
	_registrar("Surpresa: grupo %s · monstros %s" % ["surpreendido" if sg else "atento", "surpreendidos" if sm else "atentos"])
	luz.set_grade(true)
	_atualizar_visao()
	combate.iniciar(vivos(), lista, sg, sm)

## Todos param na próxima célula, sacam as armas e mostram o nome.
func _grupo_em_guarda() -> void:
	for h in vivos():
		h.parar()
	for h in vivos():
		if h.andando(): await h.parou
	for h in vivos():
		h.velocidade = Ator.VEL_BASE; h.papel_andar = "andar"
		h.empunhar(true); h.rotulo.visible = true

func _fim_do_combate(resultado: String, xp: int, rodadas: int) -> void:
	luz.set_grade(grade_forte)
	if resultado == "vitoria":
		xp_total += xp
		_registrar("[color=#ffcf6a][b]Vitória![/b][/color] %d rodada(s) (%d s). XP: +%d (total %d)." % [rodadas, rodadas * 10, xp, xp_total])
		for h in vivos(): h.tocar("vitoria")
		monstros = monstros.filter(func(m): return is_instance_valid(m) and m.vivo())
		# Quem caiu sai da fila; se a líder caiu, o próximo vivo passa a liderar (e a levar a tocha).
		var lider_antes := heroi
		grupo = vivos(); heroi = grupo[0]
		if heroi != lider_antes:
			luz.alvo = heroi
			_registrar("%s passa a liderar o grupo e pega a tocha." % heroi.nome)
		await get_tree().create_timer(2.5).timeout
		if not combate.ativo:
			for h in vivos():
				h.empunhar(false); h.rotulo.visible = false
			_mudar_modo(modo, false)
	else:
		fim = true
		_registrar("[color=#ff7a5a][b]O grupo caiu.[/b][/color]")
		hud_centro.text = "O grupo caiu na masmorra.\nR para recomeçar"

# ---------- tela ----------

func _montar_hud() -> void:
	var hud: CanvasLayer = $HUD
	$HUD/Legenda.text = "Botão esquerdo: andar / atacar / abrir porta · 1/2/3: devagar, normal, rápido · Espaço: encerrar a vez · botão direito, Q/E: girar · roda: zoom · WASD: mover · F: focar · M: mestre · G: grade · K: encontro · B: brotar goblin · R: recomeçar"
	$HUD/Legenda.label_settings = $HUD/Legenda.label_settings.duplicate()
	$HUD/Legenda.label_settings.font_size = 13
	var leg: Label = $HUD/Legenda
	leg.text = leg.text.replace(" · botão direito", "\nbotão direito")
	leg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	leg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	leg.offset_left = -600; leg.offset_right = -16; leg.offset_top = -90; leg.offset_bottom = -12
	var estilo := LabelSettings.new(); estilo.font_size = 16; estilo.outline_size = 5; estilo.outline_color = Color.BLACK
	var barra := HBoxContainer.new(); barra.position = Vector2(16, 12); barra.add_theme_constant_override("separation", 6)
	hud.add_child(barra)
	for k in ["devagar", "normal", "rapido"]:
		var b := Button.new(); b.toggle_mode = true; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_pressed_color", Color(1, 0.8, 0.35))
		b.add_theme_color_override("font_hover_pressed_color", Color(1, 0.85, 0.45))
		b.text = "%d · %s" % [["devagar", "normal", "rapido"].find(k) + 1, MOV.modos[k].nome]
		b.tooltip_text = str(MOV.modos[k].dica)
		b.pressed.connect(_mudar_modo.bind(k))
		barra.add_child(b); botoes_modo[k] = b
	var brotar := Button.new(); brotar.text = "B · Brotar goblin (teste)"; brotar.focus_mode = Control.FOCUS_NONE
	brotar.tooltip_text = "Põe 1 goblin ao lado da Tessa e começa (ou reforça) o combate"
	brotar.add_theme_color_override("font_color", Color(1, 0.6, 0.45))
	brotar.pressed.connect(func(): if not fim: _brotar_goblin())
	barra.add_child(VSeparator.new()); barra.add_child(brotar)
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
	# A câmera não muda sozinha: só se quem está agindo sair da tela é que ela desliza até ele.
	if quem and _fora_da_tela(quem.global_position + Vector3(0, 1, 0)):
		camera.alvo = camera.alvo.lerp(quem.global_position, 1.0 - exp(-2.0 * dt))
	_atualizar_monstros_visiveis()
	_atualizar_hud()

func _fora_da_tela(p: Vector3) -> bool:
	if camera.is_position_behind(p): return true
	var t := camera.unproject_position(p); var r := get_viewport().get_visible_rect().size
	return t.x < r.x * 0.08 or t.x > r.x * 0.92 or t.y < r.y * 0.1 or t.y > r.y * 0.72

func _linha_grupo() -> String:
	var partes: Array[String] = []
	for h in grupo:
		var extra := (" · %d %s" % [h.municao, "flechas" if h.dist_arma.begins_with("arco") else "pedras"]) if not h.dist_faixas.is_empty() else ""
		partes.append("%s PV %d/%d CA %d%s" % [h.nome, maxi(h.pv, 0), h.pv_max, h.ca, extra])
	return "\n".join(partes)

func _atualizar_hud() -> void:
	var area: String = grade.nomes.get(grade.area_de(heroi.celula), "")
	var tocha := "tocha: %d de %d turnos (+%d de reserva)" % [tocha_turnos, TURNOS_POR_TOCHA, tochas_reserva] if tocha_turnos > 0 else "sem luz"
	var prox := turno + (2 - turno % 2)
	hud_relogio.text = "%s\nTurno %d · %s · andado no turno: %.1f de %d m\n%s · teste de errantes no turno %d\nXP %d\n%s" % [
		area, turno, _hora(), metros_no_turno, int(_taxa_turno()), tocha, prox, xp_total, _linha_grupo()]
	if combate.ativo and combate.vez and is_instance_valid(combate.vez):
		var v: Node = combate.vez
		if v.lado == "grupo":
			var previa := "  →  este caminho: %.1f m" % combate.previa_m if combate.previa_m >= 0 else ""
			hud_combate.text = "Rodada %d · vez de %s · movimento: %.1f de %.0f m%s\nclique para andar · num inimigo para %s · numa porta para abrir · Espaço encerra a vez" % [
				combate.rodada, v.nome, combate.restante, v.mov_combate_m, previa, "atirar (%s, %d)" % [v.dist_arma, v.municao] if not v.dist_faixas.is_empty() and v.municao > 0 else "atacar"]
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
		var papel := "andar"
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--papel="): papel = x.get_slice("=", 1)
		if not OS.get_cmdline_user_args().has("--parado"): heroi.tocar(papel)
		for _f in 40: await get_tree().process_frame
	elif teste == "modos":
		for k in ["devagar", "rapido"]:
			_mudar_modo(k)
			for i in 8:
				_passar_turno()
				if not errantes.is_empty():
					print("   errantes cientes: ", errantes.map(func(x): return x.get_meta("ciente")))
					for e in errantes.duplicate(): errantes.erase(e); monstros.erase(e); e.queue_free()
		_mudar_modo("devagar")
		for i in 3: _rolar_furtividade()
		_surgir_errantes(false, false)
		print("   errantes: ", errantes.size(), " cientes: ", errantes.map(func(x): return x.get_meta("ciente")))
		await get_tree().create_timer(3.0).timeout
		print("   andando à toa: ", errantes.map(func(x): return x.andando()))
	elif teste == "brotar":
		for i in 3:
			_brotar_goblin()
			await get_tree().create_timer(0.6).timeout
		camera.alvo = heroi.position; camera.distancia = 6.5; camera.inclinacao = 42.0; camera.guinada = 160.0
		await get_tree().create_timer(5.0).timeout
	elif teste == "inicio":
		camera.alvo = Vector3(15, 0, 7); camera.distancia = 11.0; camera.inclinacao = 50.0; camera.guinada = -20.0
		_acender_porta("P03"); _desenhar_portas()
		for _f in 40: await get_tree().process_frame
	elif teste == "golpe":
		camera.alvo = heroi.position + Vector3(0, 1, 0); camera.distancia = 4.0; camera.inclinacao = 15.0; camera.guinada = 90.0
		heroi.olhar_para(heroi.position + Vector3(0, 0, -5))
		heroi.tocar("golpe", 0.0)
		for _f in 25: await get_tree().process_frame
	elif teste == "andar" or teste == "correr" or teste == "furtivo":
		camera.distancia = 8.0; camera.inclinacao = 40.0
		if teste != "andar": _mudar_modo("rapido" if teste == "correr" else "devagar", false)
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
	elif teste == "impacto":
		# Quadros do golpe da Tessa e do goblin (acerto ou erro, conforme o dado), para conferir os efeitos.
		_brotar_goblin()
		await get_tree().create_timer(1.5).timeout
		var g: Node3D = monstros[0]
		camera.alvo = (heroi.position + g.position) / 2.0; camera.distancia = 5.0; camera.inclinacao = 32.0; camera.guinada = 200.0
		var k := 0
		for par in [[heroi, g], [g, heroi], [heroi, g]]:
			if not (par[0].vivo() and par[1].vivo()): continue
			combate._atacar(par[0], par[1])
			var t0 := Time.get_ticks_msec()
			var imgs: Array[Image] = []
			for ms in [600, 760, 820, 870, 930, 1100]:
				while Time.get_ticks_msec() - t0 < ms: await get_tree().process_frame
				imgs.append(get_viewport().get_texture().get_image())
			for im in imgs:
				im.save_png(captura.replace(".png", "-%02d.png" % k)); k += 1
			await get_tree().create_timer(1.5).timeout
	elif teste == "mirar":
		# Para onde olham cabeça e escudo em cada animação de combate, em relação ao oponente.
		_brotar_goblin()
		await get_tree().create_timer(1.5).timeout
		var g: Node3D = monstros[0]
		var escudo: Node3D = null
		for n in heroi.modelo.find_children("*", "BoneAttachment3D", true, false):
			if str(n.bone_name).contains("LeftForeArm"): escudo = n
		var sk: Skeleton3D = heroi.modelo.find_children("*", "Skeleton3D", true, false)[0]
		var ic := sk.find_bone("mixamorig_Head")
		# Frente em repouso: normal dos ombros, no sentido dos pés.
		var R := func(n): return sk.get_bone_global_rest(sk.find_bone(n)).origin
		var fr0: Vector3 = Vector3.UP.cross(R.call("mixamorig_RightShoulder") - R.call("mixamorig_LeftShoulder"))
		if fr0.dot(R.call("mixamorig_LeftToeBase") - R.call("mixamorig_LeftFoot")) < 0: fr0 = -fr0
		var olhar_local: Vector3 = sk.get_bone_global_rest(ic).basis.inverse() * fr0.normalized()
		for papel in ["parado_combate", "golpe", "dano", "bloquear", "esquivar"]:
			for t in [0.2, 0.35, 0.55]:
				heroi.olhar_para(g.global_position); heroi.tocar(papel, 0.0)
				await get_tree().create_timer(0.3).timeout
				heroi.player.seek(t, true)
				await get_tree().process_frame
				var alvo: Vector3 = g.global_position - heroi.global_position; alvo.y = 0
				var ol: Vector3 = sk.global_basis * (sk.get_bone_global_pose(ic).basis * olhar_local); ol.y = 0
				var linha := "MIRAR %-15s t=%.2f olhar %4.0f°" % [papel, t, rad_to_deg(alvo.signed_angle_to(ol, Vector3.UP))]
				if escudo:
					var mi: MeshInstance3D = escudo.find_children("*", "MeshInstance3D", true, false)[0]
					var ab := mi.get_aabb(); var eix := 0
					for e in 3: if ab.size[e] < ab.size[eix]: eix = e
					var nrm: Vector3 = mi.global_basis[eix].normalized()
					if nrm.dot(alvo) < 0: nrm = -nrm
					var nh := nrm; nh.y = 0
					linha += "  escudo %4.0f°" % rad_to_deg(alvo.signed_angle_to(nh, Vector3.UP))
				print(linha)
	elif teste == "flecha":
		# A Lianne atira num goblin a uns 9 m: um acerto e um erro (esquiva), com a câmera de lado.
		var lianne: Node3D = grupo[2]
		var alc: Dictionary = grade.alcance(lianne.celula, 12.0, {}, true)
		var longe: Array = alc.keys().filter(func(c): return float(alc[c][0]) >= 7.5 and grade.linha(lianne.celula, c) and visao.visiveis.has(c))
		longe.sort_custom(func(a, b): return float(alc[a][0]) > float(alc[b][0]))
		var g := _criar_monstro("goblin", "Goblin 1", longe[0])
		g.visible = true; monstros.append(g)
		await _grupo_em_guarda()
		combate.grupo = vivos(); combate.monstros = [g]
		g.olhar_para(lianne.global_position)
		var meio: Vector3 = (lianne.position + g.position) / 2.0
		var dir: Vector3 = (g.position - lianne.position); dir.y = 0; dir = dir.normalized()
		camera.alvo = meio; camera.distancia = 11.0; camera.inclinacao = 50.0
		camera.guinada = rad_to_deg(atan2(dir.z, -dir.x))
		mestre = true; _atualizar_visao()
		await get_tree().create_timer(0.8).timeout
		var k := 0
		for r in [19, 2]:
			Dados.forcados.append(r)
			combate._atacar(lianne, g, true)
			var t0 := Time.get_ticks_msec()
			var imgs: Array[Image] = []
			for ms in [300, 700, 1000, 1200, 1400, 1700]:
				while Time.get_ticks_msec() - t0 < ms: await get_tree().process_frame
				imgs.append(get_viewport().get_texture().get_image())
			for im in imgs:
				im.save_png(captura.replace(".png", "-%02d.png" % k)); k += 1
			await get_tree().create_timer(1.5).timeout
	elif teste == "defesa":
		# Erros forçados, vistos por trás de quem ataca: o defensor deve aparecer de frente.
		_brotar_goblin()
		await get_tree().create_timer(1.5).timeout
		var g: Node3D = monstros[0]
		var cam := Camera3D.new(); add_child(cam); cam.fov = 50
		var k := 0
		for caso in [[heroi, g], [g, heroi]]:
			var at: Node3D = caso[0]; var al: Node3D = caso[1]
			var tras: Vector3 = (at.global_position - al.global_position); tras.y = 0
			cam.global_position = al.global_position + tras.normalized() * 2.6 + tras.normalized().cross(Vector3.UP) * 1.3 + Vector3(0, 2.6, 0)
			cam.look_at(al.global_position + Vector3(0, 0.9, 0)); cam.current = true
			Dados.forcados.append(2)
			combate._atacar(at, al)
			var t0 := Time.get_ticks_msec()
			var imgs: Array[Image] = []
			for ms in [450, 700, 860, 1000, 1300]:
				while Time.get_ticks_msec() - t0 < ms: await get_tree().process_frame
				imgs.append(get_viewport().get_texture().get_image())
			for im in imgs:
				im.save_png(captura.replace(".png", "-%02d.png" % k)); k += 1
			await get_tree().create_timer(1.8).timeout
	elif teste == "combate":
		_surgir_errantes(true)
		await get_tree().create_timer(3.0).timeout
	for _f in 30: await get_tree().process_frame
	if captura != "":
		get_viewport().get_texture().get_image().save_png(captura)
	get_tree().quit()
