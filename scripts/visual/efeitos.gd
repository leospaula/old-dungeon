extends RefCounted
## Efeitos de impacto do combate: congelar o quadro, texto flutuante (dano, "Bloqueou!"…) e o d20
## rolando sobre o atacante. Só visual; as regras ficam no combate.gd.

const FONTE_TAM := 64
const Sons = preload("res://scripts/visual/sons.gd")

## Congela o jogo por um instante (hit-stop). `dur` em segundos de tempo real.
static func congelar(no: Node, dur: float) -> void:
	Engine.time_scale = 0.02
	await no.get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0

## Texto que sobe e some acima de `pos`.
static func texto(pai: Node, pos: Vector3, txt: String, cor: Color, escala := 1.0, subir := 0.9, dur := 1.0) -> void:
	var l := Label3D.new()
	l.text = txt; l.modulate = cor; l.outline_modulate = Color(0.05, 0.02, 0.0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.render_priority = 10
	l.font_size = FONTE_TAM; l.outline_size = 14; l.pixel_size = 0.006
	pai.add_child(l); l.global_position = pos
	# Entra grande e assenta (pop), sobe e desaparece.
	l.scale = Vector3.ONE * escala * 1.7
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector3.ONE * escala, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "global_position", pos + Vector3(0, subir, 0), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, dur * 0.45).set_delay(dur * 0.55)
	t.tween_callback(l.queue_free)

## Dado 3D rolando sobre o ator (scripts/visual/dado3d.gd): gira, assenta com a face sorteada virada para a
## câmera e, ao parar, o resultado aparece ao lado (o número na face fica pequeno de longe). Cores: máximo
## dourado, 1 vermelho, verde se acerta/ganha, cinza se erra/perde. `lados`: d4…d20.
static var dados_ligados := true   # tecla D (explorar.gd): dados no combate e nos testes; o jogo de dados mostra sempre
## Dado do combate/testes: só aparece com os dados ligados.
static func dado_opcional(ator: Node3D, resultado: int, acerta: bool, dur := 0.5, lados := 20) -> void:
	if dados_ligados: dado(ator, resultado, acerta, dur, lados)
const ESTILO_DADO := "osso"   # "osso" (osso envelhecido, tinta escura) ou "ferro" (ferro escuro, ouro)
static func dado(ator: Node3D, resultado: int, acerta: bool, dur := 0.5, lados := 20) -> void:
	var cam := ator.get_viewport().get_camera_3d()
	var cor := Color(1.0, 0.82, 0.3) if resultado == lados else (Color(1, 0.4, 0.3) if resultado == 1 else (Color(0.55, 1.0, 0.55) if acerta else Color(0.7, 0.72, 0.76)))
	var alto: float = ator.rotulo.position.y + 0.55 if ator.get("rotulo") else 2.5
	var d: Node3D = load("res://scripts/visual/dado3d.gd").novo(lados, ESTILO_DADO, 0.21)
	ator.get_parent().add_child(d)
	d.global_position = ator.global_position + Vector3(0, alto, 0)
	if cam == null:
		d.queue_free(); return
	await d.rolar(resultado, cam, maxf(dur, 0.5) + 0.35, cor)
	if not is_instance_valid(d): return
	Sons.tocar("dado")
	# O resultado grande ao lado do dado, legível de longe.
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.render_priority = 9
	l.font_size = FONTE_TAM; l.outline_size = 14; l.pixel_size = 0.0055
	l.outline_modulate = Color(0.05, 0.02, 0.0, 0.9); l.modulate = cor; l.text = str(resultado)
	var lado := cam.global_transform.basis.x
	d.get_parent().add_child(l); l.global_position = d.global_position + lado * 0.4
	l.scale = Vector3.ONE * 1.4
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.0)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)
	var td := d.create_tween()
	td.tween_interval(1.1)
	td.tween_property(d, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	td.tween_callback(d.queue_free)

## Flecha voando de `de` até `para` (com um leve arco). Devolve ao chegar.
static func flecha(pai: Node, de: Vector3, para: Vector3, vel := 24.0) -> void:
	var raiz := Node3D.new(); pai.add_child(raiz)
	var haste := MeshInstance3D.new(); var cil := CylinderMesh.new()
	cil.top_radius = 0.012; cil.bottom_radius = 0.012; cil.height = 0.75; haste.mesh = cil
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.55, 0.4, 0.25); haste.material_override = m
	haste.rotation_degrees.x = 90; raiz.add_child(haste)
	var ponta := MeshInstance3D.new(); var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.03; cone.height = 0.09; ponta.mesh = cone
	var mp := StandardMaterial3D.new(); mp.albedo_color = Color(0.75, 0.75, 0.78); mp.metallic = 0.6; ponta.material_override = mp
	ponta.rotation_degrees.x = -90; ponta.position.z = -0.41; raiz.add_child(ponta)
	var dur := maxf(de.distance_to(para) / vel, 0.12)
	var arco := minf(de.distance_to(para) * 0.04, 0.8)
	var t0 := Time.get_ticks_msec()
	raiz.global_position = de
	while true:
		var t := clampf((Time.get_ticks_msec() - t0) / 1000.0 / dur, 0.0, 1.0)
		var pos := de.lerp(para, t) + Vector3(0, arco * 4.0 * t * (1.0 - t), 0)
		var prox := de.lerp(para, minf(t + 0.02, 1.0)) + Vector3(0, arco * 4.0 * minf(t + 0.02, 1.0) * (1.0 - minf(t + 0.02, 1.0)), 0)
		raiz.global_position = pos
		if prox.distance_to(pos) > 0.001: raiz.look_at(prox)
		if t >= 1.0: break
		await raiz.get_tree().process_frame
	raiz.queue_free()
