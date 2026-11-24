extends Control
## Livro da ficha (Handoff §1.2, formato B): abas Ficha · Inventário · Diário, um personagem por vez.
## Inventário: arrastar e soltar entre mãos, corpo, cinto e mochila; clique no item abre Usar · Dar a… · Largar.
## Em combate o livro só mostra (trocar de arma é pela barra de ações).

signal mudou(heroi: Node)
signal usar(heroi: Node, item)
signal fechou

const Ficha = preload("res://scripts/regras/ficha.gd")
const UI := "res://arte/final/interface/"
const TINTA := Color(0.2, 0.12, 0.06)
const TINTA_CLARA := Color(0.38, 0.26, 0.15)
const VERMELHO := Color(0.55, 0.12, 0.06)
const LIVRO := Vector2(1030, 618)
const NOMES_LUGAR := {"mao_d": "Mão direita", "mao_e": "Mão esquerda", "corpo": "Corpo", "cinto0": "Cinto", "cinto1": "Cinto"}

var grupo: Array = []
var heroi: Node
var diario: Array = []          # [{turno, tipo, texto}]
var em_combate := false
var adjacentes: Callable        # (a, b) -> bool
var aba := "ficha"

var fonte: Font; var negrito: Font; var titulo: Font; var italico: Font
var _livro: TextureRect
var _esq: VBoxContainer
var _dir: VBoxContainer
var _abas := {}
var _seletor: HBoxContainer
var _menu: PopupMenu
var _menu_acoes: Array = []
var _aviso: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	fonte = load("res://assets/fontes/NotoSerif-Regular.ttf"); negrito = load("res://assets/fontes/NotoSerif-Bold.ttf")
	titulo = load("res://assets/fontes/NotoSerifDisplay-Bold.ttf"); italico = load("res://assets/fontes/NotoSerif-Italic.ttf")
	var t := Theme.new(); t.default_font = fonte; t.default_font_size = 14; theme = t
	var veu := ColorRect.new(); veu.color = Color(0, 0, 0, 0.6); veu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veu.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: fechar())
	add_child(veu)
	_livro = TextureRect.new(); _livro.texture = load(UI + "recortes/livro-aberto.png")
	_livro.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _livro.stretch_mode = TextureRect.STRETCH_SCALE
	_livro.set_anchors_preset(Control.PRESET_CENTER); _livro.size = LIVRO; _livro.position = -LIVRO / 2.0 + Vector2(0, 30)
	_livro.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_livro)
	# Abas de pano presas no topo da página direita.
	var x := 600.0
	for par in [["ficha", "aba-vermelha", "Ficha"], ["inventario", "aba-verde", "Inventário"], ["diario", "aba-azul", "Diário"]]:
		var b := TextureButton.new(); b.texture_normal = load(UI + par[1] + ".png")
		b.ignore_texture_size = true; b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.size = Vector2(110, 80); b.position = Vector2(x, -52); b.focus_mode = Control.FOCUS_NONE
		var l := Label.new(); l.text = par[2]; l.add_theme_font_override("font", negrito); l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(1, 0.95, 0.85)); l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 4); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.offset_top = -8
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(l)
		b.pressed.connect(func(): mostrar(heroi, par[0]))
		_livro.add_child(b); _abas[par[0]] = b; x += 116
	# Seletor de personagem (retratos) acima da página esquerda.
	_seletor = HBoxContainer.new(); _seletor.position = Vector2(70, -50); _seletor.add_theme_constant_override("separation", 6)
	_livro.add_child(_seletor)
	_esq = _pagina(Rect2(0.075, 0.075, 0.385, 0.84))
	_dir = _pagina(Rect2(0.54, 0.075, 0.37, 0.84))
	var fechar_b := Button.new(); fechar_b.text = "✕"; fechar_b.flat = true; fechar_b.focus_mode = Control.FOCUS_NONE
	fechar_b.add_theme_font_size_override("font_size", 22); fechar_b.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	fechar_b.position = Vector2(LIVRO.x - 30, -44); fechar_b.pressed.connect(fechar); _livro.add_child(fechar_b)
	_aviso = Label.new(); _aviso.add_theme_color_override("font_color", Color(1, 0.85, 0.6)); _aviso.add_theme_font_override("font", italico)
	_aviso.add_theme_color_override("font_outline_color", Color.BLACK); _aviso.add_theme_constant_override("outline_size", 4)
	_aviso.position = Vector2(80, LIVRO.y + 4); _aviso.size = Vector2(LIVRO.x - 160, 24)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _livro.add_child(_aviso)
	_menu = PopupMenu.new(); add_child(_menu); _menu.id_pressed.connect(func(i): _menu_acoes[i].call())

