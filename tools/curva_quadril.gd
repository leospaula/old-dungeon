extends SceneTree
## Altura do quadril e inclinação do tronco ao longo de uma animação (achar onde começa a queda etc.).
## Uso: godot --headless --path . --script tools/curva_quadril.gd -- <glb> <animacao> [passos]
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var t: Node3D = load(a[0]).instantiate(); root.add_child(t)
	var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var A := ap.get_animation(a[1]); var n := int(a[2]) if a.size() > 2 else 30
	var q := sk.find_bone("mixamorig_Hips"); var c := sk.find_bone("mixamorig_Head"); var m := sk.find_bone("mixamorig_RightHand")
	var antes := Vector3.ZERO
	ap.play(a[1])
	for i in n + 1:
		ap.seek(A.length * i / n, true); ap.advance(0)
		var hq := (sk.global_transform * sk.get_bone_global_pose(q)).origin
		var hc := (sk.global_transform * sk.get_bone_global_pose(c)).origin
		var inc := rad_to_deg((hc - hq).angle_to(Vector3.UP))
		var hm := (sk.global_transform * sk.get_bone_global_pose(m)).origin
		var vel := (hm - antes).length() / (A.length / n) if i > 0 else 0.0
		antes = hm
		print("%.2fs  quadril %.2f  cabeça %.2f  inclinação %3.0f°  mão dir. alt %.2f (vel %.2f)" % [A.length * i / n, hq.y, hc.y, inc, hm.y, vel])
	quit()
