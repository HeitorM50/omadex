import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Popout do companion: casca com as abas, o teclado e o ciclo de vida.
//
// O conteúdo de cada aba vive num arquivo próprio (CompanionView, DexView,
// CatchLogView) — com as três views inline este arquivo passaria de 900 linhas,
// que é bem além do que se lê de uma vez.
//
// Nada aqui toca disco ou rede: o estado todo vem injetado pelo BarWidget, o que
// permite exercitar o painel com um collection.json escrito à mão.
//
// Deliberadamente NÃO duplica os painéis do omarchy.agents: limites por janela,
// tokens por dia e quebra por modelo já estão a um clique no bar.
Panel {
  id: root
  moduleName: "io.github.heitorm50.poketokenbar"
  ipcTarget: ""
  manageIpc: false

  // Injetados pelo widget host (ver BarWidget.injectPanel).
  property var anchorItem: null
  property var hostWidget: null
  property string pluginDir: ""
  property var host: null

  // O bar coordena popouts pelo item que ocupa o slot dele, então um painel
  // aninhado tem de entregar o widget host como identidade, ou o ponto de
  // destaque e a troca de popout caem no item errado.
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var collection: host ? host.collection : null

  readonly property var tabs: [
    { key: "companion", label: "Companion" },
    { key: "dex", label: "Pokédex" },
    { key: "log", label: "Histórico" },
    { key: "bag", label: "Bag" },
    { key: "shop", label: "Loja" }
  ]
  property int tab: 0

  function setTab(index) {
    tab = Math.max(0, Math.min(tabs.length - 1, index))
  }

  function cycleTab(delta) {
    // Circular: de Histórico com → volta para Companion, o que é menos
    // frustrante que a aba simplesmente não mudar.
    tab = (tab + delta + tabs.length) % tabs.length
  }

  function refresh() {
    if (host && typeof host.refresh === "function") host.refresh()
  }

  // Compras e usos passam pelo widget, que dispara o helper — o helper é o
  // único escritor de estado, e o QML nunca muta nada.
  function buy(key, tier) {
    if (host && typeof host.buy === "function") host.buy(key, tier)
  }

  function use(key) {
    if (host && typeof host.use === "function") host.use(key)
  }

  function pin(speciesId) {
    if (host && typeof host.pin === "function") host.pin(speciesId)
  }

  // Abre o painel rico do omarchy.agents, que é quem tem os números detalhados.
  function openAgents() {
    if (bar) bar.run("omarchy-shell omarchy.agents toggle")
    close()
  }

  // Abre já numa aba (IPC: `omarchy-shell ... dex`). Precisa passar pelo
  // pendingTab porque a abertura reseta a aba, e um `setTab` antes do `open`
  // seria justamente o que o reset apagaria.
  property int pendingTab: -1

  function openAt(index) {
    if (opened) { setTab(index); return }
    pendingTab = index
    open()
  }

  // Reabrir sempre no companion: é o que a pessoa quer ver em 9 de 10 aberturas,
  // e voltar na aba de ontem seria surpresa sem ganho.
  onOpenedChanged: {
    if (!opened) return
    setTab(pendingTab >= 0 ? pendingTab : 0)
    pendingTab = -1
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    popoutSwitching: root.popoutSwitching
    popoutSwitchClosing: root.popoutSwitchClosing
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onReturnRequested: root.refresh()
      onActivateRequested: root.refresh()
      // Tab continua sendo do bar (trocar de popout); as abas daqui andam com
      // as setas horizontais e h/l, que o PanelKeyCatcher entrega em dx.
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) { if (dx !== 0) root.cycleTab(dx > 0 ? 1 : -1) }
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "a" || t === "A") root.openAgents()
        else if (t >= "1" && t <= "5") root.setTab(parseInt(t, 10) - 1)
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // ---------- Abas ----------
        Row {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.tabs

            Rectangle {
              id: tabChip
              required property var modelData
              required property int index

              readonly property bool active: root.tab === index

              // Largura natural, não dividida igualmente. Medido na fonte real
              // a 10px, os cinco rótulos somam ~293px de chip em 340px de
              // conteúdo; a divisão igual daria 68px e cortaria "Companion".
              width: label.implicitWidth + Style.space(12)
              height: Style.space(24)
              radius: Style.space(5)
              color: active
                     ? Qt.rgba(root.contentForeground.r, root.contentForeground.g,
                               root.contentForeground.b, 0.14)
                     : (hover.hovered
                        ? Qt.rgba(root.contentForeground.r, root.contentForeground.g,
                                  root.contentForeground.b, 0.06)
                        : "transparent")

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: label
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: tabChip.modelData.label
                color: tabChip.active ? root.contentForeground
                                      : Qt.darker(root.contentForeground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: tabChip.active
              }

              HoverHandler { id: hover }
              TapHandler { onTapped: root.setTab(tabChip.index) }
            }
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        // ---------- Conteúdo da aba ----------
        //
        // As três views são carregadas sob demanda e só a ativa existe: manter
        // a grade do dex viva em segundo plano custaria imagens decodificadas
        // sem ninguém olhando.
        Loader {
          id: viewLoader
          width: parent.width
          active: true
          sourceComponent: root.tab === 0 ? companionComponent
                           : root.tab === 1 ? dexComponent
                           : root.tab === 2 ? logComponent
                           : root.tab === 3 ? bagComponent : shopComponent
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.tab === 0
                ? "←/→ troca de aba · r reavalia · a abre os detalhes · Esc fecha"
                : "←/→ troca de aba · 1-5 vai direto · Esc fecha"
          color: Qt.darker(root.contentForeground, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  Component {
    id: companionComponent
    CompanionView {
      width: viewLoader.width
      host: root.host
      bar: root.bar
      foreground: root.contentForeground
      fontFamily: root.fontFamily
      onRefreshRequested: root.refresh()
      onAgentsRequested: root.openAgents()
    }
  }

  Component {
    id: dexComponent
    DexView {
      width: viewLoader.width
      collection: root.collection
      representativeSpeciesId: root.host ? root.host.representativeSpeciesId : 0
      foreground: root.contentForeground
      fontFamily: root.fontFamily
      onPinRequested: function (speciesId) { root.pin(speciesId) }
    }
  }

  Component {
    id: bagComponent
    BagView {
      width: viewLoader.width
      host: root.host
      foreground: root.contentForeground
      fontFamily: root.fontFamily
      onUseRequested: function (key) { root.use(key) }
    }
  }

  Component {
    id: shopComponent
    ShopView {
      width: viewLoader.width
      host: root.host
      foreground: root.contentForeground
      fontFamily: root.fontFamily
      onBuyRequested: function (key, tier) { root.buy(key, tier) }
    }
  }

  Component {
    id: logComponent
    CatchLogView {
      width: viewLoader.width
      collection: root.collection
      foreground: root.contentForeground
      fontFamily: root.fontFamily
    }
  }
}
