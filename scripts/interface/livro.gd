extends Control
## Livro da ficha no padrão "Grimório escuro" (docs/padrao-visual.md).
## Página esquerda fixa: identidade, PV/CA/THAC0, atributos, proteções e o bloco Combate (só armas).
## Página direita com abas: Habilidades · Magias (só quem lança) · Equipamento · Diário.
## Equipamento: arrastar e soltar entre mãos, corpo, cinto e mochila; clique no item: usar, dar, largar.
## Em combate o livro só mostra (trocar de arma é pela barra de ações).

signal mudou(heroi: Node)
signal usar(heroi: Node, item)
signal fechou

const Ficha = preload("res://scripts/regras/ficha.gd")
const E = preload("res://scripts/interface/estilo.gd")
const Sons = preload("res://scripts/visual/sons.gd")
const ICONES := "res://arte/final/interface/icones/%s.png"
const LIVRO := Rect2(92, 52, 1096, 632)
const PAG_ESQ := Rect2(26, 44, 514, 566)     # relativo ao livro
const PAG_DIR := Rect2(556, 44, 514, 566)
const NOMES_LUGAR := {"mao_d": "Mão direita", "mao_e": "Mão esquerda", "corpo": "Corpo", "cinto0": "Cinto", "cinto1": "Cinto"}
const NOME_CARGA := {"leve": "leve", "media": "média", "pesada": "pesada"}
const ABAS := [["habilidades", "Habilidades"], ["magias", "Magias"], ["equipamento", "Equipamento"], ["diario", "Diário"]]

var grupo: Array = []
var heroi: Node
var diario: Array = []          # [{turno, tipo, texto}]
var em_combate := false
var adjacentes: Callable        # (a, b) -> bool
var aba := "habilidades"

var _livro: Control
var _esq: VBoxContainer
var _dir: VBoxContainer
var _dir_rolagem: ScrollContainer
var _abas_caixa: HBoxContainer
var _seletor: VBoxContainer
var _menu: PopupMenu
var _menu_acoes: Array = []
var _aviso: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = E.tema()
	var veu := ColorRect.new(); veu.color = Color(0, 0, 0, 0.82); veu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veu.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: fechar())
	add_child(veu)
	# Capa de couro com filete dourado.
	_livro = Panel.new(); _livro.position = LIVRO.position; _livro.size = LIVRO.size
	var capa := StyleBoxFlat.new(); capa.bg_color = E.COURO_LIVRO; capa.set_corner_radius_all(14)
	capa.set_border_width_all(2); capa.border_color = E.COURO_ARO
	capa.shadow_color = Color(0, 0, 0, 0.8); capa.shadow_size = 30; capa.shadow_offset = Vector2(0, 14)
	_livro.add_theme_stylebox_override("panel", capa); _livro.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_livro)
	var fio := Panel.new(); fio.position = Vector2(7, 7); fio.size = LIVRO.size - Vector2(14, 14)
	var sf := StyleBoxFlat.new(); sf.draw_center = false; sf.set_corner_radius_all(9); sf.set_border_width_all(1); sf.border_color = Color(0.77, 0.6, 0.32, 0.5)
	fio.add_theme_stylebox_override("panel", sf); fio.mouse_filter = Control.MOUSE_FILTER_IGNORE; _livro.add_child(fio)
	_esq = _pagina(PAG_ESQ, true).get_child(0)
	_dir_rolagem = _pagina(PAG_DIR, false)
	_dir = _dir_rolagem.get_child(0)
	# Abas penduradas no alto da página direita.
	_abas_caixa = HBoxContainer.new(); _abas_caixa.position = Vector2(580, 0); _abas_caixa.add_theme_constant_override("separation", 5)
	_abas_caixa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_livro.add_child(_abas_caixa)
	# Retratos do grupo à esquerda do livro.
	_seletor = VBoxContainer.new(); _seletor.position = Vector2(34, 110); _seletor.add_theme_constant_override("separation", 12)
	add_child(_seletor)
	var fechar_l := E.rotulo("Esc fecha", 12, E.TEXTO); fechar_l.position = Vector2(LIVRO.end.x - 80, LIVRO.end.y + 6)
	fechar_l.mouse_filter = Control.MOUSE_FILTER_STOP; fechar_l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fechar_l.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: fechar())
	add_child(fechar_l)
	_aviso = E.rotulo("", 13, E.OURO_CLARO, "italico"); _aviso.position = Vector2(LIVRO.position.x + 40, LIVRO.end.y + 6)
	_aviso.size = Vector2(LIVRO.size.x - 200, 22); add_child(_aviso)
	_menu = PopupMenu.new(); add_child(_menu); _menu.id_pressed.connect(func(i): _menu_acoes[i].call())

