extends Node
## Efeitos sonoros: cada evento do jogo (passo, porta, golpe, dado…) toca um dos arquivos de
## data/sons.json, sorteado e com uma pequena variação de tom, na posição de quem faz a ação
## (som 3D, ouvido pela câmera) ou direto (interface). Um nó só, criado por explorar.gd.
##
## Uso: Sons.tocar("porta_abrir", no_ou_posicao)   ·   Sons.tocar("livro_abrir")

const ARQ := "res://data/sons.json"
const MAX_SIMULTANEOS := 24

static var atual: Node = null
var eventos := {}
var criaturas := {}
var fundo := {}
var _cache := {}
var ligado := true
var _log := OS.get_cmdline_user_args().has("--sons-log")   # imprime cada som pedido (diagnóstico)
var musica_ligada := true
var _camadas := {}   # "ambiente"/"musica" -> AudioStreamPlayer

func _ready() -> void:
	atual = self
	if FileAccess.file_exists(ARQ):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
		eventos = d.eventos; criaturas = d.get("criaturas", {}); fundo = d.get("fundo", {})

func _exit_tree() -> void:
	if atual == self: atual = null

## Toca `evento`. `onde`: Node3D ou Vector3 (som no lugar); null = som direto (interface).
static func tocar(evento: String, onde = null, volume_extra := 0.0) -> void:
	if atual == null or not atual.ligado: return
	atual._tocar(evento, onde, volume_extra)

## Som da criatura para um momento ("voz", "dor", "morte", "alerta", "passo"), pelo id do ator
## (data/sons.json "criaturas"). Devolve false se ela não tem som para isso.
static func criatura(ator: Node, momento: String, volume_extra := 0.0) -> bool:
	if atual == null or ator == null: return false
	var id := "grupo" if str(ator.get("lado")) == "grupo" else str(ator.get_meta("id", ""))
	var ev := str(atual.criaturas.get(id, {}).get(momento, ""))
	if ev == "": return false
	tocar(ev, ator, volume_extra)
	return true

## Som contínuo preso a um nó (tocha crepitando); devolve o player (pare com `parar_laco`).
static func laco(evento: String, no: Node3D, deslocar := Vector3(0, 1.4, 0)) -> Node:
	if atual == null: return null
	var e: Dictionary = atual.eventos.get(evento, {})
	if e.is_empty() or not ResourceLoader.exists(str(e.arquivos[0])): return null
	var st: AudioStream = load(str(e.arquivos[randi() % e.arquivos.size()])).duplicate()
	if st is AudioStreamOggVorbis: st.loop = true
	var p := AudioStreamPlayer3D.new()
	p.stream = st; p.volume_db = float(e.get("volume_db", -20)); p.unit_size = 3.0
	p.max_distance = float(e.get("distancia", 8)); p.name = "Laco_" + evento
	no.add_child(p); p.position = deslocar
	p.play(randf() * maxf(st.get_length() - 0.1, 0.0))
	return p

static func parar_laco(evento: String, no: Node3D) -> void:
	if no == null: return
	var p := no.get_node_or_null("Laco_" + evento)
	if p: p.queue_free()

## Liga as camadas de fundo (ambiente e música), que emendam um arquivo no outro.
static func comecar_fundo() -> void:
	if atual == null: return
	for k in ["ambiente", "musica"]: atual._camada(k)

static func alternar_musica() -> bool:
	if atual == null: return false
	atual.musica_ligada = not atual.musica_ligada
	var p: AudioStreamPlayer = atual._camadas.get("musica")
	if p: p.stream_paused = not atual.musica_ligada
	if atual.musica_ligada and p == null: atual._camada("musica")
	return atual.musica_ligada

func _camada(k: String) -> void:
	var c: Dictionary = fundo.get(k, {})
	if c.is_empty() or (k == "musica" and not musica_ligada): return
	var lista: Array = (c.arquivos as Array).filter(func(a): return ResourceLoader.exists(str(a)))
	if lista.is_empty(): return
	var p: AudioStreamPlayer = _camadas.get(k)
	if p == null:
		p = AudioStreamPlayer.new(); p.name = "Fundo_" + k; add_child(p); _camadas[k] = p
		p.finished.connect(func(): _camada(k))
	p.stream = load(str(lista[randi() % lista.size()])); p.volume_db = float(c.get("volume_db", -20))
	p.play()

func _tocar(evento: String, onde, volume_extra: float) -> void:
	var e: Dictionary = eventos.get(evento, {})
	if _log: print("SOM ", evento, " @ ", onde.global_position if onde is Node3D else onde, "" if not e.is_empty() else " (NÃO EXISTE)")
	if e.is_empty(): return
	var lista: Array = e.arquivos
	var arq: String = lista[randi() % lista.size()]
	if not _cache.has(arq):
		if not ResourceLoader.exists(arq): return
		_cache[arq] = load(arq)
	if get_child_count() >= MAX_SIMULTANEOS + _camadas.size(): return
	for outro in e.get("tambem", []): _tocar(str(outro), onde, volume_extra)   # camadas (ex.: ferrolho + rangido)
	var tom := float(e.get("tom_base", 1.0)) * (1.0 + randf_range(-1.0, 1.0) * float(e.get("tom", 0.0)))
	var vol := float(e.get("volume_db", 0.0)) + volume_extra
	if bool(e.get("espacial", false)) and onde != null:
		var p := AudioStreamPlayer3D.new()
		p.stream = _cache[arq]; p.volume_db = vol; p.pitch_scale = tom
		p.unit_size = 9.0; p.max_distance = float(e.get("distancia", 30.0))
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		p.global_position = onde.global_position if onde is Node3D else onde
		p.finished.connect(p.queue_free); p.play()
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = _cache[arq]; p2.volume_db = vol; p2.pitch_scale = tom
		add_child(p2); p2.finished.connect(p2.queue_free); p2.play()
