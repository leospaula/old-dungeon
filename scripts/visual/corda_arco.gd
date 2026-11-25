extends Node3D
## Corda do arco desenhada em tempo de jogo: o modelo do arco não tem corda; aqui ela vai de uma ponta
## à outra. Enquanto a animação de disparo está puxando (entre encaixar a flecha e soltar), o meio da
## corda acompanha a mão direita; fora disso, fica reta.

const PUXA := {"atirar-flecha": [1.45, 3.1]}   # trecho (s) da animação em que a corda está puxada
const RAIO := 0.005                             # m (espessura da corda; mais fina some na câmera do jogo)

var _ponta_a := Vector3.ZERO   # no espaço do arco
var _ponta_b := Vector3.ZERO
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _mao := -1
var _seg_a: MeshInstance3D
var _seg_b: MeshInstance3D

static func prender(arco: Node3D, sk: Skeleton3D, ap: AnimationPlayer) -> Node3D:
	var c: Node3D = load("res://scripts/visual/corda_arco.gd").new()
	c._sk = sk; c._ap = ap; c._mao = sk.find_bone("mixamorig_RightHandIndex1")
	c._achar_pontas(arco)
	arco.add_child(c)
	return c

func _ready() -> void:
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.32, 0.27, 0.2); mat.roughness = 0.9
	for i in 2:
		var m := MeshInstance3D.new(); var cil := CylinderMesh.new()
		cil.top_radius = RAIO; cil.bottom_radius = RAIO; cil.height = 1.0; cil.radial_segments = 4; cil.rings = 1
		cil.material = mat; m.mesh = cil; m.top_level = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		if i == 0: _seg_a = m
		else: _seg_b = m

## Pontas = os vértices mais extremos ao longo do eixo mais comprido da malha.
func _achar_pontas(arco: Node3D) -> void:
	var pts: Array[Vector3] = []
	var pilha := [[arco, Transform3D.IDENTITY]]
	while pilha:
		var par = pilha.pop_back(); var no: Node = par[0]; var t: Transform3D = par[1]
		if no is Node3D and no != arco: t = t * (no as Node3D).transform
		if no is MeshInstance3D and no.mesh:
			for s in no.mesh.get_surface_count():
				for v in no.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: pts.append(t * v)
		for c in no.get_children(): pilha.append([c, t])
	if pts.is_empty(): return
	var caixa := AABB(pts[0], Vector3.ZERO)
	for p in pts: caixa = caixa.expand(p)
	var eixo := 0
	for e in 3: if caixa.size[e] > caixa.size[eixo]: eixo = e
	var lo := caixa.position[eixo]; var hi := caixa.end[eixo]; var tol := caixa.size[eixo] * 0.015
	var sa := Vector3.ZERO; var na := 0; var sb := Vector3.ZERO; var nb := 0
	for p in pts:
		if p[eixo] <= lo + tol: sa += p; na += 1
		elif p[eixo] >= hi - tol: sb += p; nb += 1
	_ponta_a = sa / maxi(na, 1); _ponta_b = sb / maxi(nb, 1)

func _process(_dt: float) -> void:
	var arco := get_parent() as Node3D
	if arco == null or not arco.is_visible_in_tree():
		_seg_a.visible = false; _seg_b.visible = false; return
	_seg_a.visible = true; _seg_b.visible = true
	var a := arco.global_transform * _ponta_a
	var b := arco.global_transform * _ponta_b
	var meio := (a + b) * 0.5
	var nome := String(_ap.assigned_animation) if _ap else ""   # current_animation some quando pausa
	if PUXA.has(nome) and _mao >= 0:
		var t := _ap.current_animation_position
		if t >= PUXA[nome][0] and t <= PUXA[nome][1]:
			meio = _sk.global_transform * _sk.get_bone_global_pose(_mao).origin
	_ligar(_seg_a, a, meio); _ligar(_seg_b, b, meio)

func _ligar(m: MeshInstance3D, de: Vector3, ate: Vector3) -> void:
	var d := ate - de; var l := d.length()
	if l < 0.001: m.visible = false; return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	m.global_transform = Transform3D(Basis(x, y * l, z), (de + ate) * 0.5)
