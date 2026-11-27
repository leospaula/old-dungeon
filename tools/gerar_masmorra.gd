extends SceneTree
## Gera a masmorra 3D (voxel) a partir da planta (data/masmorra/layout.json).
## Uso: godot --path . --script tools/gerar_masmorra.gd -- <layout.json> <saida.scn> [pasta_renders] [exportar.glb]
##
## Convenções: 1 célula = 1,5 m; x da grade → X, y da grade → Z; chão em Y = 0.
## Rocha = blocos sólidos (só os que encostam em chão). Paredes finas separam áreas vizinhas,
## exceto nas aberturas; portas ficam no vão da parede.

const CEL := 1.5
const ALT := 3.0
const ESP := 0.3
const COR_CHAO := {"sala": Color(0.47, 0.44, 0.39), "corredor": Color(0.42, 0.40, 0.36), "cela": Color(0.36, 0.34, 0.31),
	"prisao": Color(0.40, 0.38, 0.34), "caverna": Color(0.38, 0.32, 0.25), "mina": Color(0.42, 0.35, 0.27)}
const COR_ROCHA := Color(0.33, 0.33, 0.35)
const COR_PAREDE := Color(0.42, 0.41, 0.40)
const COR_MADEIRA := Color(0.45, 0.29, 0.15)
const COR_FERRO := Color(0.22, 0.23, 0.25)
const COR_ESTEIRA := Color(0.42, 0.36, 0.28)
const COR_CRISTAL := Color(0.45, 0.75, 1.0)