## Página de pergaminho com sombra na lombada. Devolve o ScrollContainer (filho 0 = VBox do conteúdo).
func _pagina(r: Rect2, esquerda: bool) -> ScrollContainer:
	var pg := TextureRect.new(); pg.texture = E.pergaminho(); pg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pg.stretch_mode = TextureRect.STRETCH_SCALE; pg.position = r.position; pg.size = r.size
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE; _livro.add_child(pg)
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0.24, 0.14, 0.04, 0.0), Color(0.24, 0.14, 0.04, 0.5)])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.width = 32; gt.height = 4
	if not esquerda: gt.fill_from = Vector2(1, 0); gt.fill_to = Vector2(0, 0)
	var lombada := TextureRect.new(); lombada.texture = gt; lombada.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lombada.stretch_mode = TextureRect.STRETCH_SCALE; lombada.size = Vector2(26, r.size.y)
	lombada.position = Vector2(r.end.x - 26, r.position.y) if esquerda else r.position
	lombada.mouse_filter = Control.MOUSE_FILTER_IGNORE; _livro.add_child(lombada)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.position = r.position + Vector2(24, 20 if esquerda else 26); sc.size = r.size - Vector2(48, 36 if esquerda else 42)
	_livro.add_child(sc)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return sc

func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and e.keycode in [KEY_ESCAPE, KEY_I]:
		fechar(); get_viewport().set_input_as_handled()

func fechar() -> void:
	if visible: Sons.tocar("livro_fechar")
	visible = false; fechou.emit()

# ---------- peças no pergaminho ----------

func _t(txt: String, tam := 13, cor := E.TINTA, tipo := "texto", quebra := true) -> Label:
	var l := E.rotulo(txt, tam, cor, tipo, false)
	if quebra: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _titulo(pai: Control, txt: String, direita := "") -> void:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new(); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(h)
	var l := _t(txt, 14, E.SANGUE, "titulo", false); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
	if direita != "": h.add_child(_t(direita, 11, E.TINTA_CLARA, "texto", false))
	var linha := ColorRect.new(); linha.color = Color(E.SANGUE, 0.35); linha.custom_minimum_size = Vector2(0, 1)
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(linha)
	pai.add_child(v)

func _caixa(borda: Color, larg := 1, raio := 4, fundo := Color(1, 0.98, 0.92, 0.35)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = fundo; sb.set_corner_radius_all(raio); sb.set_border_width_all(larg); sb.border_color = borda
	sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 3; sb.content_margin_bottom = 3
	return sb

func _painel(sb: StyleBox) -> PanelContainer:
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", sb); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _centro(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _etiqueta(quando: String) -> PanelContainer:
	var q: Array = E.QUANDO[quando]
	var sb := StyleBoxFlat.new(); sb.bg_color = q[1]; sb.set_corner_radius_all(3)
	sb.content_margin_left = 5; sb.content_margin_right = 5; sb.content_margin_top = 0; sb.content_margin_bottom = 1
	var p := _painel(sb); p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(_t(q[0], 10, Color("#f3e6c8"), "texto", false))
	return p

# ---------- montar ----------

func mostrar(h: Node, nova_aba := "") -> void:
	heroi = h
	if nova_aba != "": aba = {"ficha": "habilidades", "inventario": "equipamento"}.get(nova_aba, nova_aba)
	if aba == "magias" and not h.ficha.lanca_magia(): aba = "habilidades"
	if not visible: Sons.tocar("livro_abrir")
	visible = true
	_aviso.text = "Em combate o livro só mostra; para trocar de arma use a barra de ações." if em_combate and aba == "equipamento" else ""
	_montar_abas()
	_montar_seletor()
	for c in _esq.get_children() + _dir.get_children(): c.queue_free()
	_dir_rolagem.scroll_vertical = 0
	_pagina_fixa()
	match aba:
		"habilidades": _aba_habilidades()
		"magias": _aba_magias()
		"equipamento": _aba_equipamento()
		"diario": _aba_diario()

func _montar_abas() -> void:
	for c in _abas_caixa.get_children(): c.queue_free()
	for par in ABAS:
		if par[0] == "magias" and not heroi.ficha.lanca_magia(): continue
		var on: bool = par[0] == aba
		var b := Button.new(); b.text = par[1]; b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var sb := StyleBoxFlat.new(); sb.bg_color = E.ABA[par[0]]
		sb.corner_radius_bottom_left = 6; sb.corner_radius_bottom_right = 6
		sb.content_margin_left = 13; sb.content_margin_right = 13; sb.content_margin_top = 13 if on else 9; sb.content_margin_bottom = 7
		sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 4; sb.shadow_offset = Vector2(0, 3)
		for k in ["normal", "hover", "pressed", "hover_pressed"]: b.add_theme_stylebox_override(k, sb)
		b.add_theme_font_override("font", E.fonte("titulo")); b.add_theme_font_size_override("font_size", 13)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: b.add_theme_color_override(k, E.TEXTO_CLARO)
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.62)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var k2: String = par[0]
		b.pressed.connect(func(): mostrar(heroi, k2))
		_abas_caixa.add_child(b)

