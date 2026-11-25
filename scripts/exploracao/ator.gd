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
var dist_faixas: Array = []   # arma à distância: [curta, média, longa] em metros (vazio = não tem)
var dist_dano := "1d6"
var dist_arma := ""
var dist_mod := 0           # DES nos disparos
var municao := 0
var tem_escudo := false
var ficha = null          # ficha.gd (só personagens)
var arma_visivel := true  # a arma do modelo 3D só aparece se for a que está na mão   # quem tem escudo bloqueia os golpes que erram; quem não tem, esquiva
var mov_combate_m := 12.0
var moral := 12
var xp := 0
var fugindo := false
var no_combate := false   # ligado pelo combate enquanto ele dura (monstros correm)
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

## Estilos de luta (data/regras/estilos.json): a arma na mão escolhe guarda, golpes, disparo e defesa.
static var _estilos := {}
static func estilos() -> Dictionary:
	if _estilos.is_empty():
		_estilos = JSON.parse_string(FileAccess.get_file_as_string("res://data/regras/estilos.json"))
	return _estilos

var anim_base := {}
var estilo := ""

## Troca os papéis de combate pelos do estilo da arma (os papéis fora do estilo voltam ao padrão).
func aplicar_estilo(nome: String) -> void:
	var e: Dictionary = estilos().estilos.get(nome, {})
	if nome == estilo and not anim.is_empty(): return
	estilo = nome
	anim = anim_base.duplicate()
	for papel in ["golpe2", "golpe_critico", "atirar", "soltar", "arremessar", "aparar"]: anim.erase(papel)
	anim.merge(e, true)
	if player:
		for papel in ["parado_combate", "andar_combate"]:
			if _tem(papel): player.get_animation(anim[papel]).loop_mode = Animation.LOOP_LINEAR
		if not andando() and vivo(): tocar("parado", 0.1)   # a guarda nova entra na hora

## Defesa contra um golpe: escudo bloqueia; quem tem "aparar" no estilo apara; o resto esquiva.
func defesa() -> String:
	if tem_escudo: return "bloquear"
	return "aparar" if _tem("aparar") else "esquivar"

func montar_modelo(m: Node3D, papeis: Dictionary, giro := 0.0) -> void:
	modelo = m; anim = papeis; frente = giro; anim_base = papeis.duplicate()
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

## Modelos 3D dos itens nas mãos (scripts/visual/armas3d.gd): lugar da ficha -> [id do item, nó preso ao osso].
const Armas3D = preload("res://scripts/visual/armas3d.gd")
var _vestidos := {}

## Põe nas mãos os modelos dos itens que a ficha tem em mao_d e mao_e (troca só o que mudou).
func vestir(f, catalogo: Callable) -> void:
	if modelo == null or player == null: return
	var sk: Skeleton3D = modelo.find_children("*", "Skeleton3D", true, false)[0]
	for lugar in ["mao_d", "mao_e"]:
		var it = f.pegar(lugar)
		var id := str(it.id) if it != null else ""
		if _vestidos.has(lugar) and _vestidos[lugar][0] == id: continue
		if _vestidos.has(lugar) and is_instance_valid(_vestidos[lugar][1]): _vestidos[lugar][1].queue_free()
		_vestidos.erase(lugar)
		var m: Dictionary = catalogo.call(it).get("modelo3d", {}) if it != null else {}
		if m.is_empty(): continue
		var no := Armas3D.montar(sk, player, m, modelo.scale.x)
		if no == null: continue
		no.set_meta("escudo", str(m.get("mao", "")) == "antebraco")
		_vestidos[lugar] = [id, no]
	_mostrar_armas()
	if not andando() and vivo(): tocar("parado", 0.0)

## Armas só aparecem no combate; o escudo fica sempre no braço.
var _escondida := false
func _mostrar_armas() -> void:
	for lugar in _vestidos:
		var no: Node3D = _vestidos[lugar][1]
		if is_instance_valid(no): no.visible = (em_combate or bool(no.get_meta("escudo", false))) and not (_escondida and lugar == "mao_d")

