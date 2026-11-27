extends Node3D
## Dado 3D desenhado pelo jogo (d4, d6, d8, d10, d12, d20), com números nas faces. O resultado já vem
## decidido (o jogo rola o número como sempre); o dado só encena: aparece, dá um pulinho, gira rápido
## perdendo velocidade e assenta com a face sorteada virada para a câmera, com o número de pé.
##
## As faces saem da própria geometria (casca convexa dos vértices), e a numeração segue a dos dados reais:
## faces opostas somam lados + 1 (no d4, de 1 a 4).
##
## Uso: var d := Dado3D.novo(20, "osso"); pai.add_child(d); d.global_position = …; await d.rolar(17, camera)

const MATERIAIS := {
	# osso envelhecido com números em tinta escura
	"osso": {"corpo": Color(0.86, 0.79, 0.64), "rugosidade": 0.55, "metal": 0.0, "numero": Color(0.16, 0.09, 0.05), "contorno": Color(0.95, 0.9, 0.78, 0.0), "brilho": 0.42},
	# ferro escuro com números dourados
	"ferro": {"corpo": Color(0.34, 0.31, 0.29), "rugosidade": 0.38, "metal": 0.7, "numero": Color(0.95, 0.77, 0.42), "contorno": Color(0.1, 0.06, 0.02, 0.9), "brilho": 0.3},
}

const INCLINAR := Vector2(-20.0, 16.0)   # graus: a face parada vira um pouco para cima e para o lado
var lados := 20
var estilo := "osso"
var raio := 0.16                 # m (do centro aos vértices)
var _faces: Array = []           # [{normal, centro, cima, numero, label}]
var _corpo: MeshInstance3D

static func novo(n_lados: int, estilo_ := "osso", raio_ := 0.16) -> Node3D:
	var d: Node3D = load("res://scripts/visual/dado3d.gd").new()
	d.lados = n_lados; d.estilo = estilo_; d.raio = raio_
	return d

func _ready() -> void:
	_montar()

# ---------- geometria ----------

static func vertices(n: int) -> Array[Vector3]:
	var v: Array[Vector3] = []
	var f := (1.0 + sqrt(5.0)) / 2.0
	match n:
		4:
			for p in [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]: v.append(p)
		6:
			for x in [-1, 1]: for y in [-1, 1]: for z in [-1, 1]: v.append(Vector3(x, y, z))
		8:
			for p in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]: v.append(p)
		10:   # trapezoedro pentagonal: pipas planas com a ponta a e·(1+cos36)/(1−cos36)
			var e := 0.105
			var h := e * (1.0 + cos(deg_to_rad(36.0))) / (1.0 - cos(deg_to_rad(36.0)))
			v.append(Vector3(0, h, 0)); v.append(Vector3(0, -h, 0))
			for k in 5:
				var a := deg_to_rad(72.0 * k); var b := deg_to_rad(72.0 * k + 36.0)
				v.append(Vector3(cos(a), e, sin(a))); v.append(Vector3(cos(b), -e, sin(b)))
		12:
			for x in [-1, 1]: for y in [-1, 1]: for z in [-1, 1]: v.append(Vector3(x, y, z))
			for a in [-1, 1]:
				for b in [-1, 1]:
					v.append(Vector3(0, a / f, b * f)); v.append(Vector3(a / f, b * f, 0)); v.append(Vector3(a * f, 0, b / f))
		_:   # 20
			for a in [-1, 1]:
				for b in [-1, 1]:
					v.append(Vector3(0, a, b * f)); v.append(Vector3(a, b * f, 0)); v.append(Vector3(a * f, 0, b))
	var m := 0.0
	for p in v: m = maxf(m, p.length())
	for i in v.size(): v[i] /= m
	return v

## Faces da casca convexa: cada plano que deixa todos os vértices de um lado; os vértices dele em volta.
static func faces(v: Array[Vector3]) -> Array:
	var out: Array = []; var vistos := {}
	for i in v.size():
		for j in range(i + 1, v.size()):
			for k in range(j + 1, v.size()):
				var n := (v[j] - v[i]).cross(v[k] - v[i])
				if n.length() < 1e-6: continue
				n = n.normalized()
				if n.dot(v[i]) < 0: n = -n
				var d := n.dot(v[i])
				var fora := false; var no_plano: Array = []
				for q in v.size():
					var s := n.dot(v[q]) - d
					if s > 1e-4: fora = true; break
					if absf(s) <= 1e-4: no_plano.append(q)
				if fora: continue
				no_plano.sort()
				var chave := str(no_plano)
				if vistos.has(chave): continue
				vistos[chave] = true
				var c := Vector3.ZERO
				for q in no_plano: c += v[q]
				c /= no_plano.size()
				var ref := (v[no_plano[0]] - c).normalized(); var ref2 := n.cross(ref)
				no_plano.sort_custom(func(a, b): return atan2((v[a] - c).dot(ref2), (v[a] - c).dot(ref)) < atan2((v[b] - c).dot(ref2), (v[b] - c).dot(ref)))
				out.append({"normal": n, "centro": c, "vertices": no_plano})
	return out

