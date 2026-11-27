extends SceneTree
func _init() -> void:
	var ref: Skeleton3D = null; var refn := ""
	for f in OS.get_cmdline_user_args():
		var n: Node = load(f).instantiate(); root.add_child(n)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		if ref == null: ref = sk; refn = f.get_file(); print("ref ", refn, " hips_y=", sk.get_bone_global_rest(0).origin.y); continue
		var pior := 0.0; var qual := ""
		for i in sk.get_bone_count():
			var j := ref.find_bone(sk.get_bone_name(i))
			var a: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion()
			var b: Quaternion = ref.get_bone_rest(j).basis.get_rotation_quaternion()
			var ang := rad_to_deg(a.angle_to(b))
			if ang > pior: pior = ang; qual = sk.get_bone_name(i)
		print(f.get_file(), " maior diferença de repouso=", snappedf(pior, 0.1), "° (", qual, ") hips_y=", sk.get_bone_global_rest(0).origin.y, " escala_no=", sk.get_parent().scale if sk.get_parent() is Node3D else "")
	quit()
