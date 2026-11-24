extends SceneTree
## Mede para onde o corpo da Tessa aponta em cada animação (pela linha dos quadris e ombros).
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var arq: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "res://arte/final/3d/tessa-biblioteca.glb"
	var t: Node3D = load(arq).instantiate()
	root.add_child(t)
	var sk: Skeleton3D = t.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = t.find_children("*", "AnimationPlayer", true, false)[0]
	var nomes := []
	for i in sk.get_bone_count(): nomes.append(sk.get_bone_name(i))
	for a in ap.get_animation_list():
		for fr in [0.0, 0.3, 0.6, 0.9]:
			ap.play(a); ap.seek(ap.get_animation(a).length * fr, true); ap.advance(0)
			await process_frame
			var e := -1; var d := -1; var oe := -1; var od := -1
			for i in sk.get_bone_count():
				var n := sk.get_bone_name(i).to_lower()
				if n.contains("leftupleg") or n == "l_thigh": e = i
				if n.contains("rightupleg"): d = i
				if n.contains("leftarm") and not n.contains("fore"): oe = i
				if n.contains("rightarm") and not n.contains("fore"): od = i
			var f := func(a_: int, b_: int) -> Vector3:
				var lat: Vector3 = (sk.global_transform * sk.get_bone_global_pose(b_)).origin - (sk.global_transform * sk.get_bone_global_pose(a_)).origin
				return Vector3.UP.cross(lat).normalized()
			var hips: Vector3 = f.call(d, e) if e >= 0 and d >= 0 else Vector3.ZERO
			var omb: Vector3 = f.call(od, oe) if oe >= 0 and od >= 0 else Vector3.ZERO
			hips = -hips; omb = -omb
			var pe := Vector3.ZERO
			for lado in ["Left", "Right"]:
				var f_ := sk.find_bone("mixamorig_%sFoot" % lado); var t_ := sk.find_bone("mixamorig_%sToeBase" % lado)
				pe += (sk.get_bone_global_pose(t_).origin - sk.get_bone_global_pose(f_).origin) * Vector3(1, 0, 1)
			pe = (sk.global_transform.basis * pe).normalized()
			print("   pés: %.0f graus" % rad_to_deg(atan2(pe.x, pe.z)))
			print("%.1f %-24s quadril %s  ombros %s  (graus: %.0f / %.0f)" % [fr, a, hips.snappedf(0.01), omb.snappedf(0.01), rad_to_deg(atan2(hips.x, hips.z)), rad_to_deg(atan2(omb.x, omb.z))])
	quit()
