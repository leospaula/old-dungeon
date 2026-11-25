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
const Ficha = preload("res://scripts/regras/ficha.gd")
const Hud = preload("res://scripts/interface/hud.gd")
const Livro = preload("res://scripts/interface/livro.gd")
const Estilo = preload("res://scripts/interface/estilo.gd")
const Portas = preload("res://scripts/exploracao/portas.gd")
const Procurar = preload("res://scripts/exploracao/procurar.gd")

const LAYOUT := "res://data/masmorra/layout.json"
const TESSA_GLB := "res://arte/final/3d/tessa-heroica-biblioteca.glb"
const TESSA_ANIM := {"parado": "parado", "parado_combate": "parado-espada-escudo", "andar": "andar", "correr": "correr", "andar_furtivo": "andar-furtivo", "parado_furtivo": "parado-agachado", "andar_combate": "andar-combate", "golpe": "golpe", "dano": "levar-golpe", "morrer": "morrer", "vitoria": "vitoria", "bloquear": "bloquear", "esquivar": "esquivar"}
## Para onde o corpo aponta em cada animação (tools/medir_frente.gd); o modelo gira o contrário. Nas posturas
## de lado (guarda, dano, bloqueio, esquiva) vale para onde a cabeça olha (--teste=mirar), não o quadril.
const TESSA_GIRO := {"parado-espada-escudo": 76.0, "parado": 45.0, "andar": 90.0, "comecar-a-andar": 90.0, "correr": 90.0, "andar-furtivo": 90.0, "parado-agachado": 75.0, "andar-combate": 90.0, "golpe": 70.0,
	"levar-golpe": 85.0, "morrer": 90.0, "vitoria": 88.0, "magia": 60.0, "sacar-flecha": 81.0, "bloquear": 85.0, "esquivar": 130.0,
	"parado-luta": 78.0, "corte-dentro": 63.0, "corte-fora": 118.0, "estocada-cima": 75.0, "soltar-flecha": 84.0,
	# Estilos de luta (25/11): guardas pelo olhar; golpes pela mão no impacto; arco pela linha da flecha (--teste=olhar).
	"impacto-guarda": 91.0, "impacto-de-cima": 82.0, "impacto-horizontal": 112.0, "impacto-reves": 75.0,
	"duas-maos-guarda": 89.0, "duas-maos-golpe": 85.0, "aparar": 99.0, "haste-estocada": 84.0, "haste-guarda": 84.0, "cajado-golpe": 91.0,
	"besta-mirar": 88.0, "arco-guarda": 89.0, "arco-espera": 85.0, "arco-andar": 88.0, "atirar-flecha": 80.0, "arremessar": 93.0,
	"arremessar-faca": 101.0, "arremessar-frasco": 94.0, "chutar-porta": 73.0, "ajoelhar": 91.0, "beber": 96.0,
	"faca-guarda": 74.0, "faca-estocada": 81.0, "besta-guarda": 88.0, "besta-disparo": 89.0, "machado-guarda": 76.0,
	"haste-bloquear": 91.0, "arco-bloquear": 85.0}
const GOBLIN_GLB := "res://arte/final/3d/goblin-biblioteca.glb"
const GOBLIN_ESCALA := 0.95
## Velocidade natural de cada animação de deslocamento já na escala do jogo (tools/medir_passada.gd).
const PASSADA_TESSA := {"andar": 1.25, "correr": 2.11, "andar_furtivo": 0.97, "andar_combate": 0.70, "arco-andar": 0.79}
const PASSADA_GOBLIN := {"andar": 0.88, "correr": 1.47, "andar_furtivo": 0.67, "andar_combate": 0.50}
## Animação de deslocamento de cada modo de movimento (em combate é sempre "andar").
const PAPEL_DO_MODO := {"cauteloso": "andar_furtivo", "devagar": "andar_furtivo", "normal": "andar", "rapido": "correr"}
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
var selecionado: Node3D = null   # quem age nas ações de exploração (carta clicada); sem seleção, quem lidera
var portas: RefCounted     # ações e estado das portas (scripts/exploracao/portas.gd)
var procurar: RefCounted   # portas secretas e armadilhas de sala (scripts/exploracao/procurar.gd)
var marca_armadilhas: Node
var bonus_silencio_ate := -1   # até este turno o grupo se move em silêncio com bônus (ouviu monstros antes)
var _porta_menu := {}      # porta do balão aberto
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
var xp_total := 0

# Tela
var hud_ui: Control
var livro: Control
var diario: Array = []     # [{turno, tipo, texto}] — o diário automático do grupo
var _area_antes := ""
var hud_centro: Label

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
	portas = Portas.new(self)
	luz.set_nevoa(visao.textura(), Vector2(grade.W, grade.H))
	for n in ["marca_alcance", "marca_caminho", "marca_vez", "marca_portas", "marca_armadilhas"]:
		var m := MeshInstance3D.new(); m.set_script(Marcas); add_child(m); set(n, m)
	procurar = Procurar.new(self); procurar.desenhar()
	combate = Combate.new(); add_child(combate)
	combate.grade = grade; combate.marca_alcance = marca_alcance; combate.marca_caminho = marca_caminho; combate.marca_vez = marca_vez
	combate.exploradas = visao.exploradas
	combate.camera = camera
	combate.visivel = func(a): return mestre or visao.visiveis.has(a.celula)
	combate.abrir_porta = func(pt, _de): portas.tentar_abrir(pt, combate.vez)
	combate.registro.connect(_registrar)
	combate.terminou.connect(_fim_do_combate)
	_montar_hud()
	_mudar_modo("normal", false)
	camera.alvo = heroi.position; camera.distancia = 15.0; camera.inclinacao = 55.0; camera.guinada = -30.0
	_atualizar_visao()
	_registrar("A Tessa desce a escada para a [b]%s[/b]. Clique no chão para andar; clique numa porta para ver as ações; clique numa carta para escolher quem age." % grade.nomes.get(grade.area_de(heroi.celula), ""))
	_anotar_area()
	_linha_de_comando()

# ---------- personagens ----------

## Personagens em jogo (fichas em data/personagens/grupo-inicial.json). Todos usam as animações da Tessa
## (mesmo esqueleto Mixamo e o mesmo giro); `passo` ajusta a passada ao tamanho de cada um.
const HEROIS := {
	"tessa": {"glb": "res://arte/final/3d/tessa-heroica-biblioteca.glb", "escala": 1.5, "passo": 1.0, "mao": "mixamorig_RightHand"},
	"caco": {"glb": "res://arte/final/3d/caco-biblioteca.glb", "escala": 0.9, "passo": 1.08, "mao": "mixamorig_RightHand"},
	"lianne": {"glb": "res://arte/final/3d/lianne-biblioteca.glb", "escala": 0.86, "passo": 1.0, "mao": "mixamorig_LeftHand",
		"distancia": "arco curto"},
}
const GRUPO_EM_JOGO := ["tessa", "caco", "lianne"]

