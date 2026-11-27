extends SkeletonModifier3D
## Mãos amarradas na frente do corpo: depois da animação (andar, parado, sentado…), os dois braços são
## dobrados por IK de dois ossos (braço e antebraço) até os pulsos se encontrarem na frente da barriga,
## e uma volta de corda aparece em volta dos pulsos. `influence` de 1 a 0 solta as mãos aos poucos.
##
## Uso: Skeleton3D.add_child(MaosAmarradas.new()); para soltar, soltar() (anima e se remove).

const COR_CORDA := Color(0.42, 0.3, 0.17)

var _ossos := {}            # lado -> [braço, antebraço, mão]
var _quadril := -1
var _frente := Vector3.FORWARD
var _corda: MeshInstance3D
var _nos: Array[MeshInstance3D] = []

func _ready() -> void:
	var sk := get_skeleton()
	if sk == null: return
	for lado in ["Right", "Left"]:
		_ossos[lado] = [sk.find_bone("mixamorig_%sArm" % lado), sk.find_bone("mixamorig_%sForeArm" % lado), sk.find_bone("mixamorig_%sHand" % lado)]
	_quadril = sk.find_bone("mixamorig_Hips")
	var e := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftArm")).origin
	var d := sk.get_bone_global_rest(sk.find_bone("mixamorig_RightArm")).origin
	var lat := e - d; lat.y = 0
	_frente = lat.normalized().cross(Vector3.UP).normalized()
	var p := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftFoot")).origin
	var t := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftToeBase")).origin
	if _frente.dot(t - p) < 0: _frente = -_frente
	var mat := StandardMaterial3D.new(); mat.albedo_color = COR_CORDA; mat.roughness = 1.0
	_corda = MeshInstance3D.new(); var c := CylinderMesh.new()
	c.top_radius = 1.0; c.bottom_radius = 1.0; c.height = 1.0; c.radial_segments = 8; c.rings = 1; c.material = mat
	_corda.mesh = c; _corda.top_level = true; add_child(_corda)
	for i in 2:   # uma volta de corda em cada pulso
		var n := MeshInstance3D.new(); var tm := TorusMesh.new()
		tm.inner_radius = 0.75; tm.outer_radius = 1.0; tm.rings = 10; tm.ring_segments = 6; tm.material = mat
		n.mesh = tm; n.top_level = true; add_child(n); _nos.append(n)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _ossos.is_empty(): return
	var quadril := sk.get_bone_global_pose(_quadril).origin
	var h := sk.get_bone_global_rest(_quadril).origin.y   # altura do quadril em pé (escala do modelo)
	var lado_v := Vector3.UP.cross(_frente).normalized()  # aponta para a esquerda do personagem
	var centro := quadril + _frente * h * 0.3 + Vector3.UP * h * 0.1
	var pulsos := {}
	for lado in ["Right", "Left"]:
		var sinal := -1.0 if lado == "Right" else 1.0
		# Uma mão um pouco acima da outra (a direita por cima): os pulsos não se atravessam.
		var alvo := centro + lado_v * sinal * h * 0.03 + Vector3.UP * (h * 0.055 if lado == "Right" else 0.0) + _frente * (h * 0.02 if lado == "Right" else 0.0)
		_ik(sk, _ossos[lado], alvo, lado_v * sinal)
		pulsos[lado] = sk.get_bone_global_pose(_ossos[lado][2]).origin
	_desenhar(sk, pulsos.Right, pulsos.Left, h)

## IK de dois ossos: o cotovelo vai para trás e para fora (pelo `pole`), o pulso para o alvo.
func _ik(sk: Skeleton3D, ossos: Array, alvo: Vector3, para_fora: Vector3) -> void:
	var b0: int = ossos[0]; var b1: int = ossos[1]; var b2: int = ossos[2]
	if b0 < 0 or b1 < 0 or b2 < 0: return
	var a := sk.get_bone_global_pose(b0).origin
	var b := sk.get_bone_global_pose(b1).origin
	var c := sk.get_bone_global_pose(b2).origin
	var l1 := a.distance_to(b); var l2 := b.distance_to(c)
	var para := alvo - a
	var dist := clampf(para.length(), 0.01, (l1 + l2) * 0.999)
	var dir := para.normalized()
	var polo := -_frente * 0.6 + para_fora * 0.5 + Vector3.DOWN * 0.4
	var perp := (polo - dir * polo.dot(dir)).normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var cotovelo := a + dir * cos_a * l1 + perp * sqrt(1.0 - cos_a * cos_a) * l1
	_apontar(sk, b0, b - a, cotovelo - a)
	var b_novo := sk.get_bone_global_pose(b1).origin
	var c_atual := sk.get_bone_global_pose(b2).origin
	_apontar(sk, b1, c_atual - b_novo, (a + dir * dist) - b_novo)

## Gira o osso (no espaço do esqueleto) para que o vetor `de` (até o filho) aponte para `para`.
func _apontar(sk: Skeleton3D, osso: int, de: Vector3, para: Vector3) -> void:
	if de.length() < 0.0001 or para.length() < 0.0001: return
	var q := Quaternion(de.normalized(), para.normalized())
	var glob := sk.get_bone_global_pose(osso)
	var novo := Transform3D(Basis(q) * glob.basis, glob.origin)
	var pai := sk.get_bone_parent(osso)
	var local := sk.get_bone_global_pose(pai).affine_inverse() * novo if pai >= 0 else novo
	sk.set_bone_pose_rotation(osso, local.basis.get_rotation_quaternion())

func _desenhar(sk: Skeleton3D, d: Vector3, e: Vector3, h: float) -> void:
	var g := sk.global_transform
	var gd := g * d; var ge := g * e
	var esc := g.basis.get_scale().x
	var r := h * esc * 0.03
	var meio := (gd + ge) * 0.5; var eixo := ge - gd
	var l := maxf(eixo.length(), 0.02)
	var y := eixo.normalized() if eixo.length() > 0.0001 else Vector3.RIGHT
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.FORWARD).normalized()
	_corda.global_transform = Transform3D(Basis(x * r * 0.5, y * (l + r * 2.0), x.cross(y) * r * 0.5), meio)
	var vis := influence > 0.5 and is_visible_in_tree()
	_corda.visible = vis
	for i in 2:
		var p := gd if i == 0 else ge
		_nos[i].global_transform = Transform3D(Basis(x * r, y * r * 0.9, x.cross(y) * r), p)
		_nos[i].visible = vis

## Solta as mãos: os braços voltam à animação em `dur` s e a corda some.
func soltar(dur := 0.6) -> void:
	var t := create_tween(); t.tween_property(self, "influence", 0.0, dur)
	await t.finished
	queue_free()
