# Construção de aventura: do texto à aventura jogável

Diário de método, escrito enquanto a **Aventura 1** é montada sala a sala. Cada etapa registra o que
foi feito, as decisões e o porquê. No fim da aventura, este documento vira uma ou mais **skills**: uma
IA recebe o texto de uma aventura, junto com os catálogos e o esquema, e gera o `aventura.json` que o
jogo carrega e roda sem montagem manual.

Este documento só cresce. Para cada sala nova, acrescente o que mudou no método, e não só o que foi feito.

---

## 0. Peças que o gerador usa (referência rápida)

| Peça | Onde | Para quê |
|---|---|---|
| Planta (geometria, áreas, portas, IDs) | `data/masmorra/layout.json`, fichas `arte/mapas/areas/area-<id>.png` | Onde cada coisa fica. Área, posição "C3" (letra = coluna, número = linha, a partir do canto superior esquerdo da caixa da área), porta "P17". |
| Esquema da aventura | `data/esquemas/aventura.schema.json` | O formato do JSON (o VS Code autocompleta). |
| Verificador | `python3 tools/validar_aventura.py <aventura.json>` | Confere esquema, referências, posições, cenas e PdMs. |
| Props | `data/catalogos/props.json` | Móveis e objetos com modelo 3D (`modelo3d`), tamanho e bloqueio. |
| Itens | `data/catalogos/itens.json` | Armas e equipamento: dano, estilo de luta e modelo 3D na mão. |
| Bestiário | `data/regras/monstros.json` | Números B/X dos monstros (CA, DV, ataques, moral, XP). |
| Modelos e animações de criaturas e PdMs | `data/regras/animacoes.json` (`criaturas`, `categorias`) | Modelo 3D, escala, categoria de animação e arma de cada criatura ou PdM. |
| Estilos de luta | `data/regras/estilos.json` | Pose de guarda e golpes por tipo de arma (besta, arco, duas mãos…). |
| Animações disponíveis | lista `pj` em `data/regras/animacoes.json` | O que um passo `anim` pode tocar (ajoelhar, levantar, golpe, besta-mirar, chutar-porta, levar-golpe, ouvir…). |
| Retratos | `arte/final/retratos/<id>.jpg` | Rosto no balão de fala e na caixa de escolha. |
| Cenas | `scripts/exploracao/cena.gd` (cabeçalho documenta todos os passos) | Executor das cenas roteirizadas. |

**A fazer (pedido do Leonardo, 27/11):** um documento de catálogo com tudo o que existe: cenários,
props, personagens, monstros, PdMs, itens, IDs, posições possíveis e o mapa. É a fonte que a IA geradora lê.

---

## 1. Ler a aventura e separar por parte e sala

- Fonte: vault `RPG/Masmorra Clássica/Aventura 1 - Fuga da Dungeon de Zastan.md`.
- Cada **parte** vira um item em `partes` (id, nome, áreas, criaturas). A parte define o **pacote de
  download** do navegador (`tools/empacotar.py`): props e criaturas da parte só baixam quando o grupo chega lá.
- Cada **seção** do texto vira uma área da planta, um evento ou uma cena. Mapear "sala 1", "sala 2"… do
  texto para os IDs da planta (`"1"`, `"2"`…) pela ficha da área.
- Nomes de PdMs e monstros ficam **genéricos** ("Hobgoblin", "Prisioneiro", "Guarda"). O papel e o nome
  próprio são decididos depois, pelo Leonardo.

## 2. Início, regras da casa e grupo

- `grupo` lista os personagens prontos disponíveis; `tamanho_grupo` diz quantos o jogador escolhe.
  A tela de escolha vem antes da aventura, e a ordem da escolha é a ordem de marcha.
- `inicio`: `capturados` (preso, `sem_equipamento`, `equipamento_em` área/pos/prop), `escada` ou `livre`.
- **Rolagens do texto que o jogo resolve com as fichas:** a aventura pedia 3d6 nos atributos. Decisão:
  usar os atributos das fichas prontas. Regra geral: **o jogo usa as regras normais** (PV, THAC0, CA das
  fichas; números dos monstros do texto quando ele os dá).

