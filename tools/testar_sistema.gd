extends SceneTree
## Confere o perfil de regras ativo contra os valores do B/X (o jogo não pode mudar ao trocar o código
## das regras pelo perfil). Uso: godot --headless --path . --script tools/testar_sistema.gd
const Sistema = preload("res://scripts/regras/sistema.gd")
const Dados = preload("res://scripts/regras/dados.gd")

func _init() -> void:
	var erros := 0
	var mods := {3: -3, 4: -2, 5: -2, 6: -1, 8: -1, 9: 0, 12: 0, 13: 1, 15: 1, 16: 2, 17: 2, 18: 3}
	for v in mods:
		if Sistema.mod(v) != mods[v]: erros += 1; print("mod(%d) = %d, esperado %d" % [v, Sistema.mod(v), mods[v]])
	var t0 := {"1d4hp": 19, "1-1": 19, "1": 19, "1+1": 18, "2": 18, "2+1": 17, "3": 17, "4+1": 15, "9": 11, "12": 10}
	for dv in t0:
		if Sistema.thac0_monstro(dv) != t0[dv]: erros += 1; print("thac0(%s) = %d, esperado %d" % [dv, Sistema.thac0_monstro(dv), t0[dv]])
	for n in [2, 10, 20]:
		if Sistema.chance_acerto(n) != (21 - n) * 5: erros += 1; print("chance(%d)" % n)
	if Sistema.numero_para_acertar(19, 9, 0) != 10 or Sistema.numero_para_acertar(19, -5, 0) != 20 or Sistema.numero_para_acertar(10, 9, 5) != 2: erros += 1; print("numero_para_acertar")
	Dados.forcados.append(20); if not Sistema.atacar(19, -10, 0).acerta: erros += 1; print("20 natural")
	Dados.forcados.append(1); if Sistema.atacar(10, 9, 10).acerta: erros += 1; print("1 natural")
	for i in 50:
		var ini: Array = Sistema.iniciativa()
		if ini[0] == ini[1] or ini[0] < 1 or ini[0] > 6: erros += 1; print("iniciativa ", ini); break
	if Sistema.surpresa(1)[1] != 3: erros += 1; print("surpresa")
	if Sistema.moral(12).testa: erros += 1; print("moral 12")
	if Sistema.taxa_combate_m(36.0) != 12.0: erros += 1; print("combate")
	if Sistema.forcar_em6(3) != 5 or Sistema.forcar_em6(-3) != 1 or Sistema.em6("ouvir_em6", "anao") != 2 or Sistema.em6("ouvir_em6", "mago") != 1: erros += 1; print("exploração")
	print("SISTEMA %s: %s" % [Sistema.nome(), "tudo igual ao B/X" if erros == 0 else "%d diferença(s)" % erros])
	quit(erros)
