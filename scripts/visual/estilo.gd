extends RefCounted
## Aplica o estilo "tinta e aquarela + diorama" numa cena: materiais da masmorra, personagens,
## mesa, bases de miniatura e grão de papel. Devolve os materiais para atualizar a tocha.

static func aplicar(raiz: Node3D, masmorra: Node3D, personagens: Array) -> Array:
	var mats := []
	var novo := func(caminho: String) -> ShaderMaterial:
		var m := ShaderMaterial.new(); m.shader = load(caminho); mats.append(m); return m
	var contorno := func(m: ShaderMaterial, largura: float) -> ShaderMaterial:
		var c := ShaderMaterial.new(); c.shader = load("res://shaders/contorno.gdshader"); c.set_shader_parameter("largura", largura)
		m.next_pass = c; return m
	masmorra.get_node("Chao").material_override = novo.call("res://shaders/chao.gdshader")
	masmorra.get_node("Rocha").material_override = contorno.call(novo.call("res://shaders/pedra.gdshader"), 0.06)
	masmorra.get_node("Paredes").material_override = contorno.call(novo.call("res://shaders/pedra.gdshader"), 0.05)
	for nome in ["Portas", "Ferro", "Esteiras"]:
		masmorra.get_node(nome).material_override = contorno.call(novo.call("res://shaders/objeto.gdshader"), 0.03)
	var cr: ShaderMaterial = novo.call("res://shaders/objeto.gdshader"); cr.set_shader_parameter("brilho", 0.6); cr.set_shader_parameter("satura", 1.0)
	masmorra.get_node("Cristais").material_override = cr
	if masmorra.has_node("Rotulos"): masmorra.get_node("Rotulos").visible = false
	for p in personagens:
		for mi in _malhas(p):
			for s in mi.mesh.get_surface_count():
				var orig: Material = mi.get_active_material(s)
				var m: ShaderMaterial = novo.call("res://shaders/objeto.gdshader")
				if orig is StandardMaterial3D and orig.albedo_texture:
					m.set_shader_parameter("tex", orig.albedo_texture); m.set_shader_parameter("usa_tex", true)
				mi.set_surface_override_material(s, contorno.call(m, 0.012))
		var base := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.5; cm.bottom_radius = 0.55; cm.height = 0.08
		var mb := StandardMaterial3D.new(); mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mb.albedo_color = Color(0.10, 0.12, 0.08)
		base.mesh = cm; base.material_override = mb; base.position = Vector3(0, 0.04, 0); p.add_child(base)
	# Mesa de madeira
	var mesa := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(260, 180); mesa.mesh = pm
	var sm := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying vec3 w;\nfloat h(float p) { return fract(sin(p * 91.7) * 43758.5453); }\nvoid vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\nvoid fragment() {\n\tfloat t = floor(w.z / 2.2);\n\tfloat veio = sin(w.x * 1.7 + sin(w.z * 0.9 + t) * 2.0 + h(t) * 6.0) * 0.5 + 0.5;\n\tvec3 c = mix(vec3(0.20, 0.12, 0.06), vec3(0.32, 0.20, 0.10), veio * 0.6 + h(t) * 0.4);\n\tif (fract(w.z / 2.2) < 0.02) c *= 0.5;\n\tALBEDO = c * mix(1.0, 0.35, smoothstep(40.0, 110.0, distance(w.xz, vec2(46.0, 29.0))));\n}"
	sm.shader = sh; mesa.material_override = sm; mesa.position = Vector3(46, -0.3, 28); raiz.add_child(mesa)
	# Grão de papel por cima da tela
	var tela := CanvasLayer.new(); tela.layer = 0; raiz.add_child(tela)
	var papel := ColorRect.new(); papel.set_anchors_preset(Control.PRESET_FULL_RECT); papel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm2 := ShaderMaterial.new(); pm2.shader = load("res://shaders/papel_tela.gdshader"); papel.material = pm2
	tela.add_child(papel)
	return mats

static func _malhas(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh: out.append(n)
	for c in n.get_children(): out.append_array(_malhas(c))
	return out
