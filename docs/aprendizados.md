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