func _montar_seletor() -> void:
	for c in _seletor.get_children(): c.queue_free()
	for g in grupo:
		var b := Button.new(); b.flat = true; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(50, 50)
		b.tooltip_text = g.nome; b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var r := E.Retrato.new(g.ficha.id, 50, g.nome); b.add_child(r)
		r.aro(E.OURO_CLARO if g == heroi else Color("#8a6a3a"), 3.0 if g == heroi else 2.0)
		if g != heroi: r.modulate.a = 0.7
		if not g.vivo(): r.apagar(0.9)
		b.pressed.connect(func(): mostrar(g))
		_seletor.add_child(b)

# ---------- página esquerda (fixa) ----------

func _pagina_fixa() -> void:
	var f = heroi.ficha
	var cab := HBoxContainer.new(); cab.add_theme_constant_override("separation", 14); cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_esq.add_child(cab)
	var ret := E.Retrato.new(f.id, 74, f.nome); ret.aro(E.COURO_ARO, 3.0); cab.add_child(ret)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 1); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER; cab.add_child(v)
	v.add_child(_t(str(f.nome), 21, E.TINTA, "titulo"))
	v.add_child(_t("%s · nível %d · %s" % [f.classe(), int(f.p.nivel), f.alinhamento()], 14, E.TINTA_CLARA, "italico"))
	var b: Array = f.bonus_xp()
	var req := str(b[0])
	if not " e " in req: req += " %d" % int(f.p.atributos[req.to_lower()])
	v.add_child(_t("XP %s de %s · %s · bônus %s%d%%" % [_milhar(f.xp), _milhar(f.xp_proximo()), req, "+" if int(b[1]) >= 0 else "", int(b[1])], 12))
	# PV, CA, THAC0
	var grandes := HBoxContainer.new(); grandes.add_theme_constant_override("separation", 8); grandes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_esq.add_child(grandes)
	for x in [["PONTOS DE VIDA", "%d / %d" % [maxi(heroi.pv, 0), f.pv_max()], E.SANGUE], ["CLASSE DE ARMADURA", str(f.ca()), E.COURO_ARO], ["THAC0", str(f.thac0()), E.COURO_ARO]]:
		var sb := _caixa(x[2], 2, 6, Color(E.SANGUE, 0.06) if x[0] == "PONTOS DE VIDA" else Color(0, 0, 0, 0))
		var p := _painel(sb); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := VBoxContainer.new(); c.add_theme_constant_override("separation", 0); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(c)
		c.add_child(_centro(_t(x[0], 10, E.TINTA_CLARA, "texto", false)))
		c.add_child(_centro(_t(x[1], 21, E.TINTA, "titulo", false)))
		grandes.add_child(p)
	# Atributos
	_titulo(_esq, "Atributos")
	var g := GridContainer.new(); g.columns = 6; g.add_theme_constant_override("h_separation", 5); _esq.add_child(g)
	for k in ["for", "int", "sab", "des", "con", "car"]:
		var m: int = f.mod(k)
		var p := _painel(_caixa(Color(E.TINTA, 0.45))); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := VBoxContainer.new(); c.add_theme_constant_override("separation", -2); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(c)
		c.add_child(_centro(_t(k.to_upper(), 10, E.TINTA_CLARA, "texto", false)))
		c.add_child(_centro(_t(str(int(f.p.atributos[k])), 18, E.TINTA, "titulo", false)))
		c.add_child(_centro(_t(_sinal(m), 10, E.TINTA_CLARA, "texto", false)))
		g.add_child(p)
	# Proteções (o modificador de SAB vale contra magias)
	_titulo(_esq, "Jogadas de proteção")
	var pr := HBoxContainer.new(); pr.add_theme_constant_override("separation", 4); pr.mouse_filter = Control.MOUSE_FILTER_IGNORE; _esq.add_child(pr)
	var sab: int = f.mod("sab")
	for x in [["morte", "Morte ou veneno"], ["varinhas", "Varinhas"], ["paralisia", "Paralisia"], ["sopro", "Sopro"], ["magias", "Magias"]]:
		var c := VBoxContainer.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.add_theme_constant_override("separation", 2)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var circ := _painel(_caixa(E.COURO_ARO, 2, 17, Color(1, 0.98, 0.92, 0.4))); circ.custom_minimum_size = Vector2(36, 36)
		circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var n := _centro(_t(str(int(f.p.protecao[x[0]])), 14, E.TINTA, "titulo", false)); n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		circ.add_child(n); c.add_child(circ)
		var rot: String = x[1]
		if x[0] == "magias" and sab != 0: rot += " (%s SAB)" % _sinal(sab)
		c.add_child(_centro(_t(rot, 10, E.TINTA_CLARA)))
		pr.add_child(c)
	# Combate: só armas
	_titulo(_esq, "Combate")
	var tab := GridContainer.new(); tab.columns = 4; tab.add_theme_constant_override("h_separation", 10); tab.add_theme_constant_override("v_separation", 2)
	_esq.add_child(tab)
	for cab_t in ["ARMA", "DANO", "ACERTO", "DANO +"]: tab.add_child(_t(cab_t, 10, E.TINTA_CLARA, "texto", false))
	for linha in _linhas_de_armas(f):
		for i in 4:
			var l := _t(str(linha[i]), 12, E.TINTA, "texto", false)
			if i == 0: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab.add_child(l)
	var espaco := Control.new(); espaco.size_flags_vertical = Control.SIZE_EXPAND_FILL; espaco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_esq.add_child(espaco)
	var arm := "Sem armadura" if f.corpo == null else str(Ficha.info(f.corpo).nome)
	if f.mao_e != null and Ficha.info(f.mao_e).get("tipo") == "escudo": arm += " e escudo"
	_esq.add_child(_t("%s · carga %s (%d de %d espaços) · %d m por turno, %d m por rodada" % [arm, NOME_CARGA[f.carga()], f.espacos_usados(), f.espacos_max(), int(f.movimento_m()), int(f.movimento_m() / 3.0)], 11, E.TINTA_CLARA))

