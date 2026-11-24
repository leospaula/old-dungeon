extends Node3D
## Cena de exploração: masmorra base + Tessa tocando a biblioteca de animações.
## Teclas 1–0 trocam a animação; F centraliza a câmera na Tessa.
## M alterna modo mestre (sem escuridão) · G alterna a grade de combate.
## Linha de comando: -- --captura=arquivo.png salva uma imagem e fecha (para conferência).

const Luz = preload("res://scripts/visual/luz.gd")

const ANIMACOES := ["parado-espada-escudo", "parado", "andar", "comecar-a-andar", "golpe", "levar-golpe", "morrer", "vitoria", "sacar-flecha", "magia"]
@onready var tessa: Node3D = $Tessa
@onready var camera: Camera3D = $Camera
@onready var legenda: Label = $HUD/Legenda
var player: AnimationPlayer
var luz: Node
var mestre := false
var combate := false

func _ready() -> void:
	player = _achar_player(tessa)
	$Sol.visible = false
	luz = Luz.new(); add_child(luz)
	luz.configurar(self, $Masmorra, $Ambiente, tessa)
	luz.tochas_automaticas(self, "res://data/masmorra/layout.json", ["24", "23", "21", "22", "15", "20", "14", "10", "12"], 2)
	_tocar(0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--captura="):
			camera.alvo = tessa.global_position + Vector3(0, 0.8, 0); camera.distancia = 7.0; camera.inclinacao = 48.0; camera.guinada = -40.0
			if a.contains("baixa"): camera.distancia = 5.5; camera.inclinacao = 26.0; camera.guinada = -140.0
			if a.contains("grade"): combate = true; luz.set_grade(true)
			if a.contains("mestre"): mestre = true; luz.set_mestre(true); camera.distancia = 40.0; camera.inclinacao = 55.0; camera.alvo = Vector3(30, 0, 18)
			for _f in 45: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(a.trim_prefix("--captura="))
			get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode >= KEY_1 and e.keycode <= KEY_9: _tocar(e.keycode - KEY_1)
		elif e.keycode == KEY_0: _tocar(9)
		elif e.keycode == KEY_F: camera.alvo = tessa.global_position; camera.distancia = 14.0
		elif e.keycode == KEY_M: mestre = not mestre; luz.set_mestre(mestre); _tocar_legenda()
		elif e.keycode == KEY_G: combate = not combate; luz.set_grade(combate); _tocar_legenda()

var _anim := 0

func _tocar(i: int) -> void:
	if player == null or i >= ANIMACOES.size(): return
	_anim = i
	player.play(ANIMACOES[i])
	_tocar_legenda()

func _tocar_legenda() -> void:
	legenda.text = "Masmorra Base · Tessa: %s · %s · %s\n1–0 animações · botão direito/Q/E gira · roda aproxima · WASD move · F foca · M modo mestre · G grade de combate" % [ANIMACOES[_anim], "modo mestre" if mestre else "luz da tocha", "grade de combate" if combate else "exploração"]

func _achar_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var p := _achar_player(c)
		if p: return p
	return null
