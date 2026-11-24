extends Control
## Tela do jogo (Handoff §1.2): cartas do grupo à esquerda · barra de ações embaixo · relógio (exploração)
## ou ordem de iniciativa (combate) no canto superior direito · registro no canto inferior direito.
## A cena principal (explorar.gd) passa o estado em `atualizar(...)` e ouve os sinais.

signal modo_pedido(modo: String)
signal acao_pedida(acao: String)          # "atacar", "encerrar", "brotar", "ficha"
signal trocar_arma(heroi: Node, item)     # item da ficha
signal usar_item(heroi: Node, item)
signal ficha_pedida(heroi: Node)

const Ficha = preload("res://scripts/regras/ficha.gd")
const UI := "res://arte/final/interface/"
const PERGAMINHO := Color(0.95, 0.9, 0.78)
const TINTA := Color(0.18, 0.12, 0.07)
const OURO := Color(1.0, 0.82, 0.4)

var fonte: Font
var fonte_negrito: Font
var fonte_titulo: Font
var tema: Theme

var _cartas_caixa: VBoxContainer
var _cartas := {}            # heroi -> {painel, pv, ca, thac0, arma, extra, expandida}
var _barra: HFlowContainer
var _barra_info: Label
var _canto: PanelContainer
var _canto_caixa: VBoxContainer
var _log: RichTextLabel
var _botoes_modo := {}
var _linhas: Array[String] = []
var _menu: PopupMenu
var _menu_itens: Array = []
var _modo_barra := ""
var _herois: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fonte = load("res://assets/fontes/NotoSerif-Regular.ttf")
	fonte_negrito = load("res://assets/fontes/NotoSerif-Bold.ttf")
	fonte_titulo = load("res://assets/fontes/NotoSerifDisplay-Bold.ttf")
	tema = Theme.new(); tema.default_font = fonte; tema.default_font_size = 15
	theme = tema
	_montar_cartas(); _montar_barra(); _montar_canto(); _montar_log()
	_menu = PopupMenu.new(); add_child(_menu)
	_menu.id_pressed.connect(_ao_escolher_menu)

# ---------- peças ----------

func _caixa_pergaminho(alfa := 0.9) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI + "ui/pergaminho.png")
	sb.texture_margin_left = 18; sb.texture_margin_right = 18; sb.texture_margin_top = 18; sb.texture_margin_bottom = 18
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	sb.modulate_color = Color(1, 1, 1, alfa)
	return sb

func _couro() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI + "ui/couro.png")
	sb.texture_margin_left = 34; sb.texture_margin_right = 34; sb.texture_margin_top = 30; sb.texture_margin_bottom = 30
	sb.content_margin_left = 14; sb.content_margin_right = 16; sb.content_margin_top = 12; sb.content_margin_bottom = 18
	return sb

func _rotulo(txt: String, tam := 15, cor := PERGAMINHO, f: Font = null) -> Label:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", tam); l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85)); l.add_theme_constant_override("outline_size", 4)
	if f: l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _emblema(arquivo: String, valor: String, dica: String, tam := 34) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(tam, tam); c.tooltip_text = dica
	var t := TextureRect.new(); t.texture = load(UI + arquivo); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(t)
	var l := _rotulo(valor, 15, Color.WHITE, fonte_negrito); l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6); l.name = "valor"
	c.add_child(l)
	return c