## [nome, dano, acerto, dano+] de cada arma que o personagem carrega (a da mão primeiro).
func _linhas_de_armas(f) -> Array:
	var out: Array = []
	var vistas := {}
	var lugares := [["mão", f.mao_d], ["mão", f.mao_e]]
	for it in f.cinto: lugares.append(["cinto", it])
	for it in f.mochila: lugares.append(["mochila", it])
	for par in lugares:
		var it = par[1]
		if it == null or Ficha.info(it).get("tipo") != "arma" or vistas.has(it.id): continue
		vistas[it.id] = true
		var inf := Ficha.info(it)
		if inf.has("distancia"):
			out.append(["%s (%s)" % [inf.nome, par[0]], inf.dano, "%s · DES" % _sinal(f.mod("des")), "—"])
		else:
			out.append(["%s (%s)" % [inf.nome, par[0]], inf.dano, "%s · FOR" % _sinal(f.mod("for")), _sinal(f.mod("for"))])
			if inf.has("arremesso"): out.append(["%s, arremesso" % inf.nome, inf.dano, "%s · DES" % _sinal(f.mod("des")), "—"])
	if out.is_empty(): out.append(["Desarmado", "1d2", "%s · FOR" % _sinal(f.mod("for")), _sinal(f.mod("for"))])
	return out

# ---------- aba Habilidades ----------

func _linha_hab(pai: Control, h: Dictionary) -> void:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var linha := HBoxContainer.new(); linha.add_theme_constant_override("separation", 10); linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(linha)
	var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 0); tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE; linha.add_child(tx)
	var nl := _t(h.nome, 14, E.TINTA, "negrito"); nl.add_theme_constant_override("line_spacing", -3); tx.add_child(nl)
	var dl := _t(h.desc, 11, E.TINTA_CLARA); dl.add_theme_constant_override("line_spacing", -3); tx.add_child(dl)
	var val := _t(h.valor, 16, E.TINTA, "titulo", false); val.custom_minimum_size.x = 70
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; linha.add_child(val)
	var dir := VBoxContainer.new(); dir.add_theme_constant_override("separation", 3); dir.custom_minimum_size.x = 104
	dir.mouse_filter = Control.MOUSE_FILTER_IGNORE; linha.add_child(dir)
	var ch := E.Chance.new(float(h.chance) / 100.0 if int(h.chance) >= 0 else 0.0, 104)
	if int(h.chance) < 0: ch.modulate.a = 0.0
	dir.add_child(ch)
	dir.add_child(_etiqueta(h.quando))
	dir.alignment = BoxContainer.ALIGNMENT_CENTER
	var fio := ColorRect.new(); fio.color = Color(E.TINTA, 0.15); fio.custom_minimum_size = Vector2(0, 1); fio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fio)
	pai.add_child(v)

