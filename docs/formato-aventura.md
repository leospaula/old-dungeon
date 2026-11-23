# Formato de arquivo de aventura

Cada aventura fica em `data/aventuras/<id>/aventura.json` e preenche a planta fixa de `data/masmorra/layout.json`. As salas que a aventura não menciona ficam vazias. O arquivo completo da aventura 1 será gerado depois que o rascunho (nota *Aventura 1 - Monte Corvo* no Personal Brain, `RPG/Masmorra Clássica/`) for aprovado.

```json
{
  "id": "monte-corvo-01",
  "titulo": "A Masmorra do Monte Corvo",
  "masmorra": "monte-corvo",
  "nivel_recomendado": [1, 2],
  "gancho": "Kobolds saqueiam a estrada do vale; o mercador de Vau-Raso paga 300 po…",

  "salas": {
    "1": {
      "leitura": "A entrada é uma fenda larga na rocha, meio escondida por galhos amarrados…",
      "monstros": [{ "tipo": "kobold", "qtd": 3, "comportamento": "sentinela", "se_fugir": "alerta_sala_3" }],
      "tesouro": { "pp": 12 }
    },
    "2": {
      "leitura": "Paredes cobertas de entalhes anões…",
      "pistas": ["porta escondida onde o eco responde"],
      "armadilhas": [{ "tipo": "fosso", "chance": "2-em-6", "dano": "1d6", "procurar": true }]
    }
  },

  "portas": {
    "8-9": { "trancada": true, "armadilha": { "tipo": "agulha_veneno", "efeito": "1d4 + fraqueza 1 dia" } }
  },

  "errantes": {
    "frequencia_turnos": 2, "chance": "1-em-6",
    "tabela": ["1d4 kobold", "1d6 rato_gigante", "1d3 besouro_de_fogo", "1d4 estirge", "1d3 bandido", "1d2 esqueleto"]
  },

  "eventos": [
    { "quando": "monstro_morto:chefe_hobgoblin", "efeito": "moral_grupo:hobgoblin=6" }
  ],

  "vitoria": { "condicao": "monstro_morto:chefe_hobgoblin OU acordo:kobolds", "recompensa_po": 300 }
}
```

**Regras do formato**
- `monstros[].tipo` aponta para uma chave de `data/regras/monstros.json`.
- `portas` usa `"<de>-<para>"` e sobrescreve o que está no layout.
- O tesouro aceita `po`, `pp`, `pc`, `gemas`, `joias` e `itens` (nome + propriedades).
- `leitura` é o texto "lido em voz alta" para o grupo, como o mestre faria na mesa.
