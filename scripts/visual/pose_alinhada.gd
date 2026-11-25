extends Node3D
## Item que muda de orientação só numa animação (azagaia: ponta para a frente no arremesso). Fora dela
## fica na pegada natural do punho; a troca é suave.

var ap: AnimationPlayer
var anim := ""
var natural := Basis()
var alinhada := Basis()
var _peso := 0.0

func _process(dt: float) -> void:
	if ap == null: return
	var alvo := 1.0 if String(ap.assigned_animation) == anim and ap.is_playing() else 0.0
	_peso = move_toward(_peso, alvo, dt * 6.0)
	transform.basis = Basis(natural.get_rotation_quaternion().slerp(alinhada.get_rotation_quaternion(), _peso))