var L: Dictionary
var W: int
var H: int
var cel := []           # id da área por célula (ou "")
var tipos := {}
var abertas := {}       # "a|b" -> "hv"
var portas_borda := {}  # "v:x:y" / "h:x:y" -> porta
var rnd := RandomNumberGenerator.new()

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	L = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	rnd.seed = 42
	W = int(L.grade.largura); H = int(L.grade.altura)
	for y in H:
		var linha := []; linha.resize(W); linha.fill("")
		cel.append(linha)
	for ar in L.areas:
		tipos[ar.id] = ar.tipo
		for r in ar.retangulos:
			for y in range(int(r[1]), int(r[3])):
				for x in range(int(r[0]), int(r[2])):
					cel[y][x] = ar.id
	for p in L.aberturas:
		var par: Array = p if p is Array else p.entre
		var bordas: String = "hv" if p is Array else p.get("bordas", "hv")
		abertas[_par(par[0], par[1])] = bordas
	for pt in L.portas:
		for k in int(pt.largura):
			var chave := "v:%d:%d" % [pt.x, pt.y + k] if pt.orient == "v" else "h:%d:%d" % [pt.x + k, pt.y]
			portas_borda[chave] = pt

	var raiz := Node3D.new(); raiz.name = "MasmorraBase"
	var chao := {}; var rocha := {}; var paredes := {}; var madeira := _St.new()
	var ferro := _St.new(); var esteira := _St.new(); var cristal := _St.new()

	# Chão
	for y in H:
		for x in W:
			var id: String = cel[y][x]
			if id == "": continue
			var c: Color = COR_CHAO.get(tipos[id], Color(0.6, 0.6, 0.6))
			c = c.lightened(rnd.randf_range(-0.06, 0.06)) if rnd.randf() < 0.5 else c.darkened(rnd.randf_range(0, 0.08))
			_bloco(chao, x, y).caixa(Vector3(x * CEL, -0.25, y * CEL), Vector3((x + 1) * CEL, 0.0, (y + 1) * CEL), c)

	# Rocha: blocos que encostam em chão (8 vizinhos). Perto de caverna, altura irregular.
	for y in range(-1, H + 1):
		for x in range(-1, W + 1):
			if _id(x, y) != "": continue
			var perto := false; var natural := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var v := _id(x + dx, y + dy)
					if v != "":
						perto = true
						if tipos[v] in ["caverna", "mina"]: natural = true
			var dentro := x >= 0 and y >= 0 and x < W and y < H
			if not perto and not dentro: continue
			var alt := ALT + (rnd.randf_range(-0.6, 0.9) if natural else rnd.randf_range(0.0, 0.15))
			var c := COR_ROCHA.lightened(rnd.randf_range(0.0, 0.1)) if not natural else Color(0.36, 0.31, 0.27).lightened(rnd.randf_range(0, 0.12))
			_bloco(rocha, x, y).caixa(Vector3(x * CEL, -0.25, y * CEL), Vector3((x + 1) * CEL, alt, (y + 1) * CEL), c)

	# Paredes finas entre áreas diferentes (bordas verticais e horizontais da grade)
	for y in H:
		for x in range(1, W):
			_borda("v", x, y, _id(x - 1, y), _id(x, y), paredes, madeira, ferro)
	for y in range(1, H):
		for x in W:
			_borda("h", x, y, _id(x, y - 1), _id(x, y), paredes, madeira, ferro)
	# Portas (uma peça por porta, não por célula)
	var portas := Node3D.new(); portas.name = "Portas"
	for pt in L.portas:
		_porta(pt, portas, paredes, ferro)

	# Esteiras
	for e in L.get("esteiras", []):
		var x0: float = e.coluna * CEL + 0.15; var x1: float = (e.coluna + 1) * CEL - 0.15
		esteira.caixa(Vector3(x0, 0.0, e.de_y * CEL), Vector3(x1, 0.55, e.ate_y * CEL), COR_ESTEIRA)
		var z: float = e.de_y * CEL
		while z < e.ate_y * CEL:
			esteira.caixa(Vector3(x0 - 0.05, 0.55, z), Vector3(x1 + 0.05, 0.62, z + 0.12), COR_FERRO)
			z += 0.5
	# Cristais na gruta 33
	for ar in L.areas:
		if ar.id != "33": continue
		for r in ar.retangulos:
			for i in 40:
				var cx := rnd.randf_range(r[0] + 0.5, r[2] - 0.5) * CEL
				var cz := rnd.randf_range(r[1] + 1.0, r[3] - 0.3) * CEL
				var t := rnd.randf_range(0.12, 0.3); var h := rnd.randf_range(0.4, 1.4)
				cristal.caixa(Vector3(cx - t, 0, cz - t), Vector3(cx + t, h, cz + t), COR_CRISTAL.lightened(rnd.randf_range(0, 0.25)))

	_instanciar_blocos(raiz, "Chao", chao)
	_instanciar_blocos(raiz, "Rocha", rocha)
	_instanciar_blocos(raiz, "Paredes", paredes)
	raiz.add_child(portas)
	_instanciar(raiz, "Ferro", ferro, false)
	_instanciar(raiz, "Esteiras", esteira, false)
	_instanciar(raiz, "Cristais", cristal, true)

	# Números das áreas (Label3D, só para conferência)
	var rotulos := Node3D.new(); rotulos.name = "Rotulos"; raiz.add_child(rotulos)
	for ar in L.areas:
		if ar.tipo == "cela" and (ar.id as String).begins_with("19c"): continue
		if ar.id in ["24p", "fenda34"]: continue
		var maior: Array = ar.retangulos[0]
		for r in ar.retangulos:
			if (r[2] - r[0]) * (r[3] - r[1]) > (maior[2] - maior[0]) * (maior[3] - maior[1]): maior = r
		var lb := Label3D.new(); lb.text = ar.id; lb.font_size = 160; lb.pixel_size = 0.01
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lb.outline_size = 30; lb.modulate = Color(1, 0.95, 0.75)
		lb.position = Vector3((maior[0] + maior[2]) / 2.0 * CEL, 1.2, (maior[1] + maior[3]) / 2.0 * CEL)
		rotulos.add_child(lb)

	for n in _todos(raiz):
		if n != raiz: n.owner = raiz
	var cena := PackedScene.new(); cena.pack(raiz)
	var err := ResourceSaver.save(cena, a[1])
	print("cena=%s erro=%d" % [a[1], err])

	if a.size() > 3:
		rotulos.visible = false
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		err = doc.append_from_scene(raiz, st)
		if err == OK: err = doc.write_to_filesystem(st, a[3])
		print("glb=%s erro=%d" % [a[3], err])
		rotulos.visible = true
	if a.size() > 2:
		await _renders(raiz, a[2])
	quit()

## No Compatibility (WebGL) cada malha recebe no máximo 8 luzes: dividir chão, rocha e paredes
## em blocos de BLOCO × BLOCO células faz cada pedaço receber só as tochas próximas.
const BLOCO := 8

func _bloco(d: Dictionary, x: int, y: int) -> _St:
	var k := Vector2i(floori(float(x) / BLOCO), floori(float(y) / BLOCO))
	if not d.has(k): d[k] = _St.new()
	return d[k]

func _instanciar_blocos(raiz: Node3D, nome: String, d: Dictionary) -> void:
	var pai := Node3D.new(); pai.name = nome; raiz.add_child(pai)
	for k in d:
		_instanciar(pai, "%s_%d_%d" % [nome, k.x, k.y], d[k], false)

