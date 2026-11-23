extends SceneTree
## Compara a pose de repouso (global) de dois esqueletos: posição, direção do osso e rotação.
## Uso: godot --headless --path . --script tools/comparar_repouso.gd -- <a.glb|fbx> <b.glb|fbx>

const OSSOS := ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand", "mixamorig_RightArm", "mixamorig_RightHand", "mixamorig_LeftUpLeg", "mixamorig_LeftFoot"]

func _init() -> void:
	for c in OS.get_cmdline_user_args():
		var doc = FBXDocument.new() if c.ends_with(".fbx") else GLTFDocument.new()
		var st = FBXState.new() if c.ends_with(".fbx") else GLTFState.new()
		doc.append_from_file(c, st)
		var n: Node = doc.generate_scene(st)
		var sk := _achar(n) as Skeleton3D
		print("== ", c.get_file())
		for o in OSSOS:
			var i := sk.find_bone(o)
			var g := sk.get_bone_global_rest(i)
			var filho := -1
			for k in sk.get_bone_count():
				if sk.get_bone_parent(k) == i: filho = k; break
			var dir := (sk.get_bone_global_rest(filho).origin - g.origin).normalized() if filho >= 0 else Vector3.ZERO
			var q := g.basis.get_rotation_quaternion()
			print("%-22s pos=(%.2f, %.2f, %.2f) dir=(%.2f, %.2f, %.2f) rot=(%.2f, %.2f, %.2f, %.2f)" % [o.trim_prefix("mixamorig_"), g.origin.x, g.origin.y, g.origin.z, dir.x, dir.y, dir.z, q.x, q.y, q.z, q.w])
	quit()

func _achar(n: Node) -> Node:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _achar(c)
		if r: return r
	return null
