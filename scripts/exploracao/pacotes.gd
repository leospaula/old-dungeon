extends Node
## Pacotes de download por parte da aventura (tools/empacotar.py gera <id>.pck ao lado do index.html).
## No navegador, baixa o pacote da parte para user://pacotes/ (fica no armazenamento do site) e o carrega.
## Os pacotes ficam guardados: o grupo pode voltar a uma parte e tudo continua lá como ficou (o estado do
## mundo vai no save; os modelos, no pacote). Só um pacote de versão nova substitui o antigo.
## Fora do navegador tudo já está no projeto e nada é baixado.

signal progresso(id: String, fracao: float)

const PASTA := "user://pacotes"
const VERSOES := "res://data/pacotes.json"   # id -> md5 do pacote (escrito pelo tools/empacotar.py)

var _prontos := {}       # id -> true
var _baixando := {}      # id -> true

func web() -> bool:
	return OS.has_feature("web")

func pronto(id: String) -> bool:
	return not web() or _prontos.has(id)

## Baixa (se preciso) e carrega o pacote. Devolve true se os recursos da parte ficaram disponíveis.
func preparar(id: String) -> bool:
	if not web() or _prontos.has(id): return true
	while _baixando.has(id): await get_tree().process_frame
	if _prontos.has(id): return true
	_baixando[id] = true
	DirAccess.make_dir_recursive_absolute(PASTA)
	var arq := "%s/%s.pck" % [PASTA, id]
	var versao := _versao(id)
	var guardada := FileAccess.get_file_as_string(arq + ".versao") if FileAccess.file_exists(arq + ".versao") else ""
	if not FileAccess.file_exists(arq) or (versao != "" and guardada != versao):
		if not await _baixar(id, arq):
			_baixando.erase(id); return false
		var f := FileAccess.open(arq + ".versao", FileAccess.WRITE); if f: f.store_string(versao)
	var ok := ProjectSettings.load_resource_pack(arq, true)
	print("pacote %s: carregado=%s" % [id, ok])
	_baixando.erase(id)
	if ok: _prontos[id] = true
	progresso.emit(id, 1.0)
	return ok

func _versao(id: String) -> String:
	if not FileAccess.file_exists(VERSOES): return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(VERSOES))
	return str(d.get(id, "")) if d is Dictionary else ""

func _baixar(id: String, arq: String) -> bool:
	var base := str(JavaScriptBridge.eval("window.location.href.replace(/[^/]*([?#].*)?$/, '')", true))
	var h := HTTPRequest.new(); add_child(h)
	h.use_threads = false; h.body_size_limit = -1
	var fim := [false, 0, PackedByteArray()]
	h.request_completed.connect(func(r, codigo, _hd, corpo):
		fim[0] = true; fim[1] = codigo if r == HTTPRequest.RESULT_SUCCESS else -r; fim[2] = corpo)
	if h.request(base + id + ".pck") != OK:
		h.queue_free(); return false
	while not fim[0]:
		var total := h.get_body_size()
		progresso.emit(id, float(h.get_downloaded_bytes()) / total if total > 0 else 0.0)
		await get_tree().process_frame
	h.queue_free()
	var corpo: PackedByteArray = fim[2]
	print("pacote %s: resposta %s, %d bytes" % [id, fim[1], corpo.size()])
	if int(fim[1]) != 200 or corpo.is_empty():
		push_warning("pacote %s: falhou (%s)" % [id, fim[1]]); return false
	var f := FileAccess.open(arq, FileAccess.WRITE)
	if f == null:
		push_warning("pacote %s: não deu para gravar (%s)" % [id, FileAccess.get_open_error()]); return false
	f.store_buffer(corpo); f.close()
	return true
