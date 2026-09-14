import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Balance.js" as Balance
import "Collection.js" as Collection

// Sprite do companion no bar, e host do popout.
//
// Este widget observa e orquestra; não muta nada. Quem acumula tokens, avança
// estágios e escreve state.json é `bin/poke-sync absorb`, disparado aqui por
// timer. O motivo é que o bar instancia um widget por monitor: dois widgets
// acumulando o mesmo delta contariam em dobro, e o arquivo teria dois
// escritores. Com a mutação no helper, atrás de um flock, o número de monitores
// deixa de importar — e a regra fica testável em Python em vez de espelhada
// entre o QML e um teste.
//
// A coleta de uso também não é feita aqui. Os records em
// ~/.local/state/omarchy/agents/usage/ são um contrato público do
// omarchy.agents (schemaVersion 1), e este plugin é consumidor somente-leitura
// deles — nunca roda omarchy-agent-usage-update nem fala com as APIs dos
// provedores. Quem atualiza os records é o timer do omarchy.agents.
BarWidget {
  id: root
  moduleName: "io.github.heitorm50.poketokenbar"

  // Nenhuma propriedade de caminho é injetada nos slots de bar-widget, então o
  // diretório do plugin tem de ser recuperado da URL deste arquivo.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

  readonly property string stateBase: {
    var base = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    return base + "/omarchy"
  }
  readonly property string stateDir: stateBase + "/" + moduleName
  readonly property string usageDir: stateBase + "/agents/usage"

  // Os ids dos coletores que o omarchy.agents distribui. Um record ausente
  // simplesmente não carrega — o widget não exige nenhum agente específico.
  readonly property var agentIds: ["claude", "codex", "fireworks"]

  // ---- Settings
  readonly property real difficulty: Balance.clampDifficulty(setting("difficulty", 0.3))
  // Independente da de crescimento, como no original: uma é o ritmo do jogo, a
  // outra é o preço das coisas.
  readonly property real shopDifficulty: Balance.clampDifficulty(setting("shopDifficulty", 1.0))
  readonly property int spriteSize: Math.max(14, parseInt(setting("spriteSize", 22), 10) || 22)
  readonly property bool showTokens: setting("showTokens", true) === true
  readonly property bool showLimitPercent: setting("showLimitPercent", false) === true
  readonly property bool seedFromExisting: setting("seedFromExisting", false) === true
  readonly property int pollSeconds: Math.max(15, parseInt(setting("pollSeconds", 60), 10) || 60)

  // Espécie fixada no bar, independente do companion que está sendo criado.
  // 0 = segue o companion. Só vale se a espécie estiver no Pokédex: fixar algo
  // que você não tem seria mentir sobre a coleção.
  readonly property int representativeSpeciesId: {
    var raw = parseInt(setting("representativeSpeciesId", 0), 10) || 0
    if (raw <= 0 || !collection) return 0
    return Collection.ownsSpecies(collection, raw) ? raw : 0
  }

  readonly property var representative: {
    if (representativeSpeciesId <= 0 || !collection) return null
    return Collection.dexCell(collection, representativeSpeciesId)
  }

  // ---- Companion e progressão, ambos escritos pelo helper
  property var companion: null
  property var progressState: null

  readonly property var evolutionLine: companion && Array.isArray(companion.evolutionLine)
                                       ? companion.evolutionLine : []
  readonly property string rarity: companion && companion.rarity ? companion.rarity : "common"
  readonly property bool shiny: companion ? companion.shiny === true : false
  readonly property bool dittoDisguise: companion ? companion.dittoDisguise === true : false
  readonly property bool dittoRevealed: companion ? companion.dittoRevealed === true : false

  // O shiny que a interface pode mostrar. Um Ditto ainda disfarçado esconde o
  // brilho: revelar as duas coisas juntas é o ponto alto do easter egg.
  readonly property bool visibleShiny: shiny && (!dittoDisguise || dittoRevealed)

  // 2 quando a linha base já foi graduada antes. A conta é do helper; aqui é só
  // para o painel poder mostrar a cápsula que explica a barra andando rápido.
  readonly property bool growthBoost: {
    if (!companion || !collection) return false
    return Collection.hasGraduatedLine(collection, companion.baseSpeciesId)
  }

  readonly property real burnRate: progressState ? (progressState.burnRate || 0) : 0
  readonly property string mood: Balance.mood(progressState, todayTokens,
                                              worstLimit ? worstLimit.percent : 0,
                                              celebration > 0 && eventFresh)

  // Catch log completo. O Pokédex de espécies é projeção disto (Collection.js),
  // calculada na hora de desenhar — por isso não há arquivo de dex.
  property var collection: null
  readonly property int totalForms: Math.max(1, evolutionLine.length)

  readonly property bool hatched: progressState ? progressState.hatched === true : false
  readonly property int stage: progressState ? Math.max(0, progressState.stage || 0) : 0
  readonly property real tokensIntoStage: progressState ? (progressState.tokensIntoStage || 0) : 0
  readonly property real lifetimeTokens: progressState ? (progressState.lifetimeTokens || 0) : 0
  readonly property int graduations: progressState ? (progressState.graduations || 0) : 0

  // ---- Celebração
  //
  // Guardar o contador aqui (e não na view) é o que faz uma chocagem ocorrida
  // com o popout fechado ainda ser celebrada na próxima abertura — o original
  // aprendeu isso na prática.
  property int celebration: 0
  property bool eventFresh: false
  property string lastCelebratedKey: ""

  function noteEvent() {
    // A chave inclui estágio e espécie: chocar, evoluir e revelar Ditto mudam
    // pelo menos uma das duas.
    var key = (companion ? companion.companionId : "") + ":" + stage + ":"
              + (hatched ? "1" : "0")
    if (key === lastCelebratedKey) return
    // A primeira leitura do estado não é um evento — é só o plugin subindo.
    var first = lastCelebratedKey === ""
    lastCelebratedKey = key
    if (first) return
    celebration += 1
    eventFresh = true
    eventWindow.restart()
  }

  Timer {
    id: eventWindow
    interval: 5000
    onTriggered: root.eventFresh = false
  }

  // ---- Records de uso, por id. Só para exibição: o helper lê os mesmos
  //      arquivos por conta própria quando absorve.
  property var records: ({})

  // O bônus tem de chegar aqui, senão a barra mostra o dobro do que falta e o
  // Pokémon evolui com ela pela metade.
  readonly property var progress: Balance.progress(rarity, totalForms, stage,
                                                   tokensIntoStage, difficulty,
                                                   growthBoost ? 2 : 1)
  readonly property real hatchThreshold: Balance.hatchThreshold(difficulty)

  readonly property real todayTokens: {
    var total = 0
    for (var i = 0; i < agentIds.length; i++) {
      var rec = records[agentIds[i]]
      if (rec && typeof rec.todayTotalTokens === "number") total += rec.todayTotalTokens
    }
    return total
  }

  // O limite de janela mais apertado entre todos os agentes, para o texto
  // opcional no bar. Vem direto de limits[].percent do record.
  readonly property var worstLimit: {
    var worst = null
    for (var i = 0; i < agentIds.length; i++) {
      var limit = Balance.tightestLimit(records[agentIds[i]])
      if (limit && (!worst || limit.percent > worst.percent)) worst = limit
    }
    return worst
  }

  // Sprite do estágio atual. Antes de chocar não mostramos sprite nenhum: o
  // filhote é surpresa até o limiar de chocagem.
  readonly property string currentSprite: {
    if (!hatched) return ""
    var index = Math.min(stage, evolutionLine.length - 1)
    if (index < 0) return ""
    var form = evolutionLine[index]
    return form && form.sprite ? form.sprite : ""
  }

  readonly property string displayName: {
    if (!hatched) return "Ovo"
    var index = Math.min(stage, evolutionLine.length - 1)
    if (index < 0) return "???"
    var form = evolutionLine[index]
    return Balance.speciesLabel(form ? form.name : "")
  }

  // ---- O que o BAR mostra. Divergem do companion só quando há espécie fixada:
  //      o bar para de seguir chocagem e evolução, mas o painel continua
  //      mostrando o bicho real e o progresso dele. Confundir os dois faz o
  //      painel anunciar uma espécie com o estágio de outra.
  readonly property string barSprite: {
    if (representative)
      return representative.shinySprite || representative.sprite || ""
    return currentSprite
  }

  readonly property string barName: {
    if (representative) return Balance.speciesLabel(representative.name)
    return displayName
  }

  // ---- Leitura dos arquivos

  // Manter o último valor bom é melhor que esvaziar o bar por um instante: uma
  // escrita pela metade é estado transitório, e o helper escreve atomicamente,
  // então o próximo evento traz o arquivo íntegro.
  function parseInto(raw, assign, validate) {
    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object" && (!validate || validate(parsed))) assign(parsed)
    } catch (e) {
      console.warn(root.moduleName, "JSON ilegível, mantendo o último valor bom")
    }
  }

  function applyState(raw) {
    parseInto(raw, function (p) { root.progressState = p; root.noteEvent() })
  }

  function applyCollection(raw) {
    parseInto(raw, function (p) { root.collection = p },
              function (p) { return Array.isArray(p.entries) })
  }

  function applyCompanion(raw) {
    parseInto(raw, function (p) { root.companion = p },
              function (p) { return Array.isArray(p.evolutionLine) })
  }

  // ---- Orquestração

  // Pede ao helper que absorva os tokens novos. Se outra instância (outro
  // monitor) já estiver absorvendo, o flock do helper faz esta desistir.
  // Os três watchers de record carregam quase juntos no start do shell, e o
  // omarchy.agents reescreve os records em rajada; sem o debounce isso viraria
  // três subprocessos em sequência para o mesmo delta.
  function absorb() {
    absorbTimer.restart()
  }

  function runAbsorb() {
    if (absorbProc.running) return
    absorbProc.running = true
  }

  function requestHatch() {
    if (hatchProc.running) return
    hatchProc.running = true
  }

  function buy(key, tier) {
    if (buyProc.running) return
    var isEgg = String(key).indexOf("egg") === 0
    buyProc.key = isEgg ? "egg" : key
    buyProc.tier = isEgg ? (String(key).split(":")[1] || "") : ""
    buyProc.running = true
  }

  function use(key) {
    if (useProc.running) return
    useProc.key = key
    useProc.running = true
  }

  // Fixar é preferência, não progresso, então vive nas settings do widget
  // (shell.json) e não no state.json — é o mesmo critério do original, que as
  // guarda em UserDefaults e não no save.
  function pin(speciesId) {
    if (pinProc.running) return
    pinProc.value = String(Math.max(0, speciesId | 0))
    pinProc.running = true
  }

  // Os FileViews observam os arquivos, mas uma compra é uma mudança que a pessoa
  // acabou de pedir: recarregar na hora faz o saldo cair na tela sem esperar o
  // evento de arquivo.
  function reloadFiles() {
    stateFile.reload()
    companionFile.reload()
    collectionFile.reload()
  }

  function refresh() {
    for (var i = 0; i < watchers.count; i++) {
      var item = watchers.itemAt(i)
      if (item) item.reload()
    }
    reloadFiles()
    absorb()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onCompanionChanged: injectPanel()
  onProgressStateChanged: injectPanel()
  onCollectionChanged: injectPanel()
  onRecordsChanged: injectPanel()

  // ---- Ciclo de vida do painel. Bar.findPanelWidget exige open/close/opened na
  //      raiz do bar-widget, e Bar.requestPopout prefere closeForPopoutSwitch.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  // Abre o painel já numa aba. Serve para um atalho ir direto ao Pokédex, e é
  // o que permite dirigir as abas de fora nos testes.
  function openTab(index) {
    if (!panelLoader.item) return
    panelLoader.item.openAt(index)
  }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("pluginDir" in target) target.pluginDir = root.pluginDir
    if ("host" in target) target.host = root
  }

  // ---- IO. Tudo somente-leitura: os dois arquivos são observados, e o helper
  //      é a única coisa que os escreve.

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyState(text())
    onFileChanged: reload()
  }

  FileView {
    id: companionFile
    path: root.stateDir + "/companion.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCompanion(text())
    onFileChanged: reload()
  }

  FileView {
    id: collectionFile
    path: root.stateDir + "/collection.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCollection(text())
    onFileChanged: reload()
  }

  // Um watcher por record de uso, na forma do Agent.qml do omarchy.agents: um
  // record que aparece no diretório é um agente, quem o escreveu não importa.
  Repeater {
    id: watchers
    model: root.agentIds

    Item {
      id: watcher
      required property string modelData
      visible: false

      function reload() { view.reload() }

      FileView {
        id: view
        path: root.usageDir + "/" + watcher.modelData + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: watcher.store(text())
        onLoadFailed: watcher.store("")
      }

      function store(content) {
        var next = Object.assign({}, root.records)
        var text = String(content || "").trim()
        if (!text) {
          delete next[watcher.modelData]
        } else {
          try {
            var parsed = JSON.parse(text)
            if (parsed && typeof parsed === "object") next[watcher.modelData] = parsed
            else delete next[watcher.modelData]
          } catch (e) {
            console.warn(root.moduleName, "record inválido", watcher.modelData, e)
            return
          }
        }
        root.records = next
        // Um record novo em disco é exatamente quando há tokens novos para
        // absorver, então não esperamos o timer.
        root.absorb()
      }
    }
  }

  Process {
    id: absorbProc
    command: root.seedFromExisting
             ? [root.pluginDir + "/bin/poke-sync", "absorb", String(root.difficulty), "seed"]
             : [root.pluginDir + "/bin/poke-sync", "absorb", String(root.difficulty)]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    // O helper escreve state.json e, quando precisa, companion.json; os
    // FileViews pegam as mudanças. Nada a parsear aqui.
  }

  // Compra e uso vão pelo helper, que é o único escritor. As duas escrevem
  // state.json, então precisam do mesmo flock do absorb — e o helper já o pega.
  Process {
    id: buyProc
    property string key: ""
    property string tier: ""
    command: [root.pluginDir + "/bin/poke-sync", "buy", key,
              String(root.shopDifficulty)].concat(tier ? [tier] : [])
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) console.warn(root.moduleName, "compra recusada:", buyProc.key)
      root.reloadFiles()
    }
  }

  Process {
    id: useProc
    property string key: ""
    command: [root.pluginDir + "/bin/poke-sync", "use", key, String(root.difficulty)]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) console.warn(root.moduleName, "uso recusado:", useProc.key)
      root.reloadFiles()
    }
  }

  Process {
    id: pinProc
    property string value: "0"
    command: ["omarchy", "bar", "set", root.moduleName,
              "representativeSpeciesId", value, "--json"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) console.warn(root.moduleName, "não deu para fixar a espécie")
    }
  }

  Process {
    id: hatchProc
    command: [root.pluginDir + "/bin/poke-sync", "hatch"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: absorbTimer
    interval: 400
    repeat: false
    onTriggered: root.runAbsorb()
  }

  // Rede de segurança: os FileViews dos records reagem a cada escrita do
  // omarchy.agents, mas o coletor dele roda a cada 900s por padrão, e uma
  // escrita pode não gerar evento de arquivo.
  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.absorb()
  }

  // Primeira execução: sem companion em disco, pede um ovo para que o painel
  // tenha uma linha evolutiva para mostrar desde o começo.
  Timer {
    interval: 3000
    running: true
    repeat: false
    onTriggered: if (!root.companion) root.requestHatch()
  }

  IpcHandler {
    target: "io.github.heitorm50.poketokenbar"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refresh") }
    function hatch(): void { root.requestHatch() }
    function companion(): void { root.openTab(0) }
    function dex(): void { root.openTab(1) }
    function log(): void { root.openTab(2) }
    function bag(): void { root.openTab(3) }
    function shop(): void { root.openTab(4) }
  }

  WidgetButton {
    id: button
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    // WidgetButton dimensiona pelo label, que aqui está invisível; a largura vem
    // do conteúdo real. BarIconButton não serve: ele fixa a largura no slot de
    // um ícone e um sprite não-quadrado com texto ao lado não cabe.
    fixedWidth: root.vertical ? -1 : content.implicitWidth + Style.space(12)
    tooltipText: Balance.barTooltip({
      hatched: root.hatched,
      companionName: root.displayName,
      rarity: root.rarity,
      stage: root.stage,
      totalForms: root.totalForms,
      remaining: root.progress ? root.progress.remaining : 0,
      isFinalStage: root.progress ? root.progress.isFinalStage : false,
      hatchRemaining: Math.max(0, root.hatchThreshold - root.tokensIntoStage),
      // Quando há espécie fixada, o nome dela NUNCA é colado no estágio: o
      // tooltip a anuncia como fixada e nomeia o companion real à parte.
      pinnedName: root.representative ? root.barName : "",
      todayTokens: root.todayTokens
    })

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      // A caixa dimensiona pelo sourceSize e o sprite a preenche. O inverso —
      // caixa medindo o sprite que ancora na caixa — é laço de binding.
      Item {
        id: spriteBox
        anchors.verticalCenter: parent.verticalCenter
        visible: sprite.source != ""
        height: root.spriteSize
        // Os sprites Gen-V não são quadrados (36x66, 59x68…), então a largura
        // acompanha a proporção em vez de esticar o bicho.
        width: sprite.sourceSize.height > 0
               ? Math.round(root.spriteSize * sprite.sourceSize.width
                            / sprite.sourceSize.height)
               : root.spriteSize

        AnimatedImage {
          id: sprite
          anchors.fill: parent
          source: root.barSprite ? "file://" + root.barSprite : ""
          playing: visible
          fillMode: Image.PreserveAspectFit
          smooth: false  // pixel art: interpolar borra o sprite
        }

        // A estrela marca "esta não é a espécie que você está criando". Fica no
        // bar, não só no tooltip: depender do hover foi exatamente o que deixou
        // a pessoa sem saber em que estágio estava.
        Text {
          visible: root.representative !== null
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: -Style.space(3)
          anchors.rightMargin: -Style.space(3)
          z: 1
          textFormat: Text.PlainText
          text: "★"
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // Ovo antes de chocar; pokébola no intervalo entre chocar e o helper
      // terminar de baixar o GIF.
      Text {
        visible: !spriteBox.visible
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.hatched ? "󰐝" : "󰪯"
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== "" && !root.vertical
        textFormat: Text.PlainText
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        text: {
          var bits = []
          if (root.showTokens && root.todayTokens > 0)
            bits.push(Balance.formatTokens(root.todayTokens))
          if (root.showLimitPercent && root.worstLimit)
            bits.push(Math.round(root.worstLimit.percent * 100) + "%")
          return bits.join(" · ")
        }
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
