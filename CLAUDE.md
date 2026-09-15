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

`bin/omapkdex-sync absorb` é a única coisa que escreve `state.json`. O QML observa,
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

### 6. O que o bar mostra ≠ o companion real

`currentSprite` e `displayName` são sempre o companion de verdade.
`barSprite` e `barName` respeitam o Pokémon fixado (`representativeSpeciesId`).

Só o botão do bar usa os segundos. Se você fizer o painel usar `barSprite`, ele
passa a anunciar uma espécie com o estágio de outra — foi exatamente o bug que
apareceu quando os dois eram a mesma propriedade.

Corolário que já causou um bug reportado: com espécie fixada, o bar **não pode**
atribuir o progresso do companion ao nome da fixada. "Corphish · estágio 2/2" é
contradição, porque o Corphish é o estágio 1 — e quem lê fica sem saber em que
estágio está. O `Balance.barTooltip` garante que a fixada nunca apareça na mesma
linha que um estágio, e a estrela sobre o sprite diz no próprio bar que aquela
não é a espécie em criação. Pista que depende de hover não serve aqui.

### 6.1. A dificuldade é reescalada, nunca aplicada crua

`tokensIntoStage` é um número ABSOLUTO de tokens e o limiar é derivado da
dificuldade na hora. Então a dificuldade tem de ser lembrada: `state.difficulty`
guarda a última com que se absorveu, e `cmd_absorb` reescala o progresso antes
de acumular qualquer coisa quando ela muda.

Sem isso — e foi assim até esta versão — baixar a dificuldade encolhia o limiar
por baixo do progresso acumulado e o companion **graduava de graça**: medido,
240M de progresso contra limiares de 75M+150M cobre a linha inteira de uma vez.
Subir a dificuldade roubava progresso em silêncio.

Duas regras que o teste trava e que parecem detalhe:

- **Arredondar não pode completar um estágio.** A um token do limiar antigo, a
  proporção cai exatamente sobre o novo, e o reescalonamento entregaria a
  evolução que ele existe para evitar.
- **`difficulty` ausente adota a atual sem reescalar.** Tratar a ausência como o
  default 1.0 multiplicaria por 0.3 o progresso de quem já jogava em 0.3 — quem
  mais sofreria seria justamente quem instalou antes.

### 6.2. O perfil do indivíduo é projeção, não estado

IVs, gênero e habilidade são sorteados de um PRNG semeado pelo `companionId`
(`Profile.js`), e o nível é derivado da fração de crescimento. **Nada disso é
persistido**, então os indivíduos que já estavam no histórico ganharam perfil
retroativo, sem migração e sem backfill.

O preço é que o seed tem de ser estável para sempre: se `seedFor` mudar, os IVs
do bicho de alguém mudam sozinhos. Ela é FNV-1a, que é especificada — não o hash
da linguagem.

A **natureza é a exceção** e por isso é gravada na entrada: o Mint a re-sorteia,
então ela é mutável e não pode sair de um seed. Entradas fechadas antes do campo
existir mostram "—", e é assim que deve ser: inventar uma natureza que aquele
indivíduo nunca teve é pior que não mostrar nenhuma.

Os dados de espécie (stats base, habilidades, learnset, descrição) vêm do
`omapkdex-sync details`, que cacheia em `~/.cache/omarchy/<módulo>/details/`.
Sem eles o perfil aparece pela metade — nível, natureza e IVs não dependem de
rede — em vez de estourar.

### 7. O XP da candy não entra na carteira

A carteira é `lifetimeTokens − spentTokens`. Somar o XP da Rare Candy ao
`lifetimeTokens` faria de cada candy uma máquina de dinheiro. O XP vai **só**
para `tokensIntoStage`, e não é escalado pela dificuldade (escalar os dois se
cancelaria). `tests/test_economy.py` abre com esse caso.

### 8. A chave da janela de candy não pode ser a data

O original proíbe em comentário, e o motivo é observável aqui: o `resetsAt` do
limite de sessão do Claude vem string vazia. A chave é `<agente>:<label>`.

Duas regras que parecem simplificáveis e não são: o rearme é só
`percent < 1.0` (sem histerese — o percent de uma janela só cai na virada
dela), e `candySeeded` marca as janelas já cheias na primeira execução **sem
conceder**, senão ligar a feature com o semanal em 100% paga 5 candies
retroativas.

### 9. Os records do `omarchy.agents` são somente-leitura

`~/.local/state/omarchy/agents/usage/*.json` são dados de outro plugin. Este
aqui lê e nunca escreve, e **nunca** roda `omarchy-agent-usage-update` — quem
regenera os records é o timer do `omarchy.agents`, a cada 900s por padrão.

O contrato está documentado em
`/usr/share/omarchy/shell/plugins/agents/README.md`, seção *Data*. Se precisar
de um campo novo, leia de lá; não invente.

### 10. Uma entrada da coleção nunca é reaberta

`sync_open_entry` não abre entrada para um `companionId` que já existe **em
qualquer estado**. Sem essa guarda, uma chocagem que falhou por rede deixava
`companion.json` descrevendo o bicho já graduado, e a absorção seguinte o
acrescentava de novo como aberta: o mesmo indivíduo duas vezes no histórico, e o
graduado voltando a ser companion no estágio 0.

Pelo mesmo motivo, `cmd_absorb` trata "`hatched` verdadeiro sem companion" como
ovo aguardando sorteio. O fallback `companion or {}` daria uma linha fantasma de
uma forma, que gradua quase na hora — já medi `graduations=1` com a coleção
vazia.

