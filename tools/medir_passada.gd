extends SceneTree
## Mede a velocidade "natural" da animação de andar: quanto o pé apoiado escorrega para trás por segundo.
## Uso: godot --headless --path . --script tools/medir_passada.gd -- arquivo.glb escala [animacao]
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var arq: String = args[0]
	var esc: float = float(args[1]) if args.size() > 1 else 1.0
	var anim: String = args[2] if args.size() > 2 else "andar"
	var t: Node3D = load(arq).instantiate()
	root.add_child(t)
	var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var A := ap.get_animation(anim)
	var pes := [sk.find_bone("mixamorig_LeftFoot"), sk.find_bone("mixamorig_RightFoot")]
	var quadril := sk.find_bone("mixamorig_Hips")
	var N := 120
	var amostras := []
	ap.play(anim)
	for i in N + 1:
		ap.seek(A.length * i / N, true); ap.advance(0)
		var ps := []
		for b in pes: ps.append((sk.global_transform * sk.get_bone_global_pose(b)).origin * esc)
		amostras.append([ps, (sk.global_transform * sk.get_bone_global_pose(quadril)).origin * esc])
	var dt := A.length / N
	var vels := []
	var soma := Vector3.ZERO
	var faixa := [INF, -INF]
	for i in N:
		var p0: Array = amostras[i][0]; var p1: Array = amostras[i + 1][0]
		var k := 0 if p0[0].y < p0[1].y else 1   # pé mais baixo = apoiado
		var v: Vector3 = (p1[k] - p0[k]) / dt; v.y = 0
		vels.append(v.length()); soma -= v   # o pé apoiado vai para trás: o corpo vai para o lado oposto
		faixa[0] = minf(faixa[0], p0[0].x); faixa[1] = maxf(faixa[1], p0[0].x)
	vels.sort()
	var h0: Vector3 = amostras[0][1]; var h1: Vector3 = amostras[N][1]
	print("%s  duração %.2fs  pé apoiado: mediana %.2f m/s  (p25 %.2f  p75 %.2f)  deslocamento do quadril no ciclo %s" % [anim, A.length, vels[N / 2], vels[N / 4], vels[3 * N / 4], (h1 - h0).snappedf(0.01)])
	print("   direção do avanço: %.0f graus (para giro_anim)" % rad_to_deg(atan2(soma.x, soma.z)))
	quit()
