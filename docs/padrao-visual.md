# Padrão visual da interface: "Grimório escuro"

Aprovado em 25/11/2026. **Toda interface nova do jogo segue este padrão.**
As pranchas de referência estão no quadro "Masmorra — opções de interface" (https://claude.ai/artifact/4v5WovZ6RuRaUSWE9MtWwv), nas linhas A, A2 e A3.

A ideia: o 3D tem luz real. A interface é **couro escuro com filete dourado** por cima da cena, e o **livro de pergaminho** para a ficha. Nada de tinta ou pergaminho dentro do mundo 3D.

## 1. Cores

| Uso | Cor |
|---|---|
| Fundo de painel (couro) | gradiente `#1a120c` → `#0e0a07`, opacidade ~0,9 |
| Filete dourado (borda) | `#c49a52` a 55%; filete interno a 25% |
| Ouro de título / nomes | `#e6c27a` |
| Destaque "sua vez" / botão ativo | `#f0d08a` (brilho em volta) e nome `#fbe2a2` |
| Texto comum sobre couro | `#cdbb9a`; registro `#e6dac0` |
| Barra de PV | `#8e1f17` → `#c8402d` sobre fundo preto 55% |
| Grupo (iniciativa) | borda azul `#5b7fb8` |
| Inimigo | borda vermelha `#b8432f`; nome ferido `#f2b29a` |
| Magia arcana | azul `#b9d0ff` (texto), gema `#3a5aa8` |
| Acerto no registro | `#f0c060` |
| Pergaminho do livro | `#f3e6c8` → `#e2cfa4` → `#cfb684`, tinta `#2b1b0e`, secundária `#5a4226` |
| Títulos no pergaminho | vermelho-sangue `#7a2a14` |
| Abas do livro | Habilidades `#7a2a14` · Magias `#2a3a6a` · Equipamento `#6b4a24` · Diário `#2e4a3a` |
| Etiqueta Exploração / Combate / Ambos | `#2e4a3a` / `#7a2a14` / `#6b4a24` |

## 2. Fontes (OFL, em `assets/fontes/`)
- **Cinzel** (700): nomes, títulos de seção, números grandes (PV, CA, THAC0, atributos), rótulos dos medalhões.
- **Alegreya** (400/700/itálico): todo o resto (textos, registro, dicas, rótulos).

## 3. Peças

### Tela de jogo
- **Cartas do grupo, à esquerda** (252 px): retrato redondo com aro dourado, nome em Cinzel, estado à direita ("sua vez", "já agiu", "declarando…"), barra de PV, fichas `PV x/y · CA · T0`, uma linha com a arma e a luz ou munição. Quem está na vez: borda clara, brilho e a carta **deslocada 10 px para a direita**. Quem já agiu: opacidade 0,78. Clique expande; duplo clique abre o livro.
- **Ações, embaixo no centro**: **medalhões redondos** (54 px) de couro com aro dourado, ícone ou sigla, **tecla no canto superior direito**, **contador embaixo** (ex.: `10%`, `1/1`, `+4 ×2`, `nível 2`), rótulo abaixo. Grupos separados por um filete vertical. Botão indisponível: apagado (38%) e dessaturado, com o motivo no contador. Acima dos medalhões, uma linha de título em Cinzel ("Vez de Caco · movimento 3,0 de 9 m").
- **Balão de ação** (ao passar ou escolher): painel de couro com seta apontando o medalhão; título em Cinzel e **a conta inteira**: o que precisa no d20, a chance em %, o dano.
- **Iniciativa / relógio, em cima à direita**: fichas redondas na ordem; quem está na vez fica **maior com aro claro**, quem já agiu fica apagado; filete separando grupo e inimigos. Fora de combate: sala, turno, tempo, tocha.
- **Registro, embaixo à direita**: sem caixa, texto sobre um degradê escuro que some para cima; linhas antigas mais apagadas. Mostra os dados: `d20 15 +2 = 17 (precisa 13) → acerta · 1d8+2 = 5`.
- **Dica do alvo** na cena: painel pequeno de couro com nome, estado e o que precisa no d20.

### Livro da ficha
- Livro aberto de couro com **duas páginas de pergaminho**.
- **Página esquerda (fixa)**: retrato, nome, classe, nível, alinhamento, XP e bônus; caixas grandes PV, CA, THAC0; 6 atributos com modificador; 5 jogadas de proteção em círculos (com o ajuste de SAB anotado); bloco **Combate** só com as armas (arma · dano · acerto com a origem do bônus · bônus de dano); movimento e carga no pé.
- **Página direita (abas penduradas no alto)**: **Habilidades · Magias · Equipamento · Diário**. A aba Magias só existe para quem lança magia (mago, elfo, clérigo).
  - **Habilidades**: uma linha por habilidade com nome, frase de uso, valor (% ou "x em 6"), barrinha de chance e etiqueta de quando serve. Habilidade de destaque da classe em quadro próprio (ataque furtivo, afastar mortos-vivos com a tabela). Testes de masmorra comuns no fim.
  - **Magias**: magias por dia em **gemas** (cheia = pronta, vazia = gasta, hachurada = ainda não tem); a magia memorizada em destaque com todos os dados; grimório (mago/elfo) ou lista de orações (clérigo). Se a classe ainda não tem magia no nível, a aba existe e diz quando chega.
  - **Equipamento**: mãos, corpo, cinto e mochila em espaços; arrastar e soltar; clique: usar, dar, largar.
- Coluna de retratos do grupo à esquerda do livro para trocar de personagem.

### Ações de combate por classe
| Classe | Ações além de Atacar / Trocar arma / Cinto / Fim |
|---|---|
| Ladrão | Ataque furtivo (+4, dano ×2, só pelas costas sem ser notado), Esconder-se, Mover em silêncio (testes ocultos) |
| Mago, elfo | Magia (declarada **antes** da iniciativa; perde se for atingido antes de agir) |
| Clérigo | Afastar mortos-vivos (2d6, mostra a chance por inimigo), Orar (a partir do nível 2), Água benta |
| Elfo, halfling | Arco / funda como ação à distância |

## 4. Regras de estilo
- Retrato sempre redondo com aro dourado. Personagem sem retrato: medalhão com a inicial, até a arte ficar pronta.
- Números de regra sempre visíveis: o jogador vê a conta (d20, alvo, chance, dano), como numa mesa.
- Nada de cantos retos sem filete; nada de cores puras fora desta paleta.
- Texto em pt-BR, frases curtas.
