extends Control
## Tela do jogo no padrão "Grimório escuro" (docs/padrao-visual.md):
## cartas do grupo à esquerda · ações em medalhões embaixo · relógio (exploração) ou iniciativa (combate)
## em cima à direita · registro embaixo à direita. A cena principal (explorar.gd) passa o estado e ouve os sinais.

signal modo_pedido(modo: String)
signal acao_pedida(acao: String)          # "atacar", "encerrar", "brotar", "ficha"
signal trocar_arma(heroi: Node, item)     # item da ficha
signal usar_item(heroi: Node, item)
signal ficha_pedida(heroi: Node)

const Ficha = preload("res://scripts/regras/ficha.gd")
const E = preload("res://scripts/interface/estilo.gd")
const ICONES := "res://arte/final/interface/icones/%s.png"
const NOME_CARGA := {"leve": "leve", "media": "média", "pesada": "pesada"}

var _cartas_caixa: VBoxContainer
var _cartas := {}            # heroi -> {margem, painel, retrato, nome, estado, barra, pv, ca, t0, linha, extra}
var _barra: HBoxContainer
var _barra_titulo: Label
var _canto: PanelContainer
var _canto_caixa: VBoxContainer
var _log: RichTextLabel
var _linhas: Array[String] = []
var _menu: PopupMenu
var _menu_itens: Array = []
var _modo_barra := ""
var _herois: Array = []
var _medalhoes: Array = []
var _balao: PanelContainer
var _balao_titulo: Label
var _balao_texto: RichTextLabel
var _seta: Control
var _dica_alvo: PanelContainer
var _dica_nome: Label
var _dica_texto: Label
var _canto_chave := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = E.tema()
	_montar_cartas(); _montar_barra(); _montar_canto(); _montar_log(); _montar_balao(); _montar_dica()
	_menu = PopupMenu.new(); add_child(_menu)
	_menu.id_pressed.connect(_ao_escolher_menu)

# ---------- cartas (esquerda) ----------

func _montar_cartas() -> void:
	var rolagem := ScrollContainer.new()
	rolagem.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rolagem.offset_left = 2; rolagem.offset_top = 2; rolagem.offset_right = 2 + 306; rolagem.offset_bottom = -130
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rolagem.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rolagem.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(rolagem)
	# Margem para o brilho da carta da vez não ser cortado pela rolagem.
	var folga := MarginContainer.new(); folga.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["margin_left", "margin_top", "margin_bottom", "margin_right"]: folga.add_theme_constant_override(k, 14)
	folga.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(folga)
	_cartas_caixa = VBoxContainer.new(); _cartas_caixa.add_theme_constant_override("separation", 10)
	_cartas_caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folga.add_child(_cartas_caixa)

func definir_grupo(herois: Array) -> void:
	_herois = herois
	for c in _cartas_caixa.get_children(): c.queue_free()
	_cartas.clear()
	for h in herois: _cartas[h] = _carta(h)