func _botao(txt: String, dica := "") -> Button:
	var b := Button.new(); b.text = txt; b.tooltip_text = dica; b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", fonte_negrito); b.add_theme_font_size_override("font_size", 15)
	var n := _caixa_pergaminho(1.0); n.content_margin_left = 16; n.content_margin_right = 16; n.content_margin_top = 8; n.content_margin_bottom = 8
	var h := n.duplicate(); h.modulate_color = Color(1.1, 1.05, 0.9)
	var pr := n.duplicate(); pr.modulate_color = Color(1.0, 0.85, 0.55)
	var d := n.duplicate(); d.modulate_color = Color(0.6, 0.58, 0.55, 0.8)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr); b.add_theme_stylebox_override("hover_pressed", pr); b.add_theme_stylebox_override("disabled", d)
	for k in ["font_color", "font_hover_color", "font_focus_color"]: b.add_theme_color_override(k, TINTA)
	b.add_theme_color_override("font_pressed_color", Color(0.5, 0.15, 0.05)); b.add_theme_color_override("font_hover_pressed_color", Color(0.5, 0.15, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(0.3, 0.27, 0.24))
	return b

# ---------- cartas (esquerda) ----------

func _montar_cartas() -> void:
	var rolagem := ScrollContainer.new()
	rolagem.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rolagem.offset_left = 10; rolagem.offset_top = 10; rolagem.offset_right = 300; rolagem.offset_bottom = -78
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rolagem.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(rolagem)
	_cartas_caixa = VBoxContainer.new(); _cartas_caixa.add_theme_constant_override("separation", 6)
	_cartas_caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(_cartas_caixa)

func definir_grupo(herois: Array) -> void:
	_herois = herois
	for c in _cartas_caixa.get_children(): c.queue_free()
	_cartas.clear()
	for h in herois: _cartas[h] = _carta(h)

func _carta(h: Node) -> Dictionary:
	var f = h.ficha
	var painel := PanelContainer.new(); painel.add_theme_stylebox_override("panel", _couro())
	painel.mouse_filter = Control.MOUSE_FILTER_STOP
	painel.tooltip_text = "Clique para ver mais · duplo clique abre a ficha"
	_cartas_caixa.add_child(painel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); painel.add_child(v)
	var linha := HBoxContainer.new(); linha.add_theme_constant_override("separation", 8); v.add_child(linha)
	# Retrato na moldura
	var moldura := Control.new(); moldura.custom_minimum_size = Vector2(72, 72); moldura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ret := TextureRect.new(); ret.texture = load("res://arte/final/retratos/%s.jpg" % f.id) if ResourceLoader.exists("res://arte/final/retratos/%s.jpg" % f.id) else null
	ret.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ret.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ret.set_anchors_preset(Control.PRESET_FULL_RECT); ret.offset_left = 10; ret.offset_top = 10; ret.offset_right = -10; ret.offset_bottom = -10
	ret.mouse_filter = Control.MOUSE_FILTER_IGNORE; moldura.add_child(ret)
	var mold := TextureRect.new(); mold.texture = load(UI + "ui/moldura-retrato.png"); mold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mold.set_anchors_preset(Control.PRESET_FULL_RECT); mold.mouse_filter = Control.MOUSE_FILTER_IGNORE; moldura.add_child(mold)
	linha.add_child(moldura)
	var info := VBoxContainer.new(); info.add_theme_constant_override("separation", 2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE; linha.add_child(info)
	var nome := _rotulo(str(f.nome).get_slice(" ", 0), 18, OURO, fonte_titulo); info.add_child(nome)
	info.add_child(_rotulo("%s · nível %d" % [f.classe(), int(f.p.nivel)], 12, Color(0.92, 0.85, 0.72)))
	var em := HBoxContainer.new(); em.add_theme_constant_override("separation", 6); em.mouse_filter = Control.MOUSE_FILTER_IGNORE; info.add_child(em)
	var pv := _emblema("recortes/emblema-coracao.png", "", "Pontos de vida", 36); em.add_child(pv)
	var ca := _emblema("recortes/emblema-escudo.png", "", "Classe de armadura (menor é melhor)", 34); em.add_child(ca)
	var t0 := _emblema("emblema-medalhao.png", "", "THAC0: precisa tirar THAC0 − CA do alvo no d20", 34); em.add_child(t0)
	var arma := _rotulo("", 13, Color(0.95, 0.9, 0.8)); arma.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(arma)
	var extra := VBoxContainer.new(); extra.visible = false; extra.add_theme_constant_override("separation", 2); v.add_child(extra)
	var d := {"painel": painel, "pv": pv, "ca": ca, "thac0": t0, "arma": arma, "extra": extra, "nome": nome}
	painel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click: ficha_pedida.emit(h)
			else:
				extra.visible = not extra.visible
				if extra.visible: _preencher_extra(h, extra))
	return d

func _preencher_extra(h: Node, caixa: VBoxContainer) -> void:
	for c in caixa.get_children(): c.queue_free()
	var f = h.ficha
	var cor := Color(0.93, 0.88, 0.78)
	caixa.add_child(HSeparator.new())
	caixa.add_child(_rotulo("Carga %s · %d de %d espaços · %d m/turno" % [{"leve": "leve", "media": "média", "pesada": "pesada"}[f.carga()], f.espacos_usados(), f.espacos_max(), int(f.movimento_m())], 12, cor))
	var eq: Array[String] = []
	for par in [["mão dir.", f.mao_d], ["mão esq.", f.mao_e], ["corpo", f.corpo]]:
		if par[1] != null: eq.append("%s: %s" % [par[0], Ficha.info(par[1]).nome])
	var cin: Array[String] = []
	for it in f.cinto:
		if it != null: cin.append("%s%s" % [Ficha.info(it).nome, (" ×%d" % it.qtd) if it.qtd > 1 else ""])
	var l := _rotulo("Equipado — %s\nCinto — %s" % [", ".join(eq), ", ".join(cin) if not cin.is_empty() else "vazio"], 12, cor)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; caixa.add_child(l)
	var hab: Array[String] = []
	for x in f.habilidades_exploracao(): hab.append("%s %s" % [x[0], x[1]])
	var lh := _rotulo("Exploração — " + " · ".join(hab), 12, cor); lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caixa.add_child(lh)
	var b := _botao("Abrir ficha"); b.pressed.connect(func(): ficha_pedida.emit(h)); caixa.add_child(b)

func _atualizar_cartas(vez: Node, lider: Node, luz_txt: String) -> void:
	for h in _cartas:
		if not is_instance_valid(h): continue
		var d: Dictionary = _cartas[h]; var f = h.ficha
		d.pv.get_node("valor").text = str(maxi(h.pv, 0)); d.ca.get_node("valor").text = str(h.ca); d.thac0.get_node("valor").text = str(f.thac0())
		var a = f.arma()
		var txt := "%s %s" % [Ficha.info(a).nome, Ficha.info(a).get("dano", "")] if a != null else "desarmado"
		if a != null and Ficha.info(a).has("municao"): txt += " · %d %s" % [f.municao_de(a), str(Ficha.info(a).municao)]
		if h == lider: txt += "\n" + luz_txt
		if not h.vivo(): txt = "caído"
		d.arma.text = txt
		var ativo: bool = h == vez
		d.painel.modulate = Color(0.55, 0.5, 0.5) if not h.vivo() else (Color(1.15, 1.08, 0.9) if ativo else Color.WHITE)
		d.nome.add_theme_color_override("font_color", Color(1, 0.95, 0.55) if ativo else OURO)
		d.nome.text = ("▶ " if ativo else "") + str(f.nome).get_slice(" ", 0)

# ---------- barra de ações (embaixo) ----------

func _montar_barra() -> void:
	var fundo := VBoxContainer.new(); fundo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fundo.offset_left = 310; fundo.offset_right = -450; fundo.offset_top = -110; fundo.offset_bottom = -10
	fundo.alignment = BoxContainer.ALIGNMENT_END; fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)
	_barra_info = _rotulo("", 16, Color(1, 0.92, 0.75), fonte_negrito); _barra_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fundo.add_child(_barra_info)
	_barra = HFlowContainer.new(); _barra.alignment = FlowContainer.ALIGNMENT_CENTER
	_barra.add_theme_constant_override("h_separation", 8); _barra.add_theme_constant_override("v_separation", 6)
	fundo.add_child(_barra)