func _aba_habilidades() -> void:
	var f = heroi.ficha
	var c := str(f.p.classe)
	var habs: Array = f.habilidades()
	var d: Dictionary = f.destaque()
	if d.get("tipo") == "afastar": _quadro_afastar(d)
	if not habs.is_empty():
		_titulo(_dir, "Habilidades de ladrão" if c == "ladrao" else "Habilidades da classe")
		for h in habs: _linha_hab(_dir, h)
	if d.get("tipo") == "furtivo": _quadro_furtivo(d)
	if f.lanca_magia():
		_titulo(_dir, "Magia divina" if c == "clerigo" else "Magia arcana")
		var hm := HBoxContainer.new(); hm.add_theme_constant_override("separation", 10); hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n: int = f.magias_por_dia()
		hm.add_child(E.Gema.new("cheia" if n > 0 else "tranca", 20))
		var txt := "%d por dia no 1º círculo. Veja a aba Magias." % n if n > 0 else "Nenhuma oração no 1º nível. No 2º nível (%s XP): 1 por dia. Veja a aba Magias." % _milhar(f.xp_proximo())
		var l := _t(txt, 12); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hm.add_child(l)
		_dir.add_child(hm)
	_titulo(_dir, "Testes de masmorra")
	for h in f.testes_masmorra(): _linha_hab(_dir, h)
	var regras := {"clerigo": "Só armas contundentes · qualquer armadura e escudo", "mago": "Sem armadura · só adaga",
		"ladrao": "Só armadura de couro · qualquer arma", "guerreiro": "Qualquer arma e armadura"}
	var rod := "Idiomas: " + ", ".join(f.idiomas())
	if regras.has(c): rod = regras[c] + " · " + rod
	if c == "ladrao": rod += " · Ler idiomas no 4º nível"
	_dir.add_child(_t(rod, 11, E.TINTA_CLARA))

func _quadro_furtivo(d: Dictionary) -> void:
	var p := _painel(_caixa(E.SANGUE, 1, 6, Color(E.SANGUE, 0.06))); _dir.add_child(p)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(h)
	var n := VBoxContainer.new(); n.add_theme_constant_override("separation", -4); n.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(n)
	n.add_child(_t("+%d" % int(d.acerto), 20, E.SANGUE, "titulo", false)); n.add_child(_t("dano ×%d" % int(d.dano), 12, E.SANGUE, "titulo", false))
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
	var a = heroi.ficha.arma()
	var arma := ("Com %s: %s × 2." % [str(Ficha.info(a).nome).to_lower(), Ficha.info(a).dano]) if a != null else ""
	v.add_child(_t("Ataque furtivo. Pelas costas de um alvo que não notou %s (depois de se esconder ou se mover em silêncio). %s" % [heroi.nome, arma], 12))
	v.add_child(_etiqueta("co"))

func _quadro_afastar(d: Dictionary) -> void:
	_titulo(_dir, "Afastar mortos-vivos")
	var p := _painel(_caixa(E.SANGUE, 1, 6, Color(E.SANGUE, 0.06))); _dir.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 5); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(v)
	v.add_child(_t("Ergue o símbolo sagrado e rola 2d6. Se passar, 2d6 DV de mortos-vivos fogem, os mais fracos primeiro.", 12))
	v.add_child(_etiqueta("co"))
	var g := GridContainer.new(); g.columns = 4; g.add_theme_constant_override("h_separation", 12); v.add_child(g)
	for x in d.tabela + [["Mais fortes", 13]]:
		var imposs: bool = int(x[1]) > 12
		var cor := E.TINTA_CLARA if imposs else E.TINTA
		var nome := _t(x[0], 12, cor, "texto" if imposs else "negrito", false); nome.custom_minimum_size.x = 96; g.add_child(nome)
		g.add_child(_t("impossível" if imposs else "%d ou +" % int(x[1]), 13, cor, "titulo", false))
		var ch := E.Chance.new(0.0 if imposs else Ficha.chance_2d6(int(x[1])) / 100.0, 150); ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(ch)
		g.add_child(_t("" if imposs else "%d%%" % Ficha.chance_2d6(int(x[1])), 11, E.TINTA_CLARA, "texto", false))

