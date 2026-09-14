import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Collection.js" as Collection
import "Balance.js" as Balance

// Aba "Histórico": uma linha por indivíduo criado, do mais recente ao mais
// antigo. Onde o Pokédex guarda espécies, aqui ficam os bichos — com a data, a
// raridade, até onde evoluíram e se eram shiny.
Column {
  id: root

  property var collection: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int maxHeight: Style.space(340)

  readonly property var rows: Collection.catchLogRows(collection)

  spacing: Style.space(8)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.rows.length === 0
          ? "No Pokémon yet"
          : root.rows.length + (root.rows.length === 1 ? " raised" : " raised")
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    visible: root.rows.length === 0
    textFormat: Text.PlainText
    text: "Every Pokémon you hatch shows up here, and stays after it graduates."
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    width: parent.width
    height: Math.min(root.maxHeight, contentHeight)
    visible: root.rows.length > 0
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
      height: Style.space(36)

      Rectangle {
        anchors.fill: parent
        anchors.rightMargin: Style.space(2)
        radius: Style.space(4)
        // O companion de agora fica destacado; sem isso ele some no meio dos
        // que já graduaram.
        color: row.modelData.current
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
               : "transparent"
      }

      AnimatedImage {
        id: art
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        source: row.modelData.sprite ? "file://" + row.modelData.sprite : ""
        visible: source != ""
        playing: hover.hovered
        paused: !hover.hovered
        smooth: false
        fillMode: Image.PreserveAspectFit
        height: Style.space(28)
        width: sourceSize.height > 0
               ? Math.round(height * sourceSize.width / sourceSize.height) : height
      }

      Column {
        anchors.left: art.visible ? art.right : parent.left
        anchors.leftMargin: Style.space(8)
        anchors.right: meta.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Row {
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            text: Balance.speciesLabel(row.modelData.finalName)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: row.modelData.current
          }

          Text {
            visible: row.modelData.shiny
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "✨"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var bits = [Balance.rarityLabel(row.modelData.rarity)]
            if (row.modelData.lineLength > 1)
              bits.push("stage " + (row.modelData.finalStage + 1)
                        + "/" + row.modelData.lineLength)
            return bits.join("  ·  ")
          }
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: meta
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        // A linha já mostra tudo o que importa; um tooltip aqui seria mais
        // largo que a própria linha e seria recortado pela borda do popout.
        text: row.modelData.current ? "now" : Collection.formatDate(row.modelData.hatchedAt)
        color: Qt.darker(root.foreground, row.modelData.current ? 1.3 : 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      HoverHandler { id: hover }
    }
  }
}