func _criar_grupo() -> void:
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/personagens/grupo-inicial.json"))
	var lugares: Array[Vector2i] = [INICIO]
	var alc: Dictionary = grade.alcance(INICIO, 6.0, {}, true)
	var perto: Array = alc.keys().filter(func(c): return c != INICIO)
	perto.sort_custom(func(a, b): return float(alc[a][0]) < float(alc[b][0]))
	lugares.append_array(perto)
	for k in GRUPO_EM_JOGO.size():
		var id: String = GRUPO_EM_JOGO[k]
		for x in G.personagens:
			if x.id == id: grupo.append(_criar_heroi(x, HEROIS[id], lugares[k]))
	heroi = grupo[0]
	_recalcular_grupo()
	_gastar_tocha()   # a primeira tocha já entra acesa

func _criar_heroi(p: Dictionary, cfg: Dictionary, onde: Vector2i) -> Node3D:
	fichas.append(p)
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "grupo"
	a.nome = str(p.nome).get_slice(" ", 0)
	a.ficha = Ficha.new(p, str(cfg.get("distancia", "")))
	a.pv = int(p.pv); a.thac0 = int(p.thac0)
	# Infravisão (B/X): elfos e anões enxergam no escuro até 18 m.
	a.infravisao_m = float(p.get("infravisao_m", 18.0 if str(p.classe) in ["elfo", "anao"] else 0.0))
	add_child(a); a.colocar(onde)
	a.giro_anim = TESSA_GIRO
	var modelo: Node3D = load(cfg.glb).instantiate()
	modelo.scale = Vector3.ONE * float(cfg.escala)
	var pas := {}
	for k in PASSADA_TESSA: pas[k] = PASSADA_TESSA[k] * float(cfg.passo)
	a.passadas = pas
	var papeis := TESSA_ANIM.duplicate()
	papeis.merge(cfg.get("papeis", {}), true)
	a.montar_modelo(modelo, papeis, 0.0)
	_aplicar_ficha(a)
	a.empunhar(false)   # fora do combate a arma fica guardada
	a.rotulo.visible = false
	a.passo_iniciado.connect(_ao_iniciar_passo.bind(a))
	a.chegou.connect(_ao_chegar.bind(a))
	a.parou.connect(_ao_parar.bind(a))
	return a

## Números de combate a partir da ficha (arma na mão, armadura, escudo, munição). Nada disso é salvo.
func _aplicar_ficha(a: Node3D) -> void:
	var f = a.ficha
	a.ca = f.ca(); a.pv_max = f.pv_max()
	a.mod_acerto = f.mod("for"); a.mod_dano = f.mod("for")
	a.tem_escudo = f.mao_e != null and Ficha.info(f.mao_e).get("tipo") == "escudo"
	var w = f.arma()
	var inf := Ficha.info(w)
	a.dist_faixas = []; a.municao = 0
	a.dano = str(inf.get("dano", "1d2")); a.arma = str(inf.get("nome", "punhos"))
	if inf.has("distancia"):
		a.dist_arma = str(w.id); a.dist_dano = str(inf.dano); a.dist_faixas = inf.distancia
		a.dist_mod = f.mod("des"); a.municao = f.municao_de(w)
	a.vestir(f, func(it): return Ficha.info(it))
	a.mov_combate_m = Regras.taxa_combate_m(f.movimento_m())
	# O estilo de luta vem da arma na mão (data/regras/estilos.json).
	a.aplicar_estilo(str(inf.get("estilo", "desarmado")) if w != null else "desarmado")
	if a.em_combate: a.empunhar(true)
	a.atualizar_rotulo()

## O grupo anda no passo do mais lento (B/X); a carga de cada um vem da ficha.
func _recalcular_grupo() -> void:
	taxa_m = 999.0
	for h in vivos(): taxa_m = minf(taxa_m, h.ficha.movimento_m())

func _tochas_reserva() -> int:
	var n := 0
	for h in vivos(): n += h.ficha.contar("tocha")
	return n

## Acende uma tocha nova: sai do inventário de quem lidera (ou de quem ainda tiver).
func _gastar_tocha() -> String:
	for h in [heroi] + vivos():
		if h.ficha.gastar("tocha"): return h.nome
	return ""

## Fila: quando quem lidera dá um passo, cada um vai para onde estava o da frente.
func _puxar_fila(de: Vector2i) -> void:
	var alvo := de
	for f in grupo:
		if f == heroi or not f.vivo(): continue
		var atual: Vector2i = f.proxima_celula()
		if atual != alvo:
			var cam: Array[Vector2i] = grade.caminho(atual, alvo, _ocupadas_por(grupo))   # nunca através de monstros
			if cam.size() > 3: cam = cam.slice(0, 3)
			f.seguir(cam)
		alvo = atual

## Casas ocupadas por seres vivos (onde estão e para onde já estão indo), menos os de `exceto`.
func _ocupadas_por(exceto: Array = []) -> Dictionary:
	var d := {}
	for x in grupo + monstros + errantes:
		if not is_instance_valid(x) or not x.vivo() or x in exceto: continue
		d[x.celula] = true; d[x.proxima_celula()] = true
	return d

## Caminho de quem lidera sem atravessar ninguém. Se o grupo fecha um corredor de uma casa só, os
## companheiros dão passagem (a fila se reorganiza); monstros nunca são atravessados.
func _caminho_lider(de: Vector2i, para: Vector2i) -> Array[Vector2i]:
	var todos := _ocupadas_por([heroi])
	if todos.has(para): return []
	var desvio := todos.duplicate(); desvio.merge(procurar.vistas())   # desvia de armadilha já vista
	var cam: Array[Vector2i] = grade.caminho(de, para, desvio)
	if cam.is_empty(): cam = grade.caminho(de, para, todos)
	if cam.is_empty(): cam = grade.caminho(de, para, _ocupadas_por(grupo))
	return cam

func vivos() -> Array:
	return grupo.filter(func(h): return is_instance_valid(h) and h.vivo())

func _criar_monstro(id: String, nome: String, c: Vector2i) -> Node3D:
	var d: Dictionary = MONSTROS[id]
	var a: Node3D = Ator.new(); a.grade = grade; a.lado = "monstros"; a.nome = nome
	a.set_meta("id", id)
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
	a.passo_iniciado.connect(_ao_iniciar_passo.bind(a))
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
			KEY_O: _acao_hud("ouvir")
			KEY_P: _acao_hud("procurar")
			KEY_T: if not fim: _arsenal_teste()
			KEY_I: _acao_hud("ficha")
			KEY_ESCAPE: _selecionar(null)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				# Atalhos dos medalhões (a tecla aparece no canto de cada um).
				if hud_ui and not livro.visible: hud_ui.atalho(str(e.keycode - KEY_0))
			KEY_SPACE, KEY_ENTER: combate.encerrar_turno()
	if fim: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var mira := _mira(e.position)
		if not mira[2].is_empty():
			if combate.ativo: combate.clicar_porta(mira[2])
			else: _menu_da_porta(mira[2], e.position)
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
		if vistas.has(pt.id) or grade.porta_aberta.has(pt.id) or not (pt.tipo in ["porta", "dupla"]) or procurar.secreta(pt): continue
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
		if not pt.is_empty() and not grade.porta_aberta.has(pt.id) and pt.tipo in ["porta", "dupla"] and not procurar.secreta(pt): return pt
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
		if feitas.has(pt.id) or grade.porta_aberta.has(pt.id) or not (pt.tipo in ["porta", "dupla"]) or (procurar and procurar.secreta(pt)): continue
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
	var cam: Array[Vector2i] = _caminho_lider(de, c)
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
				var cam: Array[Vector2i] = _caminho_lider(de, c)
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
func _abrir_porta(pt: Dictionary, de: Vector2i, quem := "") -> void:
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
		_registrar("%s abre a porta %s." % [quem, pt.id] if quem != "" else "[color=#ff9a6a]Uma porta se abre (%s).[/color]" % pt.id)
	_checar_avistamento()

