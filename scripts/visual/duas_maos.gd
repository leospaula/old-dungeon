extends Node3D
## Arma de duas mãos (lança, haste, cajado, besta): presa ao punho direito, mas quando a mão esquerda
## também está no cabo (as mãos perto da linha da arma), o cabo aponta da mão direita para a esquerda.
## Com as mãos afastadas (guarda com o punho erguido), fica como o punho direito manda.

var sk: Skeleton3D
var base := Basis()          # orientação vinda do punho direito (no espaço do osso da mão)
var alcance := 0.4          # distância entre as mãos (no espaço do esqueleto) até onde ainda alinha
var _esq := -1
var frente := Vector3.ZERO   # frente da personagem em repouso (espaço do esqueleto)
## Para que lado do cabo vai a ponta: "esquerda" (além da mão esquerda: lança, besta), "direita" (além da
## mão direita, que fica junto da guarda: espada e machado de duas mãos) ou "olhar" (para onde a cabeça olha).
var ponta := "esquerda"
var ap: AnimationPlayer
var erguer := {}   # {animação: fração} puxa a arma para a vertical nessa animação (guarda mais ereta)
var _cab := -1
var _olhar_local := Vector3.ZERO   # olhar da cabeça no espaço do osso: a ponta vai para onde ela olha

func _ready() -> void:
	base = transform.basis
	_esq = sk.find_bone("mixamorig_LeftHandMiddle1") if sk else -1
	if sk and frente != Vector3.ZERO:
		_cab = sk.find_bone("mixamorig_Head")
		_olhar_local = sk.get_bone_global_rest(_cab).basis.inverse() * frente

func _process(_dt: float) -> void:
	if sk == null or _esq < 0 or not is_visible_in_tree(): return
	var pai := get_parent() as Node3D
	var esq_glob: Vector3 = sk.global_transform * sk.get_bone_global_pose(_esq).origin
	var local: Vector3 = pai.global_transform.affine_inverse() * esq_glob - position
	var d_esq := (sk.global_transform.affine_inverse() * esq_glob).distance_to(sk.global_transform.affine_inverse() * pai.global_transform * position)
	# Folga larga: só solta o alinhamento quando a mão esquerda sai mesmo do cabo (sem tremer).
	var peso := 1.0 - smoothstep(0.7, 0.9, d_esq)
	if peso <= 0.001 or local.length() < 0.001:
		transform.basis = base; return
	var y0 := base.y.normalized()
	var alvo := local.normalized()
	if ponta == "direita": alvo = -alvo
	elif ponta == "olhar" and _cab >= 0:
		var olhar: Vector3 = sk.get_bone_global_pose(_cab).basis * _olhar_local; olhar.y = 0
		var no_sk: Vector3 = sk.global_transform.basis.inverse() * (pai.global_transform.basis * alvo)
		no_sk.y = 0
		if no_sk.dot(olhar) < 0: alvo = -alvo
	if ap and erguer.has(String(ap.assigned_animation)):
		var cima: Vector3 = (pai.global_transform.basis.inverse() * Vector3.UP).normalized()
		alvo = alvo.slerp(cima, float(erguer[String(ap.assigned_animation)])).normalized()
	var giro := Quaternion(y0, alvo)
	transform.basis = Basis(Quaternion.IDENTITY.slerp(giro, peso)) * base
