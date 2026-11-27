# Sistemas de regras (nível de regras)

O jogo não guarda números de regra espalhados pelo código: ele pergunta a `scripts/regras/sistema.gd`,
que responde pelo **perfil ativo** em `data/regras/sistemas/<id>.json`.

| Nível | Perfil | Situação |
|---|---|---|
| Básico | `bx` (B/X / Old-School Essentials) | **pronto**: é o que o jogo sempre usou |
| Intermediário | `rc` (Rules Cyclopedia) | planejado: herda do `bx` (`"base": "bx"`) e liga módulos |
| Avançado | `add` (AD&D) | planejado: perfil próprio, com outras tabelas e regras de estrutura |

Escolha: `--regras=<id>` (no navegador, `?args=--regras=rc`). Depois vira uma opção na tela de escolha
do grupo. O nível de regras é separado da **dificuldade** (força dos monstros, recursos), que pode existir
junto com ele.

## O que o perfil responde

| Pergunta | Função | Campo do perfil |
|---|---|---|
| Modificador de atributo | `Sistema.mod(v)` | `atributos.mod` |
| Rolar um ataque (natural máximo/mínimo) | `Sistema.atacar(thac0, ca, mod)` | `ataque` |
| Número para acertar e a chance (tela) | `numero_para_acertar`, `chance_acerto` | `ataque` |
| Ajuste de distância por faixa | `ajuste_faixa(faixa)` | `ataque.faixa_distancia` |
| THAC0 e PV de monstro pelo DV | `thac0_monstro`, `pv_monstro` | `monstros` |
| Iniciativa | `iniciativa()` | `iniciativa` (hoje d6 por lado, empate rola de novo) |
| Surpresa | `surpresa(extra)` | `surpresa` |
| Moral (quando testa e o teste) | `testa_moral_em`, `moral(valor)` | `moral` |
| Movimento por carga e em combate | `taxa_exploracao_m`, `taxa_combate_m` | `movimento` |
| Chances de exploração em d6 | `em6(tabela, classe)`, `forcar_em6` | `exploracao` |

Conferência: `godot --headless --path . --script tools/testar_sistema.gd` compara o perfil ativo com os
valores do B/X. Ao criar o `rc`, esse teste ganha a versão dele.

## Próximos passos

1. **Intermediário (`rc`)**, módulo a módulo, cada um ligado em `"modulos"`:
   - `maestria_armas` (dano e efeitos da arma pelo treino; aparece direto no combate);
   - `pericias_gerais`;
   - `manobras_guerreiro` (golpe forte, aparar, desarmar);
   - níveis acima do 14.
2. **Avançado (`add`)**: raça separada da classe, multiclasse, força excepcional, proficiências,
   iniciativa d10 com fator de velocidade, tabelas próprias de ataque e salvaguarda, mais classes e magias.
3. **Monstros e fichas por sistema**: o bestiário ganha uma versão por perfil (ou uma conversão a partir
   do B/X), e os personagens prontos ganham uma ficha por perfil. As aventuras não mudam: citam monstros e
   testes por id, e o perfil resolve os números.

Ainda dentro do código (a migrar quando o módulo precisar): os ajustes de classe nas fichas prontas
(THAC0 e PV vêm da ficha), as habilidades de ladrão (porcentagens da ficha) e os testes de atributo da
aventura (os pães da Seção 5).