## Saca (combate) ou guarda a arma (exploração).
func empunhar(sim: bool) -> void:
	em_combate = sim
	for a in armas_na_mao: a.visible = sim and arma_visivel
	_mostrar_armas()
	if not andando() and vivo(): tocar("parado")

func tocar(papel: String, misturar := 0.2) -> void:
	if papel == "parado" and _escondida:
		_escondida = false; _mostrar_armas()
	if papel == "parado":
		if em_combate and _tem("parado_combate"): papel = "parado_combate"
		elif papel_andar == "andar_furtivo" and _tem("parado_furtivo"): papel = "parado_furtivo"   # agachado
	if player and anim.has(papel) and player.has_animation(anim[papel]):
		player.play(anim[papel], misturar)
		player.speed_scale = _ritmo(papel)
		if estilos().velocidade.has(anim[papel]): player.speed_scale = float(estilos().velocidade[anim[papel]])
		var giro := -deg_to_rad(float(giro_anim.get(anim[papel], 0.0)))
		if absf(modelo.rotation.y - giro) > 0.01:
			create_tween().tween_property(modelo, "rotation:y", giro, maxf(misturar, 0.05))

## Toca uma animação da biblioteca pelo nome (ajoelhar, chutar-porta...). Devolve a duração (s).
func tocar_anim(nome: String, misturar := 0.2) -> float:
	if player == null or not player.has_animation(nome): return 0.6
	player.play(nome, misturar); player.speed_scale = 1.0
	var giro := -deg_to_rad(float(giro_anim.get(nome, 0.0)))
	create_tween().tween_property(modelo, "rotation:y", giro, maxf(misturar, 0.05))
	return player.get_animation(nome).length

func _tem(papel: String) -> bool:
	return anim.has(papel) and player != null and player.has_animation(anim[papel])

## Em combate, o andar em guarda é mais curto: cada um anda no ritmo dele (passada × RITMO_COMBATE).
const RITMO_COMBATE := 1.8
## Monstros correm no combate e quando fogem (velocidade do modo rápido, animação de corrida).
const VEL_CORRIDA := 1.5
func _correndo() -> bool:
	return lado != "grupo" and (no_combate or fugindo) and _tem("correr")

func vel_atual() -> float:
	if _correndo(): return VEL_BASE * VEL_CORRIDA
	var pc := float(passadas.get(anim.get("andar_combate", ""), passadas.get("andar_combate", 0.0)))
	if em_combate and pc > 0.0 and _tem("andar_combate"):
		return pc * RITMO_COMBATE
	return velocidade

func _ritmo(papel: String) -> float:
	var p := float(passadas.get(anim.get(papel, ""), passadas.get(papel, 0.0)))
	return clampf(vel_atual() / p, 0.4, 2.8) if p > 0.0 else 1.0

## Papel de deslocamento: em combate, andar em guarda; fora dele, o do modo (cai para "andar").
func _papel_desloc() -> String:
	if _correndo(): return "correr"
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
## Instante em que a lâmina chega no alvo na animação "golpe" (a mão desce mais rápido em ~0,86 s;
## medido com tools/curva_quadril.gd). Dano e efeitos saem nesse momento.
const GOLPE_IMPACTO := 0.86
## Instante do impacto de cada animação de ataque (pico de velocidade da mão, tools/curva_quadril.gd).
const IMPACTOS := {"golpe-descendente": 0.86, "golpe": 0.86, "corte-dentro": 1.2, "corte-fora": 0.92, "estocada-cima": 0.78}
var _alterna := false

## Qual golpe vem agora: no crítico, o golpe especial (se houver); senão alterna entre os golpes que tiver.
func escolher_golpe(critico: bool) -> String:
	if critico and _tem("golpe_critico"): return "golpe_critico"
	if _tem("golpe2"):
		_alterna = not _alterna
		return "golpe2" if _alterna else "golpe"
	return "golpe"

func tempo_impacto(papel := "golpe") -> float:
	var n: String = anim.get(papel, "")
	var t := float(estilos().impactos.get(n, IMPACTOS.get(n, GOLPE_IMPACTO)))
	return t / float(estilos().velocidade.get(n, 1.0))