## Números: faces opostas somam lados + 1 (d4: 1 a 4 na ordem).
static func numerar(fs: Array, n: int) -> void:
	var livres := fs.duplicate()
	var proximo := 1
	livres.sort_custom(func(a, b): return a.normal.y > b.normal.y if absf(a.normal.y - b.normal.y) > 0.01 else a.normal.x > b.normal.x)
	while not livres.is_empty():
		var f: Dictionary = livres.pop_front()
		if f.has("numero"): continue
		f.numero = proximo
		var oposta: Dictionary = {}
		for g in livres:
			if g.normal.dot(f.normal) < -0.99: oposta = g; break
		if not oposta.is_empty() and n != 4:
			oposta.numero = n + 1 - proximo; livres.erase(oposta)
		proximo += 1
		while fs.any(func(x): return x.get("numero", -1) == proximo): proximo += 1

func _montar() -> void:
	var v := vertices(lados)
	_faces = faces(v)
	numerar(_faces, lados)
	var m: Dictionary = MATERIAIS.get(estilo, MATERIAIS.osso)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in _faces:
		var vs: Array = f.vertices
		for t in range(1, vs.size() - 1):
			for q in [vs[0], vs[t], vs[t + 1]]:
				st.set_normal(f.normal); st.add_vertex(v[q] * raio)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = m.corpo; mat.roughness = m.rugosidade; mat.metallic = m.metal
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Luz própria fraca: o dado é um aviso para o jogador e precisa ser lido mesmo no escuro da masmorra.
	mat.emission_enabled = true; mat.emission = m.corpo; mat.emission_energy_multiplier = float(m.brilho)
	mesh.surface_set_material(0, mat)
	_corpo = MeshInstance3D.new(); _corpo.mesh = mesh; _corpo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_corpo)
	# Números: Label3D deitado em cada face, um pouco à frente dela.
	var tam: float = {4: 0.55, 6: 0.62, 8: 0.5, 10: 0.42, 12: 0.42, 20: 0.34}.get(lados, 0.4)
	for f in _faces:
		var cima := _cima_da_face(f.normal)
		f.cima = cima
		var l := Label3D.new(); l.text = str(f.numero)
		if lados >= 10 and f.numero in [6, 9]: l.text += "."   # 6. e 9. como nos dados de verdade
		l.font_size = 64; l.pixel_size = raio * tam / 64.0
		l.modulate = m.numero; l.outline_size = 0 if m.contorno.a == 0.0 else 6; l.outline_modulate = m.contorno
		l.shaded = false; l.double_sided = false; l.render_priority = 2
		var x: Vector3 = cima.cross(f.normal).normalized()
		l.transform = Transform3D(Basis(x, cima, f.normal), f.centro * raio + f.normal * raio * 0.012)
		_corpo.add_child(l)
		f.label = l

## Direção "para cima" do número numa face: o eixo Y global projetado na face (ou Z, se a face é deitada).
func _cima_da_face(n: Vector3) -> Vector3:
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	return (ref - n * ref.dot(n)).normalized()

func _face(numero: int) -> Dictionary:
	for f in _faces:
		if int(f.numero) == numero: return f
	return _faces[0]

# ---------- rolagem ----------

## Rola até `resultado`: gira com velocidade que cai e, no fim, assenta com a face virada para a câmera.
## `cor`: brilho do número sorteado ao parar (dourado no máximo, vermelho no 1…). Devolve ao parar.
func rolar(resultado: int, camera: Camera3D, dur := 0.9, cor := Color(0, 0, 0, 0)) -> void:
	var f := _face(resultado)
	var eixo := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var giro := Quaternion(Vector3(randf(), randf(), randf()).normalized(), randf() * TAU)
	var vel := randf_range(16.0, 22.0)   # rad/s no começo
	var base_y := position.y
	var t := 0.0
	var assenta := dur * 0.62
	var q_assentar := Quaternion.IDENTITY
	while t < dur:
		var dt := get_process_delta_time()
		t += dt
		var k := t / dur
		position.y = base_y + sin(minf(k, 1.0) * PI) * raio * 1.6   # pulinho
		if t < assenta:
			giro = Quaternion(eixo, vel * dt * (1.0 - k)) * giro
			_corpo.quaternion = giro
			q_assentar = giro
		else:
			var alvo := _orientacao_final(f, camera)
			var u := clampf((t - assenta) / (dur - assenta), 0.0, 1.0)
			_corpo.quaternion = q_assentar.slerp(alvo, 1.0 - pow(1.0 - u, 3.0))
		await get_tree().process_frame
		if not is_instance_valid(self): return
	position.y = base_y
	_corpo.quaternion = _orientacao_final(f, camera)
	if cor.a > 0.0 and f.label:
		var l: Label3D = f.label
		l.modulate = cor; l.outline_size = 10; l.outline_modulate = Color(0.05, 0.02, 0.0, 0.85)

## Rotação que põe a face voltada para a câmera, com o "cima" do número no "cima" da tela.
func _orientacao_final(f: Dictionary, camera: Camera3D) -> Quaternion:
	var para_cam := (camera.global_position - global_position).normalized()
	var cima_tela := camera.global_transform.basis.y
	cima_tela = (cima_tela - para_cam * cima_tela.dot(para_cam)).normalized()
	var mundo := Basis(cima_tela.cross(para_cam), cima_tela, para_cam)
	# Um pouco inclinado (para cima e de lado): a face sorteada continua legível e o dado mostra volume.
	mundo = mundo * Basis(Vector3.RIGHT, deg_to_rad(INCLINAR.x)) * Basis(Vector3.UP, deg_to_rad(INCLINAR.y))
	var local := Basis(f.cima.cross(f.normal), f.cima, f.normal)
	var pai := global_transform.basis.orthonormalized()
	return (pai.inverse() * mundo * local.inverse()).get_rotation_quaternion()
