# CLAUDE.md — PokeTokenBar for Omarchy

Plugin Quickshell para o bar do Omarchy: um Pokémon que choca e evolui conforme
o uso de tokens de IA. Leia o `README.md` para o funcionamento; este arquivo é
sobre como mexer no código sem quebrá-lo.

## A armadilha que mais custa tempo aqui

**O engine QML serve uma cópia em cache dos componentes.** Salvar
`BarWidget.qml` ou `Panel.qml` dispara o hot-reload do Omarchy, o log diz
`Local plugin changed, reloading`, e mesmo assim a versão **antiga** continua
rodando. `omarchy-shell shell rescanPlugins` também não limpa de forma
confiável.

O sintoma é perverso: código novo que claramente não executa, sem nenhum erro.
Um `console.log` novo simplesmente não aparece no journal. É fácil passar meia
hora caçando um bug que não existe.

Antes de concluir que uma mudança em QML não funcionou:

```bash
omarchy restart shell
```

Só depois disso o que você está testando é o que está em disco.

## Invariantes de arquitetura

### 1. O helper é o único escritor de estado

`bin/poke-sync absorb` é a única coisa que escreve `state.json`. O QML observa,
nunca muta.

Isso não é estilo, é correção: **o bar instancia um widget por monitor**. Dois
widgets acumulando o mesmo delta contam em dobro e brigam pelo arquivo. Como o
`Bar.moduleWidgets()` só enxerga os widgets do próprio monitor, não dá para
eleger um escritor pelo lado do QML. A mutação vive no helper, atrás de um
`flock`, e o número de monitores deixa de importar.

Se você for tentado a escrever estado do QML — não. Adicione um subcomando ao
helper.

### 2. A regra de progressão existe em um lugar só

A mutação (acumular deltas, avançar estágios, graduar) é do Python, em
`cmd_absorb`. `Balance.js` tem apenas matemática de **leitura**: limiares,
progresso e formatação, para o bar e o painel desenharem.

Havia um `advance()` em JS que duplicava a regra; foi removido de propósito.
Duas implementações da mesma coisa divergem.

### 3. O contador de tokens só cresce

Os records do `omarchy.agents` **não** são um total histórico confiável: o
coletor do Codex só lê sessões tocadas nos últimos 30 dias, e o do Fireworks
pede 30 dias à API de billing. O total encolhe quando sessões saem da janela.

Por isso guardamos `lastSeen` por agente e somamos apenas deltas positivos.
Qualquer mudança em `cmd_absorb` precisa preservar isso, e
`tests/test_absorb.py` tem o caso do record que encolhe justamente para travar
essa regra. Rode-o antes e depois de mexer ali.

### 4. O Pokédex é projeção, não arquivo

`collection.json` guarda **indivíduos** (o catch log). O dex de espécies sai
dele em `Collection.js`, na hora de desenhar. Nunca persista um segundo arquivo
com as espécies: duas coleções dessincronizam, uma não tem como.

A regra que dá sentido ao dex é `speciesReached`: as espécies de uma entrada são
`line[0..finalStage]`, não a linha inteira. Um Pokémon que graduou sem evoluir
não te dá as evoluções. Se você "consertar" isso, o dex passa a colecionar o que
a pessoa poderia ter criado em vez do que criou.

### 5. Entradas do histórico têm id próprio, não timestamp

`companionId` existe porque `hatchedAt` tem resolução de um segundo: duas
chocagens no mesmo segundo — um duplo disparo do widget — colidiriam, e a
entrada passaria a descrever a espécie errada. Um teste cobre isso
(`test_absorb.py`, caso 9); foi ele que revelou o problema.

`companion_key()` cai para `hatchedAt` quando não há id, para companions
gravados antes deste campo existir.

### 6. Os records do `omarchy.agents` são somente-leitura

`~/.local/state/omarchy/agents/usage/*.json` são dados de outro plugin. Este
aqui lê e nunca escreve, e **nunca** roda `omarchy-agent-usage-update` — quem
regenera os records é o timer do `omarchy.agents`, a cada 900s por padrão.

O contrato está documentado em
`/usr/share/omarchy/shell/plugins/agents/README.md`, seção *Data*. Se precisar
de um campo novo, leia de lá; não invente.

## Ferramentas: cuidado com falso negativo

- **`qmlformat` e `qmllint` não parseiam `function f(): void`** nesta build do
  Qt. Todo arquivo QML com um `IpcHandler` tipado dá `rc=1` e
  `Unexpected token 'void'`. Isso vale também para plugins de primeira parte do
  Omarchy que funcionam perfeitamente. **Não é erro no seu código.** Para
  checar sintaxe de verdade, teste blocos sem funções tipadas, ou recarregue o
  shell e leia o journal.
- `journalctl --user | grep 'DEBUG qml:'` mostra os `console.log` do shell. Se o
  seu log não aparece, releia a seção do cache acima antes de duvidar do log.

## Verificação

```bash
tests/test_collection.py      # coleção e sorteio de shiny (puras, rápidas)
tests/test_absorb.py          # acumulação e integração, contra os records reais
tests/test_dex.mjs            # projeção do Pokédex
bin/poke-sync index           # reconstrói o índice (deve dar 329 espécies base)
bin/poke-sync hatch           # sorteia e baixa sprites
omarchy restart shell         # única forma confiável de testar QML novo
```

Para forçar um shiny sem esperar 64 chocagens, troque `roll_shiny` no módulo —
é o que os testes fazem:

```python
ps.roll_shiny = lambda rng=None: True
ps.cmd_hatch([])
```

Para ver uma evolução sem esperar dias: edite `tokensIntoStage` em
`state.json` para logo abaixo do limiar do estágio e rode
`bin/poke-sync absorb 0.3`. Os limiares em dificuldade 0.3, para um comum de 2
formas, são 75M e 150M.

## Convenções

- Português do Brasil no código, comentários, commits e documentação.
- Comentários explicam **por que**, não o que. Os comentários longos deste
  projeto marcam decisões que parecem arbitrárias e não são — o escritor único,
  o descarte do excedente na graduação, o `smooth: false` nos sprites.
- Sprites são pixel art: `smooth: false` sempre, e largura derivada da
  proporção (os Gen-V não são quadrados: 36x66, 59x68…).
- GIF animado só onde há foco: o estágio atual no companion, o hover na grade do
  dex e nas linhas do histórico. Uma grade inteira animada é epilética e cara.
- Nada de `ToolTip` do Qt Quick Controls — ele vem com o estilo padrão de fundo
  claro e destoa do shell. Use `PanelToolTip`. E num popout estreito prefira uma
  linha de detalhe fixa: um tooltip mais largo que o elemento é recortado pela
  borda (foi o que aconteceu na grade do dex).
- Sem co-autoria de ferramenta em commits, PRs ou arquivos versionados.