func _previa(c: Vector2i, porta: Dictionary) -> void:
	if heroi.andando(): return
	marca_caminho.limpar()
	if not porta.is_empty(): return
	if not grade.chao(c) or c == heroi.celula or not visao.exploradas.has(c): return
	var cam: Array[Vector2i] = _caminho_lider(heroi.celula, c)
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
	if quem.lado == "grupo" and quem.vivo():
		procurar.pisou(quem, _c)
		if not combate.ativo:
			procurar.elfo_passando(quem)
			if quem == heroi and modo == "cauteloso": procurar.cauteloso(quem, _c)
	if quem == heroi: _anotar_area()
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
				_abrir_porta(pt, heroi.celula, heroi.nome)
				return

## Ações que gastam tempo (ouvir, procurar, pregar...): frações de turno somam como metros andados.
func _gastar_tempo(turnos: float) -> void:
	metros_no_turno += turnos * _taxa_turno()
	while metros_no_turno >= _taxa_turno() - 0.001:
		metros_no_turno = maxf(0.0, metros_no_turno - _taxa_turno())
		_passar_turno()
	hud_ui.refazer()

# ---------- ações de exploração ----------

## Quem age: o personagem da carta selecionada; sem seleção (ou se caiu), quem lidera.
func agente() -> Node3D:
	return selecionado if is_instance_valid(selecionado) and selecionado.vivo() else heroi

func _selecionar(h) -> void:
	selecionado = h if h != selecionado else null
	hud_ui.selecionado = selecionado; hud_ui.refazer()
	if selecionado: _registrar("[i]%s vai agir nas ações de exploração.[/i]" % selecionado.nome)

## Clique numa porta fechada fora do combate: balão com as ações de quem age.
func _menu_da_porta(pt: Dictionary, onde: Vector2) -> void:
	if portas.ocupado: return
	var q := agente()
	_porta_menu = pt
	hud_ui.menu_acoes("Porta %s · %s" % [pt.id, q.nome], portas.opcoes(pt, q), onde)

func _acao_porta(id: String) -> void:
	if _porta_menu.is_empty(): return
	var pt := _porta_menu; _porta_menu = {}
	porta_alvo = {}
	await portas.agir(pt, agente(), id)

func monstros_vivos() -> Array:
	var out: Array = []
	for m in monstros + errantes:
		if is_instance_valid(m) and m.vivo() and not out.has(m): out.append(m)
	return out

## Ouvir no corredor (medalhão): quem age e quem estiver perto param e escutam (1 rodada). O sucesso
## detecta monstros até 18 m pelos caminhos abertos: o grupo não será surpreendido por eles e se move
## em silêncio com bônus por 3 turnos.
var _ouvindo := false
func _ouvir_aqui() -> void:
	if _ouvindo or portas.ocupado: return
	if modo == "rapido":
		_registrar("Correndo não dá para ouvir: mude para Normal ou Devagar."); return
	_ouvindo = true
	var q := agente()
	var ouvintes: Array = vivos().filter(func(h): return Vector2(h.celula - q.celula).length() <= 2.5)
	for h in vivos(): h.parar()
	for h in ouvintes: h.tocar_anim("ajoelhar")
	await get_tree().create_timer(2.2).timeout
	_gastar_tempo(1.0 / 60.0)
	var alc: Dictionary = grade.alcance(q.celula, Portas.LIMITE_OUVIR_M, {}, false)
	var perto: Array = monstros_vivos().filter(func(m): return alc.has(m.celula))
	var nomes := ", ".join(ouvintes.map(func(h): return h.nome))
	var ouviu: Array = portas.ouvir(ouvintes, perto)
	if ouviu.is_empty():
		_registrar("%s para%s e escuta%s: nenhum som além da tocha." % [nomes, "m" if ouvintes.size() > 1 else "", "m" if ouvintes.size() > 1 else ""])
	else:
		var m: Node3D = ouviu[0]
		var d: Vector2i = m.celula - q.celula
		var rumo: String = ("norte" if d.y < 0 else "sul") if absi(d.y) >= absi(d.x) else ("oeste" if d.x < 0 else "leste")
		var dist := float(alc[m.celula][0])
		_registrar("%s escuta%s [color=#ff9a6a]%s[/color], %s, para o %s." % [nomes, "m" if ouvintes.size() > 1 else "", portas._descrever(ouviu), "bem perto" if dist <= 9.0 else "mais adiante", rumo])
		bonus_silencio_ate = turno + 3
		_diario("evento", "Ouviram %s para o %s." % [portas._descrever(ouviu), rumo])
	for h in ouvintes:
		if h.vivo() and not h.andando(): h.tocar("parado", 0.4)
	_ouvindo = false
	_checar_avistamento()

## Alguém caiu fora do combate (armadilha): sai da fila; se era quem liderava, o próximo pega a tocha.
func _heroi_caiu_fora(h: Node3D) -> void:
	_diario("evento", "%s caiu." % h.nome)
	if vivos().is_empty():
		fim = true
		_registrar("[color=#ff7a5a][b]O grupo caiu.[/b][/color]")
		hud_centro.text = "O grupo caiu na masmorra.\nR para recomeçar"
		return
	grupo = vivos()
	if heroi != grupo[0]:
		heroi = grupo[0]; luz.alvo = heroi
		_registrar("%s passa a liderar o grupo e pega a tocha." % heroi.nome)
	hud_ui.refazer()

func _passar_turno() -> void:
	turno += 1
	tocha_turnos -= 1
	var txt := "Passa o turno %d (%s de exploração)." % [turno, _hora()]
	if tocha_turnos == 1: txt += " A tocha está no fim."
	if tocha_turnos <= 0:
		var quem := _gastar_tocha()
		if quem != "":
			tocha_turnos = TURNOS_POR_TOCHA
			txt += " A tocha apaga e %s acende outra (restam %d)." % [quem, _tochas_reserva()]
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
func _brotar_goblin(perto := false) -> void:
	# Casa livre ao acaso na mesma sala de quem lidera (nunca onde já há alguém).
	var ocup := _ocupadas_por()
	var sala: String = grade.area_de(heroi.celula)
	var alc: Dictionary = grade.alcance(heroi.celula, 30.0, {}, true, visao.exploradas)
	var lugares: Array = alc.keys().filter(func(c): return not ocup.has(c) and grade.area_de(c) == sala)
	if lugares.is_empty():
		lugares = alc.keys().filter(func(c): return not ocup.has(c) and float(alc[c][0]) <= 9.0)
	if lugares.is_empty():
		_registrar("Não há lugar livre na sala para brotar um goblin.")
		return
	_goblins_brotados += 1
	var lugar: Vector2i = lugares[randi() % lugares.size()]
	if perto:   # testes: a casa livre mais perto de quem lidera
		lugares.sort_custom(func(a, b): return float(alc[a][0]) < float(alc[b][0]))
		lugar = lugares[0]
	var m := _criar_monstro("goblin", "Goblin %d" % _goblins_brotados, lugar)
	m.visible = true
	monstros.append(m)
	m.scale = Vector3(0.01, 0.01, 0.01)
	create_tween().tween_property(m, "scale", Vector3.ONE, 0.3)
	_registrar("[i](teste)[/i] %s brota na sala." % m.nome)
	if combate.ativo:
		combate.adicionar(m)
		return
	for e in errantes.duplicate():
		errantes.erase(e); monstros.erase(e); e.queue_free()
	porta_alvo = {}
	await _grupo_em_guarda()
	luz.set_grade(true)
	_atualizar_visao()
	_anotar_combate([m])
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
	if avisar: _registrar("Movimento: [b]%s[/b] (%s)." % [m.nome, m.dica])
	# Correndo, os errantes que ainda não tinham notado o grupo passam a ouvir.
	if modo == "rapido":
		for e in errantes: e.set_meta("ciente", true)