func _par(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _id(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= W or y >= H: return ""
	return cel[y][x]

func _borda(eixo: String, x: int, y: int, a: String, b: String, paredes: Dictionary, madeira: _St, ferro: _St) -> void:
	if a == b or a == "" or b == "": return
	var ab := _par(a, b)
	if abertas.has(ab) and (abertas[ab] as String).contains(eixo): return
	if portas_borda.has("%s:%d:%d" % [eixo, x, y]): return
	var cela: bool = (tipos[a] == "cela" and b.begins_with("19")) or (tipos[b] == "cela" and a.begins_with("19"))
	var so_celas: bool = tipos[a] == "cela" and tipos[b] == "cela"
	if cela and not so_celas and (a == "19" or b == "19"):
		_grade(eixo, x, y, 1, ferro)
		return
	var p0: Vector3; var p1: Vector3
	if eixo == "v":
		p0 = Vector3(x * CEL - ESP / 2, 0, y * CEL - ESP / 2); p1 = Vector3(x * CEL + ESP / 2, ALT, (y + 1) * CEL + ESP / 2)
	else:
		p0 = Vector3(x * CEL - ESP / 2, 0, y * CEL - ESP / 2); p1 = Vector3((x + 1) * CEL + ESP / 2, ALT, y * CEL + ESP / 2)
	_bloco(paredes, x, y).caixa(p0, p1, COR_PAREDE.lightened(rnd.randf_range(-0.04, 0.06)))

func _grade(eixo: String, x: int, y: int, n: int, ferro: _St) -> void:
	var comp := n * CEL
	var passos := int(comp / 0.22)
	for i in passos + 1:
		var t := i * comp / passos
		var p := Vector3(x * CEL + (t if eixo == "h" else 0.0), 0, y * CEL + (t if eixo == "v" else 0.0))
		ferro.caixa(p - Vector3(0.04, 0, 0.04), p + Vector3(0.04, 2.6, 0.04), COR_FERRO)
	var a0 := Vector3(x * CEL, 0, y * CEL)
	var a1 := a0 + (Vector3(comp, 0, 0) if eixo == "h" else Vector3(0, 0, comp))
	for h in [0.1, 1.3, 2.55]:
		ferro.caixa(Vector3(minf(a0.x, a1.x) - 0.05, h, minf(a0.z, a1.z) - 0.05), Vector3(maxf(a0.x, a1.x) + 0.05, h + 0.08, maxf(a0.z, a1.z) + 0.05), COR_FERRO)

## Grade de cela: metade fixa ("Fixa") e uma folha com dobradiça na parede ("Folha1"), cada uma com
## uma caixa fina ("Malha") que o jogo troca pelo modelo do portão (arte/final/3d/portao.glb).
func _grade_pecas(pt: Dictionary, no: Node3D) -> void:
	var comp := int(pt.largura) * CEL
	var base := Vector3(pt.x * CEL, 0, pt.y * CEL)
	var eixo := Vector3(0, 0, 1) if pt.orient == "v" else Vector3(1, 0, 0)
	var lado := Vector3(1, 0, 0) if pt.orient == "v" else Vector3(0, 0, 1)
	var partes := [["Fixa", 0.0, comp / 2.0, 0.0], ["Folha1", comp / 2.0, comp, comp]] if int(pt.largura) > 1 else [["Folha1", 0.0, comp, comp]]
	for p in partes:
		var i0: float = p[1] + 0.03; var i1: float = p[2] - 0.03; var dob: float = p[3]
		var piv := Node3D.new(); piv.name = p[0]; piv.position = base + eixo * dob; no.add_child(piv)
		var st := _St.new()
		var a := -lado * 0.05 + eixo * (i0 - dob); var b := lado * 0.05 + Vector3(0, 2.6, 0) + eixo * (i1 - dob)
		st.caixa(Vector3(minf(a.x, b.x), 0, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), 2.6, maxf(a.z, b.z)), COR_FERRO)
		_instanciar(piv, "Malha", st, false)

## Cada porta de madeira vira um nó próprio (Portas/P01…) com uma dobradiça por folha,
## para o jogo poder abri-la. A verga de pedra vai junto com as paredes.
func _porta(pt: Dictionary, portas: Node3D, paredes: Dictionary, ferro: _St) -> void:
	var n := int(pt.largura)
	var no := Node3D.new(); no.name = pt.id; portas.add_child(no)
	no.set_meta("orient", pt.orient); no.set_meta("tipo", pt.tipo)
	if pt.tipo in ["grade", "cela"]:
		_grade_pecas(pt, no)
		return
	var folhas := 2 if pt.tipo == "dupla" else 1
	var comp := n * CEL
	var base := Vector3(pt.x * CEL, 0, pt.y * CEL)
	var eixo := Vector3(0, 0, 1) if pt.orient == "v" else Vector3(1, 0, 0)
	var lado := Vector3(1, 0, 0) if pt.orient == "v" else Vector3(0, 0, 1)
	for f in folhas:
		var i0 := comp * f / folhas + 0.06; var i1 := comp * (f + 1) / folhas - 0.06
		var dobradica := i0 if f == 0 else i1
		var sentido := 1.0 if f == 0 else -1.0
		var piv := Node3D.new(); piv.name = "Folha%d" % f; piv.position = base + eixo * dobradica; no.add_child(piv)
		var st := _St.new()
		var a := -lado * 0.08; var b := lado * 0.08 + Vector3(0, 2.4, 0) + eixo * (i1 - i0) * sentido
		st.caixa(Vector3(minf(a.x, b.x), 0, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), 2.4, maxf(a.z, b.z)), COR_MADEIRA.lightened(rnd.randf_range(0, 0.08)))
		_instanciar(piv, "Malha", st, false)
	# Verga de pedra por cima do vão
	var v0: Vector3; var v1: Vector3
	if pt.orient == "v":
		v0 = Vector3(pt.x * CEL - ESP / 2, 2.4, pt.y * CEL); v1 = Vector3(pt.x * CEL + ESP / 2, ALT, pt.y * CEL + comp)
	else:
		v0 = Vector3(pt.x * CEL, 2.4, pt.y * CEL - ESP / 2); v1 = Vector3(pt.x * CEL + comp, ALT, pt.y * CEL + ESP / 2)
	_bloco(paredes, int(pt.x), int(pt.y)).caixa(v0, v1, COR_PAREDE)