func _carta(h: Node) -> Dictionary:
	var f = h.ficha
	var margem := MarginContainer.new(); margem.add_theme_constant_override("margin_right", 12)
	margem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartas_caixa.add_child(margem)
	var painel := PanelContainer.new(); painel.add_theme_stylebox_override("panel", E.painel())
	painel.mouse_filter = Control.MOUSE_FILTER_STOP; painel.custom_minimum_size.x = 252
	painel.tooltip_text = "Clique para ver mais · duplo clique abre a ficha"
	margem.add_child(painel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel.add_child(v)
	var linha := HBoxContainer.new(); linha.add_theme_constant_override("separation", 10); linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(linha)
	var ret := E.Retrato.new(f.id, 54, f.nome); linha.add_child(ret)
	var info := VBoxContainer.new(); info.add_theme_constant_override("separation", 4); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE; linha.add_child(info)
	var topo := HBoxContainer.new(); topo.mouse_filter = Control.MOUSE_FILTER_IGNORE; info.add_child(topo)
	var nome := E.rotulo(str(f.nome).get_slice(" ", 0), 15, E.OURO, "titulo"); nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(nome)
	var estado := E.rotulo("", 12, E.TEXTO); topo.add_child(estado)
	var barra := E.Barra.new(); info.add_child(barra)
	var chips := HBoxContainer.new(); chips.add_theme_constant_override("separation", 5); chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(chips)
	var pv := E.chip(""); var ca := E.chip(""); var t0 := E.chip("")
	pv.tooltip_text = "Pontos de vida"; ca.tooltip_text = "Classe de armadura (menor é melhor)"; t0.tooltip_text = "THAC0: precisa tirar THAC0 − CA do alvo no d20"
	for c in [pv, ca, t0]: chips.add_child(c)
	var lin := E.rotulo("", 12, E.TEXTO); lin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.add_child(lin)
	var extra := VBoxContainer.new(); extra.visible = false; extra.add_theme_constant_override("separation", 3); v.add_child(extra)
	var d := {"margem": margem, "painel": painel, "retrato": ret, "nome": nome, "estado": estado, "barra": barra,
		"pv": pv, "ca": ca, "t0": t0, "linha": lin, "extra": extra}
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
	var linha := ColorRect.new(); linha.color = E.FILETE_FRACO; linha.custom_minimum_size = Vector2(0, 1); caixa.add_child(linha)
	caixa.add_child(_texto_carta("Carga %s · %d de %d espaços · %d m por turno" % [NOME_CARGA[f.carga()], f.espacos_usados(), f.espacos_max(), int(f.movimento_m())]))
	var eq: Array[String] = []
	for par in [["mão dir.", f.mao_d], ["mão esq.", f.mao_e], ["corpo", f.corpo]]:
		if par[1] != null: eq.append("%s: %s" % [par[0], Ficha.info(par[1]).nome])
	var cin: Array[String] = []
	for it in f.cinto:
		if it != null: cin.append("%s%s" % [Ficha.info(it).nome, (" ×%d" % it.qtd) if it.qtd > 1 else ""])
	caixa.add_child(_texto_carta("Equipado: %s\nCinto: %s" % [", ".join(eq), ", ".join(cin) if not cin.is_empty() else "vazio"]))
	var hab: Array[String] = []
	for x in f.habilidades_exploracao(): hab.append("%s %s" % [x[0], x[1]])
	caixa.add_child(_texto_carta("Exploração: " + " · ".join(hab)))

func _texto_carta(txt: String) -> Label:
	var l := E.rotulo(txt, 12, E.TEXTO); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## estados: heroi -> texto curto à direita do nome ("sua vez", "já agiu"…); vez: quem age agora.
func _atualizar_cartas(vez: Node, lider: Node, luz_txt: String, estados: Dictionary) -> void:
	for h in _cartas:
		if not is_instance_valid(h): continue
		var d: Dictionary = _cartas[h]; var f = h.ficha
		d.pv.get_child(0).text = "PV %d/%d" % [maxi(h.pv, 0), h.pv_max]
		d.ca.get_child(0).text = "CA %d" % h.ca
		d.t0.get_child(0).text = "T0 %d" % f.thac0()
		d.barra.definir(float(maxi(h.pv, 0)) / maxf(1.0, h.pv_max))
		var a = f.arma()
		var txt := "%s %s" % [Ficha.info(a).nome, Ficha.info(a).get("dano", "")] if a != null else "desarmado"
		if a != null and Ficha.info(a).has("municao"): txt += " · %d %s" % [f.municao_de(a), str(Ficha.info(a).municao)]
		if h == lider and vez == null: txt += " · " + luz_txt
		if not h.vivo(): txt = "caído"
		d.linha.text = txt
		var ativo: bool = h == vez
		var estado: String = estados.get(h, "%s %d" % [f.classe(), int(f.p.nivel)])
		if not h.vivo(): estado = "caído"
		d.estado.text = estado
		d.estado.add_theme_color_override("font_color", E.OURO_CLARO if ativo else E.TEXTO)
		d.nome.add_theme_color_override("font_color", E.OURO_VEZ if ativo else E.OURO)
		d.painel.add_theme_stylebox_override("panel", E.painel(ativo))
		d.margem.add_theme_constant_override("margin_left", 10 if ativo else 0)
		d.margem.add_theme_constant_override("margin_right", 2 if ativo else 12)
		d.retrato.aro(E.OURO_CLARO if ativo else Color("#c49a52"))
		d.retrato.apagar(0.9 if not h.vivo() else 0.0)
		d.painel.modulate = Color(1, 1, 1, 0.55) if not h.vivo() else (Color(1, 1, 1, 0.78) if estado == "já agiu" else Color.WHITE)

# ---------- barra de ações (embaixo, medalhões) ----------

func _montar_barra() -> void:
	var fundo := VBoxContainer.new(); fundo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fundo.offset_left = 290; fundo.offset_right = -420; fundo.offset_top = -140; fundo.offset_bottom = -10
	fundo.alignment = BoxContainer.ALIGNMENT_END; fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_theme_constant_override("separation", 8)
	add_child(fundo)
	_barra_titulo = E.rotulo("", 14, E.OURO_CLARO, "titulo"); _barra_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fundo.add_child(_barra_titulo)
	_barra = HBoxContainer.new(); _barra.alignment = BoxContainer.ALIGNMENT_CENTER
	_barra.add_theme_constant_override("separation", 4); _barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_child(_barra)

func _limpar_barra() -> void:
	for c in _barra.get_children(): c.queue_free()
	_medalhoes.clear()
	_esconder_balao()

func _med(rotulo: String, sigla := "", icone := "", tecla := "", contador := "", titulo := "", texto := "") -> E.Medalhao:
	var tex: Texture2D = load(ICONES % icone) if icone != "" and ResourceLoader.exists(ICONES % icone) else null
	var m := E.Medalhao.new(rotulo, sigla, tex, tecla, contador)
	m.balao_titulo = titulo if titulo != "" else rotulo.replace("\n", " ")
	m.balao_texto = texto
	m.mouse_entered.connect(func(): _mostrar_balao(m))
	m.mouse_exited.connect(_esconder_balao)
	_barra.add_child(m); _medalhoes.append(m)
	return m

func _filete() -> void:
	_barra.add_child(E.filete_vertical(56))

## Aperta o medalhão com esta tecla (atalhos do teclado). Devolve true se havia um ativo.
func atalho(tecla: String) -> bool:
	for m in _medalhoes:
		if is_instance_valid(m) and m.tecla == tecla and not m.disabled:
			if m.toggle_mode: m.button_pressed = true
			m.pressed.emit()
			return true
	return false

func _barra_exploracao(modos: Dictionary, modo: String, lider: Node) -> void:
	_limpar_barra()
	var i := 1
	for k in ["devagar", "normal", "rapido"]:
		var nome: String = modos[k].nome
		var m := _med(nome, nome.substr(0, 2), "", str(i), "", nome, str(modos[k].dica))
		m.ativo = k == modo
		m.pressed.connect(func(): modo_pedido.emit(k))
		i += 1
	_filete()
	var hab := {}
	if lider and lider.get("ficha"):
		for x in lider.ficha.habilidades_exploracao(): hab[x[0]] = x[1]
	var ou := _med("Ouvir", "Ou", "", "", str(hab.get("Ouvir", "")), "Ouvir atrás da porta",
		"Chance de %s: %s.\nChega com as habilidades." % [lider.nome if lider else "quem lidera", hab.get("Ouvir", "?")])
	ou.disabled = true
	var pr := _med("Procurar", "Pr", "", "", str(hab.get("Achar porta secreta", "")), "Procurar portas e armadilhas",
		"1 turno por área. Porta secreta %s, armadilha %s.\nChega com as habilidades." % [hab.get("Achar porta secreta", "?"), hab.get("Achar armadilha", "?")])
	pr.disabled = true
	var fi := _med("Ficha", "", "bolsa-moedas", "I", "", "Livro da ficha", "Atributos, habilidades, magias, equipamento e diário.")
	fi.pressed.connect(func(): acao_pedida.emit("ficha"))
	_filete()
	var br := _med("Brotar\ngoblin", "Gb", "", "B", "teste", "Brotar goblin (teste)", "Põe 1 goblin ao lado do grupo.")
	br.pressed.connect(func(): acao_pedida.emit("brotar"))

## Ações do personagem da vez. As de classe que ainda não funcionam aparecem apagadas, com o motivo.
func _barra_combate(h: Node, alvo: Dictionary) -> void:
	_limpar_barra()
	var f = h.ficha
	var a = f.arma()
	var dist: bool = a != null and Ficha.info(a).has("distancia")
	var icone_arma := str(Ficha.info(a).get("icone", "")) if a != null else ""
	var conta := "Acerto: d20 %+d ≥ THAC0 %d − CA do alvo\nDano: %s" % [h.dist_mod if dist else h.mod_acerto, f.thac0(), h.dist_dano if dist else h.dano]
	if not alvo.is_empty():
		conta = "Contra [b]%s[/b]: precisa de [b]%d[/b] (%d%%)\nDano: %s" % [alvo.nome, alvo.n, alvo.chance, alvo.dano]
	var at := _med("Atirar" if dist else "Atacar", "At" if icone_arma == "" else "", icone_arma, "1", "",
		"Atirar" if dist else "Atacar", "Clique num inimigo, ou 1 para o mais próximo.\n" + conta)
	at.pressed.connect(func(): acao_pedida.emit("atacar"))
	# Ações da classe (mecânica nas próximas etapas).
	match str(f.p.classe):
		"ladrao":
			var hl: Dictionary = f.p.habilidades_ladrao
			_med("Ataque\nfurtivo", "Fu", "", "", "+4 ×2", "Ataque furtivo", "+4 no acerto e dano ×2, pelas costas de quem não notou o %s.\nChega com as habilidades." % h.nome).disabled = true
			_med("Esconder-se", "Es", "", "", "%d%%" % int(hl.esconder), "Esconder-se nas sombras", "Teste oculto: você não sabe se falhou.\nChega com as habilidades.").disabled = true
			_med("Mover em\nsilêncio", "Si", "", "", "%d%%" % int(hl.silencio), "Mover em silêncio", "Teste oculto: você não sabe se falhou.\nChega com as habilidades.").disabled = true
		"mago", "elfo":
			var n: int = f.magias_por_dia()
			var nomes: Array = f.memorizadas().map(func(x): return str(Ficha.magias_catalogo().magias.get(x, {}).get("nome", x)))
			var mg := _med("Magia", "Mg", "", "", "%d/%d" % [maxi(n - f.magias_gastas, 0), n], "Magia",
				"Memorizada: %s.\nDeclarada antes da iniciativa; se for atingido antes de agir, perde a magia.\nChega com as habilidades." % ", ".join(nomes))
			mg.cor_sigla = E.ARCANA; mg.disabled = true
		"clerigo":
			_med("Afastar\nmortos-vivos", "Af", "", "", "2d6", "Afastar mortos-vivos", "2d6: esqueleto 7+, zumbi 9+, carniçal 11+.\nChega com as habilidades.").disabled = true
			_med("Orar", "Or", "", "", "nível 2", "Orar", "A primeira oração chega no 2º nível.").disabled = true
	_filete()
	var tr := _med("Trocar arma", "Tr", "", "2", "", "Trocar arma", "Empunhar outra arma do cinto ou da mochila (uma vez por vez, sem gastar o ataque).")
	tr.disabled = f.armas_guardadas().is_empty() or bool(h.get_meta("trocou", false))
	tr.pressed.connect(func(): _abrir_menu(h, f.armas_guardadas(), "trocar", tr))
	var cin: Array = f.cinto.filter(func(x): return x != null)
	var ic := str(Ficha.info(cin[0]).get("icone", "")) if not cin.is_empty() else ""
	var us := _med("Cinto", "Ci" if ic == "" else "", ic, "3", ("×%d" % cin[0].qtd) if not cin.is_empty() and cin[0].qtd > 1 else "",
		"Cinto", "Usar um item de acesso rápido: " + (", ".join(cin.map(func(x): return str(Ficha.info(x).nome))) if not cin.is_empty() else "vazio") + ".")
	us.disabled = cin.is_empty()
	us.pressed.connect(func(): _abrir_menu(h, cin, "usar", us))
	_filete()
	var en := _med("Encerrar", "Fim", "", "Esp", "", "Encerrar a vez", "Espaço ou Enter.")
	en.pressed.connect(func(): acao_pedida.emit("encerrar"))

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

# ---------- balão de ação ----------

func _montar_balao() -> void:
	_balao = PanelContainer.new(); _balao.add_theme_stylebox_override("panel", E.painel())
	_balao.visible = false; _balao.mouse_filter = Control.MOUSE_FILTER_IGNORE; _balao.custom_minimum_size.x = 300
	add_child(_balao)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balao.add_child(v)
	_balao_titulo = E.rotulo("", 14, E.OURO, "titulo"); v.add_child(_balao_titulo)
	_balao_texto = RichTextLabel.new(); _balao_texto.bbcode_enabled = true; _balao_texto.fit_content = true
	_balao_texto.scroll_active = false; _balao_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balao_texto.custom_minimum_size.x = 280
	_fontes_rich(_balao_texto, 13); v.add_child(_balao_texto)
	_seta = Control.new(); _seta.size = Vector2(16, 9); _seta.visible = false; _seta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seta.draw.connect(func():
		_seta.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(8, 9)]), E.COURO)
		_seta.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(8, 9), Vector2(16, 0)]), E.FILETE, 1.0, true))
	add_child(_seta)