func _pagina(r: Rect2) -> VBoxContainer:
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.position = Vector2(r.position.x * LIVRO.x, r.position.y * LIVRO.y); sc.size = Vector2(r.size.x * LIVRO.x, r.size.y * LIVRO.y)
	_livro.add_child(sc)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return v

func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and e.keycode in [KEY_ESCAPE, KEY_I]:
		fechar(); get_viewport().set_input_as_handled()

func fechar() -> void:
	visible = false; fechou.emit()

# ---------- texto ----------

func _t(txt: String, tam := 14, cor := TINTA, f: Font = null, quebra := true) -> Label:
	var l := Label.new(); l.text = txt; l.add_theme_font_size_override("font_size", tam); l.add_theme_color_override("font_color", cor)
	l.add_theme_font_override("font", f if f else fonte)
	if quebra: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _titulo(pai: Control, txt: String) -> void:
	var l := _t(txt, 19, VERMELHO, titulo); pai.add_child(l)
	var linha := ColorRect.new(); linha.color = Color(0.45, 0.25, 0.12, 0.5); linha.custom_minimum_size = Vector2(0, 1); pai.add_child(linha)

func _imagem(arq: String, tam: Vector2, valor := "", dica := "") -> Control:
	var c := Control.new(); c.custom_minimum_size = tam; c.tooltip_text = dica
	var t := TextureRect.new(); t.texture = load(arq); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(t)
	if valor != "":
		var l := _t(valor, int(tam.y * 0.36), Color.WHITE, negrito, false); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85)); l.add_theme_constant_override("outline_size", 6)
		c.add_child(l)
	return c

# ---------- montar ----------

func mostrar(h: Node, nova_aba := "") -> void:
	heroi = h
	if nova_aba != "": aba = nova_aba
	visible = true
	_aviso.text = "Em combate o livro só mostra; para trocar de arma use a barra de ações." if em_combate and aba == "inventario" else ""
	for k in _abas: _abas[k].modulate = Color.WHITE if k == aba else Color(0.7, 0.7, 0.7)
	for k in _abas: _abas[k].position.y = -58 if k == aba else -50
	for c in _seletor.get_children(): c.queue_free()
	for g in grupo:
		var b := TextureButton.new(); b.texture_normal = load("res://arte/final/retratos/%s.jpg" % g.ficha.id)
		b.ignore_texture_size = true; b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		b.custom_minimum_size = Vector2(44, 44); b.tooltip_text = g.nome; b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color.WHITE if g == h else Color(0.6, 0.6, 0.6)
		if not g.vivo(): b.modulate = Color(0.35, 0.3, 0.3)
		b.pressed.connect(func(): mostrar(g))
		_seletor.add_child(b)
	for c in _esq.get_children() + _dir.get_children(): c.queue_free()
	match aba:
		"ficha": _aba_ficha()
		"inventario": _aba_inventario()
		"diario": _aba_diario()

