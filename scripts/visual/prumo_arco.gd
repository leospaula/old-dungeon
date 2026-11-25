extends Node3D
## Arco fora do disparo: a pose de espera gira o punho e deixaria o arco deitado. Aqui ele fica em pé,
## inclinado um pouco para a frente, girando em torno da empunhadura. No disparo vale a montagem
## (que já deixa o arco em pé na puxada).

const DISPARO := ["atirar-flecha"]
const INCLINA := 0.45          # rad: quanto a ponta de cima vai para a frente

var sk: Skeleton3D
var ap: AnimationPlayer
var frente := Vector3.ZERO     # frente da personagem em repouso (espaço do esqueleto)
var eixo_item := Vector3.UP    # eixo do comprimento do arco no espaço deste nó (com a rotação do item)
var base := Basis()
var _peso := 0.0

func _process(dt: float) -> void:
	if sk == null or not is_visible_in_tree(): return
	# Só na puxada (encaixe da flecha até a soltura) vale a montagem; antes e depois o arco fica em pé.
	var t := ap.current_animation_position if ap and ap.is_playing() else 0.0
	var atirando := ap != null and String(ap.assigned_animation) in DISPARO and t >= 1.3 and t <= 3.3
	_peso = move_toward(_peso, 0.0 if atirando else 1.0, dt * 5.0)
	if _peso <= 0.001:
		transform.basis = base; return
	var pai := get_parent() as Node3D
	var f: Vector3 = (sk.global_transform.basis * frente).normalized()
	var alvo_glob := (Vector3.UP * cos(INCLINA) + f * sin(INCLINA)).normalized()
	var alvo: Vector3 = (pai.global_transform.basis.inverse() * alvo_glob).normalized()
	var atual: Vector3 = (base * eixo_item).normalized()
	if atual.dot(alvo) < 0: alvo = -alvo
	transform.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(atual, alvo), _peso)) * base
