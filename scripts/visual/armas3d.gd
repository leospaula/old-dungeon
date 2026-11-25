extends RefCounted
## Armas e escudos 3D presos ao esqueleto em tempo de jogo, a partir de `modelo3d` no catálogo de itens.
## Mesma conta da montagem (tools/montar_personagem.gd): a arma é empunhada pela mão fechada de verdade
## (pose de punho cerrado), o escudo fica no antebraço pela pose de bloqueio. Assim trocar de arma troca
## o modelo na mão, e qualquer personagem com esqueleto Mixamo pode usar qualquer item.
##
## modelo3d: {arquivo, comprimento (m reais), pega [0–1]×3 (ponto da malha que fica no punho),
##            mao: "direita" | "esquerda" | "antebraco", pose, pose_t, rotacao [graus], ao_longo, afastar (m),
##            ajuste_punho [m]×3, duas_maos (o cabo aponta para a mão esquerda quando ela está no cabo),
##            corda (arco: corda desenhada), escala_eixos [x, y, z]}

const CordaArco = preload("res://scripts/visual/corda_arco.gd")
const DuasMaos = preload("res://scripts/visual/duas_maos.gd")
const PrumoArco = preload("res://scripts/visual/prumo_arco.gd")

## Prende o item ao esqueleto. `escala` = escala do modelo do personagem no jogo (para o comprimento real).
## Devolve o BoneAttachment3D (remova-o para tirar o item).
static func montar(sk: Skeleton3D, ap: AnimationPlayer, m: Dictionary, escala: float) -> Node3D:
	var mao: String = m.get("mao", "direita")
	var osso: String = {"direita": "mixamorig_RightHand", "esquerda": "mixamorig_LeftHand", "antebraco": "mixamorig_LeftForeArm"}[mao]
	var i_osso := sk.find_bone(osso)
	if i_osso < 0 or not ResourceLoader.exists(str(m.arquivo)): return null
	var item: Node3D = load(str(m.arquivo)).instantiate()
	var caixa := _aabb(item)
	var esc: float = float(m.comprimento) / escala / maxf(caixa.size.y, maxf(caixa.size.x, caixa.size.z))
	var pg: Array = m.get("pega", [0.5, 0.15, 0.5])
	var pega: Vector3 = caixa.position + caixa.size * Vector3(pg[0], pg[1], pg[2])
	# A pegada vai para o centro da própria malha na altura do cabo (curvas, cabos tortos, arcos).
	if bool(m.get("pega_malha", true)): pega = _centro_na_altura(item, pega.y, caixa.size.y * 0.03, pega)
	var ba := BoneAttachment3D.new(); ba.bone_name = osso; sk.add_child(ba)
	var piv: Node3D = DuasMaos.new() if bool(m.get("duas_maos", false)) else (PrumoArco.new() if bool(m.get("prumo", false)) else Node3D.new())
	if piv is PrumoArco: piv.sk = sk; piv.ap = ap; piv.frente = _frente(sk)
	if piv is DuasMaos: piv.sk = sk; piv.frente = _frente(sk); piv.ponta = str(m.get("ponta", "esquerda"))
	ba.add_child(piv)
	# A pose de referência mexe no esqueleto: guarda a animação atual e devolve depois.
	var antes := ap.current_animation; var pos := ap.current_animation_position if antes != "" else 0.0
	if mao == "antebraco": piv.transform = _no_antebraco(sk, i_osso, ap, m, caixa, escala)
	else: piv.transform = _no_punho(sk, i_osso, ap, m, mao)
	# vertical_em: endireita o item (eixo do comprimento) na vertical nesta pose/instante (arco na puxada).
	var r0: Array = m.get("rotacao", [0, 0, 0])
	var rot_item := Basis.from_euler(Vector3(deg_to_rad(r0[0]), deg_to_rad(r0[1]), deg_to_rad(r0[2])))
	if m.has("vertical_em") and ap.has_animation(str(m.vertical_em[0])):
		ap.play(str(m.vertical_em[0])); ap.seek(float(m.vertical_em[1]), true); ap.advance(0); sk.force_update_all_bone_transforms()
		var osso_glob: Basis = sk.get_bone_global_pose(i_osso).basis
		var eixo_local: Vector3 = (piv.transform.basis * rot_item).y.normalized()
		var cima_local: Vector3 = (osso_glob.inverse() * Vector3.UP).normalized()
		if eixo_local.dot(cima_local) < 0: cima_local = -cima_local
		piv.transform.basis = Basis(Quaternion(eixo_local, cima_local)) * piv.transform.basis
	if piv is DuasMaos: piv.base = piv.transform.basis
	if piv is PrumoArco: piv.base = piv.transform.basis; piv.eixo_item = (rot_item * Vector3.UP).normalized()
	if antes != "": ap.play(antes); ap.seek(pos, true)
	var giro := Node3D.new(); piv.add_child(giro)
	var r: Array = m.get("rotacao", [0, 0, 0])
	giro.rotation_degrees = Vector3(r[0], r[1], r[2])
	# escala_eixos: corrige malhas que vieram grossas num eixo (ex.: arco que o Tripo fez largo demais).
	var ex: Array = m.get("escala_eixos", [1, 1, 1])
	var ev := Vector3(ex[0], ex[1], ex[2])
	giro.add_child(item); item.scale = Vector3.ONE * esc * ev; item.position = -pega * esc * ev
	if bool(m.get("corda", false)): CordaArco.prender(item, sk, ap)
	return ba

