import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Collection.js" as Collection
import "Balance.js" as Balance

// Aba "Pokédex": uma célula por espécie já possuída, em ordem de número.
//
// O dex não é um arquivo — é projetado do catch log por Collection.js. Uma
// espécie entra assim que o companion a alcança, e o ✨ na célula quer dizer
// "já tive esta espécie shiny alguma vez".
Column {
  id: root

  property var collection: null
  // 0 = o bar segue o companion.
  property int representativeSpeciesId: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int maxHeight: Style.space(320)

  signal pinRequested(int speciesId)

  readonly property var cells: Collection.dexEntries(collection)
  readonly property var stats: Collection.dexStats(collection)

  // Clicar numa célula que tenha as duas artes troca entre normal e shiny.
  property var shinyShown: ({})

  // Célula sob o cursor, para a linha de detalhe.
  property var hoveredCell: null

  function toggleShiny(id) {
    var next = Object.assign({}, shinyShown)
    next[id] = !next[id]
    shinyShown = next
  }

  spacing: Style.space(8)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: {
      if (root.stats.species === 0) return "Nenhuma espécie ainda"
      var bits = [root.stats.species + (root.stats.species === 1 ? " espécie" : " espécies")]
      if (root.stats.shiny > 0) bits.push(root.stats.shiny + " ✨")
      return bits.join("  ·  ")
    }
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    visible: root.cells.length === 0
    textFormat: Text.PlainText
    text: "O Pokédex enche sozinho: cada espécie que o seu companion alcançar "
          + "entra aqui e fica, mesmo depois de graduar."
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  GridView {
    id: grid
    width: parent.width
    // Cresce com o conteúdo até o teto, para uma coleção pequena não deixar um
    // buraco no painel nem uma grande estourá-lo.
    height: Math.min(root.maxHeight, contentHeight)
    visible: root.cells.length > 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    cellWidth: Math.floor(width / 4)
    cellHeight: Style.space(62)

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    model: root.cells

    delegate: Item {
      id: cell
      required property var modelData
      width: grid.cellWidth
      height: grid.cellHeight

      readonly property bool showShiny: modelData.shinySprite !== ""
                                        && (root.shinyShown[modelData.id] === true
                                            || modelData.sprite === "")
      readonly property string art: showShiny ? modelData.shinySprite : modelData.sprite

      Column {
        anchors.centerIn: parent
        spacing: Style.space(1)

        Item {
          width: Style.space(34)
          height: Style.space(34)
          anchors.horizontalCenter: parent.horizontalCenter

          AnimatedImage {
            id: art
            anchors.centerIn: parent
            source: cell.art ? "file://" + cell.art : ""
            visible: source != ""
            // Uma grade inteira de GIFs animados seria epilética e cara; só o
            // hover anima.
            playing: hover.hovered
            paused: !hover.hovered
            smooth: false
            fillMode: Image.PreserveAspectFit
            height: parent.height
            width: sourceSize.height > 0
                   ? Math.round(height * sourceSize.width / sourceSize.height) : height
          }

          Text {
            anchors.centerIn: parent
            visible: !art.visible
            textFormat: Text.PlainText
            text: "󰐝"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          // O ✨ marca a espécie, não a arte em exibição: ele fica mesmo quando
          // a célula está mostrando a versão normal.
          Text {
            visible: cell.modelData.shiny
            anchors.top: parent.top
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: "✨"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Estrela do representativo: fixa esta espécie no bar. Aparece no
          // hover e na que já está fixada, para não poluir a grade inteira.
          Text {
            visible: hover.hovered || root.representativeSpeciesId === cell.modelData.id
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.representativeSpeciesId === cell.modelData.id ? "★" : "☆"
            color: root.representativeSpeciesId === cell.modelData.id
                   ? Color.urgent : Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            TapHandler {
              // Clicar na estrela da já fixada desafixa: volta a seguir o
              // companion.
              onTapped: root.pinRequested(
                root.representativeSpeciesId === cell.modelData.id
                ? 0 : cell.modelData.id)
            }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          width: grid.cellWidth - Style.space(4)
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: Balance.speciesLabel(cell.modelData.name)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      HoverHandler {
        id: hover
        // Um tooltip numa grade de 4 colunas dentro de um popout de 330px é
        // sempre mais largo que a célula e acaba recortado pela borda. O
        // detalhe vai para uma linha fixa embaixo da grade, que não estoura.
        onHoveredChanged: if (hovered) root.hoveredCell = cell.modelData
                          else if (root.hoveredCell === cell.modelData) root.hoveredCell = null
      }

      TapHandler {
        // Só faz sentido alternar quando existem as duas artes.
        enabled: cell.modelData.shinySprite !== "" && cell.modelData.sprite !== ""
        onTapped: root.toggleShiny(cell.modelData.id)
      }


    }
  }

  // Detalhe do que está sob o cursor. Reserva a altura sempre, para a grade não
  // pular de posição quando o cursor entra e sai.
  Item {
    width: parent.width
    visible: root.cells.length > 0
    implicitHeight: detail.implicitHeight

    Text {
      id: detail
      width: parent.width
      textFormat: Text.PlainText
      text: {
        var c = root.hoveredCell
        if (!c) return " "
        var bits = ["Nº " + c.id, Balance.speciesLabel(c.name)]
        bits.push(c.count + (c.count === 1 ? " criado" : " criados"))
        if (c.shiny) bits.push("✨")
        if (c.shinySprite !== "" && c.sprite !== "") bits.push("clique alterna a arte")
        bits.push(root.representativeSpeciesId === c.id ? "★ no bar" : "☆ fixa no bar")
        return bits.join("  ·  ")
      }
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