# ---------- aba Magias ----------

func _cartao_magia(pai: Control, id: String, destaque: bool, apagada := false) -> void:
	var m: Dictionary = Ficha.magias_catalogo().magias.get(id, {"nome": id, "texto": "", "quando": "am", "alcance": "", "duracao": ""})
	var sb := _caixa(E.ABA.magias if destaque else Color(E.TINTA, 0.35), 2 if destaque else 1, 5, Color(0.23, 0.35, 0.66, 0.08) if destaque else Color(1, 0.98, 0.92, 0.35))
	sb.content_margin_left = 9; sb.content_margin_right = 9; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	if apagada: sb.border_color = Color(E.TINTA, 0.25)
	var p := _painel(sb); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if apagada: p.modulate.a = 0.62
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(h)
	if destaque: h.add_child(E.Gema.new("cheia", 20))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
	var topo := HBoxContainer.new(); topo.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(topo)
	var n := _t(str(m.nome), 13, E.TINTA, "titulo"); n.size_flags_horizontal = Control.SIZE_EXPAND_FILL; topo.add_child(n)
	if destaque: topo.add_child(_etiqueta(str(m.quando)))
	var txt := str(m.texto)
	if destaque: txt += " Alcance %s, dura %s." % [m.alcance, m.duracao]
	v.add_child(_t(txt, 11, Color("#4a3420")))
	pai.add_child(p)

func _aba_magias() -> void:
	var f = heroi.ficha
	var cat: Dictionary = Ficha.magias_catalogo()
	var n: int = f.magias_por_dia()
	if f.lista_magia() == "divina":
		_titulo(_dir, "Orações por dia", "o clérigo não usa grimório")
		if n == 0:
			var p := _painel(_caixa(E.SANGUE, 1, 6, Color(E.SANGUE, 0.06))); _dir.add_child(p)
			var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(h)
			h.add_child(E.Gema.new("tranca", 28))
			var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 4)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
			v.add_child(_t("Nenhuma no 1º nível. A primeira oração chega no 2º nível.", 13, E.TINTA, "negrito"))
			var ch := E.Chance.new(float(f.xp) / f.xp_proximo(), 380); v.add_child(ch)
			var b: Array = f.bonus_xp()
			v.add_child(_t("XP %s de %s · bônus %s%d%% (%s)" % [_milhar(f.xp), _milhar(f.xp_proximo()), "+" if int(b[1]) >= 0 else "", int(b[1]), b[0]], 11, E.TINTA_CLARA))
		else:
			_gemas(n)
			_titulo(_dir, "Memorizadas hoje")
			for id in f.memorizadas(): _cartao_magia(_dir, id, true)
		_titulo(_dir, "Orações do 1º círculo")
		_dir.add_child(_t("No 2º nível, escolhe 1 delas a cada manhã, depois de rezar." if n == 0 else "Escolhe a cada manhã, depois de rezar.", 11, E.TINTA_CLARA))
		_grade_magias(cat.divina, n == 0)
		return
	_titulo(_dir, "Magias por dia", "memoriza após uma noite de descanso")
	_gemas(n)
	_titulo(_dir, "Memorizada hoje" if n == 1 else "Memorizadas hoje")
	for id in f.memorizadas(): _cartao_magia(_dir, id, true)
	_dir.add_child(_t("Ao lançar, some da memória até o próximo descanso. É declarada no início da rodada; um golpe recebido antes de agir faz perder a magia.", 11, E.ABA.magias))
	var grim: Array = f.p.get("grimorio", [])
	_titulo(_dir, "Grimório", "%d magia%s" % [grim.size(), "" if grim.size() == 1 else "s"])
	_grade_magias(grim, false)
	var fora: Array = cat.arcana.filter(func(x): return not x in grim).map(func(x): return str(cat.magias[x].nome))
	if not fora.is_empty():
		_dir.add_child(_t("Outras magias de 1º círculo (fora do grimório)", 11, E.TINTA_CLARA, "negrito"))
		_dir.add_child(_t(" · ".join(fora), 12, Color("#6a5236")))
	_dir.add_child(_t("Para trocar a memorizada, descanse uma noite.", 11, E.TINTA_CLARA, "italico"))