func animar_golpe(alvo: Node3D, papel := "golpe") -> void:
	olhar_para(alvo.global_position)
	if player:
		tocar(papel, 0.1)
		await get_tree().create_timer(tempo_impacto(papel)).timeout
	else:
		var ida := (alvo.global_position - global_position).normalized() * 0.45
		var t := create_tween()
		t.tween_property(modelo, "position", ida, 0.18).set_trans(Tween.TRANS_QUAD)
		t.tween_property(modelo, "position", Vector3.ZERO, 0.25)
		await get_tree().create_timer(0.2).timeout

func gastar_municao() -> void:
	municao -= 1
	if ficha: ficha.gastar_municao(ficha.arma())

func tempo_tiro() -> float:
	if not (player and _tem("atirar")): return 0.3
	var n: String = anim.atirar
	if estilos().solta.has(n): return float(estilos().solta[n]) / float(estilos().velocidade.get(n, 1.0))
	return player.get_animation(n).length * 0.95

## Disparo: puxa a corda e devolve no instante em que a flecha sai (fim da animação "atirar").
func animar_tiro(alvo: Node3D) -> void:
	olhar_para(alvo.global_position)
	if player and _tem("atirar"): tocar("atirar", 0.12)
	await get_tree().create_timer(tempo_tiro()).timeout
	if player and _tem("soltar"): tocar("soltar", 0.05)   # a corda solta: a flecha sai agora
	# Arma de arremesso (azagaia): some da mão ao soltar; volta "nova" quando a vez acaba (tocar parado).
	if bool(estilos().estilos.get(estilo, {}).get("some_ao_soltar", false)) and _vestidos.has("mao_d"):
		_escondida = true; _mostrar_armas()

## Defesa (bloquear/esquivar) cronometrada para o auge cair no instante em que a lâmina chega.
## Auge medido com tools/curva_quadril.gd: escudo firme ~0,35 s; maior inclinação da esquiva ~0,55 s.
const DEFESA_AUGE := {"bloquear": 0.35, "esquivar": 0.55}
func defender(papel: String, de: Vector3, impacto_em: float) -> void:
	if not _tem(papel): return
	var au: Dictionary = estilos().auge_defesa
	var espera := maxf(impacto_em - float(au.get(anim.get(papel, ""), au.get(papel, DEFESA_AUGE.get(papel, 0.3)))), 0.0)
	await get_tree().create_timer(espera).timeout
	if not vivo(): return
	olhar_para(de)
	tocar(papel, 0.12)
	var dur: float = player.get_animation(anim[papel]).length
	await get_tree().create_timer(dur / maxf(player.speed_scale, 0.1) + 0.15).timeout
	if vivo() and player.current_animation == anim[papel]: tocar("parado", 0.25)

## Clarão no corpo (sobreposição sem luz que some rápido).
var _clarao: StandardMaterial3D
func piscar(cor: Color, dur := 0.14) -> void:
	if modelo == null: return
	if _clarao == null:
		_clarao = StandardMaterial3D.new()
		_clarao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_clarao.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clarao.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for m in modelo.find_children("*", "GeometryInstance3D", true, false): m.material_overlay = _clarao
	_clarao.albedo_color = cor
	var t := create_tween()
	t.tween_property(_clarao, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Empurrão para trás (acerto) ou passo de lado (esquiva), saindo de `de` e voltando.
func recuar(de: Vector3, dist := 0.3, lateral := false) -> void:
	if modelo == null: return
	var d := global_position - de; d.y = 0
	if d.length() < 0.01: return
	d = d.normalized()
	if lateral: d = (d + Vector3(-d.z, 0, d.x) * (1.0 if randf() < 0.5 else -1.0)).normalized()
	var off := global_basis.inverse() * d * dist   # o modelo é filho do ator (que gira)
	var base := modelo.position
	var t := create_tween()
	t.tween_property(modelo, "position", base + off, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(modelo, "position", base, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Altura para textos acima da cabeça.
func altura_texto() -> float:
	return rotulo.position.y * 0.55 if rotulo else 1.0

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
