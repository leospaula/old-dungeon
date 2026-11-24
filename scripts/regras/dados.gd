extends RefCounted
## Dados de mesa: "1d8", "2d4+1", "1d6-1", "3". Usa o gerador global (já aleatório ao iniciar).

## Só para testes: resultados forçados, consumidos em ordem pelo próximo d().
static var forcados: Array[int] = []

static func d(lados: int) -> int:
	if not forcados.is_empty(): return forcados.pop_front()
	return randi_range(1, lados)

static func rolar(expr: String) -> int:
	return int(detalhar(expr).total)

## Devolve {total, dados: [...], mod, texto} — o texto serve para o registro ("1d8+2: 5+2 = 7").
static func detalhar(expr: String) -> Dictionary:
	var e := expr.replace(" ", "").to_lower()
	var mod := 0
	var i := maxi(e.rfind("+"), e.rfind("-"))
	if i > 0:
		var n := int(e.substr(i + 1))
		mod = -n if e[i] == "-" else n
		e = e.substr(0, i)
	var dados: Array[int] = []
	var total := mod
	if e.contains("d"):
		var p := e.split("d")
		var qtd := 1 if p[0] == "" else int(p[0])
		for k in qtd:
			var r := d(int(p[1])); dados.append(r); total += r
	else:
		total += int(e)
	var txt := "+".join(dados.map(func(x): return str(x)))
	if mod != 0: txt += ("%+d" % mod)
	return {"total": total, "dados": dados, "mod": mod, "texto": txt}