## Cada um do grupo rola; basta um falhar para o grupo ser ouvido.
func _rolar_furtividade() -> bool:
	var partes: Array[String] = []
	var ok := true
	var bonus := 1.0 / 6.0 if turno <= bonus_silencio_ate else 0.0   # ouviram os monstros antes: +1 em 6
	for p in fichas:
		var chance := minf(Regras.furtividade(p, MOV.furtividade) + bonus, 0.95)
		var r := randf()
		var passou := r < chance
		ok = ok and passou
		partes.append("%s %d%%: %s" % [str(p.nome).get_slice(" ", 0), roundi(chance * 100), "passou" if passou else "falhou"])
	print("(furtividade do grupo: %s → %s)" % [", ".join(partes), "ninguém ouviu" if ok else "ouvidos"])   # rolagem escondida
	return ok

func _hora() -> String:
	var minutos := turno * 10
	return "%d min" % minutos if minutos < 60 else "%dh%02d" % [minutos / 60, minutos % 60]

# ---------- visão ----------

func _atualizar_visao() -> void:
	var olhos: Array = []
	for h in vivos(): olhos.append([h.celula, float(h.infravisao_m)])
	visao.atualizar_grupo(olhos, heroi.celula, tocha_turnos > 0)
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
	# Monstros que o grupo ouviu (até 3 turnos atrás): o grupo não é surpreendido por eles e, se eles
	# não ouviram o grupo, eles é que são surpreendidos.
	var ouvidos := lista.filter(func(x): return turno - int(x.get_meta("ouvido", -99)) <= 3)
	# Surpresa (normal 1–2 em d6). Devagar e sem ter sido ouvido: +1 para surpreender.
	# Correndo: impossível surpreender os monstros, e +1 na chance de ser surpreendido.
	var sg := (not grupo_ve) or Dados.d(6) <= 2 + int(mm.ser_surpreendido)
	var sm := false
	if mm.surpreender != null:
		sm = (not monstros_veem) or Dados.d(6) <= 2 + (int(mm.surpreender) if furtivos else 0)
	if not ouvidos.is_empty():
		sg = false
		if ouvidos.any(func(x): return not bool(x.get_meta("ciente", true))):
			sm = true; _registrar("Vocês os ouviram antes e eles não ouviram vocês: [color=#9ad0ff]os monstros são pegos de surpresa[/color].")
		else: _registrar("Vocês os ouviram chegando: o grupo não é pego de surpresa.")
	if grupo_ve and not monstros_veem: _registrar("%s avista os monstros antes de ser vista." % heroi.nome)
	elif monstros_veem and not grupo_ve: _registrar("[color=#ff9a6a]Algo a viu primeiro, do escuro.[/color]")
	_registrar("Surpresa: grupo %s · monstros %s" % ["surpreendido" if sg else "atento", "surpreendidos" if sm else "atentos"])
	luz.set_grade(true)
	_atualizar_visao()
	_anotar_combate(lista)
	combate.iniciar(vivos(), lista, sg, sm)

## Todos param na próxima célula, sacam as armas e mostram o nome.
func _grupo_em_guarda() -> void:
	for h in vivos():
		h.parar()
	for h in vivos():
		if h.andando(): await h.parou
	for h in vivos():
		h.velocidade = Ator.VEL_BASE; h.papel_andar = "andar"
		h.empunhar(true)   # PV dos heróis só nas cartas, não sobre a cabeça

func _fim_do_combate(resultado: String, xp: int, rodadas: int) -> void:
	luz.set_grade(grade_forte)
	if resultado == "vitoria":
		xp_total += xp
		var vivos_agora := vivos()
		for h in vivos_agora: h.ficha.xp += xp / maxi(vivos_agora.size(), 1)
		_diario("evento", "Vitória em %d rodada(s); %d XP para o grupo." % [rodadas, xp])
		for h in grupo:
			if not h.vivo(): _diario("evento", "%s caiu em combate." % h.nome)
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
	$HUD/Legenda.visible = false
	hud_ui = Hud.new(); $HUD.add_child(hud_ui)
	hud_ui.definir_grupo(grupo)
	hud_ui.modo_pedido.connect(func(k): _mudar_modo(k))
	hud_ui.acao_pedida.connect(_acao_hud)
	hud_ui.acao_escolhida.connect(_acao_porta)
	hud_ui.carta_escolhida.connect(_selecionar)
	hud_ui.trocar_arma.connect(_trocar_arma)
	hud_ui.usar_item.connect(_usar_item)
	hud_ui.ficha_pedida.connect(_abrir_ficha)
	var enorme := LabelSettings.new(); enorme.font = Estilo.fonte("titulo"); enorme.font_size = 40; enorme.font_color = Estilo.OURO_CLARO
	enorme.outline_size = 10; enorme.outline_color = Color(0.08, 0.05, 0.03)
	hud_centro = Label.new(); hud_centro.label_settings = enorme
	hud_centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_centro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hud_centro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(hud_centro)
	livro = Livro.new(); livro.visible = false; $HUD.add_child(livro)
	livro.diario = diario
	livro.adjacentes = func(a, b): return a.celula == b.celula or grade.adjacentes(a.celula, b.celula) or Vector2(a.celula - b.celula).length() < 1.5
	livro.mudou.connect(_ficha_mudou)
	livro.usar.connect(_usar_item)

func _ficha_mudou(h: Node3D) -> void:
	_aplicar_ficha(h); _recalcular_grupo(); hud_ui.refazer()

func _anotar_combate(lista: Array) -> void:
	var tipos := {}
	for m in lista: tipos[str(m.nome).get_slice(" ", 0)] = true
	for t in tipos: _diario("criatura", "%s — %s" % [t, grade.nomes.get(grade.area_de(heroi.celula), "")])
	_diario("evento", "Combate contra %s." % ", ".join(tipos.keys()))

func _anotar_area() -> void:
	var area: String = grade.nomes.get(grade.area_de(heroi.celula), "")
	if area != "" and area != _area_antes:
		_area_antes = area; _diario("lugar", area)

func _diario(tipo: String, texto: String) -> void:
	if tipo != "evento" and diario.any(func(x): return x.tipo == tipo and x.texto == texto): return
	diario.append({"turno": turno, "tipo": tipo, "texto": texto})