func _aba_ficha() -> void:
	var f = heroi.ficha
	# Cabeçalho
	var cab := HBoxContainer.new(); cab.add_theme_constant_override("separation", 12); _esq.add_child(cab)
	var ret := _retrato(f.id, 104); cab.add_child(ret)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cab.add_child(v)
	v.add_child(_t(str(f.nome), 22, TINTA, titulo))
	v.add_child(_t("%s · nível %d · %s" % [f.classe(), int(f.p.nivel), f.alinhamento()], 14, TINTA_CLARA, italico))
	var b: Array = f.bonus_xp()
	v.add_child(_t("XP %d de %d para o 2º nível" % [f.xp, f.xp_proximo()], 13))
	v.add_child(_t("Requisito principal %s · bônus de XP %s%d%%" % [b[0], "+" if int(b[1]) >= 0 else "", int(b[1])], 12, TINTA_CLARA))
	# PV, CA, THAC0
	var em := HBoxContainer.new(); em.alignment = BoxContainer.ALIGNMENT_CENTER; em.add_theme_constant_override("separation", 22); _esq.add_child(em)
	for x in [["recortes/emblema-coracao.png", "%d/%d" % [maxi(heroi.pv, 0), f.pv_max()], "Pontos de vida"],
			["recortes/emblema-escudo.png", str(f.ca()), "Classe de armadura"], ["emblema-medalhao.png", str(f.thac0()), "THAC0"]]:
		var c := VBoxContainer.new(); c.add_child(_imagem(UI + x[0], Vector2(66, 62), x[1], x[2]))
		var l := _t(x[2], 11, TINTA_CLARA); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.add_child(l); em.add_child(c)
	# Atributos
	_titulo(_esq, "Atributos")
	var g := GridContainer.new(); g.columns = 3; g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 6)
	_esq.add_child(g)
	for k in ["for", "int", "sab", "des", "con", "car"]:
		var m: int = f.mod(k)
		var caixa := PanelContainer.new(); var sb := StyleBoxTexture.new(); sb.texture = load(UI + "ui/pergaminho.png")
		for lado in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: sb.set_texture_margin(lado, 18); sb.set_content_margin(lado, 8)
		caixa.add_theme_stylebox_override("panel", sb); caixa.custom_minimum_size = Vector2(124, 0)
		var lv := VBoxContainer.new(); lv.add_theme_constant_override("separation", 0); caixa.add_child(lv)
		var a := _t(k.to_upper(), 11, TINTA_CLARA, negrito); a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lv.add_child(a)
		var n := _t("%d  (%s%d)" % [int(f.p.atributos[k]), "+" if m >= 0 else "", m], 17, TINTA, titulo); n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(n); g.add_child(caixa)
	_titulo(_esq, "Carga e movimento")
	_esq.add_child(_t("Carga %s · %d de %d espaços na mochila\n%d m por turno de exploração · %d m por rodada de combate" % [
		{"leve": "leve", "media": "média", "pesada": "pesada"}[f.carga()], f.espacos_usados(), f.espacos_max(), int(f.movimento_m()), int(f.movimento_m() / 3.0)], 13))
	# Página direita
	_titulo(_dir, "Jogadas de proteção")
	var pr := HBoxContainer.new(); pr.add_theme_constant_override("separation", 4); _dir.add_child(pr)
	for x in [["morte", "Morte ou veneno"], ["varinhas", "Varinhas"], ["paralisia", "Paralisia ou petrificação"], ["sopro", "Sopro de dragão"], ["magias", "Magias e cajados"]]:
		var c := VBoxContainer.new(); c.custom_minimum_size = Vector2(80, 0)
		c.add_child(_imagem(UI + "recortes/circulo-protecao.png", Vector2(52, 52), str(int(f.p.protecao[x[0]])), x[1]))
		var l := _t(x[1], 10, TINTA_CLARA); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.add_child(l); pr.add_child(c)
	_titulo(_dir, "Ataque")
	var a = f.arma()
	var inf := Ficha.info(a)
	var linhas: Array[String] = []
	if a != null and inf.has("distancia"):
		var faixas: Array = inf.distancia
		linhas.append("À distância: %s %s · DES %+d no acerto · %d/%d/%d m (+1 / 0 / −1) · %d %s" % [inf.nome, inf.dano, f.mod("des"), int(faixas[0]), int(faixas[1]), int(faixas[2]), f.municao_de(a), str(inf.municao)])
	elif a != null:
		linhas.append("Corpo a corpo: %s %s · FOR %+d no acerto e no dano" % [inf.nome, inf.dano, f.mod("for")])
	else:
		linhas.append("Desarmado: 1d2 · FOR %+d" % f.mod("for"))
	linhas.append("Acerta quando d20 + bônus ≥ THAC0 (%d) − CA do alvo. 20 sempre acerta, 1 sempre erra." % f.thac0())
	_dir.add_child(_t("\n".join(linhas), 13))
	_titulo(_dir, "Habilidades")
	var hab: Array[String] = []
	for x in f.habilidades_exploracao(): hab.append("%s — %s" % [x[0], x[1]])
	for x in f.habilidades_especiais(): hab.append(str(x))
	if not f.magias().is_empty(): hab.append("Grimório: " + ", ".join(f.magias()))
	_dir.add_child(_t("· " + "\n· ".join(hab), 13))
	_titulo(_dir, "Idiomas")
	_dir.add_child(_t(", ".join(f.idiomas()), 13))