func _mostrar_balao(m: Control) -> void:
	if m.balao_texto == "" and m.balao_titulo == "": return
	_balao_titulo.text = m.balao_titulo
	_balao_texto.text = m.balao_texto
	_balao.visible = true; _balao.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(m) or not _balao.visible: return
	var centro: float = m.global_position.x + m.size.x * 0.5
	var topo: float = m.global_position.y - 8
	_balao.global_position = Vector2(clampf(centro - 40, 8, size.x - _balao.size.x - 8), topo - _balao.size.y - 9)
	_seta.global_position = Vector2(centro - 8, topo - 9.5); _seta.visible = true; _seta.queue_redraw()

func _esconder_balao() -> void:
	if _balao: _balao.visible = false; _seta.visible = false

# ---------- dica do alvo (na cena) ----------

func _montar_dica() -> void:
	_dica_alvo = PanelContainer.new(); var sb := E.painel(); sb.content_margin_top = 5; sb.content_margin_bottom = 6; sb.content_margin_left = 10; sb.content_margin_right = 10
	_dica_alvo.add_theme_stylebox_override("panel", sb); _dica_alvo.visible = false; _dica_alvo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dica_alvo)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 1); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; _dica_alvo.add_child(v)
	_dica_nome = E.rotulo("", 13, E.FERIDO, "titulo"); v.add_child(_dica_nome)
	_dica_texto = E.rotulo("", 12, E.TEXTO); v.add_child(_dica_texto)

