# Aprendizados do porte

Notas do que só ficou claro construindo. A ordem é mais ou menos a ordem em que
cada coisa apareceu.

## 1. A pergunta certa não era "dá para portar?"

O PokeTokenBar é macOS nativo: `Package.swift` declara
`platforms: [.macOS(.v14)]`, Swift 6, SwiftUI/AppKit, `NSStatusItem`, Keychain.
Não há porte — nem via container, nem via camada de compatibilidade.

Mas medir o repositório mudou a conversa. Dos ~19.700 LOC de Swift:

| Parte | LOC | Destino |
|---|---|---|
| Coletores de uso (`LocalUsageReader`, `UsageStore`, `OAuthLimitsProvider`, `SessionKeyLimitsProvider`, `CursorUsageAPI`, `ModelPricing`, `KeychainAccess`…) | ~7.000 | **descartado** — o `omarchy.agents` já faz |
| Camada de jogo (`CompanionStore`, `CompanionModel`, `PokemonProfile`, `PokeAPIClient`, `SpriteLoader`) | ~4.500 | portado |
| UI, localização, atualizador, telemetria | ~8.000 | reescrito ou fora de escopo |

A metade cara do app — descobrir sessões, parsear transcripts, autenticar em
endpoints de uso, precificar por modelo — já existia na máquina, melhor feita e
já autenticada. O porte virou ~1.600 LOC.

**A lição:** antes de decidir se dá para portar algo, meça que fração do
original é problema que o ambiente de destino já resolveu. A resposta muda o
tamanho do trabalho em uma ordem de grandeza.

## 2. Dados de terceiros mentem sobre serem cumulativos

O primeiro desenho somava `modelUsage` dos records a cada leitura e usava isso
como total histórico. Parece óbvio: são contadores.

Só que o README do `omarchy.agents` avisa, numa nota de rodapé, que o coletor do
Codex só lê arquivos de sessão tocados nos últimos 30 dias, e o do Fireworks
pede 30 dias à API de billing. O "total" **encolhe** quando sessões saem da
janela.

Num tracker de uso isso é um detalhe de exibição. Aqui significaria um Pokémon
que desevolui sozinho — regressão visível, sem erro nenhum no log, e que só
apareceria semanas depois.

A correção é pequena: guardar o último total visto por agente e somar só deltas
positivos.

```python
delta = current - previous
if delta > 0:
    gained += delta
```

**A lição:** antes de tratar um número de outro sistema como monotônico, leia o
que ele realmente mede. E quando a monotonicidade for requisito, force-a na
borda em vez de confiar na fonte. O teste que trava isso
(`tests/test_absorb.py`, caso 3) é o mais valioso do projeto.

## 3. "Um widget" é mentira — o bar cria um por monitor

Escrevi a acumulação e a persistência dentro do `BarWidget.qml`. Funcionou
perfeitamente, porque esta máquina tem um monitor.

O que denunciou foi ler o `BarWidget` base do Omarchy e encontrar `broadcast()`,
com o comentário explicando que existe *porque uma superfície de bar existe por
monitor*. Duas instâncias, cada uma absorvendo o mesmo delta e escrevendo o
mesmo arquivo: contagem em dobro e escrita concorrente, latentes até o dia de
plugar uma segunda tela.

A primeira tentativa de conserto foi eleger uma instância escritora via
`bar.moduleWidgets(moduleName)`. Não funciona: cada monitor tem seu próprio
`Bar`, e `moduleWidgets` só enxerga os widgets daquele bar. Não há como eleger
pelo lado do QML.

A solução foi mover a mutação inteira para o helper, atrás de um `flock`. O QML
virou observador puro. Efeitos colaterais bons: a regra ficou testável em Python
de verdade, em vez de espelhada num teste JS que reimplementava o QML — e essa
duplicação já tinha me dado um falso negativo.

**A lição:** num shell com superfícies por monitor, "meu componente é único" é
uma suposição, não um fato. Quem escreve estado precisa ser um processo, não um
componente de UI.

## 4. Cache invisível de componentes QML

O pior tempo perdido do projeto.

Editei o `BarWidget.qml`, salvei, o journal registrou
`Local plugin changed, reloading: io.github.heitorm50.poketokenbar` — e o código
antigo continuou rodando. `console.log` novo não aparecia. O `state.json` era
escrito por uma versão que eu já tinha apagado do disco, sem lock, porque aquela
versão escrevia direto do QML.