func _retrato(id: String, tam: int) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(tam, tam)
	var r := TextureRect.new(); r.texture = load("res://arte/final/retratos/%s.jpg" % id); r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := int(tam * 0.14); r.offset_left = m; r.offset_top = m; r.offset_right = -m; r.offset_bottom = -m; c.add_child(r)
	var mold := TextureRect.new(); mold.texture = load(UI + "ui/moldura-retrato.png"); mold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); c.add_child(mold)
	return c

# ---------- inventário ----------

func _aba_inventario() -> void:
	var f = heroi.ficha
	_titulo(_esq, "Equipado")
	_esq.add_child(_t("Arraste os itens entre as mãos, o corpo, o cinto e a mochila. Clique num item para usar, dar ou largar.", 11, TINTA_CLARA, italico))
	var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 10); g.add_theme_constant_override("v_separation", 6)
	_esq.add_child(g)
	for lugar in ["mao_d", "mao_e", "corpo", "cinto0", "cinto1"]:
		var linha := HBoxContainer.new(); linha.add_theme_constant_override("separation", 6)
		linha.add_child(_espaco(f.pegar(lugar), lugar))
		var it = f.pegar(lugar)
		var txt: String = NOMES_LUGAR[lugar] + "\n" + (_nome_item(it) if it != null else "—")
		var l := _t(txt, 12); l.custom_minimum_size = Vector2(120, 0); linha.add_child(l)
		g.add_child(linha)
	_titulo(_esq, "Dinheiro e tesouro")
	var moedas: Array[String] = []
	for k in ["pl", "po", "pe", "pp", "pc"]: moedas.append("%s %d" % [k.to_upper(), int(f.moedas[k])])
	var mh := HBoxContainer.new(); mh.add_child(_imagem(UI + "icones/bolsa-moedas.png", Vector2(40, 40)))
	var ml := _t("  ·  ".join(moedas) + "\nCada 200 moedas ocupam 1 espaço da mochila.", 12); ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(ml); _esq.add_child(mh)
	_titulo(_esq, "Carga")
	_esq.add_child(_t("%s · %d de %d espaços · %d m por turno" % [{"leve": "Leve", "media": "Média", "pesada": "Pesada"}[f.carga()], f.espacos_usados(), f.espacos_max(), int(f.movimento_m())], 13))
	# Mochila
	_titulo(_dir, "Mochila — %d de %d espaços" % [f.espacos_usados(), f.espacos_max()])
	var grade := GridContainer.new(); grade.columns = 5; grade.add_theme_constant_override("h_separation", 6); grade.add_theme_constant_override("v_separation", 6)
	_dir.add_child(grade)
	var usados := 0
	for it in f.mochila:
		var n: int = f._espacos(it)
		grade.add_child(_espaco(it, "mochila"))
		for _i in n - 1: grade.add_child(_espaco(null, "mochila", true))
		usados += n
	for _i in maxi(0, f.espacos_max() - usados): grade.add_child(_espaco(null, "mochila"))
	var lista: Array[String] = []
	for it in f.mochila: lista.append(_nome_item(it))
	if not lista.is_empty(): _dir.add_child(_t(", ".join(lista), 12, TINTA_CLARA))

func _nome_item(it) -> String:
	var inf := Ficha.info(it)
	var s := str(inf.nome)
	if it.qtd > 1: s += " ×%d" % it.qtd
	if inf.has("dano"): s += " (%s)" % inf.dano
	return s

