extends Node3D
## Quem anda e luta na grade: personagem do grupo ou monstro.
## Guarda a ficha de combate, anda célula a célula por um caminho e toca as animações.
## Modelos com AnimationPlayer (Tessa) usam a biblioteca de animações; modelos provisórios
## (goblin) usam movimentos simples por código.

signal passo_iniciado(de: Vector2i, para: Vector2i)
signal chegou(celula: Vector2i, metros: float)
signal parou


var grade: RefCounted
var nome := ""
var lado := "grupo"       # "grupo" ou "monstros"
var pv := 1
var pv_max := 1
var ca := 9
var thac0 := 19
var dano := "1d6"
var arma := "arma"
var mod_acerto := 0
var mod_dano := 0
var mov_combate_m := 12.0
var moral := 12
var xp := 0
var fugindo := false
var infravisao_m := 0.0
const VEL_BASE := 2.0     # m/s andando na tela (ritmo normal)
var velocidade := VEL_BASE
## Velocidade "natural" de cada animação de deslocamento no tamanho do jogo (m/s), medida com
## tools/medir_passada.gd (papel -> m/s). O ritmo das pernas acompanha a velocidade real para o pé
## não escorregar no chão. Papel sem medida = sem sincronia.
var passadas := {}
## Papel usado para se deslocar: "andar", "correr" ou "andar_furtivo" (segue o modo de movimento).
var papel_andar := "andar"
var celula := Vector2i.ZERO

var modelo: Node3D
var player: AnimationPlayer
var anim := {}            # papel -> nome da animação ("parado", "andar", "golpe", "dano", "morrer", "vitoria")
var frente := 0.0         # giro extra do nó (radianos) para o modelo olhar para +Z
## Correção por animação (graus): a importação deixou cada animação virada num ângulo diferente
## (ex.: "andar" de lado, 90°). O modelo gira o contrário para o corpo apontar para a frente do nó.
var giro_anim := {}
var em_combate := false   # parado em guarda e arma na mão só em combate
var armas_na_mao: Array[Node3D] = []
var rotulo: Label3D
var _caminho: Array[Vector2i] = []
var _de := Vector2i.ZERO
var _passo := 0.0         # tempo do balanço do modelo provisório

func vivo() -> bool:
	return pv > 0 and not fugindo

func andando() -> bool:
	return not _caminho.is_empty()

## Célula onde ele vai estar ao terminar o passo atual (para mudar de rumo sem cortar parede).
func proxima_celula() -> Vector2i:
	return _caminho[0] if andando() else celula

func colocar(c: Vector2i) -> void:
	celula = c; _de = c
	position = grade.centro(c)

func montar_modelo(m: Node3D, papeis: Dictionary, giro := 0.0) -> void:
	modelo = m; anim = papeis; frente = giro
	add_child(m)
	player = _achar_player(m)
	if player:
		for papel in ["parado", "parado_furtivo", "andar", "correr", "andar_furtivo", "andar_combate"]:
			if anim.has(papel) and player.has_animation(anim[papel]):
				player.get_animation(anim[papel]).loop_mode = Animation.LOOP_LINEAR
	rotulo = Label3D.new(); rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rotulo.font_size = 40
	rotulo.pixel_size = 0.006; rotulo.outline_size = 10; rotulo.no_depth_test = true
	rotulo.position = Vector3(0, 2.2 if lado == "grupo" else 1.6, 0); add_child(rotulo)
	atualizar_rotulo()
	tocar("parado")

func atualizar_rotulo() -> void:
	if rotulo == null: return
	var f := float(maxi(pv, 0)) / pv_max
	if lado == "grupo":
		rotulo.text = "%s  %d/%d" % [nome, maxi(pv, 0), pv_max]
	else:
		# Monstro: como na mesa, ninguém sabe os PV exatos, só o estado aparente.
		rotulo.text = "%s · %s" % [nome, "ileso" if f >= 1.0 else ("ferido" if f > 0.5 else "muito ferido")]
	rotulo.modulate = Color(1, 0.95, 0.85) if f > 0.5 else (Color(1, 0.75, 0.3) if f > 0.25 else Color(1, 0.4, 0.3))

## Saca (combate) ou guarda a arma (exploração).
func empunhar(sim: bool) -> void:
	em_combate = sim
	for a in armas_na_mao: a.visible = sim
	if not andando() and vivo(): tocar("parado")