## 3. Cenário de cada área

- `luz`: `iluminado` (tochas de parede automáticas), `penumbra` (luz fraca e fria espalhada, por exemplo
  a que entra pela grade) ou escuro (sem nada).
- `props`: tipo do catálogo + `pos` (+ `giro`). Um prop que bloqueia tira as casas do caminho.
- `portas`: só as que mudam (`trancada` com `abre_com`, `inquebravel`, `emperrada`…). Grade de cela
  inquebrável = só abre com a chave.
- `leitura`: texto lido ao entrar na área pela primeira vez (vai para o registro).

## 4. PdMs (personagens do mestre)

Em `pdms`, por id: `nome`, `base` (id da criatura com modelo em `animacoes.json`, ou do bestiário),
`atitude`, `pv`, `ca`, `arma` (nome nas mensagens), `dano`, `arma3d` (item do catálogo na mão; `""` =
mão vazia), `empunhar` e `retrato`.

- O PdM **não entra no combate nem nos errantes**: é ator de cena. Bloqueia casas como qualquer pessoa.
- Aparece só quando alguém do grupo vê a casa dele (névoa), como os monstros.
- Arma na mão do PdM: `arma3d` com o item do catálogo (o carcereiro usa o `chicote`, desenhado pelo jogo
  como a funda: cabo trançado + tira de couro com física). Com `empunhar: true` ele fica em guarda com a
  arma à mostra. O passo `ataque` sem `anim` usa o golpe do estilo da arma.
- **Item que falta no catálogo vira item de verdade**, com modelo (ou desenho procedural), estilo de
  luta e lugar no arsenal do Ateliê, antes de ir para a cena.

## 5. Eventos e cenas

- **Evento** (`eventos`): `quando` (um gatilho) → `faz` (efeitos). Gatilho novo: `inicio` (segundos depois
  de a aventura começar). Efeito novo: `{"cena": "<id>"}`.
- **Cena** (`cenas`): lista de passos executados em ordem por `scripts/exploracao/cena.gd`. Enquanto a
  cena roda, o jogador só assiste: não anda, não abre porta, não troca quem lidera. A câmera continua
  livre, e um clique ou espaço pula a fala.
- **Sub-cenas** (`{"faz":"cena","id":…}`) evitam repetir trechos. Exemplo: `carcereiro-tranca` (fechar e
  trancar) e `carcereiro-sai` (guardas saem, depois o carcereiro) são usadas por mais de uma reação.
  **Separar "trancar" de "sair"** foi preciso porque uma reação tem uma fala entre as duas.

### 5.0 Encadear eventos e guardar o que a aventura muda
- Um evento pode esperar outro: `"quando": {"evento": "<id>"}` com `"atraso"` em segundos. A Seção 3
  começa 2 s depois de a cena do carcereiro terminar.
- O que a aventura muda e precisa ser lembrado (dívidas, informações já contadas, jogos interrompidos) vai
  em `aventura.estado`, que é o que entra no save.
- Informação que o grupo descobre vai para o **diário** (`tipo: "pista"`).
- Nome de PdM nos textos: `{pdm:<id>}` (por exemplo `{pdm:feiticeiro}`). O nome fica num lugar só
  (`pdms.<id>.nome`) e o Leonardo troca quando decidir.

### 5.1 Tabela de reações → passo `escolha`
A tabela do texto ("ação dos PJs → reação do PdM") vira uma `escolha`:
- cada linha vira uma opção (`texto`, `dica`, `faz`); a que encerra a situação leva `fim: true`;
- as opções sem `fim` fazem a escolha **voltar** (com `texto_depois`), como na mesa;
- o "último recurso" do texto vira `limite` + `ao_limite`: depois de N escolhas sem fim, ele acontece
  (os 12 guardas com bestas) e só sobram as opções com fim;
