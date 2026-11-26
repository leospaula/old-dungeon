extends SceneTree
## Mede a caixa (AABB) de cada .glb: altura, largura, profundidade em metros, sem escala.
## Uso: godot --headless --path . --script tools/medir_glb.gd -- a.glb b.glb ...
func _init() -> void:
	for f in OS.get_cmdline_user_args():
		var n: Node3D = load(f).instantiate()
		root.add_child(n)
		var box := AABB(); var primeiro := true
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if primeiro else box.merge(b); primeiro = false
		print("%s alt=%.2f larg=%.2f prof=%.2f" % [f.get_file(), box.size.y, box.size.x, box.size.z])
		n.queue_free()
	quit()