func tocar(papel: String, misturar := 0.2) -> void:
	if papel == "parado":
		if em_combate and _tem("parado_combate"): papel = "parado_combate"
		elif papel_andar == "andar_furtivo" and _tem("parado_furtivo"): papel = "parado_furtivo"   # agachado
	if player and anim.has(papel) and player.has_animation(anim[papel]):
		player.play(anim[papel], misturar)
		player.speed_scale = _ritmo(papel)
		var giro := -deg_to_rad(float(giro_anim.get(anim[papel], 0.0)))
		if absf(modelo.rotation.y - giro) > 0.01:
			create_tween().tween_property(modelo, "rotation:y", giro, maxf(misturar, 0.05))

func _tem(papel: String) -> bool:
	return anim.has(papel) and player != null and player.has_animation(anim[papel])

## Em combate, o andar em guarda é mais curto: cada um anda no ritmo dele (passada × RITMO_COMBATE).
const RITMO_COMBATE := 1.8
func vel_atual() -> float:
	if em_combate and float(passadas.get("andar_combate", 0.0)) > 0.0 and _tem("andar_combate"):
		return float(passadas.andar_combate) * RITMO_COMBATE
	return velocidade

func _ritmo(papel: String) -> float:
	var p := float(passadas.get(papel, 0.0))
	return clampf(vel_atual() / p, 0.4, 2.8) if p > 0.0 else 1.0

## Papel de deslocamento: em combate, andar em guarda; fora dele, o do modo (cai para "andar").
func _papel_desloc() -> String:
	if em_combate and _tem("andar_combate"): return "andar_combate"
	return papel_andar if _tem(papel_andar) else "andar"

## Segue um caminho (lista de células, sem a atual).
func seguir(cam: Array[Vector2i]) -> void:
	if cam.is_empty(): return
	var estava := andando()
	_caminho = cam.duplicate()
	if not estava:
		_de = celula
		passo_iniciado.emit(_de, _caminho[0])
		tocar(_papel_desloc())

## Para na próxima célula (não fica entre duas).
func parar() -> void:
	if _caminho.size() > 1: _caminho.resize(1)

## Para onde o ator está olhando (no chão).
func frente_vetor() -> Vector3:
	var a := rotation.y - frente
	return Vector3(sin(a), 0, cos(a))

func olhar_para(p: Vector3) -> void:
	var d := p - global_position; d.y = 0
	if d.length() > 0.01: rotation.y = atan2(d.x, d.z) + frente

func _process(dt: float) -> void:
	if _caminho.is_empty():
		if player == null and modelo: modelo.position.y = 0.0
		return
	var alvo: Vector3 = grade.centro(_caminho[0])
	var d := alvo - position
	olhar_para(alvo)
	var passo := vel_atual() * dt
	if player:
		var pd := _papel_desloc()
		if player.current_animation != anim.get(pd, ""): tocar(pd)   # trocou de modo no meio do caminho
		player.speed_scale = _ritmo(pd)
	if player == null and modelo:
		_passo += dt * 12.0; modelo.position.y = absf(sin(_passo)) * 0.06
	if d.length() <= passo:
		position = alvo
		var antes := _de
		celula = _caminho.pop_front(); _de = celula
		chegou.emit(celula, grade.custo(antes, celula))
		if _caminho.is_empty():
			tocar("parado")
			parou.emit()
		else:
			passo_iniciado.emit(celula, _caminho[0])
	else:
		position += d.normalized() * passo

## Golpe: anima e devolve quando a lâmina "acerta" (para o dano aparecer na hora certa).
func animar_golpe(alvo: Node3D) -> void:
	olhar_para(alvo.global_position)
	if player:
		tocar("golpe", 0.1)
		await get_tree().create_timer(0.55).timeout
	else:
		var ida := (alvo.global_position - global_position).normalized() * 0.45
		var t := create_tween()
		t.tween_property(modelo, "position", ida, 0.18).set_trans(Tween.TRANS_QUAD)
		t.tween_property(modelo, "position", Vector3.ZERO, 0.25)
		await get_tree().create_timer(0.2).timeout

func animar_dano() -> void:
	atualizar_rotulo()
	if player:
		tocar("dano", 0.05)
		get_tree().create_timer(0.9).timeout.connect(func(): if vivo(): tocar("parado"))
	else:
		var t := create_tween()
		t.tween_property(modelo, "rotation:x", -0.35, 0.08)
		t.tween_property(modelo, "rotation:x", 0.0, 0.2)

