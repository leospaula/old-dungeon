extends Node3D
## Chicote desenhado no jogo (como a funda): cabo de couro trançado na mão direita e uma tira de couro que
## afina até a ponta, simulada como corrente de pontos (Verlet com gravidade, atrito e chão). O movimento da
## mão no golpe faz a tira chicotear; parado, ela cai e se deita no chão.
## Fica num BoneAttachment3D da mão; a simulação roda no espaço do mundo.
##
## Cabo: atravessa o punho fechado na linha dos nós dos dedos (do mínimo para o indicador) e sai do lado do
## polegar; a tira começa na ponta do cabo.

const N := 18                   # pontos da tira (N-1 segmentos)
const GRAVIDADE := Vector3(0, -9.8, 0)
const ATRITO := 0.95            # couro curtido: corre no golpe, mas sem balançar à toa
const ITERACOES := 8
const CABO := 0.34              # m reais
const CABO_ATRAS := 0.08        # quanto do cabo sai pelo lado do dedo mínimo
const RAIO_BASE := 0.014
const RAIO_PONTA := 0.003
const RIGIDEZ_BASE := 0.985     # couro enrijecido: perto do cabo quase não dobra...
const RIGIDEZ_PONTA := 0.86     # ...e a ponta continua viva
const TEX_COR := "res://arte/texturas/couro_cor.png"
const TEX_NORMAL := "res://arte/texturas/couro_normal.png"

var sk: Skeleton3D
var comprimento := 1.5          # tira, no espaço do personagem (já dividido pela escala)
var _mao := -1; var _ind := -1; var _min := -1
var _p: PackedVector3Array
var _ant: PackedVector3Array
var _iniciou := false
var _cabo: MeshInstance3D
var _segs: Array[MeshInstance3D] = []

func _ready() -> void:
	if sk:
		_mao = sk.find_bone("mixamorig_RightHand")
		_ind = sk.find_bone("mixamorig_RightHandIndex1")
		_min = sk.find_bone("mixamorig_RightHandPinky1")
	var trancado := couro_envelhecido(Color(0.62, 0.55, 0.5), Vector3(1.0, 4.0, 1.0))   # cabo: couro mais escuro e gasto
	var couro := couro_envelhecido(Color.WHITE, Vector3(1.0, 1.0, 1.0))
	_cabo = MeshInstance3D.new(); var c := CylinderMesh.new()
	c.top_radius = 0.021; c.bottom_radius = 0.025; c.height = 1.0; c.radial_segments = 10; c.rings = 1
	c.material = trancado; _cabo.mesh = c; _cabo.top_level = true; add_child(_cabo)
	for i in N - 1:
		var m := MeshInstance3D.new(); var cm := CylinderMesh.new()
		var f0 := float(i) / (N - 1); var f1 := float(i + 1) / (N - 1)
		cm.bottom_radius = lerpf(RAIO_BASE, RAIO_PONTA, f0); cm.top_radius = lerpf(RAIO_BASE, RAIO_PONTA, f1)
		cm.height = 1.0; cm.radial_segments = 6; cm.rings = 1; cm.material = couro
		m.mesh = cm; m.top_level = true; m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(m); _segs.append(m)

## Couro envelhecido (tools/gerar_couro.py), o mesmo do chicote e da funda.
static func couro_envelhecido(tom: Color, uv: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_COR); m.albedo_color = tom
	m.normal_enabled = true; m.normal_texture = load(TEX_NORMAL); m.normal_scale = 0.8
	m.roughness = 0.82; m.uv1_scale = uv
	return m

func _osso(i: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(i).origin

## Ponta do cabo (onde a tira começa) e a base dele, no mundo.
func _cabo_pontas() -> Array:
	var esc: float = sk.global_transform.basis.get_scale().x
	if _mao < 0 or _ind < 0 or _min < 0: return [global_position, global_position + Vector3.UP * 0.2]
	var mao := _osso(_mao); var ind := _osso(_ind); var mi := _osso(_min)
	var nos := (ind + mi) * 0.5
	var centro := mao.lerp(nos, 0.8)                    # meio do punho fechado
	var eixo := (ind - mi).normalized()                  # ao longo dos nós dos dedos, saindo pelo polegar
	var fator := esc / maxf(get_meta("escala", 1.0), 0.001)
	return [centro - eixo * CABO_ATRAS * fator, centro + eixo * (CABO - CABO_ATRAS) * fator]

func _physics_process(dt: float) -> void:
	if sk == null: return
	var esc: float = sk.global_transform.basis.get_scale().x
	var l: float = comprimento * esc / (N - 1)
	var pc := _cabo_pontas()
	var ponta: Vector3 = pc[1]
	var chao: float = sk.global_position.y + RAIO_BASE
	if not _iniciou:
		_p.resize(N); _ant.resize(N)
		var dir: Vector3 = ((pc[1] - pc[0]) as Vector3).normalized()
		for i in N:
			_p[i] = ponta + dir * l * i; _p[i].y = maxf(_p[i].y, chao); _ant[i] = _p[i]
		_iniciou = true
	for i in range(1, N):
		var v := (_p[i] - _ant[i]) * ATRITO
		_ant[i] = _p[i]
		_p[i] += v + GRAVIDADE * dt * dt
	_p[0] = ponta; _ant[0] = ponta
	for _k in ITERACOES:
		_p[0] = ponta
		for i in N - 1:
			var d := _p[i + 1] - _p[i]; var dl := d.length()
			if dl < 0.00001: continue
			var corr := d * (1.0 - l / dl)
			if i == 0: _p[i + 1] -= corr
			else: _p[i] += corr * 0.5; _p[i + 1] -= corr * 0.5
		# Couro enrijecido: dois segmentos seguidos não dobram além do limite (mais rígido perto do cabo),
		# e o primeiro sai na direção do cabo.
		var dir_cabo: Vector3 = ((pc[1] - pc[0]) as Vector3).normalized()
		_p[1] = _p[1].lerp(ponta + dir_cabo * l, 0.35)
		for i in N - 2:
			var minimo: float = 2.0 * l * lerpf(RIGIDEZ_BASE, RIGIDEZ_PONTA, float(i) / (N - 3))
			var d2 := _p[i + 2] - _p[i]; var dl2 := d2.length()
			if dl2 < minimo and dl2 > 0.00001:
				var c2 := d2 * (1.0 - minimo / dl2) * 0.5
				if i == 0: _p[i + 2] -= c2 * 2.0
				else: _p[i] += c2; _p[i + 2] -= c2
		for i in range(1, N):
			if _p[i].y < chao:   # deita no chão e arrasta com atrito
				_p[i].y = chao
				_ant[i] = _ant[i].lerp(_p[i], 0.3)
	_desenhar(pc)

func _process(_dt: float) -> void:
	if sk and _iniciou: _desenhar(_cabo_pontas())
	var vis := is_visible_in_tree()
	_cabo.visible = vis
	for s in _segs: s.visible = vis

func _desenhar(pc: Array) -> void:
	_ligar(_cabo, pc[0], pc[1])
	for i in N - 1: _ligar(_segs[i], _p[i], _p[i + 1])

func _ligar(m: MeshInstance3D, de: Vector3, ate: Vector3) -> void:
	var d := ate - de; var l := d.length()
	if l < 0.0005: return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	m.global_transform = Transform3D(Basis(x, y * l, x.cross(y)), (de + ate) * 0.5)
