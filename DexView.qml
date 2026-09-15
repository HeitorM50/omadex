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

  readonly property var allCells: Collection.dexEntries(collection)
  readonly property var stats: Collection.dexStats(collection)

  // Filtro de raridade. Vazio = sem filtro. Só uma raridade por vez, como no
  // original: combinar duas não responde nenhuma pergunta que a lista inteira
  // já não responda.
  property string rarityFilter: ""

  readonly property var cells: {
    if (!rarityFilter) return allCells
    return allCells.filter(function (c) { return c.rarity === root.rarityFilter })
  }

  // Ordem dos chips: do mais raro para o mais comum, que é a ordem em que se
  // procura na própria coleção.
  readonly property var rarityOrder: ["legendary", "rare", "uncommon", "common"]

  function toggleRarity(key) {
    // Trocar o filtro muda quais células existem, e a linha de detalhe passaria
    // a descrever uma que saiu da grade.
    hoveredCell = null
    rarityFilter = rarityFilter === key ? "" : key
  }

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
    // O total NÃO acompanha o filtro: a contagem da raridade filtrada já está
    // no chip aceso, e um total que encolhe ao filtrar parece perda de coleção.
    text: {
      if (root.stats.species === 0) return "No species yet"
      var bits = [root.stats.species + (root.stats.species === 1 ? " species" : " species")]
      if (root.stats.shiny > 0) bits.push(root.stats.shiny + " ✨")
      return bits.join("  ·  ")
    }
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Chips de raridade. `Flow` e não `Row`: os quatro rótulos em inglês somam
  // perto da largura do painel, e um Flow quebra para uma segunda linha em vez
  // de empurrar o quarto chip para fora da borda.
  Flow {
    width: parent.width
    visible: root.allCells.length > 0
    spacing: Style.space(4)

    Repeater {
      model: root.rarityOrder

      Rectangle {
        id: chip
        required property string modelData

        readonly property int count: root.stats.byRarity[modelData] || 0
        readonly property bool active: root.rarityFilter === modelData
        // Sem espécie daquela raridade não há nada para filtrar; o chip fica
        // visível (a raridade existe no jogo) mas inerte.
        readonly property bool enabled: count > 0

        width: chipLabel.implicitWidth + Style.space(10)
        height: Style.space(20)
        radius: Style.space(4)
        opacity: enabled ? 1 : 0.4
        color: active
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
               : (chipHover.hovered && enabled
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                  : "transparent")

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          id: chipLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: Balance.rarityLabel(chip.modelData) + " " + chip.count
          color: chip.active ? root.foreground : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: chip.active
        }

        HoverHandler { id: chipHover; enabled: chip.enabled }
        TapHandler {
          enabled: chip.enabled
          onTapped: root.toggleRarity(chip.modelData)
        }
      }
    }
  }

  Text {
    width: parent.width
    visible: root.allCells.length === 0
    textFormat: Text.PlainText
    text: "Your Pokédex fills itself: every species your companion reaches "
          + "lands here and stays, even after it graduates."
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

      // Número da Pokédex e ✨ ancorados na CÉLULA, não no sprite. O sprite tem
      // 34px centralizados numa célula de ~80: ancorado nele, o número flutuaria
      // a uns 20px da borda e pareceria solto no meio do nada. Na célula ele
      // encosta no canto, que é onde o olho procura o número.
      Text {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Style.space(2)
        textFormat: Text.PlainText
        text: cell.modelData.id
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // O ✨ marca a ESPÉCIE, não a arte em exibição: fica aceso mesmo quando a
      // célula está mostrando a versão normal.
      Text {
        visible: cell.modelData.shiny
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(2)
        textFormat: Text.PlainText
        text: "✨"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
        var bits = ["No. " + c.id, Balance.speciesLabel(c.name),
                    Balance.rarityLabel(c.rarity)]
        bits.push(c.count + (c.count === 1 ? " raised" : " raised"))
        if (c.shiny) bits.push("✨")
        if (c.shinySprite !== "" && c.sprite !== "") bits.push("click to swap artwork")
        bits.push(root.representativeSpeciesId === c.id ? "★ on the bar" : "☆ pin to the bar")
        return bits.join("  ·  ")
      }
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
