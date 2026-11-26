---
name: importar-aventura
description: Transforma uma aventura de RPG vinda de prints, PDF, fotos ou texto num Guia do Mestre estruturado para a Masmorra Clássica, converte a numeração das salas para a Planta base do jogo e gera a lista de arte e itens. Use quando o Leonardo mandar imagens ou arquivos de uma aventura para registrar, pedir para "passar a aventura para o jogo", "converter as salas" ou "adaptar para a nossa masmorra".
---

# Importar aventura para a Masmorra Clássica

Fluxo usado na Aventura 1 (Fuga da Dungeon de Zastan). O resultado são duas notas no cofre e, depois, o JSON do motor.

Responda sempre em pt-BR. Referência pronta para copiar o formato: `~/Documentos/Personal Brain/RPG/Masmorra Clássica/Aventura 1 - Fuga da Dungeon de Zastan.md` e `Aventura 1 - Lista de arte e itens.md`.

## 1. Leitura das fontes

1. Leia **todas** as imagens ou páginas antes de escrever qualquer coisa. Prints em sequência costumam se sobrepor: use o texto repetido entre um print e outro para costurar a ordem e não duplicar trechos.
2. Siga a numeração de seções do original (1, 2, 3…), não a ordem em que as colunas aparecem no print. Texto de uma seção que continua na coluna ou página seguinte pertence à mesma seção.
3. Fichas de monstro cortadas entre colunas: junte as metades (ex.: começo da ficha no pé da coluna esquerda, resto no topo da direita).
4. Aplique as **trocas de nome** pedidas em todo o texto (vilão, lugares, PNJs) e não deixe o nome antigo em lugar nenhum: título, tabelas, falas, nomes de sala ("cozinha de X").
5. Anote as **lacunas**: trechos cortados, mapa que não veio, cartões ou livros citados que não estão nas fontes. Peça o que falta ao Leonardo em vez de inventar. Quando ele mandar a parte que faltava, compare com o que já foi escrito e só ajuste o que mudou.

## 2. Estrutura do Guia do Mestre

Nota `Aventura N - <Nome>.md` em `~/Documentos/Personal Brain/RPG/Masmorra Clássica/`:

1. **Frontmatter** do cofre (`tipo`, `tags: [rpg, jogo, masmorra-classica, aventura]`, `local: ~/Personal/masmorra-classica`, `atualizado`) e a linha `Parte de [[Masmorra Clássica]]. Planta: [[Planta base]]. Arte e itens: [[Aventura N - Lista de arte e itens]].`
2. **Status** (ex.: guia registrado, falta passar para o JSON).
3. **Visão geral:** tabela Parte | Salas | Foco | Classes disponíveis. Depois, a **premissa** em 1 ou 2 frases.
4. **Uma seção `##` por parte e uma `###` por seção do original**, sempre com o número da sala no título. Dentro de cada uma, nesta ordem:
   - preparação (onde pôr os marcadores);
   - ***Ler:*** o texto para os jogadores, como roteiro curto;
   - PNJs e como interpretá-los;
   - mecânica (testes, surpresa, moral, armadilhas com as porcentagens);
   - tabelas (reações, métodos e resultados, armas, alcances, ataque por CA);
   - tesouro;
   - o que acontece em caso de morte ou TPK;
   - para onde ir em seguida.
5. **Ficha de monstro numa linha**, sempre neste formato: `CA; DV (PV); Mov; ataque e dano; proteção; moral; alinhamento; XP`. Nas partes introdutórias, que só dão PV e o número para acertar, use uma tabela Criatura | PV.
6. **Tabelas de ataque por CA** como tabela horizontal (CA 9 → 0 nas colunas, o d20 necessário embaixo).
7. **No fim:** resumo de tesouro por parte, a tabela de **correspondência de salas** (se houve conversão) e as **Pendências** (regras citadas que ainda faltam no jogo e a passagem para o JSON).

## 3. Lista de salas e dependências

Antes de converter, entregue ao Leonardo:

1. **Tabela de todas as salas:** Sala | Parte | O que acontece. Marque o que é corredor, as salas livres (que o mestre preenche) e as saídas.
2. **Dependências que precisam sobreviver à renumeração.** Exemplos:
   - porta entre X e Y (de onde vêm os monstros, cobertura, porta secreta);
   - chave da sala X que abre a sala Y;
   - rota de disfarce;
   - PNJs que só acompanham o grupo até a sala X;
   - de que sala em diante começam os monstros errantes;
   - avisos ("evitem a sala X").

## 4. Conversão de salas

O Leonardo passa a relação no formato **sala nova → sala da aventura**.

1. **Confirme o entendimento antes de editar:** devolva uma tabela Nova | Antiga | Conteúdo e liste:
   - números novos que não aparecem na relação (pergunte o que são: corredor, vazio, sala livre);
   - números antigos que ficaram sem destino;
   - **fusões** (várias salas antigas numa nova) e **divisões**.
2. **Fusão em sub-áreas:** a sala nova vira `15a…15e`, com as letras na ordem dos números antigos. Faça uma tabela Área | Posição | Conteúdo.
3. **Registre a estrutura interna da sala com mini-mapa** em texto. Mantenha as proporções aproximadas em células, as portas (`P`), a entrada e os símbolos do original (▲ etc.). Liste também quem se liga a quem e as portas que ficam fora do mini-mapa. Uma sala que precisava se trancar sozinha e virou sub-área vira um cercado ou jaula de props com portão de mola, mantendo a mecânica.
4. **Reescreva todas as referências cruzadas** com os números novos (as dependências do passo 3). Procure no texto cada número antigo para não sobrar nenhum.
5. **Reordene as seções pela rota do grupo**, não pela ordem numérica nova.
6. Coloque um aviso no início da parte convertida ("segue a numeração da [[Planta base]]"), anote os corredores e ponha no fim a tabela **Correspondência de salas (planta base → numeração antiga)**.

## 5. Lista de arte e itens

Nota `Aventura N - Lista de arte e itens.md`, na numeração nova:

- **Monstros:** Monstro | Onde | Notas para a arte (arma, quantidade, poses especiais, mais de uma forma).
- **PNJs:** PNJ | Papel | Visual. Inclua os PJs pré-gerados e os nomes que só são citados.
- **Itens e tesouros**, nestes grupos: itens mágicos; pergaminhos e livros; poções; armas comuns; armaduras e equipamento; tesouros (moedas, gemas, joias, outros).
- **Props de cenário por ambiente**, agrupados pelas salas na numeração nova. Inclua sinais e avisos escritos.
- **Texturas:** rocha e chão; materiais especiais (sal, cristal…); metais; madeira; tecidos e couro; efeitos (teia, lodo, trevas, brilhos, luz de tocha).

Use nomes genéricos para os assets.

## 6. Salvar e registrar

1. As duas notas ficam no cofre, em `RPG/Masmorra Clássica/`. **Decisões e handoff nunca vão para o repo do jogo**, que é público; lá só entra o JSON e a documentação técnica.
2. Atualize a nota-mapa `Masmorra Clássica.md`, com uma linha por nota nova na tabela de notas. Se a numeração das aventuras mudar, renomeie as notas e corrija os `[[links]]` em todo o cofre.
3. Commit no cofre, como manda o `CLAUDE.md` dele (`git add` só nos arquivos tocados). Push só se pedirem.
4. Próximo passo, quando o Leonardo liberar: passar a aventura para `data/aventuras/<id>/aventura.json` seguindo `docs/formato-aventura.md` (portas P01–P35, coordenadas por área, catálogo de props), e rodar `tools/validar_aventura.py` e `tools/desenhar_aventura.py`.