func _barra_exploracao(modos: Dictionary, modo: String) -> void:
	for c in _barra.get_children(): c.queue_free()
	_botoes_modo.clear()
	var i := 1
	for k in ["devagar", "normal", "rapido"]:
		var b := _botao("%d · %s" % [i, modos[k].nome], str(modos[k].dica)); b.toggle_mode = true
		b.button_pressed = k == modo
		b.pressed.connect(func(): modo_pedido.emit(k))
		_barra.add_child(b); _botoes_modo[k] = b; i += 1
	_barra.add_child(VSeparator.new())
	var fb := _botao("I · Ficha", "Abrir a ficha de quem lidera"); fb.pressed.connect(func(): acao_pedida.emit("ficha")); _barra.add_child(fb)
	var br := _botao("B · Brotar goblin", "Teste: põe 1 goblin ao lado do grupo"); br.pressed.connect(func(): acao_pedida.emit("brotar")); _barra.add_child(br)

func _barra_combate(h: Node) -> void:
	for c in _barra.get_children(): c.queue_free()
	_botoes_modo.clear()
	var f = h.ficha
	var a = f.arma()
	var dist: bool = a != null and Ficha.info(a).has("distancia")
	var at := _botao("Atirar" if dist else "Atacar", "Ataca o inimigo mais próximo ao alcance (ou clique num inimigo)")
	at.pressed.connect(func(): acao_pedida.emit("atacar")); _barra.add_child(at)
	var tr := _botao("Trocar arma", "Empunhar outra arma do cinto ou da mochila (uma vez por vez)")
	tr.disabled = f.armas_guardadas().is_empty() or bool(h.get_meta("trocou", false))
	tr.pressed.connect(func(): _abrir_menu(h, f.armas_guardadas(), "trocar", tr)); _barra.add_child(tr)
	var cin: Array = f.cinto.filter(func(x): return x != null)
	var us := _botao("Cinto", "Usar um item de acesso rápido"); us.disabled = cin.is_empty()
	us.pressed.connect(func(): _abrir_menu(h, cin, "usar", us)); _barra.add_child(us)
	var en := _botao("Encerrar (Espaço)"); en.pressed.connect(func(): acao_pedida.emit("encerrar")); _barra.add_child(en)

