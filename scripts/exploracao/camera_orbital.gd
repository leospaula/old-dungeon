extends Camera3D
## Câmera de mesa: gira em volta de um ponto, aproxima e se move pelo mapa.
## Botão direito (ou Q/E) gira · roda do mouse aproxima · WASD ou botão do meio move · F centraliza na Tessa.

@export var alvo := Vector3(45, 0, 28)
@export var distancia := 38.0
@export var guinada := -30.0   # graus em volta do eixo Y
@export var inclinacao := 55.0 # graus acima do chão
var _girando := false
var _movendo := false

func _ready() -> void:
	_aplicar()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT: _girando = e.pressed
		elif e.button_index == MOUSE_BUTTON_MIDDLE: _movendo = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: distancia = maxf(4.0, distancia * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: distancia = minf(120.0, distancia * 1.1)
	elif e is InputEventMouseMotion:
		if _girando:
			guinada -= e.relative.x * 0.3
			inclinacao = clampf(inclinacao + e.relative.y * 0.3, 15.0, 89.0)
		elif _movendo:
			_mover(Vector2(-e.relative.x, -e.relative.y) * distancia * 0.0025)
	_aplicar()

func _process(dt: float) -> void:
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_S): v.y += 1
	if Input.is_key_pressed(KEY_Q): guinada += 60 * dt
	if Input.is_key_pressed(KEY_E): guinada -= 60 * dt
	if v != Vector2.ZERO: _mover(v * distancia * 0.8 * dt)
	_aplicar()

func _mover(d: Vector2) -> void:
	var r := deg_to_rad(guinada)
	var direita := Vector3(cos(r), 0, -sin(r))
	var frente := Vector3(-sin(r), 0, -cos(r))
	alvo += direita * d.x - frente * d.y

func _aplicar() -> void:
	var r := deg_to_rad(guinada); var i := deg_to_rad(inclinacao)
	position = alvo + Vector3(sin(r) * cos(i), sin(i), cos(r) * cos(i)) * distancia
	look_at(alvo)
