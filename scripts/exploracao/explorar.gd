extends Node3D
## Cena de exploração: masmorra base + Tessa tocando a biblioteca de animações.
## Teclas 1–0 trocam a animação; F centraliza a câmera na Tessa.
## Linha de comando: -- --captura=arquivo.png salva uma imagem e fecha (para conferência).

const ANIMACOES := ["parado-espada-escudo", "parado", "andar", "comecar-a-andar", "golpe", "levar-golpe", "morrer", "vitoria", "sacar-flecha", "magia"]
@onready var tessa: Node3D = $Tessa
@onready var camera: Camera3D = $Camera
@onready var legenda: Label = $HUD/Legenda
var player: AnimationPlayer

func _ready() -> void:
	player = _achar_player(tessa)
	_tocar(0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--captura="):
			camera.alvo = tessa.global_position; camera.distancia = 9.0; camera.inclinacao = 35.0
			for _f in 45: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(a.trim_prefix("--captura="))
			get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode >= KEY_1 and e.keycode <= KEY_9: _tocar(e.keycode - KEY_1)
		elif e.keycode == KEY_0: _tocar(9)
		elif e.keycode == KEY_F: camera.alvo = tessa.global_position; camera.distancia = 14.0

func _tocar(i: int) -> void:
	if player == null or i >= ANIMACOES.size(): return
	player.play(ANIMACOES[i])
	legenda.text = "Masmorra Base · Tessa: %s\n1–0 animações · botão direito/Q/E gira · roda aproxima · WASD move · F foca na Tessa" % ANIMACOES[i]

func _achar_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var p := _achar_player(c)
		if p: return p
	return null