func _abrir_menu(h: Node, itens: Array, tipo: String, perto: Control) -> void:
	_menu.clear(); _menu_itens.clear()
	for it in itens:
		var inf := Ficha.info(it)
		var txt := "%s%s" % [inf.nome, (" ×%d" % it.qtd) if it.qtd > 1 else ""]
		if tipo == "trocar" and inf.has("dano"): txt += " (%s)" % inf.dano
		_menu.add_item(txt, _menu_itens.size())
		_menu_itens.append([h, it, tipo])
	_menu.reset_size()
	_menu.position = Vector2i(perto.get_screen_position()) + Vector2i(0, -_menu.size.y - 6)
	_menu.popup()

func _ao_escolher_menu(i: int) -> void:
	var x: Array = _menu_itens[i]
	if x[2] == "trocar": trocar_arma.emit(x[0], x[1])
	else: usar_item.emit(x[0], x[1])

# ---------- canto superior direito: relógio ou iniciativa ----------

func _montar_canto() -> void:
	_canto = PanelContainer.new(); _canto.add_theme_stylebox_override("panel", _couro())
	_canto.set_anchors_preset(Control.PRESET_TOP_RIGHT); _canto.offset_left = -380; _canto.offset_right = -10; _canto.offset_top = 10
	_canto.grow_horizontal = Control.GROW_DIRECTION_BEGIN; _canto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canto)
	_canto_caixa = VBoxContainer.new(); _canto_caixa.add_theme_constant_override("separation", 3); _canto.add_child(_canto_caixa)

var _relogio_antes: Array = []
func _canto_relogio(linhas: Array) -> void:
	if linhas == _relogio_antes and _canto_caixa.get_child_count() > 0: return
	_relogio_antes = linhas.duplicate()
	for c in _canto_caixa.get_children(): c.queue_free()
	for i in linhas.size():
		var l := _rotulo(str(linhas[i]), 17 if i == 0 else 14, OURO if i == 0 else PERGAMINHO, fonte_titulo if i == 0 else null)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; _canto_caixa.add_child(l)