## alvo: {} ou {nome, estado, n, chance, dano, tela: Vector2}
func _atualizar_dica(alvo: Dictionary) -> void:
	if alvo.is_empty():
		_dica_alvo.visible = false; return
	_dica_nome.text = "%s · %s" % [alvo.nome, alvo.estado]
	_dica_nome.add_theme_color_override("font_color", E.OURO if alvo.estado == "ileso" else E.FERIDO)
	_dica_texto.text = "Precisa de %d no d20 (%d%%) · dano %s" % [alvo.n, alvo.chance, alvo.dano]
	_dica_alvo.visible = true; _dica_alvo.reset_size()
	_dica_alvo.position = (alvo.tela as Vector2) + Vector2(34, -_dica_alvo.size.y * 0.5)

# ---------- canto superior direito: relógio ou iniciativa ----------

func _montar_canto() -> void:
	_canto = PanelContainer.new(); var sb := E.painel(); sb.content_margin_left = 14; sb.content_margin_right = 14
	_canto.add_theme_stylebox_override("panel", sb)
	_canto.set_anchors_preset(Control.PRESET_TOP_RIGHT); _canto.offset_right = -16; _canto.offset_top = 16
	_canto.grow_horizontal = Control.GROW_DIRECTION_BEGIN; _canto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canto)
	_canto_caixa = VBoxContainer.new(); _canto_caixa.add_theme_constant_override("separation", 6)
	_canto_caixa.mouse_filter = Control.MOUSE_FILTER_IGNORE; _canto.add_child(_canto_caixa)