Cheguei a duvidar do `Process`, do `pluginDir`, do `flock`, do `journalctl`.
Instrumentei três vezes. A instrumentação também não aparecia — o que, em
retrospecto, era a evidência decisiva: o código não estava rodando, ponto.

`omarchy-shell shell rescanPlugins` não resolveu. Só `omarchy restart shell`.

**A lição:** quando uma instrumentação recém-adicionada não aparece no log, a
hipótese principal não é "o log está quebrado", é "este código não está
rodando". Testar que o observador funciona vem antes de investigar o observado.

## 5. Falsos negativos de ferramenta parecem bugs

`qmllint` e `qmlformat` desta build do Qt não parseiam `function f(): void`, a
sintaxe tipada que todo `IpcHandler` usa. Resultado: `rc=1`,
`Unexpected token 'void'`, em todo arquivo com IPC.

Passei um tempo bissetando o arquivo atrás de um erro de sintaxe inexistente. O
que resolveu foi rodar a mesma ferramenta contra um plugin de primeira parte do
Omarchy que comprovadamente funciona: deu o mesmo erro.

**A lição:** ao ver um erro de ferramenta em código novo, rode a ferramenta
contra código conhecidamente bom antes de acreditar nela. Um baseline custa
trinta segundos e economiza meia hora.

## 6. Glifos de Nerd Font não se adivinham

Chutei codepoints para o ícone de ovo três vezes. `U+F0AC1` — helicóptero.
`U+F06D3` — uma pena, que ficou no bar por um bom tempo parecendo intencional.

A forma certa é perguntar à fonte:

```python
from fontTools.ttLib import TTFont
f = TTFont('/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf')
rev = {}
for cp, name in f.getBestCmap().items():
    rev.setdefault(name, cp)
print([(n, hex(rev[n])) for n in rev if 'egg' in n.lower()])
# md-egg -> 0xf0aaf
```

E renderizar com `magick label:` para conferir com o olho antes de commitar.

Detalhe que quase me enganou de novo: o glifo errado aparecia **colorido** na
captura de tela, o que me fez pensar em fonte de emoji colorida. Era fringing de
subpixel num glifo branco. Ampliar a imagem antes de teorizar teria resolvido.

## 7. Balanceamento de jogo é específico da máquina

O PokeTokenBar é calibrado para ~253M tokens/dia. Medindo os records reais desta
máquina: ~357M por semana, uns 51M/dia. No balanceamento original, uma graduação
comum (750M) levaria ~15 dias — lento o bastante para o mascote parecer parado.

Em vez de mexer na tabela de constantes portada, expus o multiplicador de
dificuldade que o original já tinha e mudei o **padrão** para 0.3. Uma simulação
de 60 dias no consumo real dá uma graduação a cada ~5 dias, que era a cadência
pretendida.

**A lição:** ao portar um sistema calibrado, meça o ambiente de destino antes de
aceitar os defaults. E prefira mexer no parâmetro que o original já expôs a
mexer nas constantes — a tabela continua sendo referência verificável contra o
upstream.

## 8. Verificar contra dados reais pega o que teste sintético não pega

Dois exemplos:

- O índice de espécies base deu **329**. O README do original diz "329 possible
  starts". Bater com um número que eu não tinha usado como alvo foi a melhor
  evidência de que o filtro de formas base estava certo.
- A distribuição de raridade deu lendário 1 em 95, contra "1-in-129" do
  original. Perto o suficiente para confirmar a forma da curva, diferente o
  suficiente para saber que a ponderação não é idêntica — e isso é informação,
  não falha.

O teste de absorção usa cópias dos records reais num `XDG_STATE_HOME`
temporário, em vez de fixtures escritas à mão. Records reais têm campos que a
gente não anteciparia: `fireworks.json` com `modelUsage` vazio, `todaySessions`
zerado, `limits` ausente.

## 9. Duas coisas que decidi deixar imperfeitas, de propósito

**O excedente na graduação é descartado.** Carregá-lo para o ovo seguinte faria
cascata no caso do `seedFromExisting`, que solta 1,3B de uma vez e graduaria
vários Pokémon em sequência contra uma linha evolutiva que o helper ainda nem
sorteou. Em uso normal a perda é de no máximo um delta, e só no instante da
graduação. Está comentado no código como escolha, não como descuido.

**`companion` não é zerado ao graduar.** Zerá-lo deixaria `evolutionLine` vazia
até o helper responder, e uma linha vazia vira `totalForms = 1` — que gradua de
novo no limiar seguinte. Offline, viraria um loop de graduação contra um Pokémon
inexistente. Deixar o companion antigo à mostra por alguns segundos é o
comportamento degradado mais benigno.