## ordem: [{nome, lado, vivo, retrato (id ou ""), vez}]
func _canto_iniciativa(rodada: int, ordem: Array) -> void:
	for c in _canto_caixa.get_children(): c.queue_free()
	var t := _rotulo("Rodada %d" % rodada, 18, OURO, fonte_titulo); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_canto_caixa.add_child(t)
	var fila := HFlowContainer.new(); fila.alignment = FlowContainer.ALIGNMENT_END; fila.add_theme_constant_override("h_separation", 6)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE; _canto_caixa.add_child(fila)
	for e in ordem:
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 0)
		var q := PanelContainer.new(); q.custom_minimum_size = Vector2(52, 52)
		var sb := StyleBoxFlat.new(); sb.set_corner_radius_all(4); sb.set_border_width_all(3)
		sb.border_color = Color(1, 0.85, 0.3) if e.vez else (Color(0.35, 0.55, 0.9) if e.lado == "grupo" else Color(0.8, 0.25, 0.2))
		sb.bg_color = Color(0.12, 0.08, 0.05); q.add_theme_stylebox_override("panel", sb)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if e.retrato != "" and ResourceLoader.exists("res://arte/final/retratos/%s.jpg" % e.retrato):
			var r := TextureRect.new(); r.texture = load("res://arte/final/retratos/%s.jpg" % e.retrato)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; q.add_child(r)
		else:
			var l := _rotulo("?" if e.nome == "?" else str(e.nome).substr(0, 1) + str(e.nome).right(1), 16, Color(1, 0.75, 0.65), fonte_negrito)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; q.add_child(l)
		if not e.vivo: q.modulate = Color(0.4, 0.4, 0.4)
		v.add_child(q)
		var n := _rotulo(str(e.nome), 11, Color(1, 0.95, 0.6) if e.vez else PERGAMINHO); n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = 56; n.clip_text = true; v.add_child(n)
		fila.add_child(v)

# ---------- registro (inferior direito) ----------

func _montar_log() -> void:
	var fundo := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.06, 0.04, 0.02, 0.72); sb.set_corner_radius_all(6); sb.set_content_margin_all(10)
	sb.border_color = Color(0.45, 0.3, 0.15, 0.8); sb.set_border_width_all(2)
	fundo.add_theme_stylebox_override("panel", sb)
	fundo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fundo.offset_left = -440; fundo.offset_right = -10; fundo.offset_top = -230; fundo.offset_bottom = -10
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)
	_log = RichTextLabel.new(); _log.bbcode_enabled = true; _log.scroll_following = true
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]: _log.add_theme_font_size_override(k, 13)
	_log.add_theme_font_override("normal_font", fonte); _log.add_theme_font_override("bold_font", fonte_negrito)
	_log.add_theme_font_override("italics_font", load("res://assets/fontes/NotoSerif-Italic.ttf"))
	_log.add_theme_color_override("default_color", Color(0.93, 0.88, 0.8))
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_child(_log)

func registrar(txt: String) -> void:
	_linhas.append(txt)
	if _linhas.size() > 80: _linhas.pop_front()
	_log.text = "\n".join(_linhas)

# ---------- estado ----------

## Exploração: relógio no canto e modos na barra.
func atualizar_exploracao(modos: Dictionary, modo: String, relogio: Array, lider: Node, luz_txt: String) -> void:
	if _modo_barra != "exploracao":
		_modo_barra = "exploracao"; _barra_exploracao(modos, modo)
	for k in _botoes_modo: _botoes_modo[k].button_pressed = k == modo
	_barra_info.text = ""
	_canto_relogio(relogio)
	_atualizar_cartas(null, lider, luz_txt)

## Combate: iniciativa no canto, ações do personagem da vez na barra.
func atualizar_combate(rodada: int, ordem: Array, vez: Node, info: String, lider: Node, luz_txt: String) -> void:
	var vivos := ordem.filter(func(e): return e.vivo).size()
	var chave := "combate:%d:%s:%s:%d:%d" % [rodada, str(vez.get_instance_id()) if vez else "", _assinatura(vez), vivos, ordem.size()]
	if _modo_barra != chave:
		_modo_barra = chave; _relogio_antes = []
		for c in _barra.get_children(): c.queue_free()
		if vez and vez.lado == "grupo": _barra_combate(vez)
		_canto_iniciativa(rodada, ordem)
	_barra_info.text = info
	_atualizar_cartas(vez, lider, luz_txt)

## Muda quando algo que a barra mostra muda (arma na mão, cinto, troca feita).
func _assinatura(h: Node) -> String:
	if h == null or not h.get("ficha"): return ""
	var f = h.ficha
	return "%s|%s|%s" % [str(f.mao_d), str(f.cinto), str(h.get_meta("trocou", false))]

func refazer() -> void:
	_modo_barra = ""