## A animação de morrer do Mixamo começa com ~0,7 s em pé e reto antes de desabar
## (medido com tools/curva_quadril.gd). Encadeia: tranco do golpe -> queda, já do meio do desabar.
const MORRER_INICIO := 1.0
const DANO_ANTES_DE_CAIR := 0.28

func animar_morte() -> void:
	atualizar_rotulo()
	rotulo.visible = false
	if player:
		if _tem("dano"):
			tocar("dano", 0.05)
			await get_tree().create_timer(DANO_ANTES_DE_CAIR).timeout
		tocar("morrer", 0.3)
		if _tem("morrer"): player.seek(MORRER_INICIO, false)
	else:
		var t := create_tween()
		t.tween_property(modelo, "rotation:x", -PI / 2, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.tween_interval(1.5)
		t.tween_property(modelo, "position:y", -0.6, 1.2)

func sumir() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	t.tween_callback(queue_free)

func _achar_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var p := _achar_player(c)
		if p: return p
	return null

## Goblin provisório feito de formas simples, olhando para +Z, até o modelo 3D final ficar pronto.
static func goblin_provisorio() -> Node3D:
	var raiz := Node3D.new()
	var pele := StandardMaterial3D.new(); pele.albedo_color = Color(0.40, 0.47, 0.34); pele.roughness = 0.8
	var couro := StandardMaterial3D.new(); couro.albedo_color = Color(0.33, 0.2, 0.12); couro.roughness = 0.9
	var ferro := StandardMaterial3D.new(); ferro.albedo_color = Color(0.55, 0.52, 0.48); ferro.metallic = 0.7; ferro.roughness = 0.45
	var olho := StandardMaterial3D.new(); olho.albedo_color = Color(1, 0.85, 0.2); olho.emission_enabled = true
	olho.emission = Color(1, 0.8, 0.2); olho.emission_energy_multiplier = 1.5
	var peca := func(malha: Mesh, mat: Material, pos: Vector3, rot: Vector3, esc: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new(); mi.mesh = malha; mi.material_override = mat
		mi.position = pos; mi.rotation_degrees = rot; mi.scale = esc; raiz.add_child(mi)
		return mi
	var perna := CapsuleMesh.new(); perna.radius = 0.07; perna.height = 0.5
	peca.call(perna, pele, Vector3(-0.12, 0.25, 0), Vector3(0, 0, -6), Vector3.ONE)
	peca.call(perna, pele, Vector3(0.12, 0.25, 0), Vector3(0, 0, 6), Vector3.ONE)
	var corpo := CapsuleMesh.new(); corpo.radius = 0.2; corpo.height = 0.6
	peca.call(corpo, couro, Vector3(0, 0.72, 0.04), Vector3(22, 0, 0), Vector3.ONE)
	var braco := CapsuleMesh.new(); braco.radius = 0.055; braco.height = 0.55
	peca.call(braco, pele, Vector3(-0.27, 0.68, 0.1), Vector3(20, 0, -14), Vector3.ONE)
	peca.call(braco, pele, Vector3(0.27, 0.68, 0.1), Vector3(20, 0, 14), Vector3.ONE)
	var cabeca := SphereMesh.new(); cabeca.radius = 0.2; cabeca.height = 0.36
	peca.call(cabeca, pele, Vector3(0, 1.08, 0.16), Vector3.ZERO, Vector3(1.1, 1, 1))
	var orelha := CylinderMesh.new(); orelha.top_radius = 0.0; orelha.bottom_radius = 0.07; orelha.height = 0.32
	peca.call(orelha, pele, Vector3(-0.27, 1.12, 0.12), Vector3(0, 0, 70), Vector3(1, 1, 0.4))
	peca.call(orelha, pele, Vector3(0.27, 1.12, 0.12), Vector3(0, 0, -70), Vector3(1, 1, 0.4))
	var o := SphereMesh.new(); o.radius = 0.03; o.height = 0.06
	peca.call(o, olho, Vector3(-0.08, 1.11, 0.33), Vector3.ZERO, Vector3.ONE); peca.call(o, olho, Vector3(0.08, 1.11, 0.33), Vector3.ZERO, Vector3.ONE)
	var lamina := BoxMesh.new(); lamina.size = Vector3(0.03, 0.08, 0.5)
	peca.call(lamina, ferro, Vector3(0.34, 0.45, 0.32), Vector3(-20, 0, 0), Vector3.ONE)
	return raiz
