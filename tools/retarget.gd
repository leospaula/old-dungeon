extends RefCounted
## Retarget entre esqueletos com os mesmos nomes de ossos (padrão Mixamo), mas com orientação
## da personagem, pose de repouso (A × T) e eixos dos ossos diferentes.
## Copia a DIREÇÃO de cada osso no espaço (com a torção), não a rotação local.

const FPS := 30.0

static func filho_preferido(sk: Skeleton3D, i: int) -> int:
	var nome := sk.get_bone_name(i)
	var filhos := []
	for k in sk.get_bone_count():
		if sk.get_bone_parent(k) == i: filhos.append(k)
	if filhos.is_empty(): return -1
	for pref in ["Spine", "Neck", "Head", "Middle1", "Arm", "Leg", "Foot", "ToeBase"]:
		for k in filhos:
			var n := sk.get_bone_name(k)
			if n.contains(pref) and not (nome.contains("Hips") and n.contains("Leg")): return k
	return filhos[0]

static func _lateral(sk: Skeleton3D) -> Vector3:
	var e := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftArm")).origin
	var d := sk.get_bone_global_rest(sk.find_bone("mixamorig_RightArm")).origin
	var v := e - d; v.y = 0
	return v.normalized()

## Base "personagem": X = esquerda, Y = cima, Z = frente.
static func base_personagem(sk: Skeleton3D) -> Basis:
	var esq := _lateral(sk)
	var cima := Vector3.UP
	var frente := esq.cross(cima).normalized()  # esquerda × cima = frente (mão direita)
	if frente.dot(_frente_pelos_pes(sk)) < 0: frente = -frente
	return Basis(esq, cima, frente)

static func _frente_pelos_pes(sk: Skeleton3D) -> Vector3:
	var p := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftFoot")).origin
	var t := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftToeBase")).origin
	var v := t - p; v.y = 0
	return v.normalized()

## Quadro normalizado de um osso: Y = direção do osso, X ⟂ à frente da personagem (ou ao "cima" quando degenera).
static func quadro(dir: Vector3, frente: Vector3, usar_cima: bool) -> Basis:
	var ref := Vector3.UP if usar_cima else frente
	var x := dir.cross(ref).normalized()
	var z := x.cross(dir).normalized()
	return Basis(x, dir, z)

## Converte a animação `anim` (feita para `src`) em uma nova animação para `dst`.
static func converter(anim: Animation, src: Skeleton3D, dst: Skeleton3D, caminho_dst: String, no_lugar := false) -> Animation:
	var bs := base_personagem(src); var bd := base_personagem(dst)
	var R: Basis = bd * bs.inverse()               # leva o espaço da origem para o do destino
	var n := src.get_bone_count()
	# Trilhas da origem por osso
	var rot_tr := {}; var pos_tr := {}
	for i in anim.get_track_count():
		var osso := anim.track_get_path(i).get_concatenated_subnames()
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D: rot_tr[osso] = i
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D: pos_tr[osso] = i
	# Correções por osso, calculadas no repouso
	var corr := {}
	var frente_s: Vector3 = bs.z
	for i in n:
		var nome := src.get_bone_name(i)
		var j := dst.find_bone(nome)
		if j < 0: continue
		var fs := filho_preferido(src, i); var fd := filho_preferido(dst, j)
		if fs < 0 or fd < 0: continue
		var gs := src.get_bone_global_rest(i); var gd := dst.get_bone_global_rest(j)
		var ds := (src.get_bone_global_rest(fs).origin - gs.origin).normalized()
		var dd := (dst.get_bone_global_rest(fd).origin - gd.origin).normalized()
		var dd_s: Vector3 = R.inverse() * dd       # direção do destino no espaço da origem
		var cima := absf(ds.dot(frente_s)) > 0.8 or absf(dd_s.dot(frente_s)) > 0.8
		var Fs := quadro(ds, frente_s, cima)
		var Fd := quadro(dd_s, frente_s, cima)
		var Gd_s: Basis = R.inverse() * gd.basis   # repouso do destino no espaço da origem
		# Gd(t) = R * Gs(t) * Gs_rest⁻¹ * Fs * Fd⁻¹ * Gd_s
		corr[i] = gs.basis.inverse() * Fs * Fd.inverse() * Gd_s
	# Altura do quadril
	var hs := src.find_bone("mixamorig_Hips"); var hd := dst.find_bone("mixamorig_Hips")
	var razao := dst.get_bone_global_rest(hd).origin.y / src.get_bone_global_rest(hs).origin.y
	var saida := Animation.new(); saida.length = anim.length
	var trilhas := {}
	for i in n:
		if not corr.has(i): continue
		var t := saida.add_track(Animation.TYPE_ROTATION_3D)
		saida.track_set_path(t, NodePath(caminho_dst + ":" + src.get_bone_name(i)))
		trilhas[i] = t
	var tq := saida.add_track(Animation.TYPE_POSITION_3D)
	saida.track_set_path(tq, NodePath(caminho_dst + ":mixamorig_Hips"))
	var quadros := int(ceil(anim.length * FPS)) + 1
	for f in quadros:
		var tempo: float = min(f / FPS, anim.length)
		# Pose global da origem neste instante
		var gsrc := []; gsrc.resize(n)
		for i in n:
			var nome := src.get_bone_name(i)
			var rest := src.get_bone_rest(i)
			var q: Quaternion = anim.rotation_track_interpolate(rot_tr[nome], tempo) if rot_tr.has(nome) else rest.basis.get_rotation_quaternion()
			var p: Vector3 = anim.position_track_interpolate(pos_tr[nome], tempo) if pos_tr.has(nome) else rest.origin
			var local := Transform3D(Basis(q).scaled(rest.basis.get_scale()), p)
			var pai := src.get_bone_parent(i)
			gsrc[i] = (gsrc[pai] * local) if pai >= 0 else local
		# Pose global do destino e conversão para local
		var gdst := {}
		for i in n:
			if not corr.has(i): continue
			var j := dst.find_bone(src.get_bone_name(i))
			var b: Basis = R * gsrc[i].basis * corr[i]
			gdst[j] = b
			var pai := dst.get_bone_parent(j)
			var bp: Basis = gdst[pai] if gdst.has(pai) else (dst.get_bone_global_rest(pai).basis if pai >= 0 else Basis())
			saida.rotation_track_insert_key(trilhas[i], tempo, (bp.inverse() * b).get_rotation_quaternion())
		var desloc: Vector3 = R * (gsrc[hs].origin - src.get_bone_global_rest(hs).origin) * razao
		if no_lugar: desloc = Vector3(0, desloc.y, 0)   # tira o avanço horizontal (o código do jogo move o personagem)
		saida.position_track_insert_key(tq, tempo, dst.get_bone_rest(hd).origin + desloc)
	return saida