- `{agente}` e `{mais_forte}` nos textos viram nomes (quem age, maior FOR).
- **Dicas das opções (regra do Leonardo, 27/11):** o resultado de uma opção fica em suspense. A `dica`
  só aparece quando as opções envolvem **personagens diferentes** (quem age: "{agente} desfaz o nó") ou
  **testes** (a chance), para o jogador decidir quem é melhor para aquilo. Nunca descreve o que vai acontecer.
- **Ataques de cena são de verdade** (d20 contra THAC0 − CA, dano da arma), mas **a cena não derruba
  ninguém** (PV mínimo 1). Quem decide a luta é o combate, não a cena.

### 5.0b PdM que fica esperando o grupo → `interacao`
Recusou uma proposta? O PdM não some: vai para um canto (sentado) com um **ícone de conversa** em cima
(`interacao` {quem, cena}), e um clique nele roda a cena de novo. `fim_interacao` tira o ícone. O fluxo
vira uma pequena máquina de estados feita de cenas que se chamam: `pede` → `pede-de-novo` → `canto` (por
clique) → `desamarrar` → `propoe` → (aceitou) `rodadas` / (recusou) o ícone volta em `propoe` → (parou o
jogo) o ícone em `volta`.

### 5.1b Minijogos com PdM → passo próprio e genérico
Mecânica nova da aventura vira um **passo reutilizável**, e não código da sala. O jogo de dados do
prisioneiro virou `jogo_dados`:
- o PdM rola o dado dele, e cada personagem rola um dado diferente na ordem de marcha
  (`dados_grupo` [12, 10, 8, 6, 4]: o texto dizia "cada um escolhe outro dado");
- se alguém tirar mais, o PdM conta a próxima informação; se ele tirar mais, cada um deve `aposta` po;
  empate não conta;
- dá para parar e voltar depois (o progresso fica em `estado`);
- o dado gira em cima da cabeça de cada um (o mesmo efeito do d20 do ataque, com o número de lados).

### 5.2 Falas
- Balão sobre a cabeça de quem fala (retrato, nome e a fala entre aspas), que acompanha o personagem na
  tela. A fala também vai para o registro.
- Fica na tela por `max(2,6 s; 0,06 s por letra)`, ou até um clique.
- As falas são **escritas com palavras próprias** a partir do sentido do texto, curtas, no tom do PdM.

### 5.3 Câmera
- Passo `camera` {área, pos, dx, dz, distancia, inclinacao, guinada}: desliza até lá em 1–1,2 s.
- **No fim da cena, a câmera volta** à distância e aos ângulos que o jogador usava.
- **Corredor estreito entre paredes altas** (o vestíbulo 2 tem 2 casas de fundo): a 40–55° as paredes
  tapam o chão. Usar **68–72° de inclinação**, a 10 m, olhando do lado de onde a ação vem (do corredor
  para a cela, `guinada` −200). Escolher o sentido do giro pelo caminho mais curto a partir do ângulo do
  jogador (de −30 para −200, e não para +160).
- Conferir sempre **com imagem**: `--teste=carcereiro --fotos=<prefixo>` (uma foto a cada 1,5 s, ou
  `--fotos-ritmo=`). Para estudar um ângulo: `--camera-fixa --alvo-casa=x,y --camera=d,i,g`.

### 5.4 Movimento
- Ritmo de cena: quem anda numa cena vai a 72% do passo normal (correndo, 130%): `VEL_CENA` em
  `cena.gd`. No ritmo do jogador, os PdMs pareciam apressados (Leonardo, 27/11).
