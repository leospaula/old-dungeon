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
var _cache := {}
var ligado := true

func _ready() -> void:
	atual = self
	if FileAccess.file_exists(ARQ): eventos = JSON.parse_string(FileAccess.get_file_as_string(ARQ)).eventos

func _exit_tree() -> void:
	if atual == self: atual = null

## Toca `evento`. `onde`: Node3D ou Vector3 (som no lugar); null = som direto (interface).
static func tocar(evento: String, onde = null, volume_extra := 0.0) -> void:
	if atual == null or not atual.ligado: return
	atual._tocar(evento, onde, volume_extra)

func _tocar(evento: String, onde, volume_extra: float) -> void:
	var e: Dictionary = eventos.get(evento, {})
	if e.is_empty(): return
	var lista: Array = e.arquivos
	var arq: String = lista[randi() % lista.size()]
	if not _cache.has(arq):
		if not ResourceLoader.exists(arq): return
		_cache[arq] = load(arq)
	if get_child_count() >= MAX_SIMULTANEOS: return
	var tom := 1.0 + randf_range(-1.0, 1.0) * float(e.get("tom", 0.0))
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