func _registrar(txt: String) -> void:
	if hud_ui: hud_ui.registrar(txt)
	print(txt)

func _acao_hud(acao: String) -> void:
	match acao:
		"atacar": combate.atacar_mais_proximo()
		"encerrar": combate.encerrar_turno()
		"brotar": if not fim: _brotar_goblin()
		"arsenal": if not fim: _arsenal_teste()
		"ouvir": if not fim and not combate.ativo: _ouvir_aqui()
		"procurar": if not fim and not combate.ativo and not portas.ocupado: procurar.procurar_sala()
		"ficha": _abrir_ficha(combate.vez if combate.ativo and combate.vez and combate.vez.lado == "grupo" else heroi)

## Teste (tecla T): quem lidera passa para a próxima arma do catálogo, para ver todos os estilos de luta.
## Arma de duas mãos guarda o escudo na mochila; a de uma mão o devolve. Dá munição se faltar.
var _arsenal_i := -1
func _arsenal_teste() -> void:
	var lista: Array = Ficha.catalogo().keys().filter(func(k): return Ficha.catalogo()[k].has("estilo"))
	_arsenal_i = (_arsenal_i + 1) % lista.size()
	var id: String = lista[_arsenal_i]
	var inf: Dictionary = Ficha.catalogo()[id]
	var f = heroi.ficha
	if f.mao_d != null and str(f.mao_d.id) != id: f.tirar(f.mao_d)
	f.mao_d = {"id": id, "qtd": 1}
	var escudo = f.mao_e
	if int(inf.get("maos", 1)) >= 2:
		if escudo != null: f.mao_e = null; f.mochila.append(escudo)
	elif f.mao_e == null:
		for x in f.mochila:
			if Ficha.info(x).get("tipo") == "escudo" and f.escudo_permitido(x, f.mao_d): f.mochila.erase(x); f.mao_e = x; break
	if f.mao_e != null and not f.escudo_permitido(f.mao_e, f.mao_d):
		f.mochila.append(f.mao_e); f.mao_e = null
	if inf.has("municao") and f.contar(str(inf.municao)) < 10: f.mochila.append({"id": str(inf.municao), "qtd": 20})
	_aplicar_ficha(heroi); hud_ui.refazer()
	_registrar("[i](teste T)[/i] %s empunha [b]%s[/b] · estilo %s · %d de %d." % [heroi.nome, inf.nome, str(inf.estilo).replace("_", " "), _arsenal_i + 1, lista.size()])

## Trocar de arma no combate: uma vez por vez, sem gastar o ataque.
func _trocar_arma(h: Node3D, item) -> void:
	if combate.ativo and (combate.vez != h or combate.ocupado or bool(h.get_meta("trocou", false))): return
	h.ficha.empunhar(item)
	_aplicar_ficha(h)
	h.set_meta("trocou", true)
	_registrar("%s empunha: %s." % [h.nome, Ficha.info(item).nome])
	if combate.ativo: combate._mostrar_alcance()

func _usar_item(h: Node3D, item) -> void:
	var inf := Ficha.info(item)
	match str(item.id):
		"tocha":
			if h.ficha.gastar("tocha"):
				tocha_turnos = TURNOS_POR_TOCHA; luz.luz_grupo.visible = true
				_registrar("%s acende uma tocha nova (6 turnos de luz)." % h.nome)
				_atualizar_visao()
		"rações":
			if h.ficha.gastar("rações"): _registrar("%s come uma ração (restam %d)." % [h.nome, h.ficha.contar("rações")])
		_:
			_registrar("[i]%s: o uso deste item entra com as habilidades.[/i]" % inf.nome)
	_ficha_mudou(h)

func _abrir_ficha(h: Node3D) -> void:
	if livro.visible: livro.fechar(); return
	livro.grupo = grupo; livro.em_combate = combate.ativo
	livro.mostrar(h)

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