- Jogar dados não tem animação: os números só giram em cima das cabeças.
- Um ator só: `andar` (vai para a casa pedida ou para a livre mais perto; `junto` = não espera chegar).
- **Grupo de PdMs: `andar_grupo`**, a mesma mecânica da fila do grupo do jogador. Pedido do Leonardo:
  controlar o grupo, e não um de cada vez, para ficar fluido e ninguém montar em ninguém.
  - Lidera quem está mais perto do destino. O destino **mais fundo** fica com quem lidera, e os mais
    rasos com quem vem atrás. Na saída de 4 guardas enfileirados, puxar a fila pelo que estava mais longe
    da porta fazia um passar por dentro do outro.
  - A cada passo de quem lidera, cada um anda até a casa que o da frente deixou (no máximo 3 casas, sem
    atravessar ninguém). Quando quem lidera chega, os outros vão para os seus destinos, um de cada vez,
    com 0,25 s de intervalo.
  - **Saída em ordem:** primeiro o grupo (guardas), depois o líder da cena (carcereiro). Nunca os dois juntos.
  - Medida: `--medir-grupo` imprime a menor distância entre dois PdMs durante cada `andar_grupo`. Aceito
    ≥ 1,2 m (uma casa = 1,5 m).
- PJs em cena: `grupo` {deitar, levantar, recuar} e `pj` (quem age vai até a porta, rastejando ou
  correndo, e anima).

### 5.5 Poses
- **Deitar no chão:** a animação `levantar` de trás para a frente, segura no tempo 0 (estendido de
  costas). Segurar a 55% deixava o personagem sentado. Como não há animação de bruços, a fala diz
  "deitado no chão", e não "de cara no chão".
- **Levantar de joelhos:** `"anim": "ajoelhar:reverso"`. A animação `levantar` é para quem está **deitado
  no chão**: usada depois de ajoelhar, ela derruba o personagem antes de levantar.
- **Mãos amarradas:** a mão direita um pouco acima e à frente da esquerda; com as duas na mesma altura, uma
  atravessava a outra. `pose: "amarrado"` liga uma IK de dois ossos nos braços
  (`scripts/visual/maos_amarradas.gd`), que funciona por cima de qualquer animação (parado, andando,
  sentado), com uma corda nos pulsos. `pose: "solto"` solta aos poucos. Sem isso, a opção "desamarrar"
  não faz sentido na tela.
- **Sentado no chão:** `pose: "sentado"` = o "levantar" parado em 30% (joelhos para cima). Em 15%, fica
  reclinado para trás. `pose: "em_pe"` levanta dali.
- **Desamarrar, entregar, conversar:** o personagem só vai até o PdM e os dois se olham de frente
  (`pj` com `ir: "pdm:<id>"`). Não precisa ajoelhar.
- **Ameaça armada:** quem ameaça entra em **pose de combate do estilo da arma** (`guarda`: saca a arma
  e usa a guarda do estilo; besta = `besta-guarda`) e então **mira** (`mirar: "besta-mirar"`, segura em
  0,9 s). Na pose normal, a besta ficava solta na mão, num ângulo errado (print do Leonardo).
- Correndo para a posição, a arma fica guardada; ela só aparece quando o PdM toma a guarda.
- Trancar e destrancar: pausa curta mais a mensagem ("uma chave gira…"). O `examinar-ajoelhado` ficou
  estranho para uma fechadura na altura da cintura.

### 5.6 Portas por evento
- `abrir_porta` (`fresta` = só entreabre, no visual, sem liberar a passagem), `fechar_porta` (as folhas
  voltam; luz e visão param de passar, mas a grade continua deixando ver) e `trancar_porta` (estado
  `trancada` + barrada: monstros e PdMs não atravessam).

## 5.7 Seções como pontos de partida (`secoes`)
Cada seção nova ganha uma entrada em `secoes` no aventura.json, para ser testada sozinha:
- `preparar`: passos de cena que montam o mundo como ele estaria naquele ponto (PdMs onde estão, poses,
  portas). Exemplo: na seção 3, o prisioneiro já está amarrado na cela e o carcereiro na sala 4;
- `estado`: o que o `aventura.estado` já teria (dívidas, jogos…);
- `eventos_feitos`: eventos de antes, que não devem disparar;
- `evento` (ou `cena`): o que começa a seção, e `atraso`.

