extends RefCounted
## Padrão visual "Grimório escuro" (aprovado em 25/11/2026, docs/padrao-visual.md).
## Toda interface do jogo usa estas cores, fontes e peças: couro escuro com filete dourado sobre a cena,
## pergaminho no livro da ficha, retratos redondos com aro dourado, ações em medalhões redondos.

# ---------- cores ----------
const COURO := Color(0.08, 0.055, 0.035, 0.9)
const COURO_LIVRO := Color(0.16, 0.1, 0.055)
const FILETE := Color(0.77, 0.6, 0.32, 0.55)
const FILETE_FRACO := Color(0.77, 0.6, 0.32, 0.3)
const OURO := Color("#e6c27a")
const OURO_CLARO := Color("#f0d08a")
const OURO_VEZ := Color("#fbe2a2")
const TEXTO := Color("#cdbb9a")
const TEXTO_CLARO := Color("#efe2c4")
const REGISTRO := Color("#e6dac0")
const PV_ESCURO := Color("#8e1f17")
const PV_CLARO := Color("#c8402d")
const GRUPO := Color("#5b7fb8")
const INIMIGO := Color("#b8432f")
const FERIDO := Color("#f2b29a")
const ARCANA := Color("#b9d0ff")
const GEMA := Color("#3a5aa8")
const ACERTO := Color("#f0c060")
const TINTA := Color("#2b1b0e")
const TINTA_CLARA := Color("#5a4226")
const SANGUE := Color("#7a2a14")
const COURO_ARO := Color("#6b4a24")
const ABA := {"habilidades": Color("#7a2a14"), "magias": Color("#2a3a6a"), "equipamento": Color("#6b4a24"), "diario": Color("#2e4a3a")}
const QUANDO := {"ex": ["EXPLORAÇÃO", Color("#2e4a3a")], "co": ["COMBATE", Color("#7a2a14")], "am": ["EXPL. E COMBATE", Color("#6b4a24")]}

const RETRATOS := "res://arte/final/retratos/%s.jpg"
const SHADER_RETRATO := preload("res://shaders/ui_retrato.gdshader")

# ---------- fontes ----------
static var _fontes := {}

## tipo: "titulo" (Cinzel 700), "texto" (Alegreya), "negrito" (Alegreya 700), "italico" (Alegreya itálico)
static func fonte(tipo := "texto") -> Font:
	if _fontes.has(tipo): return _fontes[tipo]
	var arq: String = {"titulo": "Cinzel", "texto": "Alegreya", "negrito": "Alegreya", "italico": "Alegreya-Italic"}[tipo]
	var base: Font = load("res://assets/fontes/%s.ttf" % arq)
	var v := FontVariation.new(); v.base_font = base
	var peso := 700 if tipo in ["titulo", "negrito"] else 400
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): peso}
	_fontes[tipo] = v
	return v

static func tema() -> Theme:
	var t := Theme.new(); t.default_font = fonte("texto"); t.default_font_size = 14
	# Dicas (tooltip) e menus também em couro.
	var sb := painel(); sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_color("font_color", "TooltipLabel", REGISTRO)
	t.set_font("font", "TooltipLabel", fonte("texto")); t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_stylebox("panel", "PopupMenu", sb)
	t.set_stylebox("hover", "PopupMenu", _caixa(Color(0.77, 0.6, 0.32, 0.25), 3))
	t.set_color("font_color", "PopupMenu", TEXTO_CLARO); t.set_color("font_hover_color", "PopupMenu", OURO_VEZ)
	t.set_color("font_disabled_color", "PopupMenu", Color(TEXTO, 0.45))
	t.set_font("font", "PopupMenu", fonte("texto")); t.set_font_size("font_size", "PopupMenu", 14)
	# Rolagem discreta: trilho invisível, pegador fino cor de couro.
	var trilho := StyleBoxEmpty.new(); trilho.content_margin_left = 4; trilho.content_margin_right = 0
	var pega := _caixa(Color(0.48, 0.16, 0.08, 0.45), 2); pega.content_margin_left = 4
	t.set_stylebox("scroll", "VScrollBar", trilho)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]: t.set_stylebox(k, "VScrollBar", pega)
	return t