func _atualizar_hud() -> void:
	if hud_ui == null: return
	var luz_txt := ("tocha %d de %d turnos" % [tocha_turnos, TURNOS_POR_TOCHA]) if tocha_turnos > 0 else "sem luz"
	if not combate.ativo:
		var area: String = grade.nomes.get(grade.area_de(heroi.celula), "")
		var prox := turno + (2 - turno % 2)
		hud_ui.atualizar_exploracao(MOV.modos, modo, {"area": area, "turno": turno, "hora": _hora(), "andado": metros_no_turno,
			"taxa": _taxa_turno(), "errantes": prox, "xp": xp_total, "tocha": tocha_turnos, "tocha_max": TURNOS_POR_TOCHA,
			"reserva": _tochas_reserva()}, heroi, luz_txt)
		return
	var v: Node = combate.vez
	var info := ""
	if v and is_instance_valid(v):
		if v.lado == "grupo":
			var previa := ("  →  este caminho: %.1f m" % combate.previa_m).replace(".", ",") if combate.previa_m >= 0 else ""
			info = ("Vez de %s · movimento %.1f de %.0f m" % [v.nome, combate.restante, v.mov_combate_m]).replace(".", ",") + previa
		else:
			info = "Vez %s" % (("do " + v.nome) if v.visible else "de algo no escuro")
	var ordem: Array = []
	for lado in combate.ordem_lados:
		var lista: Array = combate.grupo if lado == "grupo" else combate.monstros
		for a in lista:
			if not is_instance_valid(a): continue
			var visto: bool = a.lado == "grupo" or a.visible
			ordem.append({"nome": a.nome if visto else "?", "lado": a.lado, "vivo": a.vivo(), "vez": a == v, "no": a,
				"retrato": (str(a.ficha.id) if a.get("ficha") else str(a.nome).get_slice(" ", 0).to_lower()) if visto else ""})
	# Dica do inimigo sob o mouse: o que precisa no d20, a chance e o dano.
	var alvo := {}
	var ap: Node = combate.alvo_pairado
	if v and is_instance_valid(v) and v.lado == "grupo" and ap and is_instance_valid(ap) and ap.vivo() and ap.visible:
		var pr: Dictionary = combate.previsao(v, ap)
		var fr: float = float(maxi(ap.pv, 0)) / ap.pv_max
		var topo: Vector3 = ap.global_position + Vector3(0, ap.altura_texto() * 0.6, 0)
		alvo = {"nome": ap.nome, "estado": "ileso" if fr >= 1.0 else ("ferido" if fr > 0.5 else "muito ferido"),
			"n": pr.n, "chance": pr.chance, "dano": pr.dano, "tela": camera.unproject_position(topo)}
	hud_ui.atualizar_combate(combate.rodada, [combate.ini_grupo, combate.ini_monstros], ordem, v, info, heroi, luz_txt, alvo)

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
			_brotar_goblin(true)
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
		_brotar_goblin(true)
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
		_brotar_goblin(true)
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
	elif teste == "olhar":
		# Ângulo do olhar (cabeça) em relação ao oponente, por animação e instante, com o giro atual.
		_brotar_goblin(true)
		await get_tree().create_timer(1.5).timeout
		var g: Node3D = monstros[0]
		var casos := [[0, "parado-espada-escudo", 0.5], [0, "parado-espada-escudo", 0.5, 0.0], [2, "sacar-flecha", 1.0], [2, "atirar-flecha", 2.6, 0.0], [2, "atirar-flecha", 3.0, 0.0]]
		for x in [["faca-guarda", 1.0], ["faca-estocada", 0.73], ["corte-fora", 0.87], ["besta-guarda", 1.0], ["besta-disparo", 0.15], ["machado-guarda", 1.0], ["haste-bloquear", 0.3], ["arco-bloquear", 0.3], ["arco-guarda", 1.0]]:
			casos.append([0, x[0], x[1], 0.0])
		for caso in casos:
			var eu: Node3D = grupo[caso[0]]
			var sk: Skeleton3D = eu.modelo.find_children("*", "Skeleton3D", true, false)[0]
			var ic := sk.find_bone("mixamorig_Head")
			var R := func(n): return sk.get_bone_global_rest(sk.find_bone(n)).origin
			var fr0: Vector3 = Vector3.UP.cross(R.call("mixamorig_RightShoulder") - R.call("mixamorig_LeftShoulder"))
			if fr0.dot(R.call("mixamorig_LeftToeBase") - R.call("mixamorig_LeftFoot")) < 0: fr0 = -fr0
			var olhar_local: Vector3 = sk.get_bone_global_rest(ic).basis.inverse() * fr0.normalized()
			eu.olhar_para(g.global_position)
			var gi: float = float(caso[3]) if caso.size() > 3 else float(eu.giro_anim.get(caso[1], 0.0))
			eu.player.play(caso[1], 0.0); eu.modelo.rotation.y = -deg_to_rad(gi)
			eu.player.seek(caso[2], true)
			await get_tree().process_frame
			var alvo: Vector3 = g.global_position - eu.global_position; alvo.y = 0
			var ol: Vector3 = sk.global_basis * (sk.get_bone_global_pose(ic).basis * olhar_local); ol.y = 0
			var hm: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin - sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin
			hm.y = 0
			var corda: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin - sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
			corda.y = 0
			print("OLHAR %s %-20s t=%.2f giro %4.0f  olhar %4.0f°  mão %4.0f°  mãoD→mãoE %4.0f°" % [eu.nome, caso[1], caso[2], gi, rad_to_deg(alvo.signed_angle_to(ol, Vector3.UP)), rad_to_deg(alvo.signed_angle_to(hm, Vector3.UP)), rad_to_deg(alvo.signed_angle_to(corda, Vector3.UP))])
	elif teste == "livro":
		var aba := "ficha"
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--aba="): aba = x.get_slice("=", 1)
		var quem := 0
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--heroi="): quem = int(x.get_slice("=", 1))
		livro.grupo = grupo; livro.mostrar(grupo[quem], aba)
		await get_tree().create_timer(0.5).timeout
	elif teste == "tela":
		# Combate de verdade (goblin brotado) para ver a tela de combate na vez de um personagem.
		_brotar_goblin(true); _brotar_goblin(true)
		await get_tree().create_timer(1.5).timeout
		for _i in 40:
			if combate.vez and combate.vez.lado == "grupo": break
			await get_tree().create_timer(0.25).timeout
		await get_tree().create_timer(0.5).timeout
	elif teste == "caco":
		# O Caco ataca um goblin ao lado: corte para dentro, corte para fora e estocada no crítico.
		var caco: Node3D = grupo[1]
		var livre: Array = []
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var c: Vector2i = caco.celula + Vector2i(dx, dy)
				if c != caco.celula and grade.chao(c) and grade.adjacentes(caco.celula, c) and grupo.all(func(h): return h.celula != c): livre.append(c)
		var g := _criar_monstro("goblin", "Goblin 1", livre[0])
		g.visible = true; monstros.append(g); g.pv = 99
		await _grupo_em_guarda()
		combate.grupo = vivos(); combate.monstros = [g]
		g.olhar_para(caco.global_position)
		var dir: Vector3 = (g.position - caco.position); dir.y = 0; dir = dir.normalized()
		camera.alvo = (caco.position + g.position) / 2.0; camera.distancia = 4.5; camera.inclinacao = 22.0
		camera.guinada = rad_to_deg(atan2(-dir.z, dir.x)); mestre = true; _atualizar_visao()
		await get_tree().create_timer(1.0).timeout
		var k := 0
		for r in [15, 15, 20]:
			Dados.forcados.append(r)
			var golpe: String = "golpe_critico" if r == 20 else ("golpe" if caco._alterna else "golpe2")
			var imp: float = caco.tempo_impacto(golpe)
			combate._atacar(caco, g)
			var t0 := Time.get_ticks_msec()
			var imgs: Array[Image] = []
			for ms in [imp * 1000 * 0.4, imp * 1000 * 0.75, imp * 1000, imp * 1000 + 150]:
				while Time.get_ticks_msec() - t0 < ms: await get_tree().process_frame
				imgs.append(get_viewport().get_texture().get_image())
			for im in imgs:
				im.save_png(captura.replace(".png", "-%02d.png" % k)); k += 1
			await get_tree().create_timer(2.0).timeout
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
			for ms in [500, 1200, 1700, 1900, 2100, 2500]:
				while Time.get_ticks_msec() - t0 < ms: await get_tree().process_frame
				imgs.append(get_viewport().get_texture().get_image())
			for im in imgs:
				im.save_png(captura.replace(".png", "-%02d.png" % k)); k += 1
			await get_tree().create_timer(1.5).timeout
	elif teste == "estilo":
		# Close de um herói usando o estilo da arma: --heroi=N --arma=<item> (opcional). Golpe (ou disparo) num goblin.
		var quem := 0; var arma_id := ""
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--heroi="): quem = int(x.get_slice("=", 1))
			if x.begins_with("--arma="): arma_id = x.get_slice("=", 1)
		var eu: Node3D = grupo[quem]
		if arma_id != "":
			eu.ficha.empunhar({"id": arma_id, "qtd": 1}); _aplicar_ficha(eu)
		var alc: Dictionary = grade.alcance(eu.celula, 12.0, {}, true)
		var dist: bool = not eu.dist_faixas.is_empty()
		var lugar: Array = alc.keys().filter(func(c): return (float(alc[c][0]) >= 6.0 if dist else grade.adjacentes(c, eu.celula)) and grade.linha(eu.celula, c) and not grupo.any(func(h): return h.celula == c))
		lugar.sort_custom(func(a, b): return float(alc[a][0]) < float(alc[b][0]))
		var g := _criar_monstro("goblin", "Goblin 1", lugar[0])
		g.visible = true; monstros.append(g)
		await _grupo_em_guarda()
		combate.grupo = vivos(); combate.monstros = [g]
		g.olhar_para(eu.global_position); eu.olhar_para(g.global_position)
		var dir: Vector3 = (g.position - eu.position); dir.y = 0; dir = dir.normalized()
		camera.alvo = eu.position + Vector3(0, 0.9, 0); camera.distancia = 5.0; camera.inclinacao = 18.0
		camera.guinada = rad_to_deg(atan2(dir.z, -dir.x)) + 35.0
		mestre = true; _atualizar_visao()
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png(captura.replace(".png", "-guarda.png"))
		var papel: String = "atirar" if dist else eu.escolher_golpe(false)
		var t_imp: float = eu.tempo_tiro() if dist else eu.tempo_impacto(papel)
		Dados.forcados.append(19)
		combate._atacar(eu, g, dist)
		var t0 := Time.get_ticks_msec(); var k := 0
		for f in [0.3, 0.7, 1.0, 1.15]:
			while Time.get_ticks_msec() - t0 < int(t_imp * f * 1000.0): await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(captura.replace(".png", "-%d.png" % k)); k += 1
		await get_tree().create_timer(1.5).timeout
	elif teste == "besta":
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--heroi="): heroi = grupo[int(x.get_slice("=", 1))]
		_brotar_goblin(true)
		await get_tree().create_timer(1.5).timeout
		for k in 18:
			_arsenal_teste()
			if str(heroi.ficha.mao_d.id) == "besta": break
		for i in 6:
			await get_tree().create_timer(0.5).timeout
			print("BESTA anim=", heroi.player.current_animation, " em_combate=", heroi.em_combate, " estilo=", heroi.estilo, " parado_combate=", heroi.anim.get("parado_combate"))
	elif teste == "ocupacao":
		# 12 goblins pela tecla B: nenhum pode cair onde já há alguém; e o cursor sobre um deles.
		for k in 12: _brotar_goblin(); await get_tree().process_frame
		var casas := {}; var repetidas := 0
		for x in grupo + monstros:
			if casas.has(x.celula): repetidas += 1
			casas[x.celula] = true
		print("OCUPACAO seres=", (grupo + monstros).size(), " casas repetidas=", repetidas, " sala=", grade.area_de(heroi.celula),
			" goblins fora da sala=", monstros.filter(func(m): return grade.area_de(m.celula) != grade.area_de(heroi.celula)).size())
		await get_tree().create_timer(2.0).timeout
		for k in 20:
			if combate.vez == heroi: break
			await get_tree().create_timer(0.5).timeout
		var alvo: Node3D = null
		for m in monstros:
			if m.vivo() and combate._ve(m): alvo = m; break
		if alvo:
			combate.pairar(alvo.celula, alvo)
			print("CURSOR sobre ", alvo.nome, ": ", combate._cursor)
	elif teste == "portas":
		# Ações de porta: Caco (selecionado) na P01 trancada com agulha; Tessa força a P03 e prega.
		var caco: Node3D = grupo.filter(func(h): return h.nome == "Caco")[0]
		var p1: Dictionary = portas.por_id["P01"]; var p3: Dictionary = portas.por_id["P03"]
		_selecionar(caco)
		for a in ["abrir", "ouvir", "armadilha", "desarmar", "desarmar", "fechadura", "abrir"]:
			var ops: Array = portas.opcoes(p1, agente()).map(func(o): return "%s%s" % [o.id, "" if o.ativo else "(x)"])
			print("PORTA P01 opções=", ops, " → ", a)
			await portas.agir(p1, agente(), a)
			print("   estado=", portas.de(p1).estado, " aberta=", grade.porta_aberta.has("P01"), " barrada=", grade.porta_barrada.has("P01"), " Caco PV=", caco.pv, " turno=", turno, " celula=", caco.celula)
		_selecionar(caco)   # volta para quem lidera
		await portas.agir(p3, agente(), "abrir")
		for k in 8:
			if grade.porta_aberta.has("P03"): break
			await portas.agir(p3, agente(), "forcar")
		print("PORTA P03 aberta=", grade.porta_aberta.has("P03"), " turno=", turno)
		var outra: Dictionary = portas.por_id["P02"]
		await portas.agir(outra, agente(), "pregar")
		print("PORTA P02 estado=", portas.de(outra).estado, " barrada=", grade.porta_barrada.has("P02"),
			" monstro passa=", grade.passa_reto(grade.lados_da_porta(outra)[0][0], grade.lados_da_porta(outra)[0][1], true), " turno=", turno)
	elif teste == "balao":
		# Balão da porta P01 com o Caco selecionado (para a captura de tela).
		_selecionar(grupo.filter(func(h): return h.nome == "Caco")[0])
		var pt: Dictionary = portas.por_id["P01"]; portas.de(pt).sabe = "trancada"
		var lado: Vector2i = grade.lados_da_porta(pt)[0][0]
		camera.alvo = grade.centro(lado); await get_tree().create_timer(0.6).timeout
		_menu_da_porta(pt, get_viewport().get_camera_3d().unproject_position(grade.centro(lado)))
		await get_tree().create_timer(0.5).timeout
	elif teste == "vao":
		# Tessa no vão da P03 (aberta), goblin do outro lado, Caco ao lado dela: Caco golpeia na diagonal
		# e atravessa a Tessa; e cada um vê com os próprios olhos.
		var tessa: Node3D = grupo[0]; var caco: Node3D = grupo[1]; var lianne: Node3D = grupo[2]
		var p3: Dictionary = portas.por_id["P03"]; portas.de(p3).estado = "fechada"
		_abrir_porta(p3, Vector2i(11, 5), "teste")
		tessa.colocar(Vector2i(11, 5)); caco.colocar(Vector2i(11, 4)); lianne.colocar(Vector2i(9, 3))
		print("VAO diagonal Caco(11,4)->(12,5) adjacentes=", grade.adjacentes(Vector2i(11, 4), Vector2i(12, 5)),
			" · andar cortando a quina=", grade.passa(Vector2i(11, 4), Vector2i(12, 5)))
		combate.grupo = grupo; combate.monstros = []; combate.vez = caco; combate.restante = 18.0
		combate._mostrar_alcance()
		print("VAO Caco atravessa a Tessa: chega em (13,5)=", combate._alc.has(Vector2i(13, 5)), " · pode parar na casa dela=", combate._alc.has(Vector2i(11, 5)))
		combate.vez = null; combate.marca_alcance.limpar(); combate.marca_vez.limpar()
		# visão: com só a Tessa na sala, a casa (14,5) do 23 conta? E com o Caco no vão?
		tessa.colocar(Vector2i(7, 5)); caco.colocar(Vector2i(11, 5)); _atualizar_visao()
		print("VAO Caco no vão vê (14,5)=", visao.visiveis.has(Vector2i(14, 5)), " · (16,5)=", visao.visiveis.has(Vector2i(16, 5)), " lianne infravisão=", lianne.infravisao_m)
	elif teste == "ouvir":
		# Goblins errantes fora da vista; ouvir no corredor e na porta, depois o combate.
		var na23: Array = grade.area.keys().filter(func(c): return grade.area_de(c) == "23" and grade.chao(c))
		na23.sort_custom(func(a, b): return a.x > b.x)
		for k in 2:
			var g := _criar_monstro("goblin", "Goblin %d" % (k + 1), na23[k * 3])
			g.set_meta("ciente", false); g.set_meta("turno", turno); monstros.append(g); errantes.append(g)
		var p3x: Dictionary = portas.por_id["P03"]; portas.de(p3x).estado = "fechada"
		print("OUVIR errantes=", errantes.size(), " em ", errantes.map(func(x): return grade.area_de(x.celula)))
		for k in 6:
			var tessa: Node3D = grupo[0]
			await _ouvir_aqui()
			if errantes.any(func(x): return x.has_meta("ouvido")): break
		print("OUVIR marcados=", errantes.filter(func(x): return x.has_meta("ouvido")).size(), " bônus até turno ", bonus_silencio_ate, " turno=", turno)
		var p3: Dictionary = portas.por_id["P03"]
		for k in 8:
			await portas.agir(p3, agente(), "ouvir_todos")
			if errantes.any(func(x): return x.has_meta("ouvido")): break
			_gastar_tempo(1.0)
		print("OUVIR opções depois=", portas.opcoes(p3, agente()).map(func(o): return "%s%s" % [o.id, "" if o.ativo else "(x)"]))
		for g in errantes:
			if g.has_meta("ouvido"): g.set_meta("ciente", false)
		if errantes.any(func(x): return x.has_meta("ouvido")): await _comecar_combate(true, false)
	elif teste == "procurar":
		# Grupo no corredor 23 (P03 aberta): procurar acha a P02 secreta e o fosso; elfo de passagem; cauteloso.
		var p3: Dictionary = portas.por_id["P03"]; portas.de(p3).estado = "fechada"; _abrir_porta(p3, Vector2i(11, 5), "teste")
		var p2: Dictionary = portas.por_id["P02"]
		print("PROCURAR P02 secreta=", procurar.secreta(p2), " clicável=", not _porta_perto(grade.centro(Vector2i(12, 4)) + Vector3(0, 0, -0.6)).is_empty(), " monstro passa=", grade.passa_reto(Vector2i(12, 3), Vector2i(12, 4), true))
		grupo[0].colocar(Vector2i(14, 5)); grupo[1].colocar(Vector2i(13, 5)); grupo[2].colocar(Vector2i(15, 6)); _atualizar_visao()
		print("PROCURAR área=", grade.area_de(grupo[0].celula), " trechos=", procurar.trechos("23"), " turnos=", procurar.turnos_para("23"))
		for k in 12:
			await procurar.procurar_sala()
			if not procurar.secreta(p2) and procurar.armadilhas[Vector2i(17, 5)].visto: break
			procurar.procurou.clear()
		print("PROCURAR achou P02=", not procurar.secreta(p2), " fosso visto=", procurar.armadilhas[Vector2i(17, 5)].visto, " turno=", turno,
			" P02 clicável=", not _porta_perto(grade.centro(Vector2i(12, 4)) + Vector3(0, 0, -0.6)).is_empty())
		var cam: Array[Vector2i] = _caminho_lider(grupo[0].celula, Vector2i(19, 5))
		print("PROCURAR caminho desvia do fosso=", not cam.has(Vector2i(17, 5)), " ", cam)
		var f2: Dictionary = procurar.armadilhas[Vector2i(10, 1)]
		var caiu := false
		for k in 20:
			procurar.pisou(grupo[0], Vector2i(10, 1))
			if f2.visto: caiu = true; break
		print("PROCURAR pisou no fosso escondido: disparou=", caiu, " Tessa PV=", grupo[0].pv)
	elif teste == "secreta":
		# Captura da P02 vista do corredor 23: escondida (--revelar: depois de achada).
		var p3: Dictionary = portas.por_id["P03"]; portas.de(p3).estado = "fechada"; _abrir_porta(p3, Vector2i(11, 5), "teste")
		for i in 3: grupo[i].colocar(Vector2i(13 + i, 6))
		if OS.get_cmdline_user_args().has("--revelar"): procurar.revelar(portas.por_id["P02"], "teste")
		_atualizar_visao()
		camera.alvo = grade.centro(Vector2i(12, 4)); camera.distancia = 8.0; camera.guinada = -20.0; camera.inclinacao = 40.0
		await get_tree().create_timer(1.0).timeout
	elif teste == "corrida":
		# No combate os monstros correm (velocidade do modo rápido, animação de corrida); fugindo também.
		for k in 3: _brotar_goblin(); await get_tree().process_frame
		var visto := {}
		for k in 120:
			for m in monstros:
				if is_instance_valid(m) and m.andando() and not visto.has(m.nome):
					visto[m.nome] = true
					print("CORRIDA ", m.nome, " anim=", m.player.current_animation, " vel=", m.vel_atual(), " perto=", combate._perto_de_inimigo(m))
			if visto.size() >= 2: break
			await get_tree().create_timer(0.1).timeout
		var heroi_longe: Node3D = grupo[2]; heroi_longe.no_combate = true; heroi_longe.perto_de_inimigo = func(_a): return false
		print("CORRIDA herói longe: vel=", heroi_longe.vel_atual(), " papel=", heroi_longe._papel_desloc())
		heroi_longe.perto_de_inimigo = func(_a): return true
		print("CORRIDA herói perto: vel=", heroi_longe.vel_atual(), " papel=", heroi_longe._papel_desloc())
		var g: Node3D = monstros.filter(func(m): return is_instance_valid(m) and m.vivo())[0]
		combate._fugir(g); await get_tree().create_timer(0.3).timeout
		print("FUGA ", g.nome, " anim=", g.player.current_animation, " vel=", g.vel_atual(), " andando=", g.andando())
	elif teste == "arsenal":
		# A Tessa passa por todas as armas (tecla T) e ataca um goblin com cada uma; quadro no impacto.
		_brotar_goblin(true)
		await get_tree().create_timer(1.5).timeout
		var g: Node3D = monstros[0]
		g.pv = 999; g.pv_max = 999
		var cam := Camera3D.new(); add_child(cam); cam.fov = 45
		var n: int = Ficha.catalogo().keys().filter(func(k): return Ficha.catalogo()[k].has("estilo")).size()
		for k in n:
			_arsenal_teste()
			await get_tree().create_timer(0.8).timeout
			var dist: bool = not heroi.dist_faixas.is_empty()
			var lado: Vector3 = (g.global_position - heroi.global_position); lado.y = 0; lado = lado.normalized()
			cam.global_position = heroi.global_position + lado.cross(Vector3.UP) * 3.2 + lado * 0.6 + Vector3(0, 1.6, 0)
			cam.look_at(heroi.global_position + lado * 0.6 + Vector3(0, 0.9, 0)); cam.current = true
			get_viewport().get_texture().get_image().save_png(captura.replace(".png", "-%02d-a.png" % k))
			var papel: String = "atirar" if dist else heroi.escolher_golpe(false)
			var t_imp: float = heroi.tempo_tiro() if dist else heroi.tempo_impacto(papel)
			Dados.forcados.append(19)
			combate._atacar(heroi, g, dist)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < int(t_imp * 1000.0) - 40: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(captura.replace(".png", "-%02d-b.png" % k))
			await get_tree().create_timer(1.6).timeout
	elif teste == "defesa":
		# Erros forçados, vistos por trás de quem ataca: o defensor deve aparecer de frente. --arma=<item> troca a arma da Tessa.
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--arma="): heroi.ficha.empunhar({"id": x.get_slice("=", 1).replace("_", " "), "qtd": 1}); _aplicar_ficha(heroi)
		_brotar_goblin(true)
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
	if OS.get_cmdline_user_args().has("--sem-hud"):
		$HUD.visible = false
		for _f in 3: await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--depurar-hud"):
		print("HUD ", hud_ui.size, " vis=", hud_ui.visible, " filhos=", hud_ui.get_child_count(), " layer_vis=", $HUD.visible)
		for c in hud_ui.get_children(): print("  ", c.get_class(), " ", c.position, " ", c.size, " vis=", c.visible, " mod=", c.modulate)
	if captura != "":
		get_viewport().get_texture().get_image().save_png(captura)
	get_tree().quit()