Abrir: `tools/secao.sh <id>` (sem argumento, lista as seções), ou `--aventura=<id> --secao=<id>`. O grupo
padrão entra sem a tela de escolha (`--escolher` para ver a tela; `--grupo=a,b,c` para escolher). Com
`--escolhas=a,b,…` as escolhas se respondem sozinhas (para os testes sem tela).
**Regra do método: ao terminar uma seção, ela entra em `secoes`.**

## 6. Verificação de cada sala
1. `python3 tools/validar_aventura.py data/aventuras/<id>/aventura.json` → "tudo certo".
2. Cena sem tela, todas as ramificações: `--teste=<cena> --escolhas=a,b,c` (respostas automáticas).
   Conferir a ordem das falas, o estado final das portas e onde cada um termina.
3. Cena com imagem: `--fotos=`. Folha de contato com as fotos e inspeção quadro a quadro (luz, câmera,
   pose, sobreposição).
4. Regressão: portas, procurar, tocha, fosso, ocupacao, corpo, marcas, combate, separar, cela.

---

## Diário por sala

### Sala 1 — a cela (26/11)
Grupo preso, sem equipamento; grade P17 trancada e inquebrável; penumbra; catres em A4 e D4; pilha de
equipamento na sala 4 (F5). Retratos e modelos dos PdMs criados antes (arte no padrão do elenco).

### Sala 2 — o carcereiro e o prisioneiro (27/11)
- Gatilho: `inicio: 10` (10 s depois de a aventura começar).
- Cena `carcereiro`:
  1. passos no corredor;
  2. câmera no vestíbulo;
  3. hobgoblin e prisioneiro surgem na sala 4 e vêm juntos (`andar_grupo`) até a frente da grade;
  4. a fala manda deitar;
  5. quem está colado na grade recua;
  6. `escolha` com as 5 reações da tabela, `limite: 3`, com os guardas como último recurso.
- Reações:
  - **deitar** (fim): abre a grade, empurra o prisioneiro para dentro, tranca, sai.
  - **recusar**: chicotada de verdade pelas barras.
  - **correr para a grade**: a grade entreabre, o PJ corre, ele bate e tranca antes; o PJ leva o tranco.
  - **fingir doença** (fim): o PJ rasteja até a grade; ele abre, joga o prisioneiro em cima, tranca, ri, sai.
  - **forçar as barras**: o mais forte tenta; o hobgoblin balança as chaves fora de alcance.
  - **Último recurso:** 4 guardas com bestas (o texto fala em "uma dúzia enche o vestíbulo e o corredor")
    vêm em grupo, tomam a guarda de besta e miram na cela.
- O prisioneiro fica na cela como PdM, para a seção 3 (o jogo de dados).

### Seção 3 — o jogo de dados do prisioneiro (27/11)
- Evento `prisioneiro-dados` encadeado na cena do carcereiro (2 s depois).
- O prisioneiro pede para desamarrar as mãos: escolha "desamarrar" (quem age vai até ele, ajoelha, desfaz o
  nó, se levanta) ou "deixar amarrado". As duas seguem.
- "Informação custa 2 po… ninguém tem, então vamos jogar" → `jogo_dados` com as 5 informações do texto, na
  ordem. Depois da 5ª ele para e lembra as dívidas.
- **Correção do Leonardo (27/11):** o prisioneiro entra de mãos amarradas e só joga e conta coisas
  **depois de solto**. Recusou soltar: ele propõe o jogo mas exige ser solto; recusou de novo: ele senta no
  canto com o ícone. Solto, ele **pergunta se o grupo aceita** o jogo; aceitando, explica as regras, **pega
  o d20**, e o grupo escolhe quem fica com cada um dos outros dados (`escolher_dados`, do maior para o menor).
- **Decisão de leitura:** "cada PJ escolhe outro dado" = cada um com um dado **diferente** (d12, d10, d8, d6,
  d4), que fecha com os 5 personagens. Ganha quem passar o d20 dele.
- Conferência: `--teste=eventos --escolhas=deitar,desamarrar,jogar,…` roda a aventura a partir do primeiro
  evento, com os encadeados; imprime o `estado` e as pistas do diário.
