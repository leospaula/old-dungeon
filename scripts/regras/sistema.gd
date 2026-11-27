extends RefCounted
## Sistema de regras ativo: o jogo pergunta aqui o que é regra (acerto, iniciativa, surpresa, moral,
## monstros, chances de exploração). As respostas vêm do perfil em data/regras/sistemas/<id>.json.
## Hoje só existe o "bx" (Básico). Os níveis Intermediário (Rules Cyclopedia: o B/X mais módulos) e
## Avançado (AD&D: outras tabelas) serão outros perfis; um perfil pode herdar de outro ("base") e ligar
## "modulos". Ver docs/sistemas-de-regras.md.
##
## Escolha do perfil: --regras=<id> na linha de comando (padrão: bx).

const Dados = preload("res://scripts/regras/dados.gd")
const PASTA := "res://data/regras/sistemas/%s.json"

static var _perfil: Dictionary = {}

## Perfil ativo (carrega o padrão na primeira vez).
static func perfil() -> Dictionary:
	if _perfil.is_empty(): usar(_pedido())
	return _perfil

static func id() -> String: return str(perfil().get("id", "bx"))
static func nome() -> String: return str(perfil().get("nome", ""))
static func tem_modulo(m: String) -> bool: return (perfil().get("modulos", []) as Array).has(m)

## Troca o perfil ativo. Um perfil com "base" herda tudo dela e sobrescreve só o que traz.
static func usar(pid: String) -> void:
	_perfil = _carregar(pid)

static func _carregar(pid: String) -> Dictionary:
	var arq := PASTA % pid
	if not FileAccess.file_exists(arq):
		push_warning("sistema de regras '%s' não existe; usando bx" % pid); arq = PASTA % "bx"
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arq))
	var base := str(d.get("base", ""))
	if base != "":
		var b := _carregar(base)
		var mods: Array = (b.get("modulos", []) as Array) + (d.get("modulos", []) as Array)
		_mesclar(b, d); b.modulos = mods
		return b
	return d

