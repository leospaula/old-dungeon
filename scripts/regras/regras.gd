extends RefCounted
## Regras B/X usadas pelo jogo (Old-School Essentials / Basic Fantasy). Ver Personal Brain: Regras B-X.

const Dados = preload("res://scripts/regras/dados.gd")

## Modificador de atributo (3: −3 · 4–5: −2 · 6–8: −1 · 9–12: 0 · 13–15: +1 · 16–17: +2 · 18: +3)
static func mod(v: int) -> int:
	if v <= 3: return -3
	if v <= 5: return -2
	if v <= 8: return -1
	if v <= 12: return 0
	if v <= 15: return 1
	if v <= 17: return 2
	return 3

## Movimento por turno de exploração (10 min), pela carga: leve 36 m · média 27 m · pesada 18 m.
## Por enquanto só olha a armadura; o catálogo de itens vai somar os espaços ocupados.
static func taxa_exploracao_m(equipamento: Array) -> float:
	var taxa := 36.0
	for it in equipamento:
		var s := str(it).to_lower()
		if s.contains("placas"): return 18.0
		if s.contains("cota de malha"): taxa = 27.0
	return taxa

## Movimento de combate por rodada (10 s) = 1/3 do movimento de exploração.
static func taxa_combate_m(taxa_exploracao: float) -> float:
	return taxa_exploracao / 3.0

## THAC0 dos monstros pelo dado de vida (tabela do OSE): até 1 → 19 · 1+ e 2 → 18 · 2+ e 3 → 17 …
static func thac0_monstro(dv: String) -> int:
	if dv.ends_with("hp"): return 19
	var mais := dv.contains("+")
	var base := int(dv.get_slice("+", 0).get_slice("-", 0))
	return clampi((19 - base) if mais else (20 - base), 10, 19)

## PV de um monstro: "1-1" = 1d8−1 (mín. 1) · "2" = 2d8 · "1d4hp" = 1d4.
static func pv_monstro(dv: String) -> int:
	if dv.ends_with("hp"): return maxi(1, Dados.rolar(dv.trim_suffix("hp")))
	var m := 0
	var base := dv
	if dv.contains("+"): base = dv.get_slice("+", 0); m = int(dv.get_slice("+", 1))
	elif dv.contains("-"): base = dv.get_slice("-", 0); m = -int(dv.get_slice("-", 1))
	return maxi(1, Dados.rolar("%sd8" % base) + m)