func _limpar_canto() -> void:
	for c in _canto_caixa.get_children(): c.queue_free()
	_canto.reset_size()

## r: {area, turno, hora, andado, taxa, errantes, xp, tocha, tocha_max, reserva}
func _canto_relogio(r: Dictionary) -> void:
	var chave := "rel:" + str(r)
	if chave == _canto_chave: return
	_canto_chave = chave
	_limpar_canto()
	_canto.custom_minimum_size.x = 300
	var topo := HBoxContainer.new(); topo.mouse_filter = Control.MOUSE_FILTER_IGNORE; _canto_caixa.add_child(topo)
	var area := E.rotulo(str(r.area), 18, E.OURO, "titulo"); area.size_flags_horizontal = Control.SIZE_EXPAND_FILL; topo.add_child(area)
	topo.add_child(E.rotulo("Turno %d · %s" % [int(r.turno), str(r.hora)], 12, E.TEXTO))
	_canto_caixa.add_child(E.rotulo("Andado no turno: %s de %d m" % [_num(float(r.andado)), int(r.taxa)], 12, E.TEXTO))
	var b := E.Barra.new(); b.cores = [Color("#8a6a3a"), Color("#e6c27a")]; b.custom_minimum_size.y = 6
	b.definir(float(r.andado) / maxf(1.0, float(r.taxa))); _canto_caixa.add_child(b)
	var luz := HBoxContainer.new(); luz.add_theme_constant_override("separation", 4); luz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canto_caixa.add_child(luz)
	var ic := TextureRect.new(); ic.texture = load(ICONES % "tocha"); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.custom_minimum_size = Vector2(18, 18); luz.add_child(ic)
	for i in int(r.tocha_max):
		var s := Panel.new(); s.custom_minimum_size = Vector2(16, 7); s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new(); sb.set_corner_radius_all(2)
		sb.bg_color = Color("#e8a33a") if i < int(r.tocha) else Color(0.77, 0.6, 0.32, 0.2)
		s.add_theme_stylebox_override("panel", sb); s.mouse_filter = Control.MOUSE_FILTER_IGNORE; luz.add_child(s)
	luz.add_child(E.rotulo("  +%d tochas" % int(r.reserva) if int(r.tocha) > 0 else "  sem luz · +%d tochas" % int(r.reserva), 12, E.TEXTO))
	luz.tooltip_text = "Tocha acesa: %d de %d turnos" % [int(r.tocha), int(r.tocha_max)]
	_canto_caixa.add_child(E.rotulo("Teste de errantes no turno %d · XP do grupo %d" % [int(r.errantes), int(r.xp)], 12, E.TEXTO))