static func _mesclar(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.get(k) is Dictionary and b[k] is Dictionary: _mesclar(a[k], b[k])
		else: a[k] = b[k]

static func _pedido() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--regras="): return a.trim_prefix("--regras=")
	return "bx"

# ---------- atributos ----------

## Modificador de um valor de atributo (B/X: 3 → −3 · 4–5 → −2 · 6–8 → −1 · 9–12 → 0 · 13–15 → +1 · 16–17 → +2 · 18 → +3).
static func mod(v: int) -> int:
	for faixa in perfil().atributos.mod:
		if v <= int(faixa[0]): return int(faixa[1])
	return 0

# ---------- ataque ----------

## Número que precisa sair no d20 (antes dos modificadores) para acertar.
static func precisa(thac0: int, ca_alvo: int) -> int:
	return thac0 - ca_alvo

## Rolagem de ataque: {r, total, precisa, acerta}. Natural máximo sempre acerta; natural mínimo sempre erra.
static func atacar(thac0: int, ca_alvo: int, modificador: int) -> Dictionary:
	var at: Dictionary = perfil().ataque
	var r := Dados.d(int(at.dado))
	var n := precisa(thac0, ca_alvo)
	var total := r + modificador
	var acerta := r == int(at.natural_acerta) or (r != int(at.natural_erra) and total >= n)
	return {"r": r, "total": total, "precisa": n, "acerta": acerta, "critico": r == int(at.natural_acerta), "falha": r == int(at.natural_erra)}

## Para a previsão na tela: o número que precisa no dado (já com bônus), entre o mínimo e o máximo possíveis.
static func numero_para_acertar(thac0: int, ca_alvo: int, modificador: int) -> int:
	var at: Dictionary = perfil().ataque
	return clampi(precisa(thac0, ca_alvo) - modificador, int(at.natural_erra) + 1, int(at.natural_acerta))

## Chance (%) de acertar precisando de `n` no d20.
static func chance_acerto(n: int) -> int:
	var dado := int(perfil().ataque.dado)
	return (dado + 1 - n) * 100 / dado

## Ajuste de acerto à distância por faixa (curta, média, longa).
static func ajuste_faixa(faixa: int) -> int:
	return int(perfil().ataque.faixa_distancia[faixa])

static func dano_minimo() -> int:
	return int(perfil().ataque.dano_minimo)

# ---------- monstros ----------

## THAC0 de um monstro pelo dado de vida ("1-1", "2+1", "1d4hp"…).
static func thac0_monstro(dv: String) -> int:
	var t: Dictionary = perfil().monstros.thac0
	if dv.ends_with("hp"): return int(t.so_pv)
	var mais := dv.contains("+")
	var base := int(dv.get_slice("+", 0).get_slice("-", 0))
	return clampi((int(t.com_mais) if mais else int(t.sem_mais)) - base, int(t.minimo), int(t.maximo))

## PV de um monstro: "1-1" = 1d8−1 · "2" = 2d8 · "1d4hp" = 1d4 (mínimo do perfil).
static func pv_monstro(dv: String) -> int:
	var mo: Dictionary = perfil().monstros
	if dv.ends_with("hp"): return maxi(int(mo.pv_minimo), Dados.rolar(dv.trim_suffix("hp")))
	var m := 0
	var base := dv
	if dv.contains("+"): base = dv.get_slice("+", 0); m = int(dv.get_slice("+", 1))
	elif dv.contains("-"): base = dv.get_slice("-", 0); m = -int(dv.get_slice("-", 1))
	return maxi(int(mo.pv_minimo), Dados.rolar("%sd%d" % [base, int(mo.dado_vida)]) + m)

# ---------- iniciativa, surpresa e moral ----------

## Iniciativa por lado: [grupo, monstros], sem empate.
static func iniciativa() -> Array:
	var ini: Dictionary = perfil().iniciativa
	var ig := Dados.d(int(ini.dado)); var im := Dados.d(int(ini.dado))
	while ig == im and str(ini.empate) == "rola_de_novo":
		ig = Dados.d(int(ini.dado)); im = Dados.d(int(ini.dado))
	return [ig, im]

## Surpresa: [rolagem, alvo]; surpreso se rolagem ≤ alvo. `extra` soma na chance (modo de movimento).
static func surpresa(extra := 0) -> Array:
	var s: Dictionary = perfil().surpresa
	return [Dados.d(int(s.dado)), int(s.chance) + extra]

## Teste de moral: {testa (false = moral imune), r, foge}.
static func moral(valor: int) -> Dictionary:
	var m: Dictionary = perfil().moral
	if valor >= int(m.imune_a_partir): return {"testa": false, "r": 0, "foge": false}
	var r := Dados.rolar(str(m.dados))
	return {"testa": true, "r": r, "foge": r > valor}

## Quando a moral é testada: "primeira_baixa", "metade_caida".
static func testa_moral_em(momento: String) -> bool:
	return (perfil().moral.testa_em as Array).has(momento)

# ---------- movimento ----------

static func taxa_exploracao_m(carga: String) -> float:
	return float(perfil().movimento.exploracao_m.get(carga, 36))

static func taxa_combate_m(taxa_exploracao: float) -> float:
	return taxa_exploracao / float(perfil().movimento.combate_divisor)

# ---------- exploração (chances em d6) ----------

## Chance em 6 numa tabela de exploração ("ouvir_em6", "armadilha_em6"…) para a classe.
static func em6(tabela: String, classe: String) -> int:
	var t: Dictionary = perfil().exploracao[tabela]
	return int(t.get(classe, t.padrao))

static func forcar_em6(mod_for: int) -> int:
	var f: Dictionary = perfil().exploracao.forcar_em6
	return clampi(int(f.base) + mod_for, int(f.minimo), int(f.maximo))
