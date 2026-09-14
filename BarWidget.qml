import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

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
  readonly property int spriteSize: Math.max(14, parseInt(setting("spriteSize", 22), 10) || 22)
  readonly property bool showTokens: setting("showTokens", true) === true
  readonly property bool showLimitPercent: setting("showLimitPercent", false) === true
  readonly property bool seedFromExisting: setting("seedFromExisting", false) === true
  readonly property int pollSeconds: Math.max(15, parseInt(setting("pollSeconds", 60), 10) || 60)

  // ---- Companion e progressão, ambos escritos pelo helper
  property var companion: null
  property var progressState: null

  readonly property var evolutionLine: companion && Array.isArray(companion.evolutionLine)
                                       ? companion.evolutionLine : []
  readonly property string rarity: companion && companion.rarity ? companion.rarity : "common"
  readonly property int totalForms: Math.max(1, evolutionLine.length)

  readonly property bool hatched: progressState ? progressState.hatched === true : false
  readonly property int stage: progressState ? Math.max(0, progressState.stage || 0) : 0
  readonly property real tokensIntoStage: progressState ? (progressState.tokensIntoStage || 0) : 0
  readonly property real lifetimeTokens: progressState ? (progressState.lifetimeTokens || 0) : 0
  readonly property int graduations: progressState ? (progressState.graduations || 0) : 0

  // ---- Records de uso, por id. Só para exibição: o helper lê os mesmos
  //      arquivos por conta própria quando absorve.
  property var records: ({})

  readonly property var progress: Balance.progress(rarity, totalForms, stage,
                                                   tokensIntoStage, difficulty)
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
    parseInto(raw, function (p) { root.progressState = p })
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

  function refresh() {
    for (var i = 0; i < watchers.count; i++) {
      var item = watchers.itemAt(i)
      if (item) item.reload()
    }
    stateFile.reload()
    companionFile.reload()
    absorb()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onCompanionChanged: injectPanel()
  onProgressStateChanged: injectPanel()
  onRecordsChanged: injectPanel()

  // ---- Ciclo de vida do painel. Bar.findPanelWidget exige open/close/opened na
  //      raiz do bar-widget, e Bar.requestPopout prefere closeForPopoutSwitch.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
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
    tooltipText: {
      var parts = [root.displayName]
      if (root.hatched) {
        parts.push(Balance.rarityLabel(root.rarity)
                   + " · estágio " + (root.stage + 1) + "/" + root.totalForms)
        parts.push(Balance.formatTokens(root.progress.remaining) + " tokens até "
                   + (root.progress.isFinalStage ? "graduar" : "evoluir"))
      } else {
        parts.push(Balance.formatTokens(Math.max(0, root.hatchThreshold - root.tokensIntoStage))
                   + " tokens até chocar")
      }
      if (root.todayTokens > 0) parts.push("Hoje: " + Balance.formatTokens(root.todayTokens))
      return parts.join("\n")
    }

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      AnimatedImage {
        id: sprite
        source: root.currentSprite ? "file://" + root.currentSprite : ""
        visible: source != ""
        playing: visible
        anchors.verticalCenter: parent.verticalCenter
        height: root.spriteSize
        // Os sprites Gen-V não são quadrados (36x66, 59x68…), então a largura
        // acompanha a proporção em vez de esticar o bicho.
        width: sourceSize.height > 0
               ? Math.round(root.spriteSize * sourceSize.width / sourceSize.height)
               : root.spriteSize
        fillMode: Image.PreserveAspectFit
        smooth: false  // pixel art: interpolar borra o sprite
      }

      // Ovo antes de chocar; pokébola no intervalo entre chocar e o helper
      // terminar de baixar o GIF.
      Text {
        visible: !sprite.visible
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
