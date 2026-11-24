extends MeshInstance3D
## Marcações no chão da grade: alcance de movimento, caminho, alvo. Uma camada por instância.

const CEL := 1.5
var _im := ImmediateMesh.new()
var _celulas: Array = []   # [Vector2i, Color, margem]

func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func limpar() -> void:
	_celulas.clear(); _redesenhar()

func por(celulas: Array, cor: Color, margem := 0.06) -> void:
	for c in celulas: _celulas.append([c, cor, margem])
	_redesenhar()

func _redesenhar() -> void:
	_im.clear_surfaces()
	if _celulas.is_empty(): return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for item in _celulas:
		var c: Vector2i = item[0]; var cor: Color = item[1]; var mg: float = item[2]
		var a := Vector3(c.x * CEL + mg, 0.03, c.y * CEL + mg)
		var b := Vector3((c.x + 1) * CEL - mg, 0.03, (c.y + 1) * CEL - mg)
		var v := [a, Vector3(b.x, a.y, a.z), b, Vector3(a.x, a.y, b.z)]
		for i in [0, 1, 2, 0, 2, 3]:
			_im.surface_set_color(cor); _im.surface_add_vertex(v[i])
	_im.surface_end()