# ---------- caixas ----------

static func _caixa(cor: Color, raio := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = cor; sb.set_corner_radius_all(raio)
	return sb

## Painel de couro com filete dourado (cartas, canto, balões, dicas).
static func painel(destaque := false) -> StyleBoxFlat:
	var sb := _caixa(COURO, 6)
	sb.set_border_width_all(1)
	sb.border_color = OURO_CLARO if destaque else FILETE
	sb.shadow_color = Color(0.94, 0.82, 0.54, 0.35) if destaque else Color(0, 0, 0, 0.55)
	sb.shadow_size = 12 if destaque else 8
	sb.set_content_margin_all(10)
	return sb

## Ficha pequena de texto sobre couro ("PV 9/9", "CA 3").
static func chip(txt: String) -> PanelContainer:
	var c := PanelContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _caixa(Color(0, 0, 0, 0.35), 3); sb.set_border_width_all(1); sb.border_color = Color(0.77, 0.6, 0.32, 0.45)
	sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 0; sb.content_margin_bottom = 1
	c.add_theme_stylebox_override("panel", sb)
	c.add_child(rotulo(txt, 12, TEXTO_CLARO, "texto", false))
	return c

static func rotulo(txt: String, tam := 14, cor := TEXTO, tipo := "texto", sombra := true) -> Label:
	var l := Label.new(); l.text = txt
	l.add_theme_font_override("font", fonte(tipo)); l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	if sombra:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func filete_vertical(altura := 56.0) -> Control:
	var r := ColorRect.new(); r.color = Color(0.77, 0.6, 0.32, 0.45); r.custom_minimum_size = Vector2(1, altura)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER; r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static var _pergaminho: Texture2D
## Fundo das páginas do livro: pergaminho claro no meio, mais escuro nas bordas.
static func pergaminho() -> Texture2D:
	if _pergaminho: return _pergaminho
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color("#f3e6c8"), Color("#e2cfa4"), Color("#cfb684")])
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.4); t.fill_to = Vector2(1.15, 1.1); t.width = 256; t.height = 256
	_pergaminho = t
	return t

static func retrato_existe(id: String) -> bool:
	return ResourceLoader.exists(RETRATOS % id)

# ---------- peças ----------

## Retrato redondo com aro dourado. Sem arte: medalhão com a inicial.
class Retrato extends Control:
	var textura: Texture2D
	var inicial := ""
	var fundo := Color("#3a2a1a")
	var _mat: ShaderMaterial

	func _init(id: String, tam: float, nome := "") -> void:
		custom_minimum_size = Vector2(tam, tam); size = Vector2(tam, tam)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if id != "" and ResourceLoader.exists("res://arte/final/retratos/%s.jpg" % id):
			textura = load("res://arte/final/retratos/%s.jpg" % id)
		else:
			inicial = (nome if nome != "" else id).substr(0, 1).to_upper()
			fundo = {"mirela": Color("#3a4a8e"), "anselmo": Color("#a8925a")}.get(id, Color("#5a4a3a"))
			var l := Label.new(); l.text = inicial
			l.add_theme_font_override("font", load("res://scripts/interface/estilo.gd").fonte("titulo"))
			l.add_theme_font_size_override("font_size", int(tam * 0.42)); l.add_theme_color_override("font_color", Color("#f3e6c8"))
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
		_mat = ShaderMaterial.new(); _mat.shader = load("res://shaders/ui_retrato.gdshader")
		_mat.set_shader_parameter("largura", clampf(4.0 / tam, 0.03, 0.09))
		material = _mat

	func aro(cor: Color, largura_px := 2.0) -> void:
		_mat.set_shader_parameter("aro", cor)
		_mat.set_shader_parameter("largura", clampf((largura_px + 1.5) / (size.x * 0.5), 0.03, 0.14))

	func apagar(v: float) -> void:
		_mat.set_shader_parameter("apagado", v)

	func _draw() -> void:
		if textura: draw_texture_rect(textura, Rect2(Vector2.ZERO, size), false)
		else: draw_rect(Rect2(Vector2.ZERO, size), fundo)