func _gemas(n: int) -> void:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_t("1º círculo", 13, E.TINTA, "titulo", false))
	var gastas: int = heroi.ficha.magias_gastas
	for i in n: h.add_child(E.Gema.new("vazia" if i < gastas else "cheia", 20))
	var l := _t("%d de %d pronta%s" % [maxi(n - gastas, 0), n, "" if n == 1 else "s"], 13, E.TINTA, "texto", false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
	h.add_child(_t("2º círculo no 3º nível", 11, E.TINTA_CLARA, "texto", false))
	_dir.add_child(h)

func _grade_magias(ids: Array, apagadas: bool) -> void:
	var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 6); g.add_theme_constant_override("v_separation", 6)
	_dir.add_child(g)
	for id in ids: _cartao_magia(g, id, false, apagadas)

# ---------- aba Equipamento ----------

func _aba_equipamento() -> void:
	var f = heroi.ficha
	_titulo(_dir, "Equipado")
	var eq := HBoxContainer.new(); eq.add_theme_constant_override("separation", 10); eq.mouse_filter = Control.MOUSE_FILTER_IGNORE; _dir.add_child(eq)
	for lugar in ["mao_d", "mao_e", "corpo", "-", "cinto0", "cinto1"]:
		if lugar == "-":
			var fio := ColorRect.new(); fio.color = Color(E.TINTA, 0.3); fio.custom_minimum_size = Vector2(1, 58); eq.add_child(fio); continue
		var c := VBoxContainer.new(); c.add_theme_constant_override("separation", 3); c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(_espaco(f.pegar(lugar), lugar))
		c.add_child(_centro(_t(NOMES_LUGAR[lugar], 11, E.TINTA_CLARA, "texto", false)))
		eq.add_child(c)
	_titulo(_dir, "Mochila", "%d de %d espaços" % [f.espacos_usados(), f.espacos_max()])
	var grade := GridContainer.new(); grade.columns = 6; grade.add_theme_constant_override("h_separation", 8); grade.add_theme_constant_override("v_separation", 8)
	_dir.add_child(grade)
	var usados := 0
	for it in f.mochila:
		var n: int = f._espacos(it)
		grade.add_child(_espaco(it, "mochila"))
		for _i in n - 1: grade.add_child(_espaco(null, "mochila", true))
		usados += n
	var moedas_esp: int = f.espacos_usados() - usados
	for _i in maxi(0, moedas_esp): grade.add_child(_espaco({"id": "moedas", "qtd": 1}, "mochila", false, true))
	for _i in maxi(0, f.espacos_max() - f.espacos_usados()): grade.add_child(_espaco(null, "mochila"))
	_titulo(_dir, "Dinheiro e carga")
	var mh := HBoxContainer.new(); mh.add_theme_constant_override("separation", 12); mh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new(); ic.texture = load(ICONES % "bolsa-moedas"); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.custom_minimum_size = Vector2(40, 40); mh.add_child(ic)
	var moedas: Array[String] = []
	for k in [["pl", "peças de platina"], ["po", "peças de ouro"], ["pe", "peças de electro"], ["pp", "peças de prata"], ["pc", "peças de cobre"]]:
		if int(f.moedas[k[0]]) > 0: moedas.append("%d %s" % [int(f.moedas[k[0]]), k[1]])
	var ml := _t("%s\nCarga %s · %d m por turno · %d m por rodada" % [", ".join(moedas) if not moedas.is_empty() else "Sem moedas", NOME_CARGA[f.carga()], int(f.movimento_m()), int(f.movimento_m() / 3.0)], 13)
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mh.add_child(ml); _dir.add_child(mh)
	_dir.add_child(_t("Arraste entre mãos, corpo, cinto e mochila. Clique num item: usar, dar, largar. Cada 200 moedas ocupam 1 espaço.", 11, E.TINTA_CLARA, "italico"))

func _nome_item(it) -> String:
	var inf := Ficha.info(it)
	var s := str(inf.nome)
	if it.qtd > 1: s += " ×%d" % it.qtd
	if inf.has("dano"): s += " (%s)" % inf.dano
	return s