func _espaco(it, lugar: String, continua := false) -> Control:
	var c := Panel.new(); c.custom_minimum_size = Vector2(64, 64)
	var sb := StyleBoxTexture.new(); sb.texture = load(UI + "recortes/espaco-inventario.png")
	c.add_theme_stylebox_override("panel", sb)
	if continua:
		c.modulate = Color(0.85, 0.8, 0.75); c.tooltip_text = "(o item ao lado ocupa 2 espaços)"
		var l := _t("⟵", 22, TINTA_CLARA); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; c.add_child(l)
	elif it != null:
		var ic: Texture2D = Ficha.icone(it)
		if ic:
			var t := TextureRect.new(); t.texture = ic; t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			t.offset_left = 6; t.offset_top = 6; t.offset_right = -6; t.offset_bottom = -6; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(t)
		else:
			var l := _t(str(Ficha.info(it).nome), 10, TINTA, negrito); l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; c.add_child(l)
		if it.qtd > 1:
			var q := _t("×%d" % it.qtd, 13, Color.WHITE, negrito, false); q.add_theme_color_override("font_outline_color", Color.BLACK)
			q.add_theme_constant_override("outline_size", 5); q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; q.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			q.offset_right = -7; q.offset_bottom = -4; c.add_child(q)
		c.tooltip_text = _nome_item(it) + ("\n" + str(Ficha.info(it).dica) if Ficha.info(it).has("dica") else "")
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
	var prev := TextureRect.new(); prev.texture = Ficha.icone(it); prev.size = Vector2(56, 56)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.set_drag_preview(prev)
	return {"item": it}

func _pode_soltar(d, lugar: String) -> bool:
	return d is Dictionary and d.has("item") and not em_combate and heroi.ficha.motivo_para_nao(d.item, lugar) == ""

func _soltar(d, lugar: String) -> void:
	var m: String = heroi.ficha.mover(d.item, lugar)
	_aviso.text = m
	mudou.emit(heroi); mostrar(heroi)

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
	_menu.reset_size(); _menu.position = Vector2i(perto.get_screen_position()) + Vector2i(66, 0); _menu.popup()

func _menu_add(txt: String, acao: Callable, ativo := true) -> void:
	_menu.add_item(txt, _menu_acoes.size()); _menu.set_item_disabled(_menu_acoes.size(), not ativo); _menu_acoes.append(acao)

func _usar(it) -> void:
	usar.emit(heroi, it); mostrar(heroi)

func _dar(it, g: Node) -> void:
	var m: String = heroi.ficha.dar(it, g.ficha)
	_aviso.text = m if m != "" else "%s deu a %s: %s." % [heroi.nome, g.nome, Ficha.info(it).nome]
	mudou.emit(heroi); mudou.emit(g); mostrar(heroi)

func _largar(it) -> void:
	heroi.ficha.tirar(it)
	_aviso.text = "%s largou no chão: %s." % [heroi.nome, Ficha.info(it).nome]
	mudou.emit(heroi); mostrar(heroi)

# ---------- diário ----------

func _aba_diario() -> void:
	_titulo(_esq, "Lugares")
	var lug := diario.filter(func(x): return x.tipo == "lugar")
	_esq.add_child(_t("\n".join(lug.map(func(x): return "Turno %d — %s" % [x.turno, x.texto])) if not lug.is_empty() else "Nada ainda.", 13))
	_titulo(_esq, "Criaturas")
	var cr := diario.filter(func(x): return x.tipo == "criatura")
	_esq.add_child(_t("\n".join(cr.map(func(x): return "· " + x.texto)) if not cr.is_empty() else "Nenhuma ainda.", 13))
	_titulo(_dir, "Acontecimentos")
	var ev := diario.filter(func(x): return x.tipo == "evento")
	_dir.add_child(_t("\n".join(ev.map(func(x): return "Turno %d — %s" % [x.turno, x.texto])) if not ev.is_empty() else "Nada ainda.", 13))
	_dir.add_child(_t("\nO diário se escreve sozinho: lugares visitados, criaturas encontradas e o que aconteceu.", 11, TINTA_CLARA, italico))