### 11. A rede nunca roda fora do lock, e o lock nunca é infinito

`cmd_buy` e `cmd_use` passam a escrita da coleção e a chocagem no parâmetro
`after` do `_with_state_lock`, que roda **dentro** do lock. Antes rodavam fora,
porque o `return` do `_with_state_lock` está dentro do `with` e solta o lock ao
retornar — fácil de não notar.

Como consequência, quem pede o lock espera por rede, então a aquisição tem
timeout (`LOCK_TIMEOUT`): uma compra devolve erro em vez de pendurar o clique.

E toda chamada a `cmd_hatch` fora do próprio `cmd_hatch` é envolvida em
`try/except`: uma falha de rede não pode abortar a operação que a chamou, porque
o estado já está coerente e a próxima passada tenta de novo.

### 12. O shiny visível é calculado em dois lugares, e isso é certo

A regra "um Ditto disfarçado esconde o brilho" vale em toda parte. Ela existe em
`Collection.js` (`visibleShiny`, para a projeção do dex e do histórico, que opera
sobre entradas) e em `BarWidget.qml` (`visibleShiny`, para o bar, que lê
`companion.json` direto). Formatos de dado diferentes, mesma regra — não é
duplicação a eliminar. Havia uma terceira cópia em Python que não era usada por
ninguém; foi removida.

Por isso a entrada da coleção carrega `dittoDisguise` e `dittoRevealed` ao lado
do `shiny` bruto: o bicho **é** shiny, e quem decide se pode aparecer é a
exibição.

## Um laço fácil de criar: FileView que falha e Process que "sai bem"

`onLoadFailed` disparar o helper é o gatilho normal da primeira abertura de uma
espécie. Mas se o helper sair com 0 sem deixar o arquivo legível, o FileView
recarrega, falha, dispara o helper de novo — **laço infinito de processos**.

Aconteceu de verdade: `cmd_details` usava `os.path.exists` para o cache, e um
diretório com o nome do arquivo satisfazia a checagem. Dois consertos, e os dois
são necessários: `os.path.isfile` no helper, e `fetchDetailsOnce` no widget, que
permite **uma** tentativa automática por espécie (o botão de tentar de novo é
que rearma).

## Navegação pedida de fora: o Loader não recarrega se a aba não muda

`openProfileAt` guarda o pedido em `pendingProfile` e o aplica no `onLoaded` do
Loader da aba. Só que reabrir o painel na aba em que ele já estava **não** troca
o `sourceComponent`, então o Loader não recarrega e o `onLoaded` nunca dispara —
o pedido ficava preso e o comando parecia não fazer nada (sempre na segunda vez
seguida). Por isso `applyPendingProfile` é chamada de todos os caminhos que
podem ter acabado de deixar a view pronta: `onLoaded`, `onTabChanged` e a
abertura.

## Ferramentas: cuidado com falso negativo

- **Glifo de Nerd Font não se adivinha.** Já custou três chutes errados neste
  projeto. Consulte a cmap da fonte antes:
  ```python
  from fontTools.ttLib import TTFont
  cmap = TTFont('/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf').getBestCmap()
  print(0xF0493 in cmap)   # md-cog, o da aba de settings
  ```
  E confira os bytes depois de escrever: o glifo da engrenagem chegou ao arquivo
  como string **vazia** na primeira tentativa (o heredoc o engoliu), e o chip
  apareceu em branco sem erro nenhum no journal.
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
tests/test_economy.py         # carteira, preços, candy, ovos, taxa de queima
tests/test_ditto.py           # o easter egg: disfarce, shiny escondido, revelação
tests/test_dex.mjs            # projeção do Pokédex, ownsSpecies, 2×
tests/test_shop.mjs           # lista da loja, bag, humor, tooltip
tests/test_resilience.py      # falha de rede no meio das operações
tests/test_details.py         # dados de espécie: normalização, cache, fallback REST
tests/test_profile.mjs        # IVs, gênero, habilidade, nível, stats, golpes
bin/omapkdex-sync index           # reconstrói o índice (deve dar 329 espécies base)
bin/omapkdex-sync details 341     # baixa e cacheia os dados de espécie do perfil
bin/omapkdex-sync hatch           # sorteia e baixa sprites
omarchy restart shell         # única forma confiável de testar QML novo
```

Para forçar um shiny sem esperar 64 chocagens, troque `roll_shiny` no módulo —
é o que os testes fazem:

```python
ps.roll_shiny = lambda rng=None, denominator=64: True
ps.roll_ditto = lambda rarity, forms, rng=None: True
ps.cmd_hatch([])
```

Para simular rede fora, troque `load_index` (ou `evolution_line`) por algo que
levante `urllib.error.URLError` — é o que `tests/test_resilience.py` faz. Todos
os outros stubs substituem a rede por funções que sempre funcionam, e foi essa
lacuna que deixou passar três bugs de estado incoerente.

O `cmd_absorb` só roda a progressão quando há **delta novo de tokens** — é o que
o original faz. Um teste que injeta `tokensIntoStage` e espera evolução não vai
funcionar; ele precisa somar tokens a um record (ver `Sandbox.bump` em
`tests/test_ditto.py`).

Para ver uma evolução sem esperar dias: edite `tokensIntoStage` em
`state.json` para logo abaixo do limiar do estágio e rode
`bin/omapkdex-sync absorb 0.3`. Os limiares em dificuldade 0.3, para um comum de 2
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
