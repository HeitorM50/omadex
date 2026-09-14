import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

// Aba "Loja": os tokens que você já queimou são a moeda.
//
// Uma lista só, em ordem de preço, itens e ovos juntos — como no original. O
// passivo já comprado afunda para o fim em vez de desaparecer, para dar para
// ver que já é seu.
//
// A confirmação é em dois toques, inline: um preço de bilhões merece uma
// segunda batida, e um diálogo modal dentro de um popout de layer-shell é
// briga com o compositor.
Column {
  id: root

  property var host: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal buyRequested(string key, string tier)

  readonly property var progressState: host ? host.progressState : null
  readonly property var inventory: progressState && progressState.inventory
                                   ? progressState.inventory : ({})
  readonly property real wallet: Balance.availableTokens(progressState)
  readonly property real shopDifficulty: host ? host.shopDifficulty : 1.0
  readonly property bool hatched: host ? host.hatched === true : false
  readonly property bool shiny: host ? host.shiny === true : false

  readonly property var rows: Balance.shopEntries(inventory, shopDifficulty, wallet)

  // Chave aguardando confirmação; vazio = nenhuma. Só uma por vez.
  property string pending: ""

  function press(row) {
    if (row.owned) return
    if (!row.affordable) return
    if (row.isEgg && !root.hatched) return

    if (root.pending !== row.key) {
      root.pending = row.key
      resetTimer.restart()
      return
    }
    root.pending = ""
    resetTimer.stop()
    root.buyRequested(row.key, row.tier || "")
  }

  // A confirmação expira sozinha: um "confirmar" pendurado é um clique
  // acidental esperando para acontecer.
  Timer {
    id: resetTimer
    interval: 4000
    onTriggered: root.pending = ""
  }

  spacing: Style.space(8)

  Row {
    width: parent.width
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      text: "Carteira"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item { width: parent.width - 2 - x; height: 1 }
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: Balance.formatTokens(root.wallet) + " disponíveis"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: "Tudo o que você já queimou, menos o que já gastou."
    color: Qt.darker(root.foreground, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  PanelSeparator { foreground: root.foreground }

  ListView {
    id: list
    width: parent.width
    height: Math.min(Style.space(300), contentHeight)
    clip: true
    spacing: Style.space(2)
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    model: root.rows

    delegate: Item {
      id: row
      required property var modelData
      width: list.width
      height: Style.space(38)

      readonly property bool confirming: root.pending === modelData.key
      // Ovo sem companion não tem o que descartar — o helper recusaria, então a
      // linha já sai desabilitada em vez de deixar a pessoa tentar.
      readonly property bool blocked: modelData.owned
                                      || !modelData.affordable
                                      || (modelData.isEgg && !root.hatched)

      Rectangle {
        anchors.fill: parent
        anchors.rightMargin: Style.space(2)
        radius: Style.space(4)
        color: row.confirming
               ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
               : (hover.hovered && !row.blocked
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                  : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.modelData.glyph
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        opacity: row.blocked ? 0.45 : 1
      }

      Column {
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(8)
        anchors.right: priceText.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          opacity: row.blocked ? 0.55 : 1
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            if (row.modelData.owned) return "já é seu"
            if (row.modelData.isEgg && !root.hatched) return "você já está num ovo"
            if (row.confirming)
              return root.shiny && row.modelData.isEgg
                     ? "toque nova­mente — o atual é SHINY"
                     : "toque novamente para confirmar"
            return row.modelData.hint
          }
          color: row.confirming ? Color.urgent : Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: priceText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.modelData.owned ? "✓" : Balance.formatTokens(row.modelData.price)
        color: row.modelData.affordable || row.modelData.owned
               ? root.foreground : Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      HoverHandler { id: hover }
      TapHandler {
        enabled: !row.blocked
        onTapped: root.press(row.modelData)
      }
    }
  }
}