**A lição:** quando o comportamento correto é feio, comente o porquê no lugar
onde o próximo leitor vai querer "consertar". Os dois trechos acima parecem bug
para quem chega depois.

## 10. Uma economia de duas moedas sobre o mesmo número

Os tokens fazem duas coisas ao mesmo tempo: medem o crescimento do Pokémon e são
a carteira da loja. O original documenta isso num comentário sobre o preço da
Rare Candy, e a consequência não é óbvia — se o XP da candy entrasse em
`lifetimeTokens`, usar uma candy aumentaria o saldo, e a economia viraria
infinita.

Escrevi o teste desse caso antes do código, e foi o primeiro da suíte. Não
porque eu previ o bug: porque o comentário do original dizia que o preço existia
para conter uma dupla contagem, e eu quis saber qual era.

**A lição:** quando um sistema cobra um preço que parece alto sem explicação, o
motivo costuma estar numa interação que você ainda não viu. Vale procurar antes
de "corrigir" o número.

## 11. Duas propriedades que eram uma

O Pokémon fixado no bar quebrou o painel de um jeito que os testes não pegariam:
`currentSprite` passou a devolver a espécie fixada, e o painel — que usa a mesma
propriedade — começou a anunciar "Corphish" com o estágio "2/2" do Crawdaunt.

Nenhuma asserção falhou, porque a lógica de projeção estava certa. Só a captura
de tela mostrou.

A separação virou `currentSprite`/`displayName` (o bicho real, para o painel) e
`barSprite`/`barName` (o fixado, só para o bar), com o porquê comentado no
código e no `CLAUDE.md`.

**A lição:** quando uma feature faz duas superfícies discordarem sobre o mesmo
dado, a resposta é duas propriedades com nomes honestos, não um condicional
dentro de uma. E teste visual pega classe de bug que teste de unidade não pega.

## 12. Testes que injetam estado no lugar errado

Escrevi quatro testes do Ditto que colocavam `tokensIntoStage` logo abaixo do
limiar e esperavam a evolução. Todos falharam, e por um bom tempo pareceu bug na
revelação.

Não era: o `cmd_absorb` só roda a progressão quando há **delta novo de tokens** —
que é o que o original faz, porque tokens bancados são consumidos no momento em
que entram. Meus testes injetavam o progresso sem nunca entregar tokens.

A correção foi os testes passarem a somar tokens a um record de verdade
(`Sandbox.bump`), que é como o sistema realmente recebe crescimento.

**A lição:** um teste que prepara estado por dentro em vez de pela porta da
frente pode estar testando um caminho que não existe. Quando vários testes novos
falham juntos e o código parece certo, desconfie do arranjo antes do alvo.

## 13. Aritmética de balanceamento é fácil de errar de cabeça

Errei três expectativas numéricas nesta fase, todas por conta mental:

- Achei que a candy de 100M não evoluiria em dificuldade 0.3. O limiar ali é 75M.
- Achei que em 0.1 ela subiria um estágio. A linha inteira custa 75M em 0.1, então
  ela **gradua**.
- Estimei que cinco abas de texto não caberiam em 340px. Medindo na fonte real,
  somam 293px.

Nos três casos o código estava certo e a minha conta errada. O que resolveu foi
medir: `magick -format %w label:` para a largura do texto, e escrever a conta do
limiar no comentário do teste em vez de confiar na memória.

**A lição:** em sistema com tabela de balanceamento, escreva a aritmética no
teste ao lado da asserção. O comentário "dif 0.2 numa linha de 2 formas:
limiares 50M e 100M" vale mais que o número nu, porque o próximo leitor —
inclusive você — vai querer conferir.

## 14. Um bug que as propriedades certas não impediam

O Heitor reportou: o bar mostrava Corphish, o painel mostrava Crawdaunt, e ele
não sabia em que estágio estava.

Instrumentei as fronteiras antes de teorizar, e todas as propriedades estavam
corretas: `barSprite` apontava para `342.gif`, `sourceSize` era `70x64` (o
Crawdaunt, não o Corphish de `59x46`), `representative` era `null`. Os arquivos
de sprite também estavam certos. Cheguei a suspeitar de cache de imagem do Qt —
e estava errado.

A causa era o **texto**, não a imagem. Com espécie fixada, o tooltip montava:

```
Corphish              ← nome da espécie fixada
Comum · estágio 2/2   ← estágio do companion real
```

