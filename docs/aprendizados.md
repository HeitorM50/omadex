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
`Local plugin changed, reloading: io.github.heitorm50.omapkdex` — e o código
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

## 18. O estado derivado de um parâmetro que vive fora dele

`tokensIntoStage` é um número absoluto de tokens; o limiar é derivado da
dificuldade, que mora no `shell.json` e muda por fora. Ninguém guardava a
dificuldade usada — então baixá-la encolhia o limiar por baixo do progresso já
acumulado, e o próximo delta **graduava o Pokémon de graça**. Medido: 240M
contra limiares de 75M+150M cobre a linha inteira de uma vez.

O bug existia desde o começo, e não em código novo: ele só ficou visível quando
fui construir a aba que expõe o parâmetro. Uma feature que dá acesso fácil a um
botão revela o que acontece quando o botão é apertado — que ninguém tinha
apertado ainda.

**A lição:** quando um estado persistido é interpretado à luz de um parâmetro
que não está persistido com ele, o par está quebrado por construção. Ou se
guarda o parâmetro junto (foi o conserto: `state.difficulty`, e reescala quando
muda), ou se persiste o estado numa unidade que não dependa dele. Vale procurar
esse padrão antes de expor o parâmetro: `grep` por quem lê a setting e por onde
o número derivado é comparado.

E um detalhe do reescalonamento que parece preciosismo e não é: **arredondar não
pode completar um estágio**. A um token do limiar antigo, a proporção cai
exatamente sobre o novo, e o reescalonamento entregaria a evolução que ele
existe para evitar.

## 19. Projeção em vez de migração

O perfil do indivíduo (IVs, gênero, habilidade, nível) parecia exigir campos
novos em cada Pokémon salvo — e, portanto, um backfill para os que já existiam.
Não exigiu: tudo sai de um PRNG semeado pelo `companionId`, que já estava lá, e
o nível é a fração do crescimento. Zero migração, zero arquivo novo, e os bichos
antigos ganharam perfil retroativo.

É a mesma decisão que o Pokédex já usava (projeção sobre o catch log) aplicada um
nível abaixo. Vale perguntar, antes de adicionar campo: **isto é dado ou é
função do dado que já tenho?**

O contra-exemplo está no mesmo commit: a **natureza** não pode sair de um seed,
porque o Mint a re-sorteia. Ela é mutável, logo é dado, logo é gravada. A
fronteira é exatamente essa — o que muda por ação da pessoa é estado; o que é
fixo desde o nascimento é função do id.

O preço da projeção é que o seed passa a ser uma promessa permanente: se
`seedFor` mudar, os IVs do bicho de alguém mudam sozinhos. Por isso é FNV-1a
(especificada) e não o hash da linguagem — o original tropeçou nisso em Swift,
onde `Hasher` é aleatório por processo.

## 20. Dois consertos para um laço, e os dois eram necessários

`FileView.onLoadFailed` dispara o helper que cria o arquivo: é o gatilho normal
da primeira abertura de uma espécie. Mas o helper saía com 0 sem escrever nada
(usava `os.path.exists` para o cache, e um **diretório** com o nome do arquivo
satisfazia a checagem), então o FileView recarregava, falhava, disparava o
helper de novo — laço infinito de processos.

Consertar só o helper resolveria o caso que eu tinha em mãos. Mas o laço é do
formato "quem repara não consegue reparar", e ele voltaria com disco cheio,
permissão errada ou JSON truncado. Então o conserto é dos dois lados:
`os.path.isfile` no helper, e **uma** tentativa automática por espécie no
widget, com o botão de tentar de novo rearmando.

**A lição:** quando A conserta B e B redispara A, o limite de tentativas é parte
do desenho, não uma defesa extra. E vale procurar esse par sempre que um
`onLoadFailed` chama um processo.

## 21. Verificar o que não dá para clicar

A grade do Pokédex só responde a clique, e não há como sintetizar clique no
Wayland daqui (`wtype` manda tecla, não botão; `ydotool` exige `/dev/uinput` e
root). O caminho foi expor a navegação por IPC — `profile` e `profileOf <n>` —
que é atalho útil de verdade **e** a única forma de dirigir a tela de fora.

E foi aí que apareceu um bug que clique nenhum teria mostrado facilmente: o
pedido era aplicado só no `onLoaded` do `Loader` da aba, e reabrir o painel na
aba em que ele já estava não troca o `sourceComponent` — o Loader não recarrega,
o `onLoaded` não dispara, e o comando parecia não fazer nada. Sempre na segunda
vez seguida.

**A lição:** tornar a UI dirigível de fora não é andaime de teste, é feature que
paga o próprio custo. Mas a verificação tem de ser honesta sobre o que ela não
cobre: o `TapHandler` em si continua verificado só por padrão (é o mesmo dos
chips de aba, que funcionam na captura).

## 22. A checagem que informa não é a checagem que protege

Eu já tinha uma forma de saber se o popout estava aberto antes de capturar a
tela — a camada `omarchy-keyboard-panel` só existe enquanto ele está. Usei-a,
ela imprimiu `aberto: 0`... e o script capturou a tela mesmo assim, porque o
`grim` vinha na linha seguinte do mesmo bloco. Resultado: a área de trabalho do
Heitor num arquivo, de novo, pelo segundo motivo diferente.

**A lição:** uma pré-condição que só imprime não é pré-condição. Ela tem de
**abortar** — virou um script com `exit 3` que espera a camada aparecer e, se
ela não aparece, não chama o `grim`. Impossível esquecer de olhar o resultado,
porque não existe resultado.

## 23. README é interface, e interface se olha renderizada

Escrevi a página com tabelas HTML de duas colunas e sprites animados e ia
entregar sem ver. Renderizei pela API do GitHub (`gh api /markdown`) num HTML
com o `github-markdown-css` e fotografei com o Chromium headless — e as três
coisas que estavam erradas só apareciam ali: as linhas da tabela ficavam
gigantes (um print de 810px ao lado de um parágrafo de 3 linhas), os sprites em
sequência não alinhavam (imagem inline alinha pela base do texto, não pelo
centro), e o cabeçalho de tabela vazio (`| | |`) desenhava uma faixa em branco
com borda que parecia defeito.

Uma armadilha no meio do caminho: **o modo importa**. `mode=gfm` é a semântica
de comentário — converte cada quebra de linha do fonte em `<br>`, e eu "consertei"
parágrafos que não estavam quebrados. `mode=markdown` é a de arquivo, que é como
o README aparece no repositório. Os alertas (`> [!IMPORTANT]`) são o inverso:
saem só no `gfm` e no github.com, não no `markdown`. A verdade é a união dos
dois renders.

## 24. Medir o recorte, não deduzi-lo

As capturas do painel saíam assimétricas: borda visível na direita, nenhuma na
esquerda. Eu tinha deduzido a posição do card de uma captura antiga (`x=1355`) e
estava 5px dentro dele — cortando fora a borda esquerda.

Medir foi trivial e eu não tinha feito: varrer as colunas da captura procurando
a que é clara em quase toda a altura acha as duas bordas de uma vez (`x=1350` e
`x=1891`, 3px cada). Com os dois limites medidos e o topo/fundo detectados por
linha, o recorte fica exato em qualquer aba, e a altura deixa de ser um chute que
às vezes corta conteúdo e às vezes pega papel de parede.

**A lição:** um número que veio de "pareceu certo naquela vez" merece uma
medição de trinta segundos antes de virar constante em sete arquivos.
