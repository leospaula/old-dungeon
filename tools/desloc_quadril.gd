extends SceneTree
## Deslocamento do quadril (x, y, z no espaço do modelo) ao longo de uma animação: quanto ela sobe e
## avança (escalar, pular, levantar). Uso: godot --headless --path . --script tools/desloc_quadril.gd -- <glb> <anim> [passos]
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var t: Node3D = load(a[0]).instantiate(); root.add_child(t)
	var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var A := ap.get_animation(a[1]); var n := int(a[2]) if a.size() > 2 else 12
	var q := sk.find_bone("mixamorig_Hips")
	ap.play(a[1])
	print("%s: %.2f s" % [a[1], A.length])
	for i in n + 1:
		ap.seek(A.length * i / n, true); ap.advance(0)
		var p := (sk.global_transform * sk.get_bone_global_pose(q)).origin
		print("%5.2fs  x %5.2f  y %5.2f  z %5.2f" % [A.length * i / n, p.x, p.y, p.z])
	quit()
