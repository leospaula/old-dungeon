# Como escrever uma aventura

Uma aventura é **um arquivo JSON** que descreve só o que muda por cima da planta base: onde o grupo começa, o estado das portas, as secretas ativas e o conteúdo de cada área. A geometria nunca é copiada; tudo é citado por ID.

```
data/masmorra/layout.json              planta base (áreas, portas P01…, secretas S01…)
data/regras/monstros.json              bestiário B/X
data/catalogos/props.json              catálogo de props (móveis e objetos de cenário)
data/esquemas/aventura.schema.json     esquema do formato
data/aventuras/<id>/aventura.json      a aventura
data/aventuras/<id>/mapa.png           mapa gerado
```

Exemplo completo: `data/aventuras/exemplo-fuga-da-prisao/aventura.json`.

## Passo a passo
1. Crie a pasta `data/aventuras/<id>/` e copie o exemplo como ponto de partida.
2. Deixe `"$schema": "../../esquemas/aventura.schema.json"` no topo. O VS Code passa a autocompletar e sublinhar erros.
3. Consulte as **fichas das áreas** (`arte/mapas/areas/area-<id>.png`) para achar as coordenadas, e a planta (`arte/mapas/planta-base.png`) para os números das portas.
4. Valide: `python3 tools/validar_aventura.py data/aventuras/<id>/aventura.json`
5. Gere o mapa: `python3 tools/desenhar_aventura.py data/aventuras/<id>/aventura.json data/aventuras/<id>/mapa.png`

## Como apontar para as coisas
| O quê | Como | Exemplo |
|---|---|---|
| Área | id da planta | `"15"`, `"19a"`, `"19cC"` (cela C da prisão) |
| Posição dentro da área | **letra = coluna, número = linha**, a partir do canto superior esquerdo da área | `"C3"` |
| Porta | id da planta | `"P17"` |
| Secreta | id da planta (só as sugeridas) | `"S01"` |
| Prop | id do catálogo | `"bau"`, `"mesa-grande"` |
| Monstro | id do bestiário | `"bandido"`, `"rato_gigante"` |
| Item da aventura | id em `itens` (com hífen) | `"chave-da-cela"` |

Um prop maior que 1×1 ocupa a partir da posição para a direita e para baixo. Com `"giro": 90` ou `270`, largura e altura trocam.

## Seções
| Seção | Para que serve |
|---|---|
| `inicio` | `escada` (desce pela escada 2×2 em `pos`), `capturados` (começa preso, com `sem_equipamento` e `equipamento_em`) ou `livre` |
| `portas` | só as que mudam: `aberta`, `fechada`, `emperrada` (com `dificuldade` 1–6), `trancada` (`abre_com` uma chave), `quebrada`, `secreta`; `armadilha` opcional. Portas de cela não podem ser secretas. |
| `secretas` | quais secretas sugeridas existem nesta aventura |
| `areas` | por área: `leitura` (texto em voz alta), `notas` (mestre), `luz`, `props`, `monstros` (`pos` ou `posicoes`, `estado`, `carrega`), `pdms`, `tesouros`, `armadilhas`, `pistas` |
| `itens` | chaves, objetos de missão e itens mágicos citados por id |
| `pdms` | personagens do mestre (nome, atitude, fala, o que querem) |
| `eventos` | `quando` (um gatilho) → `faz` (lista de efeitos) |
| `errantes` | tabela de monstros errantes, com chance e frequência |
| `objetivos` | condições de vitória, XP e o objetivo `final` |

**Gatilhos:** `entrar_area`, `porta_aberta`, `monstro_morto`, `item_pego`, `prop_usado`, `grupo_em`, `turno`, `evento`.
**Efeitos:** `mensagem`, `acordar`, `abrir_porta`, `trancar_porta`, `revelar_secreta`, `surgir`, `dar_item`, `moral`, `objetivo`.

## O que o verificador confere
- o arquivo segue o esquema;
- áreas, portas, secretas, props, monstros, itens, PdMs, eventos e objetivos citados existem;
- cada posição é chão da área certa, e cada prop cabe inteiro na área (considerando o giro);
- a escada 2×2 do início cabe, e a área de início é uma das entradas principais (se não for, gera aviso);
- props que bloqueiam não se sobrepõem, e monstros não ficam em cima deles (aviso);
- a tabela de errantes cobre exatamente 1–6 no d6 (aviso).