func _espaco(it, lugar: String, continua := false, moedas := false) -> Control:
	var c := Panel.new(); c.custom_minimum_size = Vector2(58, 58)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.31, 0.22, 0.1, 0.12); sb.set_corner_radius_all(5)
	sb.set_border_width_all(1); sb.border_color = Color(E.TINTA, 0.5)
	c.add_theme_stylebox_override("panel", sb)
	if continua:
		sb.border_color = Color(E.TINTA, 0.25); c.tooltip_text = "O item ao lado ocupa 2 espaços."
		var l := _centro(_t("—", 18, E.TINTA_CLARA, "texto", false)); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; c.add_child(l)
		return c
	if moedas:
		var t := TextureRect.new(); t.texture = load(ICONES % "bolsa-moedas"); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_left = 7; t.offset_top = 7; t.offset_right = -7; t.offset_bottom = -7; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(t)
		c.tooltip_text = "Moedas (cada 200 ocupam 1 espaço)"
		return c
	if it != null:
		var ic: Texture2D = Ficha.icone(it)
		if ic:
			var t := TextureRect.new(); t.texture = ic; t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			t.offset_left = 7; t.offset_top = 7; t.offset_right = -7; t.offset_bottom = -7; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(t)
		else:
			var l := _centro(_t(str(Ficha.info(it).nome), 10, E.TINTA, "negrito")); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.offset_left = 3; l.offset_right = -3; c.add_child(l)
		if it.qtd > 1:
			var q := _t("×%d" % it.qtd, 11, E.TINTA, "negrito", false); q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; q.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			q.offset_right = -4; q.offset_bottom = -1; c.add_child(q)
		c.tooltip_text = _nome_item(it) + ("\n" + str(Ficha.info(it).dica) if Ficha.info(it).has("dica") else "")
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not e.double_click:
				_menu_item(it, c))
	c.set_drag_forwarding(
		func(_p): return _arrastar(it, c),
		func(_p, d): return _pode_soltar(d, lugar),
		func(_p, d): _soltar(d, lugar))
	return c

func _arrastar(it, c: Control):
	if it == null or em_combate: return null
	var prev := TextureRect.new(); prev.texture = Ficha.icone(it); prev.size = Vector2(52, 52)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.set_drag_preview(prev)
	return {"item": it}

func _pode_soltar(d, lugar: String) -> bool:
	return d is Dictionary and d.has("item") and not em_combate and heroi.ficha.motivo_para_nao(d.item, lugar) == ""

func _soltar(d, lugar: String) -> void:
	var m: String = heroi.ficha.mover(d.item, lugar)
	mudou.emit(heroi); mostrar(heroi)
	_aviso.text = m

func _menu_item(it, perto: Control) -> void:
	if em_combate: return
	_menu.clear(); _menu_acoes.clear()
	var tipo := str(Ficha.info(it).get("tipo", ""))
	if tipo in ["luz", "consumivel"]: _menu_add("Usar", _usar.bind(it))
	for g in grupo:
		if g == heroi or not g.vivo(): continue
		var perto_ok: bool = adjacentes.call(heroi, g) if adjacentes.is_valid() else true
		_menu_add("Dar a %s%s" % [g.nome, "" if perto_ok else " (precisa estar ao lado)"], _dar.bind(it, g), perto_ok)
	_menu_add("Largar no chão", _largar.bind(it))
	_menu.reset_size(); _menu.position = Vector2i(perto.get_screen_position()) + Vector2i(62, 0); _menu.popup()

func _menu_add(txt: String, acao: Callable, ativo := true) -> void:
	_menu.add_item(txt, _menu_acoes.size()); _menu.set_item_disabled(_menu_acoes.size(), not ativo); _menu_acoes.append(acao)

func _usar(it) -> void:
	usar.emit(heroi, it); mostrar(heroi)

func _dar(it, g: Node) -> void:
	var m: String = heroi.ficha.dar(it, g.ficha)
	mudou.emit(heroi); mudou.emit(g); mostrar(heroi)
	_aviso.text = m if m != "" else "%s deu a %s: %s." % [heroi.nome, g.nome, Ficha.info(it).nome]

func _largar(it) -> void:
	heroi.ficha.tirar(it)
	mudou.emit(heroi); mostrar(heroi)
	_aviso.text = "%s largou no chão: %s." % [heroi.nome, Ficha.info(it).nome]

# ---------- aba Diário ----------

func _aba_diario() -> void:
	for sec in [["lugar", "Lugares", true], ["criatura", "Criaturas", false], ["evento", "Acontecimentos", true]]:
		_titulo(_dir, sec[1])
		var lista := diario.filter(func(x): return x.tipo == sec[0])
		if lista.is_empty(): _dir.add_child(_t("Nada ainda.", 12, E.TINTA_CLARA, "italico")); continue
		for x in lista:
			_dir.add_child(_t(("Turno %d · %s" % [x.turno, x.texto]) if sec[2] else "· " + str(x.texto), 12))
	_dir.add_child(_t("O diário se escreve sozinho: lugares visitados, criaturas encontradas e o que aconteceu.", 11, E.TINTA_CLARA, "italico"))

# ---------- números ----------

static func _sinal(n: int) -> String:
	return "±0" if n == 0 else ("+%d" % n if n > 0 else "−%d" % -n)

static func _milhar(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.substr(0, s.length() - 3) + "." + s.right(3)
