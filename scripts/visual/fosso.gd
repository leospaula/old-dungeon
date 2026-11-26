extends Node3D
## Fosso de armadilha numa casa: buraco de pedra (o chão em cima é cortado pelo shader do chão,
## uniform `buracos`) tapado por um alçapão de duas folhas com a mesma laje do piso. Escondido, é
## igual ao resto do chão. Ao disparar, as folhas giram para baixo e ficam abertas.
## A regra é a do B/X (3 m, 1d6); o buraco desenhado tem PROF m para o personagem lá dentro aparecer.

const CEL := 1.5
const PROF := 2.4
const ESP := 0.06            # espessura das folhas do alçapão
const RECUO := 0.02          # paredes do buraco um pouco para dentro (não brigam com a lateral do piso)

var celula := Vector2i.ZERO
var aberto := false
var _folhas: Array[Node3D] = []

## cor_chao: matiz do tipo de área (a mesma do gerador da masmorra).
func montar(c: Vector2i, chao_mat: ShaderMaterial, tampa_mat: ShaderMaterial, pedra_mat: ShaderMaterial, cor_chao: Color) -> void:
	celula = c
	# A laje da casa continua lá para a sombra (o shader só a apaga na tela): dentro do buraco, sem sombra.
	var parede_m := _padrao(pedra_mat, Color(0.62, 0.6, 0.58), 0.42)
	var fundo_m := _padrao(chao_mat, cor_chao.lightened(0.2), 0.33)
	position = Vector3(c.x * CEL, 0, c.y * CEL)
	var a := RECUO; var b := CEL - RECUO
	# Paredes (viradas para dentro) e fundo.
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.36, 0.35, 0.34))
	_quad(st, Vector3(a, 0, a), Vector3(b, 0, a), Vector3(b, -PROF, a), Vector3(a, -PROF, a), Vector3(0, 0, 1))
	_quad(st, Vector3(b, 0, b), Vector3(a, 0, b), Vector3(a, -PROF, b), Vector3(b, -PROF, b), Vector3(0, 0, -1))
	_quad(st, Vector3(a, 0, b), Vector3(a, 0, a), Vector3(a, -PROF, a), Vector3(a, -PROF, b), Vector3(1, 0, 0))
	_quad(st, Vector3(b, 0, a), Vector3(b, 0, b), Vector3(b, -PROF, b), Vector3(b, -PROF, a), Vector3(-1, 0, 0))
	var paredes := MeshInstance3D.new(); paredes.mesh = st.commit(); paredes.material_override = parede_m
	add_child(paredes)
	var sf := SurfaceTool.new(); sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	sf.set_color(cor_chao.darkened(0.35))
	_quad(sf, Vector3(a, -PROF, a), Vector3(b, -PROF, a), Vector3(b, -PROF, b), Vector3(a, -PROF, b), Vector3(0, 1, 0))
	var fundo := MeshInstance3D.new(); fundo.mesh = sf.commit(); fundo.material_override = fundo_m
	add_child(fundo)
	# Alçapão: duas folhas, cada uma presa na borda de fora (eixo z), abrindo para baixo.
	for lado in [0, 1]:
		var piv := Node3D.new(); piv.position = Vector3(0.0 if lado == 0 else CEL, 0, 0)
		add_child(piv)
		var sl := SurfaceTool.new(); sl.begin(Mesh.PRIMITIVE_TRIANGLES); sl.set_color(cor_chao)
		var x0 := 0.0 if lado == 0 else -CEL / 2; var x1 := CEL / 2 if lado == 0 else 0.0
		_caixa(sl, Vector3(x0, -ESP, 0), Vector3(x1, 0, CEL))
		var f := MeshInstance3D.new(); f.mesh = sl.commit(); f.material_override = tampa_mat
		piv.add_child(f)
		_folhas.append(piv)

## Dispara: as folhas giram para baixo (presas na borda) e o buraco fica à mostra.
func abrir(animado := true) -> void:
	if aberto: return
	aberto = true
	for i in _folhas.size():
		var ang := -PI * 0.5 if i == 0 else PI * 0.5
		if animado:
			var t := create_tween()
			t.tween_property(_folhas[i], "rotation:z", ang * 1.08, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(_folhas[i], "rotation:z", ang, 0.25).set_trans(Tween.TRANS_SINE)
		else:
			_folhas[i].rotation.z = ang

## Dentro do buraco os shaders da masmorra saem escuros demais: material padrão com a mesma textura
## projetada no mundo (triplanar) e o relevo.
static func _padrao(m: ShaderMaterial, cor: Color, escala: float) -> StandardMaterial3D:
	var d := StandardMaterial3D.new()
	d.albedo_texture = m.get_shader_parameter("cor_tex"); d.albedo_color = cor
	d.normal_enabled = true; d.normal_texture = m.get_shader_parameter("normal_tex"); d.normal_scale = 1.2
	d.uv1_triplanar = true; d.uv1_world_triplanar = true; d.uv1_scale = Vector3.ONE * escala
	d.roughness = 0.92
	return d

func fundo_y() -> float:
	return -PROF

func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	# Ordem dos vértices ajustada para a face apontar para n (cull_back).
	var ordem := [p0, p1, p2, p0, p2, p3]
	if (p1 - p0).cross(p2 - p0).dot(n) > 0: ordem = [p0, p2, p1, p0, p3, p2]
	for p in ordem:
		st.set_normal(n); st.add_vertex(p)

func _caixa(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	_quad(st, Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(0, 1, 0))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z), Vector3(0, -1, 0))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z), Vector3(0, 0, -1))
	_quad(st, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(0, 0, 1))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z), Vector3(-1, 0, 0))
	_quad(st, Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(1, 0, 0))