## ordem: [{nome, lado, vivo, retrato, vez, agiu}]
func _canto_iniciativa(rodada: int, ini: Array, ordem: Array) -> void:
	var chave := "ini:%d:%s:%s" % [rodada, str(ini), str(ordem)]
	if chave == _canto_chave: return
	_canto_chave = chave
	_limpar_canto()
	_canto.custom_minimum_size.x = 0
	var topo := HBoxContainer.new(); topo.alignment = BoxContainer.ALIGNMENT_END; topo.add_theme_constant_override("separation", 10)
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE; _canto_caixa.add_child(topo)
	topo.add_child(E.rotulo("surpresa" if int(ini[0]) == 0 else "grupo %d × monstros %d" % [int(ini[0]), int(ini[1])], 12, E.TEXTO))
	topo.add_child(E.rotulo("Rodada %d" % rodada, 17, E.OURO, "titulo"))
	var fila := HBoxContainer.new(); fila.alignment = BoxContainer.ALIGNMENT_END; fila.add_theme_constant_override("separation", 8)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE; _canto_caixa.add_child(fila)
	var lado_antes := ""
	for e in ordem:
		if lado_antes != "" and e.lado != lado_antes: fila.add_child(E.filete_vertical(42))
		lado_antes = e.lado
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 2)
		v.alignment = BoxContainer.ALIGNMENT_BEGIN
		var tam := 54.0 if e.vez else 42.0
		var r := E.Retrato.new(str(e.retrato), tam, str(e.nome))
		r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		r.aro(E.OURO_CLARO if e.vez else (E.GRUPO if e.lado == "grupo" else E.INIMIGO), 3.0 if e.vez else 2.0)
		if not e.vivo: r.apagar(0.9)
		v.add_child(r)
		var n := E.rotulo(str(e.nome), 11, E.OURO_CLARO if e.vez else E.TEXTO); n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = 54; n.clip_text = true; n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n)
		if e.agiu or not e.vivo: v.modulate.a = 0.5
		fila.add_child(v)

# ---------- registro (inferior direito) ----------