func _instanciar(raiz: Node3D, nome: String, st: _St, brilho: bool) -> void:
	if st.vazio(): return
	var mi := MeshInstance3D.new(); mi.name = nome
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if brilho:
		mat.emission_enabled = true; mat.emission = COR_CRISTAL; mat.emission_energy_multiplier = 0.6
	mi.mesh = st.malha(mat)
	raiz.add_child(mi)

func _todos(n: Node) -> Array:
	var out := [n]
	for c in n.get_children(): out.append_array(_todos(c))
	return out

func _renders(raiz: Node3D, pasta: String) -> void:
	DirAccess.make_dir_recursive_absolute(pasta)
	var vp := SubViewport.new(); vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp); vp.add_child(raiz)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.9, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.35; vp.add_child(env)
	var sol := DirectionalLight3D.new(); sol.rotation_degrees = Vector3(-55, -35, 0); sol.light_energy = 1.1; sol.shadow_enabled = true
	vp.add_child(sol)
	var cam := Camera3D.new(); vp.add_child(cam); cam.current = true
	var cx := W * CEL / 2.0; var cz := H * CEL / 2.0
	var vistas := [
		["topo", Vector2i(1860, 1140), true, Vector3(cx, 80, cz + 0.01), Vector3(cx, 0, cz), 0.0],
		["perspectiva", Vector2i(1600, 900), false, Vector3(cx - 10, 62, cz + 70), Vector3(cx, 0, cz + 2), 40.0],
		["centro-e-prisao", Vector2i(1600, 900), false, Vector3(30, 26, 62), Vector3(30, 0, 36), 50.0],
		["salao-esteiras", Vector2i(1600, 900), false, Vector3(70, 22, 58), Vector3(80, 0, 30), 55.0],
	]
	for v in vistas:
		vp.size = v[1]
		if v[2]:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = H * CEL + 4
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE; cam.fov = v[5]
		cam.position = v[3]; cam.look_at(v[4], Vector3.FORWARD if v[2] else Vector3.UP)
		for _f in 4: await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(pasta.path_join(v[0] + ".png"))
		print("render ", v[0])

## Acumulador de caixas com cor por vértice.
class _St:
	var st := SurfaceTool.new()
	var n := 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	func vazio() -> bool:
		return n == 0
	func caixa(a: Vector3, b: Vector3, c: Color) -> void:
		n += 1
		var v := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
			Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
		var faces := [[4, 5, 6, 7, Vector3.UP, 1.0], [0, 3, 2, 1, Vector3.DOWN, 0.5], [0, 1, 5, 4, Vector3.FORWARD, 0.8],
			[2, 3, 7, 6, Vector3.BACK, 0.8], [1, 2, 6, 5, Vector3.RIGHT, 0.7], [3, 0, 4, 7, Vector3.LEFT, 0.7]]
		for f in faces:
			var cor := c * Color(f[5], f[5], f[5], 1.0)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(cor); st.set_normal(f[4]); st.add_vertex(v[f[idx]])
	func malha(mat: Material) -> ArrayMesh:
		st.set_material(mat)
		return st.commit()