"Corphish · estágio 2/2" é contradição: o Corphish *é* o estágio 1. As duas
identidades estavam corretas cada uma no seu lugar, e o defeito era juntá-las
numa frase que afirmava algo falso. A única pista de que havia duas coisas era
uma linha de tooltip **abaixo** da informação contraditória.

O conserto tem duas partes. O tooltip virou função pura (`Balance.barTooltip`)
com um teste que trava a regra — a fixada nunca aparece na mesma linha que um
estágio — e o bar ganhou uma estrela sobre o sprite, porque a pista de que
aquela não é a espécie em criação não pode depender de hover.

**A lição:** quando cada valor está certo e o resultado está errado, o defeito
está na composição. Instrumentar as fronteiras me disse rápido *onde não era*, o
que valeu mais que qualquer palpite — mas eu só achei o bug quando parei de olhar
a imagem e li a frase que o programa escrevia.

E uma lição sobre mim: a segunda parte do conserto (a estrela) atende ao que ele
de fato reclamou, que era não saber em que estágio estava. Consertar só o texto
teria resolvido a contradição e deixado a ambiguidade.

## 15. Os stubs que sempre funcionam esconderam os piores bugs

A inspeção final achou quatro bugs, três deles invisíveis para 349 asserções. O
que os três tinham em comum: só aparecem quando a **rede falha no meio de uma
operação**, e nenhum teste simulava isso. Todos os stubs substituíam
`load_index`, `evolution_line` e `hydrate_sprites` por lambdas que sempre
devolvem sucesso.

Os três, reproduzidos:

- **Graduação fantasma.** Rede cai na primeira chocagem: sobra `hatched=True`
  sem `companion.json`. A absorção seguinte roda a progressão com o fallback
  `companion or {}` — uma linha de uma forma que gradua quase na hora. Medi
  `graduations=1` **com a coleção vazia** e a notificação de nome vazio.
- **Entrada duplicada.** A entrada é fechada antes da chocagem. Se ela falha,
  `companion.json` ainda descreve o bicho antigo, e a absorção seguinte o
  acrescenta de novo: o graduado volta a ser companion no estágio 0, para ser
  graduado outra vez.
- **Token cobrado sem entrega.** Compra de ovo: `spentTokens` sobe antes da rede.

**A lição:** um stub que sempre dá certo testa o caminho felizardo e nada mais.
Em sistema que fala com a rede, a suíte precisa de um teste que force a exceção —
e ele pertence a um arquivo próprio, com nome que diga isso, senão ninguém
lembra de estendê-lo. Virou `tests/test_resilience.py`.

## 16. A leitura tem de espelhar a escrita, ou a barra mente

O `phase_threshold` do helper recebe um multiplicador de crescimento e **divide**
o limiar. O `phaseThreshold` do `Balance.js` — que é a leitura do mesmo número,
para a UI desenhar — nunca ganhou esse parâmetro.

Resultado: com o bônus de linha repetida ativo, a UI pedia 75M quando o helper
cobrava 37,5M. O Pokémon evoluía com a barra pela metade, e o "faltam X tokens"
errava por 37 milhões.

O `CLAUDE.md` já dizia que o `Balance.js` é a leitura do que o helper escreve. O
invariante estava escrito e eu o quebrei ao adicionar um parâmetro só de um lado.

**A lição:** quando a mesma fórmula existe em duas linguagens por necessidade
(uma cobra, a outra exibe), a mudança de assinatura em uma é mudança na outra. O
teste que trava isso não é "a fórmula está certa", é **"as duas concordam"** — um
cruzamento que roda os dois lados e compara. Escrevi um com 17 constantes na fase
anterior e ele passou; o que faltou foi incluir o parâmetro novo nele.

## 17. Revisão de olhos frescos no próprio código

Pedi uma revisão externa porque sou o autor e tenho viés, e ela achou **três dos
quatro bugs** — incluindo o de maior impacto no uso diário. Meu lado achou o
código morto, a divergência de estado que eu reproduzi, e fechou com dado uma
suspeita que a revisão levantou sem conseguir confirmar (se toda lendária tem
`capture_rate ≤ 45`: sim, as 48, com máximo exatamente 45).

A divisão que funcionou: eu fiz o que dá para automatizar e verificar
(cruzamento de constantes, propriedades órfãs, simulação de cenário), a revisão
fez o que exige ler o código sem saber o que ele deveria fazer. Nenhuma das duas
teria achado tudo.
