import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Balance.js" as Balance
import "Collection.js" as Collection
import "Profile.js" as Profile

// Perfil de uma espécie do Pokédex, e de cada indivíduo dela.
//
// Abre a partir de uma célula da grade. Nada aqui é lido de disco: os dados de
// espécie (stats base, habilidades, learnset, descrição) vêm do cache que o
// `omapkdex-sync details` escreve e o widget observa; os IVs, o gênero e a
// habilidade são sorteados do `companionId` na hora de desenhar.
//
// Sem os dados de espécie, o perfil aparece pela metade em vez de estourar: IVs,
// nível e natureza não dependem de rede, e são o que se quer ver primeiro.
Column {
  id: root

  property var collection: null
  property int speciesId: 0
  property var cell: null
  property var details: null
  property bool detailsLoading: false
  property bool detailsFailed: false

  // Contexto de crescimento do companion VIVO. Para os fechados, o nível sai do
  // estágio que eles alcançaram — e aí a dificuldade não importa, porque o nível
  // é uma fração e ela se cancela.
  property string liveCompanionId: ""
  property int stage: 0
  property real tokensIntoStage: 0
  property real difficulty: 1.0
  property bool growthBoost: false

  property int representativeSpeciesId: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int maxHeight: Style.space(360)

  signal backRequested()
  signal retryRequested()
  signal pinRequested(int speciesId)

  readonly property var individuals: Collection.individualsOf(collection, speciesId)
  property int selected: 0

  readonly property var individual: individuals.length > 0
                                    ? individuals[Math.max(0, Math.min(selected, individuals.length - 1))]
                                    : null

  readonly property bool pinned: representativeSpeciesId === speciesId

  // Os limiares de cada estágio da linha DESTE indivíduo. O nível é a fração do
  // total, então o bônus de 2× e a dificuldade se cancelam para quem já fechou;
  // para o vivo eles importam, porque tokensIntoStage é absoluto.
  function thresholdsFor(ind) {
    var forms = Math.max(1, ind.lineLength)
    var mult = (ind.current && root.growthBoost) ? 2 : 1
    var out = []
    for (var i = 0; i < forms; i++)
      out.push(Balance.phaseThreshold(ind.rarity, forms, i, root.difficulty, mult))
    return out
  }

  function contextFor(ind) {
    return {
      thresholds: thresholdsFor(ind),
      stage: ind.current ? root.stage : ind.finalStage,
      tokensIntoStage: ind.current ? root.tokensIntoStage : 0,
      graduated: ind.graduated
    }
  }

  readonly property var profile: individual
                                 ? Profile.profileFor(individual, details,
                                                      contextFor(individual))
                                 : null

  readonly property string art: {
    if (!cell) return ""
    if (individual && individual.shiny && cell.shinySprite) return cell.shinySprite
    return cell.sprite || cell.shinySprite || ""
  }

  spacing: Style.space(8)

  // ---------- Cabeçalho ----------
  Item {
    width: parent.width
    height: Math.max(back.implicitHeight, number.implicitHeight)

    Text {
      id: back
      anchors.left: parent.left
      textFormat: Text.PlainText
      text: "‹ Pokédex"
      color: backHover.hovered ? root.foreground : Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption

      HoverHandler { id: backHover }
      TapHandler { onTapped: root.backRequested() }
    }

    Text {
      id: number
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: "No. " + root.speciesId
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---------- Identidade ----------
  Row {
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: Style.space(56)
      height: Style.space(56)

      AnimatedImage {
        id: sprite
        anchors.centerIn: parent
        source: root.art ? "file://" + root.art : ""
        visible: source != ""
        playing: true
        smooth: false
        fillMode: Image.PreserveAspectFit
        height: parent.height
        width: sourceSize.height > 0
               ? Math.round(height * sourceSize.width / sourceSize.height) : height
      }

      Text {
        anchors.centerIn: parent
        visible: !sprite.visible
        textFormat: Text.PlainText
        text: "󰐝"
        color: Qt.darker(root.foreground, 1.8)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Column {
      width: parent.width - Style.space(70)
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: Balance.speciesLabel(root.cell ? root.cell.name : "")
              + (root.individual && root.individual.shiny ? "  ✨" : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        // Raridade e tipos só. O genus ("Valiant Pokémon") não cabe aqui — a
        // linha inteira dava 42 caracteres em 320px e saía elidida — e ele é
        // texto de sabor, então desceu para junto da descrição.
        text: {
          var bits = [Balance.rarityLabel(root.cell ? root.cell.rarity : "common")]
          if (root.details && root.details.types && root.details.types.length)
            bits.push(root.details.types.map(Balance.speciesLabel).join(" · "))
          return bits.join("  ·  ")
        }
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.pinned ? "★ on the bar" : "☆ pin to the bar"
        color: root.pinned ? Color.urgent : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption

        TapHandler {
          onTapped: root.pinRequested(root.pinned ? 0 : root.speciesId)
        }
      }
    }
  }

  // ---------- Seletor de indivíduo ----------
  //
  // Só aparece com mais de um: um seletor de uma opção é ruído. O rótulo é
  // "#n · Lv" como no Picker do original, com o vivo marcado.
  Flow {
    width: parent.width
    visible: root.individuals.length > 1
    spacing: Style.space(4)

    Repeater {
      model: root.individuals

      Rectangle {
        id: pick
        required property var modelData
        required property int index

        readonly property bool active: root.selected === index
        readonly property int level: Profile.levelFor(root.contextFor(modelData))

        width: pickLabel.implicitWidth + Style.space(10)
        height: Style.space(20)
        radius: Style.space(4)
        color: active
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
               : (pickHover.hovered
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                  : "transparent")

        Text {
          id: pickLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          // O índice existe porque dois indivíduos podem estar no mesmo nível —
          // dois graduados estão ambos em 100, e sem o número os chips ficam
          // indistinguíveis. É o mesmo rótulo do Picker do original.
          text: "#" + (pick.index + 1) + " Lv " + pick.level
                + (pick.modelData.current ? " ●" : "")
                + (pick.modelData.shiny ? " ✨" : "")
          color: pick.active ? root.foreground : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: pick.active
        }

        HoverHandler { id: pickHover }
        TapHandler { onTapped: root.selected = pick.index }
      }
    }
  }

  // ---------- Corpo, rolável ----------
  //
  // Seis barras de stat, quatro golpes e a descrição passam da altura que o
  // popout tem. Cresce com o conteúdo até o teto, como a grade do dex.
  Flickable {
    id: body
    width: parent.width
    height: Math.min(root.maxHeight, contentHeight)
    contentHeight: bodyColumn.implicitHeight
    visible: root.individual !== null
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: bodyColumn
      width: body.width
      spacing: Style.space(6)

      // Nível, gênero, natureza.
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: {
          if (!root.profile) return ""
          var bits = ["Lv " + root.profile.level,
                      Profile.genderLabel(root.profile.gender),
                      Profile.natureLabel(root.profile.nature)]
          if (root.individual.graduated) bits.push("graduated")
          else if (root.individual.released) bits.push("released")
          else bits.push("stage " + (root.stage + 1) + "/"
                         + Math.max(1, root.individual.lineLength))
          return bits.join("  ·  ")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: root.profile && root.profile.ability !== null
        text: {
          if (!root.profile || !root.profile.ability) return ""
          return "Ability: " + Profile.abilityLabel(root.profile.ability.name)
                 + (root.profile.ability.isHidden ? "  ·  hidden" : "")
        }
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.profile && root.profile.stats.length === 0
        textFormat: Text.PlainText
        text: {
          if (!root.profile) return ""
          var ivs = root.profile.ivs
          var bits = []
          for (var i = 0; i < Profile.STAT_ORDER.length; i++) {
            var key = Profile.STAT_ORDER[i]
            bits.push(Profile.statLabel(key) + " " + ivs[key])
          }
          return "IVs: " + bits.join(" · ") + "   (" + root.profile.ivTotal + "/186)"
        }
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // Barras de stat. O IV vai na mesma linha: é o que faz dois indivíduos da
      // mesma espécie serem diferentes, e sem ele as barras seriam da espécie,
      // não do bicho.
      Repeater {
        model: root.profile ? root.profile.stats : []

        Item {
          id: statRow
          required property var modelData
          width: bodyColumn.width
          height: Style.space(14)

          Text {
            id: statName
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            textFormat: Text.PlainText
            text: Profile.statLabel(statRow.modelData.name)
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: statValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(58)
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: statRow.modelData.value + "   IV " + statRow.modelData.iv
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            anchors.left: statName.right
            anchors.right: statValue.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(4)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g,
                           root.foreground.b, 0.12)

            Rectangle {
              height: parent.height
              radius: parent.radius
              width: parent.width * Math.min(1, statRow.modelData.value
                                                / Math.max(1, root.profile.scaleMax))
              color: root.foreground
              opacity: 0.75
            }
          }
        }
      }

      // Golpes.
      Text {
        width: parent.width
        visible: root.profile && root.profile.moves.length > 0
        textFormat: Text.PlainText
        text: "Moves"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.profile ? root.profile.moves : []

        Item {
          id: moveRow
          required property var modelData
          width: bodyColumn.width
          height: Style.space(13)

          Text {
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: Profile.abilityLabel(moveRow.modelData.name)
            color: Qt.darker(root.foreground, 1.2)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: "Lv " + moveRow.modelData.level
            color: Qt.darker(root.foreground, 1.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Descrição da espécie, com o genus como epígrafe.
      Text {
        width: parent.width
        visible: root.details && root.details.genus
        textFormat: Text.PlainText
        text: root.details ? root.details.genus : ""
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.details && root.details.flavorText
        textFormat: Text.PlainText
        text: root.details ? root.details.flavorText : ""
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        elide: Text.ElideRight
      }
    }
  }

  // ---------- Estados de carga ----------
  Text {
    width: parent.width
    visible: root.detailsLoading && !root.details
    textFormat: Text.PlainText
    text: "Loading species data…"
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    width: parent.width
    visible: root.detailsFailed && !root.details
    spacing: Style.space(4)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Species data unavailable — base stats, ability and moves need one "
            + "request to PokéAPI. Everything above is already yours: level, "
            + "nature and IVs come from the Pokémon itself."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      textFormat: Text.PlainText
      text: "↻ Try again"
      color: retryHover.hovered ? root.foreground : Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption

      HoverHandler { id: retryHover }
      TapHandler { onTapped: root.retryRequested() }
    }
  }
}