## Botão de ação: medalhão redondo de couro com aro dourado, tecla no canto, contador embaixo e rótulo.
class Medalhao extends Button:
	var icone: Texture2D
	var sigla := ""
	var tecla := ""
	var contador := ""
	var rotulo := ""
	var ativo := false
	var cor_sigla := Color("#e6c27a")
	var balao_titulo := ""
	var balao_texto := ""
	const R := 27.0

	func _init(p_rotulo: String, p_sigla := "", p_icone: Texture2D = null, p_tecla := "", p_contador := "") -> void:
		rotulo = p_rotulo; sigla = p_sigla; icone = p_icone; tecla = p_tecla; contador = p_contador
		flat = true; focus_mode = Control.FOCUS_NONE; text = ""
		var linhas := rotulo.count("\n") + 1
		custom_minimum_size = Vector2(68, 2 * R + 12 + 14 * linhas)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw); mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw); button_up.connect(queue_redraw)

	func _draw() -> void:
		var E = load("res://scripts/interface/estilo.gd")
		var c := Vector2(size.x * 0.5, R + 4)
		var sobre := is_hovered() and not disabled
		var a := 0.38 if disabled else 1.0
		if ativo and not disabled:
			draw_circle(c, R + 9, Color(0.94, 0.82, 0.54, 0.12)); draw_circle(c, R + 5, Color(0.94, 0.82, 0.54, 0.22))
		draw_circle(c, R + 1, Color(0.08, 0.05, 0.03, a))
		draw_circle(c, R - 1, Color(0.2, 0.14, 0.09, a))
		draw_circle(c + Vector2(-4, -5), R - 7, Color(0.24, 0.17, 0.1, a * 0.7))
		var aro: Color = E.OURO_CLARO if (ativo or sobre) else Color("#a9824a")
		if disabled: aro = Color(0.45, 0.42, 0.38)
		draw_arc(c, R, 0, TAU, 48, Color(aro, a), 2.0, true)
		draw_arc(c, R - 3, 0, TAU, 48, Color(0.08, 0.05, 0.03, a), 1.5, true)
		if is_pressed() or (button_pressed and toggle_mode): draw_circle(c, R - 4, Color(0.94, 0.82, 0.54, 0.12))
		var modula := Color(0.55, 0.55, 0.55, a) if disabled else Color.WHITE
		if icone:
			var t := 34.0
			draw_texture_rect(icone, Rect2(c - Vector2(t, t) * 0.5, Vector2(t, t)), false, modula)
		elif sigla != "":
			var f: Font = E.fonte("titulo")
			var tam := 15 if sigla.length() <= 3 else 12
			if sigla.length() == 1: tam = 24
			var w := f.get_string_size(sigla, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
			draw_string(f, c + Vector2(-w * 0.5, tam * 0.36), sigla, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(cor_sigla, a) * modula)
		var ft: Font = E.fonte("negrito")
		if tecla != "":
			var tw := maxf(16.0, ft.get_string_size(tecla, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 9)
			var r := Rect2(c + Vector2(R * 0.62, -R - 3), Vector2(tw, 15))
			draw_style_box(_pilula(Color(0.77, 0.6, 0.32, a), Color(0, 0, 0, 0)), r)
			draw_string(ft, r.position + Vector2(0, 11.5), tecla, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color(0.08, 0.05, 0.03, a))
		if contador != "":
			var cw := ft.get_string_size(contador, HORIZONTAL_ALIGNMENT_LEFT, -1, 10.5).x + 10
			var r := Rect2(Vector2(c.x - cw * 0.5, c.y + R - 8), Vector2(cw, 15))
			draw_style_box(_pilula(Color(0.29, 0.16, 0.08, maxf(a, 0.7)), Color(0.77, 0.6, 0.32, maxf(a, 0.7))), r)
			draw_string(ft, r.position + Vector2(0, 11.5), contador, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10.5, Color("#f3e6c8"))
		var fl: Font = E.fonte("texto")
		var y := c.y + R + 18.0
		for linha in rotulo.split("\n"):
			draw_string(fl, Vector2(0, y), linha, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(Color("#d8c7a4"), maxf(a, 0.55)))
			y += 13.0

	func _pilula(fundo: Color, borda: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new(); sb.bg_color = fundo; sb.set_corner_radius_all(8)
		if borda.a > 0: sb.set_border_width_all(1); sb.border_color = borda
		return sb

## Barra de PV: vermelha sobre fundo escuro com filete.
class Barra extends Control:
	var fracao := 1.0
	var cores := [Color("#8e1f17"), Color("#c8402d")]
	func _init() -> void:
		custom_minimum_size = Vector2(0, 7); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func definir(f: float) -> void:
		fracao = clampf(f, 0.0, 1.0); queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var fundo := StyleBoxFlat.new(); fundo.bg_color = Color(0, 0, 0, 0.55); fundo.set_corner_radius_all(4)
		fundo.set_border_width_all(1); fundo.border_color = Color(0.77, 0.6, 0.32, 0.35)
		draw_style_box(fundo, r)
		if fracao <= 0.0: return
		var w := (size.x - 2) * fracao
		var p := Rect2(1, 1, w, size.y - 2)
		draw_polygon(PackedVector2Array([p.position, p.position + Vector2(w, 0), p.end, p.position + Vector2(0, p.size.y)]),
			PackedColorArray([cores[0], cores[1], cores[1], cores[0]]))

## Barrinha de chance no pergaminho (habilidades).
class Chance extends Control:
	var fracao := 0.0
	var cor := Color("#7a2a14")
	func _init(f: float, largura := 92.0) -> void:
		fracao = clampf(f, 0.0, 1.0); custom_minimum_size = Vector2(largura, 6); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var f := StyleBoxFlat.new(); f.bg_color = Color(0.17, 0.11, 0.05, 0.15); f.set_corner_radius_all(3)
		draw_style_box(f, Rect2(Vector2.ZERO, size))
		if fracao > 0:
			var b := StyleBoxFlat.new(); b.bg_color = cor; b.set_corner_radius_all(3)
			draw_style_box(b, Rect2(Vector2.ZERO, Vector2(size.x * fracao, size.y)))

## Gema de magia: cheia (pronta), vazia (gasta) ou hachurada (ainda não tem).
class Gema extends Control:
	var estado := "cheia"
	func _init(p_estado := "cheia", tam := 20.0) -> void:
		estado = p_estado; custom_minimum_size = Vector2(tam, tam); mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5; var r := size.x * 0.5 - 1
		match estado:
			"cheia":
				draw_circle(c, r, Color("#1b2a55")); draw_circle(c + Vector2(-r, -r) * 0.15, r * 0.78, Color("#3a5aa8"))
				draw_circle(c + Vector2(-r, -r) * 0.35, r * 0.32, Color("#b9d0ff"))
			"vazia": draw_circle(c, r, Color(0.17, 0.11, 0.05, 0.12))
			"tranca":
				draw_circle(c, r, Color(0.17, 0.11, 0.05, 0.08))
				# Hachura diagonal recortada no círculo.
				var n := Vector2(1, 1).normalized(); var d := Vector2(1, -1).normalized()
				for i in range(-3, 4):
					var s := i * r * 0.28
					var h := sqrt(maxf(r * r - s * s, 0.0))
					draw_line(c + n * s - d * h, c + n * s + d * h, Color(0.17, 0.11, 0.05, 0.3), 1.2)
		draw_arc(c, r, 0, TAU, 32, Color("#6b4a24"), 2.0, true)
