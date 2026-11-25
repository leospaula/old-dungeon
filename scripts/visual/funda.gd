extends Node3D
## Funda desenhada no jogo: duas cordas presas à mão direita e uma bolsinha de couro na ponta, que
## balança como pêndulo (Verlet com gravidade). O movimento da mão no arremesso faz a bolsinha girar.
## Fica num BoneAttachment3D da mão; a simulação roda no espaço do mundo.

const RAIO_CORDA := 0.004
const GRAVIDADE := Vector3(0, -9.8, 0)
const ATRITO := 0.88          # bem amortecido: corda de couro firme, não elástico

var sk: Skeleton3D
var comprimento := 0.5          # no espaço do personagem (já dividido pela escala)
var _dedo := -1
var _p := Vector3.ZERO          # bolsinha (mundo)
var _p_ant := Vector3.ZERO
var _iniciou := false
var _corda_a: MeshInstance3D
var _corda_b: MeshInstance3D
var _bolsa: MeshInstance3D

func _ready() -> void:
	_dedo = sk.find_bone("mixamorig_RightHandIndex1") if sk else -1
	var couro := StandardMaterial3D.new(); couro.albedo_color = Color(0.36, 0.19, 0.11); couro.roughness = 1.0   # couro gasto, cor das botas
	var corda := StandardMaterial3D.new(); corda.albedo_color = Color(0.33, 0.22, 0.14); corda.roughness = 0.95
	for i in 2:
		var m := MeshInstance3D.new(); var c := CylinderMesh.new()
		c.top_radius = RAIO_CORDA; c.bottom_radius = RAIO_CORDA; c.height = 1.0; c.radial_segments = 5; c.rings = 1
		c.material = corda; m.mesh = c; m.top_level = true; add_child(m)
		if i == 0: _corda_a = m
		else: _corda_b = m
	_bolsa = MeshInstance3D.new(); var e := SphereMesh.new(); e.radius = 0.03; e.height = 0.035; e.radial_segments = 8; e.rings = 4
	e.material = couro; _bolsa.mesh = e; _bolsa.top_level = true; add_child(_bolsa)

func _mao() -> Vector3:
	if _dedo >= 0: return sk.global_transform * sk.get_bone_global_pose(_dedo).origin
	return global_position

func _physics_process(dt: float) -> void:
	if sk == null: return
	var l: float = comprimento * sk.global_transform.basis.get_scale().x
	var mao := _mao()
	if not _iniciou:
		_p = mao + Vector3(0, -l, 0); _p_ant = _p; _iniciou = true
	var v := (_p - _p_ant) * ATRITO
	_p_ant = _p
	_p += v + GRAVIDADE * dt * dt
	var d := _p - mao
	if d.length() > 0.0001: _p = mao + d.normalized() * l   # corda esticada
	_desenhar(mao)

func _process(_dt: float) -> void:
	if sk and _iniciou: _desenhar(_mao())
	var vis := is_visible_in_tree()
	_corda_a.visible = vis; _corda_b.visible = vis; _bolsa.visible = vis

func _desenhar(mao: Vector3) -> void:
	var d := (_p - mao)
	var lado := d.cross(Vector3.UP)
	lado = lado.normalized() * 0.018 if lado.length() > 0.0001 else Vector3(0.018, 0, 0)
	_ligar(_corda_a, mao, _p + lado); _ligar(_corda_b, mao, _p - lado)
	_bolsa.global_position = _p

func _ligar(m: MeshInstance3D, de: Vector3, ate: Vector3) -> void:
	var d := ate - de; var l := d.length()
	if l < 0.001: return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	m.global_transform = Transform3D(Basis(x, y * l, x.cross(y)), (de + ate) * 0.5)
