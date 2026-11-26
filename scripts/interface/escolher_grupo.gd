extends Control
## Tela de escolha do grupo antes da aventura (padrão "Grimório escuro"): cartas com os personagens
## prontos (um de cada classe do B/X); o jogador escolhe N. A ordem da escolha é a ordem de marcha.

signal escolhido(ids: Array)

const E = preload("res://scripts/interface/estilo.gd")
const CLASSE := {"guerreiro": "Guerreiro", "anao": "Anão", "ladrao": "Ladrão", "elfo": "Elfo", "mago": "Mago",
	"clerigo": "Clérigo", "halfling": "Halfling"}
const CLASSE_F := {"guerreiro": "Guerreira", "elfo": "Elfa", "mago": "Maga"}
const ATR := [["for", "FOR"], ["int", "INT"], ["sab", "SAB"], ["des", "DES"], ["con", "CON"], ["car", "CAR"]]

var quantos := 5
var _fichas: Array = []        # fichas dos personagens disponíveis
var _ordem: Array = []         # ids escolhidos, na ordem
var _cartas := {}              # id -> {painel, numero}
var _contador: Label
var _botao: Button

func montar(titulo: String, fichas: Array, n: int) -> void:
	_fichas = fichas; quantos = n
	theme = E.tema()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veu := ColorRect.new(); veu.color = Color(0.035, 0.025, 0.018, 0.97); veu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veu)
	var centro := CenterContainer.new(); centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(centro)
	var painel := PanelContainer.new(); painel.add_theme_stylebox_override("panel", _painel_grande()); centro.add_child(painel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); painel.add_child(v)
	var t := E.rotulo("Escolha o grupo", 26, E.OURO, "titulo"); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
	var sub := E.rotulo("%s · escolha %d de %d. A ordem da escolha é a ordem de marcha." % [titulo, quantos, fichas.size()], 15, E.TEXTO)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(sub)
	var grade := GridContainer.new(); grade.columns = 4
	grade.add_theme_constant_override("h_separation", 14); grade.add_theme_constant_override("v_separation", 14)
	v.add_child(grade)
	for p in fichas: grade.add_child(_carta(p))
	var pe := HBoxContainer.new(); pe.add_theme_constant_override("separation", 18); pe.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(pe)
	_contador = E.rotulo("", 15, E.TEXTO_CLARO); pe.add_child(_contador)
	_botao = Button.new(); _botao.text = "Começar a aventura"; _botao.custom_minimum_size = Vector2(220, 40)
	_botao.add_theme_font_override("font", E.fonte("titulo")); _botao.add_theme_font_size_override("font_size", 15)
	_botao.add_theme_stylebox_override("normal", E.painel(false)); _botao.add_theme_stylebox_override("hover", E.painel(true))
	_botao.add_theme_stylebox_override("pressed", E.painel(true)); _botao.add_theme_stylebox_override("disabled", E.painel(false))
	_botao.add_theme_color_override("font_color", E.OURO); _botao.add_theme_color_override("font_hover_color", E.OURO_VEZ)
	_botao.add_theme_color_override("font_disabled_color", Color(E.TEXTO, 0.4))
	_botao.pressed.connect(func(): if _ordem.size() == quantos: escolhido.emit(_ordem.duplicate()))
	pe.add_child(_botao)
	_atualizar()

func _painel_grande() -> StyleBoxFlat:
	var sb := E.painel(false); sb.bg_color = Color(0.08, 0.055, 0.035, 0.96); sb.set_content_margin_all(26)
	return sb

func _carta(p: Dictionary) -> Control:
	var id := str(p.id)
	var painel := PanelContainer.new(); painel.custom_minimum_size = Vector2(212, 0)
	painel.mouse_filter = Control.MOUSE_FILTER_STOP; painel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	painel.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: alternar(id))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel.add_child(v)
	var topo := Control.new(); topo.custom_minimum_size = Vector2(0, 92); topo.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(topo)
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.add_child(cc)
	var r := E.Retrato.new(id, 88, str(p.nome)); cc.add_child(r); r.aro(E.FILETE, 2.0)
	var num := E.rotulo("", 18, E.OURO_VEZ, "titulo"); num.position = Vector2(0, 0); topo.add_child(num)
	var nome := E.rotulo(str(p.get("nome_curto", str(p.nome).get_slice(" ", 0))), 17, E.OURO, "titulo")
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(nome)
	var cl: String = str(p.classe)
	var fem := str(p.get("genero", "")) == "f" or id in ["tessa", "lianne", "mirela"]
	var classe := E.rotulo("%s · nível %d" % [CLASSE_F.get(cl, CLASSE.get(cl, cl)) if fem else CLASSE.get(cl, cl), int(p.get("nivel", 1))], 13, E.TEXTO)
	classe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(classe)
	var chips := HBoxContainer.new(); chips.alignment = BoxContainer.ALIGNMENT_CENTER; chips.add_theme_constant_override("separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(E.chip("PV %d" % int(p.pv))); chips.add_child(E.chip("THAC0 %d" % int(p.thac0)))
	v.add_child(chips)
	var a: Dictionary = p.get("atributos", {})
	var linhas := VBoxContainer.new(); linhas.add_theme_constant_override("separation", 0); linhas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for metade in [ATR.slice(0, 3), ATR.slice(3, 6)]:
		var l := E.rotulo("  ".join(metade.map(func(x): return "%s %d" % [x[1], int(a.get(x[0], 0))])), 12, E.TEXTO_CLARO)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; linhas.add_child(l)
	v.add_child(linhas)
	_cartas[id] = {"painel": painel, "numero": num, "retrato": r}
	return painel

func alternar(id: String) -> void:
	if _ordem.has(id): _ordem.erase(id)
	elif _ordem.size() < quantos: _ordem.append(id)
	_atualizar()

func _atualizar() -> void:
	for id in _cartas:
		var c: Dictionary = _cartas[id]
		var k := _ordem.find(id)
		var sb := E.painel(k >= 0); sb.set_content_margin_all(12)
		c.painel.add_theme_stylebox_override("panel", sb)
		c.numero.text = str(k + 1) if k >= 0 else ""
		c.retrato.aro(E.OURO_CLARO if k >= 0 else E.FILETE, 2.0)
		c.painel.modulate = Color(1, 1, 1, 1.0 if k >= 0 or _ordem.size() < quantos else 0.62)
	_contador.text = "%d de %d escolhidos" % [_ordem.size(), quantos]
	_botao.disabled = _ordem.size() != quantos
