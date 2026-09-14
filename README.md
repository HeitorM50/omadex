# PokeTokenBar for Omarchy

Um Pokémon no bar do Omarchy que choca e evolui conforme você queima tokens de
IA. Porte da camada de companion do
[PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (macOS) para um plugin
Quickshell, lendo os dados que o `omarchy.agents` já coleta.

```
󰪯  19.3M          ovo, com os tokens de hoje ao lado
🦀 19.3M          depois de chocar, o sprite Gen-V animado
```

## Como funciona

O plugin **não coleta uso nenhum**. Os arquivos em
`~/.local/state/omarchy/agents/usage/*.json` são um contrato público do
`omarchy.agents` (`schemaVersion: 1`, documentado em
`/usr/share/omarchy/shell/plugins/agents/README.md`), e este plugin é
consumidor somente-leitura deles. Quem autentica nas APIs dos provedores e
regenera os records é o `omarchy.agents`; aqui só somamos `modelUsage`.

Isso é o que torna o porte viável: dos ~19.700 LOC de Swift do original, cerca
de 7.000 são coletores de uso que o Omarchy já tem prontos e melhores.

### Progressão

Portada de `PokemonBalance` (`CompanionModel.swift:104-127` do original):

| | Tokens |
|---|---|
| Ovo choca | 5M |
| Graduação — comum | 750M |
| Graduação — incomum | 1,875B |
| Graduação — raro | 3B |
| Graduação — lendário | 6B |

O custo do estágio `i` (0-based) numa linha de `k` formas é
`T · (i+1) / (k(k+1)/2)`. A soma sobre todos os estágios é exatamente `T`, então
a graduação cai no total da raridade independente do tamanho da linha.

Tudo isso é multiplicado por `difficulty`. O padrão é **0.3**, não 1.0: o
original é balanceado para ~253M tokens/dia, e em ~50M/dia uma graduação comum
levaria uns 15 dias. Em 0.3 dá cerca de 5 dias. Use `1.0` para o balanceamento
original.

A raridade vem do `capture_rate` da PokéAPI (`≤45` raro, `≤120` incomum, senão
comum; `is_legendary`/`is_mythical` força lendário), e a chocagem é ponderada
por esse mesmo número — na prática, lendário sai cerca de 1 em 95.

### Pokédex e histórico

O popout tem três abas: **Companion** (o Pokémon de agora), **Pokédex** (uma
célula por espécie já possuída) e **Histórico** (uma linha por indivíduo
criado).

O Pokédex **não é um arquivo** — é projetado do histórico por `Collection.js`.
Duas coleções persistidas dessincronizariam; uma não tem como.

Uma espécie entra no dex assim que o companion a alcança, e fica para sempre.
O dex registra espécies **alcançadas**, não a linha inteira: um Corphish que
graduou sem evoluir não dá o Crawdaunt. É a diferença entre colecionar o que
você criou e o que poderia ter criado.

### Shiny

Uma chocagem em **64** sai shiny. O 1/4096 dos jogos daria uma a cada algumas
décadas no ritmo de uso real; o próprio PokeTokenBar já afrouxa a taxa.

Um shiny mantém as cores por toda a linha evolutiva, e os sprites vêm das
subpastas próprias da PokéAPI (`.../animated/shiny/<id>.gif`, com fallback para
`.../shiny/<id>.png` e, se nem isso existir, para a arte normal — melhor um
Pokémon com a cor errada que um sem arte).

O ✨ aparece no nome do companion, na linha do histórico e na célula do dex.
Na célula ele marca a **espécie**: quer dizer "já tive esta shiny alguma vez", e
fica mesmo quando a célula está mostrando a arte normal. Uma espécie possuída
nas duas versões pode alternar a arte no clique.

O bar fica de fora de propósito: em 22px o sprite shiny já é a diferença
visível, e mais um glifo só apertaria os vizinhos.

### O contador é monotônico

Os records **não** servem como total histórico: o coletor do Codex só lê sessões
tocadas nos últimos 30 dias e o do Fireworks pede 30 dias à API de billing.
Somar `modelUsage` a cada leitura daria um total que encolhe quando sessões saem
da janela — e um Pokémon que desevolui.

Então guardamos o último total visto por agente e acumulamos só deltas
positivos. Um record que encolhe, zera, ou é reescrito contribui zero, nunca
negativo.

Por padrão a contagem começa em zero: na primeira execução o histórico já gasto
só marca a régua, para o primeiro Pokémon não graduar instantaneamente. Ligue
`seedFromExisting` para que ele conte.

## Arquitetura

```
BarWidget.qml     observa e orquestra; não escreve nada
Panel.qml         casca do popout: abas, teclado, ciclo de vida
CompanionView.qml \
DexView.qml        > uma aba cada, apresentação pura
CatchLogView.qml  /
Balance.js        matemática de leitura (limiares, progresso, formatação)
Collection.js     projeção do Pokédex sobre o histórico
bin/poke-sync     o único escritor: PokéAPI, sprites e a progressão
```

A mutação do estado vive no helper, não no QML, porque **o bar instancia um
widget por monitor**: dois widgets acumulando o mesmo delta contariam em dobro, e
`state.json` teria dois escritores. Com a regra no helper, atrás de um `flock`, o
número de monitores deixa de importar — e a lógica fica testável em Python em vez
de espelhada entre o QML e um teste.

### Arquivos

| Caminho | Escrito por |
|---|---|
| `~/.local/state/omarchy/<id>/state.json` | `poke-sync absorb` |
| `~/.local/state/omarchy/<id>/companion.json` | `poke-sync hatch` |
| `~/.local/state/omarchy/<id>/collection.json` | `poke-sync hatch` e `absorb` |
| `~/.cache/omarchy/<id>/sprites/` | `poke-sync` |
| `~/.cache/omarchy/<id>/base-species.json` | `poke-sync index` |

### O helper

```bash
bin/poke-sync index              # reconstrói o índice das 329 espécies base
bin/poke-sync hatch [raridade]   # sorteia uma espécie e resolve a linha
bin/poke-sync sprites <ids...>   # (re)baixa sprites
bin/poke-sync absorb <dif> [seed]  # acumula tokens e avança a progressão
```

Sprites são os GIFs animados Gen-V de
`raw.githubusercontent.com/PokeAPI/sprites`, com fallback para o PNG estático
quando a espécie não tem animação. Baixados uma vez e cacheados. O índice sai do
GraphQL da PokéAPI (0,7s) com fallback REST (~60s) se ele estiver fora.

### Testes

```bash
tests/test_collection.py   # coleção e sorteio de shiny (funções puras)
tests/test_absorb.py       # absorção e integração, contra os records reais
tests/test_dex.mjs         # projeção do Pokédex
```

107 asserções. As que mais importam:

- **O record que encolhe** (`test_absorb.py`): `lifetimeTokens` não pode cair e
  o estágio não pode regredir quando sessões saem da janela de 30 dias do
  coletor do Codex.
- **Duas chocagens seguidas** não deixam duas entradas abertas no histórico. Foi
  este teste que revelou que `hatchedAt` — resolução de um segundo — não servia
  como identidade de entrada.
- **O ✨ só marca espécies alcançadas** (`test_dex.mjs`): um shiny que parou na
  forma base não dá o brilho na evolução que ele nunca virou.

Nenhum dos três toca a rede nem o seu estado real.

## Interações

- **Ícone no bar:** esquerda abre o painel, meio reavalia o uso.
- **Painel:** `←`/`→` (ou `h`/`l`) trocam de aba, `1`/`2`/`3` vão direto a uma,
  `r` reavalia, `a` abre o painel detalhado do `omarchy.agents`, Tab vai para o
  painel vizinho, Esc fecha.
- **Pokédex:** o hover mostra o detalhe embaixo da grade; clicar numa espécie
  que você teve nas duas versões alterna entre a arte normal e a shiny.
- **IPC:** `omarchy-shell io.github.heitorm50.poketokenbar <open|close|toggle|refresh|hatch|companion|dex|log>`
  — `dex` e `log` abrem direto na aba, o que serve para um atalho de teclado.

## Settings

Em `~/.config/omarchy/shell.json`, na entrada do widget:

```bash
omarchy bar set io.github.heitorm50.poketokenbar difficulty 1.0 --json
omarchy bar set io.github.heitorm50.poketokenbar spriteSize 26 --json
```

| Chave | Padrão | O que faz |
|---|---|---|
| `difficulty` | `0.3` | Multiplica os limiares. 0.1–2.0; abaixo de 1 evolui mais rápido |
| `spriteSize` | `22` | Altura do sprite no bar, em px |
| `showTokens` | `true` | Mostra os tokens de hoje ao lado do sprite |
| `showLimitPercent` | `false` | Mostra o % do limite de janela mais apertado |
| `seedFromExisting` | `false` | Conta o uso já registrado em vez de começar de zero |
| `pollSeconds` | `60` | Rede de segurança; os records já são observados por evento |

## Instalação

```bash
git clone <repo> ~/.config/omarchy/plugins/io.github.heitorm50.poketokenbar
omarchy bar add io.github.heitorm50.poketokenbar --section right
```

Precisa de Python 3 (só a stdlib) e de rede na primeira chocagem de cada
espécie.

### Ao editar o plugin

Salvar um arquivo sob `~/.config/omarchy/plugins/` recarrega o plugin, mas o
engine QML mantém um cache de componentes que **nem o hot-reload nem
`omarchy-shell shell rescanPlugins` limpam de forma confiável**. Uma mudança em
`BarWidget.qml` ou `Panel.qml` pode continuar rodando a versão antiga sem
nenhum aviso — o sintoma é código novo que claramente não executa. Para ter
certeza de estar testando o que está em disco:

```bash
omarchy restart shell
```

## Documentação

- [`CLAUDE.md`](CLAUDE.md) — invariantes de arquitetura e as armadilhas do
  ambiente, para quem (ou o que) for mexer no código.
- [`docs/aprendizados.md`](docs/aprendizados.md) — o que só ficou claro
  construindo: o dado de terceiros que não era cumulativo, o widget que não era
  único, o cache invisível de QML.

## Crédito e escopo

A ideia, o balanceamento de tokens e a mecânica de companion são do
**PokeTokenBar** de [chattymin](https://github.com/chattymin/PokeTokenBar)
(MIT). Este plugin reimplementa só a fatia do mascote — choca, evolui, gradua.
Ficaram de fora, e podem virar uma fase 2 sobre a mesma base de estado: loja,
Pokédex, catch log, shiny, natures, Rare Candy por limite batido e o pet
flutuante no desktop.

Projeto de fã, não-comercial e não oficial. Pokémon é marca registrada da
Nintendo / Creatures Inc. / GAME FREAK inc. Sprites e dados vêm da
[PokéAPI](https://pokeapi.co/). Ver `NOTICE.md`.
