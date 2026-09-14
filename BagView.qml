import QtQuick
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

// Aba "Bag": o que você tem e pode usar.
//
// Lista só o que existe — uma linha "0x Rare Candy" é ruído. O Shiny Charm
// aparece sem contagem e sem botão, porque é passivo: vale enquanto é seu.
Column {
  id: root

  property var host: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal useRequested(string key)

  readonly property var progressState: host ? host.progressState : null
  readonly property var inventory: progressState && progressState.inventory
                                   ? progressState.inventory : ({})
  readonly property bool hatched: host ? host.hatched === true : false
  readonly property var rows: Balance.bagEntries(inventory)

  spacing: Style.space(8)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.rows.length === 0 ? "Bag vazia" : "Bag"
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    visible: root.rows.length === 0
    textFormat: Text.PlainText
    text: "Encher um limite de janela — 5 horas ou semanal — te dá Rare Candy. "
          + "O momento em que você bate o teto passa a ser o momento em que seu "
          + "Pokémon cresce."
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.rows

    Item {
      id: row
      required property var modelData
      width: parent.width
      height: Style.space(40)

      // Candy sem Pokémon chocado não tem onde ser aplicada; o helper recusaria.
      readonly property bool usable: modelData.usable && root.hatched

      Rectangle {
        anchors.fill: parent
        anchors.rightMargin: Style.space(2)
        radius: Style.space(4)
        color: hover.hovered && row.usable
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
               : "transparent"
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
      }

      Column {
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(8)
        anchors.right: action.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.count !== null
                ? row.modelData.count + "× " + row.modelData.label
                : row.modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            if (row.modelData.passive) return "ativo — " + row.modelData.hint
            if (!root.hatched) return "espere o ovo chocar"
            return row.modelData.hint
          }
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Passivo não tem botão: não há o que acionar.
      Text {
        id: action
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.modelData.passive
        textFormat: Text.PlainText
        text: "usar"
        color: row.usable ? root.foreground : Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: row.usable && hover.hovered
      }

      HoverHandler { id: hover }
      TapHandler {
        enabled: row.usable
        onTapped: root.useRequested(row.modelData.key)
      }
    }
  }
}