## Empunhadura pela mão fechada: furo do punho (média das juntas dos 4 dedos), cabo do mindinho para o
## indicador e guarda nos nós dos dedos, no espaço do osso da mão.
static func _no_punho(sk: Skeleton3D, i_mao: int, ap: AnimationPlayer, m: Dictionary, mao: String) -> Transform3D:
	var pose: String = m.get("pose", "parado-espada-escudo")
	if ap.has_animation(pose):
		ap.play(pose); ap.seek(ap.get_animation(pose).length * float(m.get("pose_t", 0.3)), true); ap.advance(0)
	sk.force_update_all_bone_transforms()
	var g := sk.get_bone_global_pose(i_mao)
	var lado := "Right" if mao == "direita" else "Left"
	var local := func(nome: String) -> Vector3:
		return g.affine_inverse() * sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand%s" % [lado, nome])).origin
	var centro := Vector3.ZERO
	for dedo in ["Index", "Middle", "Ring", "Pinky"]:
		for j in [1, 2, 3, 4]: centro += local.call("%s%d" % [dedo, j])
	centro /= 16.0
	var y: Vector3 = (local.call("Index1") - local.call("Pinky1")).normalized()
	var z: Vector3 = local.call("Middle1"); z = (z - y * z.dot(y)).normalized()
	var x := y.cross(z).normalized()
	var aj: Array = m.get("ajuste_punho", [0, 0, 0])
	return Transform3D(Basis(x, y, z), centro + x * float(aj[0]) + y * float(aj[1]) + z * float(aj[2]))

## Escudo no antebraço pela pose de bloqueio: a face (eixo mais fino da malha) para onde a cabeça olha,
## o plano paralelo ao antebraço.
static func _no_antebraco(sk: Skeleton3D, i_osso: int, ap: AnimationPlayer, m: Dictionary, caixa: AABB, escala: float) -> Transform3D:
	var pose: String = m.get("pose", "bloquear")
	if ap.has_animation(pose):
		ap.play(pose); ap.seek(float(m.get("pose_t", 0.35)), true); ap.advance(0)
	sk.force_update_all_bone_transforms()
	var i_filho := sk.find_bone("mixamorig_LeftHand")
	var g := sk.get_bone_global_pose(i_osso)
	var d: Vector3 = (sk.get_bone_global_pose(i_filho).origin - g.origin)
	var i_cab := sk.find_bone("mixamorig_Head")
	var olhar_local: Vector3 = sk.get_bone_global_rest(i_cab).basis.inverse() * _frente(sk)
	var frente: Vector3 = sk.get_bone_global_pose(i_cab).basis * olhar_local
	frente.y = 0; frente = frente.normalized()
	var n: Vector3 = (frente - d.normalized() * frente.dot(d.normalized())).normalized()
	var fino := 0
	for e in 3: if caixa.size[e] < caixa.size[fino]: fino = e
	var outro := (fino + 1) % 3; var terceiro := (fino + 2) % 3
	var cols := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[fino] = n; cols[outro] = d.normalized(); cols[terceiro] = n.cross(d.normalized())
	var b := Basis(cols[0], cols[1], cols[2])
	if b.determinant() < 0: cols[terceiro] = -cols[terceiro]; b = Basis(cols[0], cols[1], cols[2])
	var ponto: Vector3 = g.origin + d * float(m.get("ao_longo", 0.55)) + n * float(m.get("afastar", 0.07)) / escala
	return g.affine_inverse() * Transform3D(b, ponto)

## Frente da personagem em repouso (pelos pés), no espaço do esqueleto.
static func _frente(sk: Skeleton3D) -> Vector3:
	var e := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftArm")).origin
	var d := sk.get_bone_global_rest(sk.find_bone("mixamorig_RightArm")).origin
	var lat := e - d; lat.y = 0
	var f := lat.normalized().cross(Vector3.UP).normalized()
	var p := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftFoot")).origin
	var t := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftToeBase")).origin
	var pe := t - p; pe.y = 0
	return f if f.dot(pe) >= 0 else -f

## Centro (x, z) dos vértices numa faixa de altura y ± faixa, no espaço do item.
static func _centro_na_altura(n: Node3D, y: float, faixa: float, padrao: Vector3) -> Vector3:
	var soma := Vector3.ZERO; var k := 0
	var pilha := [[n, Transform3D.IDENTITY]]
	while pilha:
		var par = pilha.pop_back(); var no: Node = par[0]; var t: Transform3D = par[1]
		if no is Node3D and no != n: t = t * (no as Node3D).transform
		if no is MeshInstance3D and no.mesh:
			for si in no.mesh.get_surface_count():
				for v in no.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = t * v
					if absf(p.y - y) <= faixa: soma += p; k += 1
		for c in no.get_children(): pilha.append([c, t])
	if k < 3: return padrao
	return Vector3(soma.x / k, y, soma.z / k)

static func _aabb(n: Node) -> AABB:
	var caixa := AABB(); var primeiro := true
	var pilha := [[n, Transform3D.IDENTITY]]
	while pilha:
		var par = pilha.pop_back(); var no: Node = par[0]; var t: Transform3D = par[1]
		if no is Node3D and no != n: t = t * (no as Node3D).transform
		if no is MeshInstance3D and no.mesh:
			var b: AABB = t * no.mesh.get_aabb()
			caixa = b if primeiro else caixa.merge(b); primeiro = false
		for c in no.get_children(): pilha.append([c, t])
	return caixa