func _montar_log() -> void:
	var caixa := Control.new(); caixa.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	caixa.offset_left = -416; caixa.offset_right = -16; caixa.offset_top = -216; caixa.offset_bottom = -16
	caixa.mouse_filter = Control.MOUSE_FILTER_IGNORE; caixa.clip_contents = true
	add_child(caixa)
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(0.04, 0.03, 0.02, 0.0), Color(0.04, 0.03, 0.02, 0.8), Color(0.04, 0.03, 0.02, 0.85)])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 64
	var fundo := TextureRect.new(); fundo.texture = gt; fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_SCALE; fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE; caixa.add_child(fundo)
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14; v.offset_right = -14; v.offset_bottom = -12; v.offset_top = 12
	v.alignment = BoxContainer.ALIGNMENT_END; v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE; caixa.add_child(v)
	_log = RichTextLabel.new(); _log.bbcode_enabled = true; _log.fit_content = true; _log.scroll_active = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fontes_rich(_log, 13)
	_log.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); _log.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(_log)

func _fontes_rich(r: RichTextLabel, tam: int) -> void:
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]: r.add_theme_font_size_override(k, tam)
	r.add_theme_font_override("normal_font", E.fonte("texto")); r.add_theme_font_override("bold_font", E.fonte("negrito"))
	r.add_theme_font_override("italics_font", E.fonte("italico"))
	r.add_theme_color_override("default_color", E.REGISTRO)

func registrar(txt: String) -> void:
	_linhas.append(txt)
	if _linhas.size() > 14: _linhas.pop_front()
	# As linhas antigas vão sumindo para cima.
	var partes: Array[String] = []
	var n := _linhas.size()
	for i in n:
		var idade := n - 1 - i
		var alfa: float = [1.0, 0.85, 0.7, 0.58][idade] if idade < 4 else 0.45
		partes.append("[color=#e6dac0%02x]%s[/color]" % [int(alfa * 255), _linhas[i]])
	_log.text = "\n".join(partes)

# ---------- estado ----------

## Exploração: relógio no canto e modos na barra.
func atualizar_exploracao(modos: Dictionary, modo: String, relogio: Dictionary, lider: Node, luz_txt: String) -> void:
	var chave := "exploracao:%s:%s" % [modo, str(lider.get_instance_id()) if lider else ""]
	if _modo_barra != chave:
		_modo_barra = chave; _barra_exploracao(modos, modo, lider)
	_barra_titulo.text = ""
	_canto_relogio(relogio)
	_atualizar_dica({})
	_atualizar_cartas(null, lider, luz_txt, {})

## Combate: iniciativa no canto, ações do personagem da vez na barra.
## ordem: [{nome, lado, vivo, retrato, vez}]; ini: [d6 grupo, d6 monstros]; alvo: dica do inimigo sob o mouse.
func atualizar_combate(rodada: int, ini: Array, ordem: Array, vez: Node, info: String, lider: Node, luz_txt: String, alvo: Dictionary) -> void:
	var i_vez := -1
	for i in ordem.size():
		if ordem[i].vez: i_vez = i
	var estados := {}
	for i in ordem.size():
		ordem[i]["agiu"] = i_vez >= 0 and i < i_vez
	for h in _cartas:
		var idx := -1
		for i in ordem.size():
			if ordem[i].get("no") == h: idx = i
		if h == vez: estados[h] = "sua vez"
		elif idx >= 0 and i_vez >= 0: estados[h] = "já agiu" if idx < i_vez else "depois"
	for e in ordem: e.erase("no")
	var vivos := ordem.filter(func(e): return e.vivo).size()
	var alvo_chave := "%s:%s" % [alvo.get("nome", ""), alvo.get("n", "")]
	var chave := "combate:%d:%s:%s:%d:%d:%s" % [rodada, str(vez.get_instance_id()) if vez else "", _assinatura(vez), vivos, ordem.size(), alvo_chave]
	if _modo_barra != chave:
		_modo_barra = chave
		_limpar_barra()
		if vez and vez.lado == "grupo": _barra_combate(vez, alvo)
	_canto_iniciativa(rodada, ini, ordem)
	_barra_titulo.text = info
	_atualizar_dica(alvo if vez and vez.lado == "grupo" else {})
	_atualizar_cartas(vez, lider, luz_txt, estados)

## Muda quando algo que a barra mostra muda (arma na mão, cinto, troca feita).
func _assinatura(h: Node) -> String:
	if h == null or not h.get("ficha"): return ""
	var f = h.ficha
	return "%s|%s|%s" % [str(f.mao_d), str(f.cinto), str(h.get_meta("trocou", false))]

func refazer() -> void:
	_modo_barra = ""; _canto_chave = ""

static func _num(x: float) -> String:
	return ("%.1f" % x).replace(".", ",")
