import QtQuick
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

// Aba "Companion": o Pokémon de agora, o progresso e de onde vêm os tokens.
//
// Apresentação pura. Recebe o widget host em `host` e não toca em disco.
Column {
  id: root

  property var host: null
  property var bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal refreshRequested()
  signal agentsRequested()

  readonly property bool hatched: host ? host.hatched === true : false
  readonly property var line: host && host.evolutionLine ? host.evolutionLine : []
  readonly property int stage: host ? host.stage : 0
  readonly property string rarity: host ? host.rarity : "common"
  // shiny VISÍVEL: um Ditto ainda disfarçado esconde o brilho, porque revelar as
  // duas coisas juntas é o ponto alto do easter egg.
  readonly property bool shiny: host ? host.visibleShiny === true : false
  readonly property var progress: host ? host.progress : null
  readonly property real lifetimeTokens: host ? host.lifetimeTokens : 0
  readonly property int graduations: host ? host.graduations : 0
  readonly property string displayName: host ? host.displayName : "—"
  readonly property real hatchThreshold: host ? host.hatchThreshold : 0
  readonly property real tokensIntoStage: host ? host.tokensIntoStage : 0
  readonly property string currentSprite: host && host.currentSprite ? host.currentSprite : ""
  readonly property bool growthBoost: host ? host.growthBoost === true : false
  readonly property string mood: host ? host.mood : "egg"
  readonly property int celebration: host ? host.celebration : 0
  readonly property bool dittoRevealed: host ? host.dittoRevealed === true : false
  // O ovo "chocando" a partir de 90% do limiar: sem isso um ovo parado a 99%
  // parece quebrado.
  readonly property bool eggImminent: !hatched && barFraction >= 0.9

  // Antes de chocar a barra mostra o progresso do ovo; depois, o do estágio.
  readonly property real barFraction: {
    if (hatched) return progress ? progress.fraction : 0
    return hatchThreshold > 0 ? Math.min(1, tokensIntoStage / hatchThreshold) : 0
  }
  readonly property real barRemaining: {
    if (hatched) return progress ? progress.remaining : 0
    return Math.max(0, hatchThreshold - tokensIntoStage)
  }
  readonly property string nextLabel: {
    if (!hatched) return "até chocar"
    if (!progress) return ""
    return progress.isFinalStage ? "até graduar" : "até evoluir"
  }

  readonly property var agentRows: {
    var rows = []
    if (!host || !host.records) return rows
    var ids = host.agentIds || []
    for (var i = 0; i < ids.length; i++) {
      var record = host.records[ids[i]]
      if (!record) continue
      var limit = Balance.tightestLimit(record)
      rows.push({
        id: ids[i],
        name: record.name || ids[i],
        today: record.todayTotalTokens || 0,
        limitLabel: limit ? limit.label : "",
        percent: limit ? limit.percent : -1
      })
    }
    return rows
  }

  spacing: Style.space(12)

  // ---------- Herói: o sprite grande, o nome e a raridade ----------
  Item {
    width: parent.width
    implicitHeight: Math.max(Style.space(64), heroLabels.implicitHeight)

    Item {
      id: heroArt
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(64)
      height: Style.space(64)

      AnimatedImage {
        id: heroSprite
        anchors.centerIn: parent
        source: root.currentSprite ? "file://" + root.currentSprite : ""
        visible: source != ""
        playing: visible
        // Pixel art de 36x66 escalada: com smooth ligado vira borrão.
        smooth: false
        fillMode: Image.PreserveAspectFit
        height: Math.min(parent.height, sourceSize.height * 2)
        width: sourceSize.height > 0
               ? Math.round(height * sourceSize.width / sourceSize.height) : height

        // Pulo de celebração, na mola do original (resposta 0.5, amortecimento
        // 0.55 viram ~360ms com leve overshoot).
        transform: Scale {
          id: pop
          origin.x: heroSprite.width / 2
          origin.y: heroSprite.height
          xScale: 1
          yScale: 1
        }
      }

      // Flash branco por cima do sprite, que some em 0.8s.
      Rectangle {
        id: flash
        anchors.fill: heroSprite
        color: "white"
        opacity: 0
        visible: opacity > 0
        radius: Style.space(4)
      }

      // O ovo balança a partir de 90%: é o sinal de que está quase.
      SequentialAnimation {
        running: root.eggImminent && !root.hatched
        loops: Animation.Infinite
        NumberAnimation { target: eggGlyph; property: "rotation"; to: 5
                          duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { target: eggGlyph; property: "rotation"; to: -5
                          duration: 350; easing.type: Easing.InOutQuad }
      }

      // Dispara a celebração quando o contador do host muda — e não quando o
      // painel abre. O host guarda o contador, então uma chocagem que aconteceu
      // com o popout fechado ainda é celebrada na próxima abertura.
      Connections {
        target: root
        function onCelebrationChanged() {
          if (root.celebration <= 0) return
          celebrate.restart()
        }
      }

      SequentialAnimation {
        id: celebrate
        ParallelAnimation {
          NumberAnimation { target: flash; property: "opacity"
                            from: 0.85; to: 0; duration: 800
                            easing.type: Easing.OutCubic }
          SequentialAnimation {
            NumberAnimation { targets: [pop]; properties: "xScale,yScale"
                              from: 0.6; to: 1.08; duration: 220
                              easing.type: Easing.OutCubic }
            NumberAnimation { targets: [pop]; properties: "xScale,yScale"
                              to: 1; duration: 140
                              easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        id: eggGlyph
        anchors.centerIn: parent
        visible: !heroSprite.visible
        textFormat: Text.PlainText
        text: root.hatched ? "󰐝" : "󰪯"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
      }
    }

    Column {
      id: heroLabels
      anchors.left: heroArt.right
      anchors.leftMargin: Style.space(12)
      anchors.right: refreshButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          text: root.displayName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // O ✨ só aparece quando é shiny de verdade — é o ponto inteiro dele.
        Text {
          visible: root.shiny && root.hatched
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "✨"
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: {
          var bits = [Balance.rarityLabel(root.rarity)]
          if (root.hatched && root.line.length > 1)
            bits.push("estágio " + (root.stage + 1) + "/" + root.line.length)
          return bits.join("  ·  ")
        }
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Row {
        width: parent.width
        spacing: Style.space(5)

        Text {
          textFormat: Text.PlainText
          text: Balance.moodLabel(root.mood)
          color: root.mood === "tired" ? Color.urgent
                                       : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // A cápsula só aparece quando o bônus está ativo — é informação que
        // explica por que a barra está andando rápido.
        Rectangle {
          visible: root.growthBoost && root.hatched
          anchors.verticalCenter: parent.verticalCenter
          width: boostLabel.implicitWidth + Style.space(8)
          height: boostLabel.implicitHeight + Style.space(2)
          radius: height / 2
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2)

          Text {
            id: boostLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "2× crescimento"
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        width: parent.width
        visible: root.graduations > 0
        textFormat: Text.PlainText
        text: root.graduations + (root.graduations === 1 ? " graduado" : " graduados")
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      id: refreshButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰑐"
      tooltipText: "Reavaliar o uso (r)"
      foreground: root.foreground
      onClicked: root.refreshRequested()
    }
  }

  // ---------- Progresso até o próximo estágio ----------
  Column {
    width: parent.width
    spacing: Style.space(5)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Balance.formatTokens(root.barRemaining) + " " + root.nextLabel
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Rectangle {
      width: parent.width
      height: Style.space(6)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

      Rectangle {
        height: parent.height
        width: Math.min(parent.width, Math.max(parent.height, parent.width * root.barFraction))
        radius: parent.radius
        color: root.foreground

        Behavior on width {
          NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: {
        var into = root.hatched ? (root.progress ? root.progress.tokens : 0)
                                : root.tokensIntoStage
        var of = root.hatched ? (root.progress ? root.progress.threshold : 0)
                              : root.hatchThreshold
        return Balance.formatTokens(into) + " de " + Balance.formatTokens(of)
               + "  ·  " + Balance.formatTokens(root.lifetimeTokens) + " no total"
      }
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // ---------- Linha evolutiva ----------
  Column {
    width: parent.width
    visible: root.line.length > 1
    spacing: Style.space(6)

    PanelSectionHeader {
      text: "Linha evolutiva"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: root.line

        Row {
          id: formRow
          required property var modelData
          required property int index
          spacing: Style.space(3)

          readonly property bool reached: root.hatched && index <= root.stage
          readonly property bool current: root.hatched && index === root.stage

          Text {
            visible: formRow.index > 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "›"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Column {
            spacing: Style.space(1)

            AnimatedImage {
              source: formRow.modelData && formRow.modelData.sprite
                      ? "file://" + formRow.modelData.sprite : ""
              visible: source != ""
              // Só o estágio atual anima. Três GIFs em loop ao mesmo tempo dão
              // um painel inquieto e gastam GPU sem motivo.
              playing: formRow.current
              paused: !formRow.current
              smooth: false
              fillMode: Image.PreserveAspectFit
              height: Style.space(32)
              width: sourceSize.height > 0
                     ? Math.round(height * sourceSize.width / sourceSize.height) : height
              opacity: formRow.reached ? 1 : 0.3
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: Balance.speciesLabel(formRow.modelData ? formRow.modelData.name : "")
              color: formRow.current ? root.foreground
                                     : Qt.darker(root.foreground, formRow.reached ? 1.4 : 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: formRow.current
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
        }
      }
    }
  }

  PanelSeparator {
    visible: root.agentRows.length > 0
    foreground: root.foreground
  }

  // ---------- De onde vêm os tokens ----------
  Column {
    width: parent.width
    visible: root.agentRows.length > 0
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "Agentes"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: root.agentRows

      Item {
        id: agentRow
        required property var modelData
        width: parent.width
        implicitHeight: agentName.implicitHeight

        Text {
          id: agentName
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: agentRow.modelData.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.right: parent.right
          anchors.baseline: agentName.baseline
          textFormat: Text.PlainText
          text: {
            var bits = []
            if (agentRow.modelData.today > 0)
              bits.push(Balance.formatTokens(agentRow.modelData.today) + " hoje")
            if (agentRow.modelData.percent >= 0)
              bits.push(Math.round(agentRow.modelData.percent * 100) + "%")
            return bits.length ? bits.join("  ·  ") : "—"
          }
          color: agentRow.modelData.percent >= 0.8
                 ? Color.urgent : Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
