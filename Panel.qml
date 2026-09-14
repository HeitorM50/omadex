import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

// Popout do companion.
//
// Apresentação apenas. Todo o estado vem injetado por BarWidget.qml, que é o
// dono dos records e do state.json — este arquivo nunca toca disco nem rede, e
// por isso pode ser exercitado ponta a ponta com um state.json escrito à mão.
//
// Deliberadamente NÃO duplica os painéis do omarchy.agents: limites por janela,
// tokens por dia e quebra por modelo já estão a um clique de distância no bar,
// e repetir isso aqui só criaria duas telas para manter em sincronia. O que
// aparece aqui é o que o omarchy.agents não tem: o companion.
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

  readonly property bool hatched: host ? host.hatched === true : false
  readonly property var line: host && host.evolutionLine ? host.evolutionLine : []
  readonly property int stage: host ? host.stage : 0
  readonly property string rarity: host ? host.rarity : "common"
  readonly property var progress: host ? host.progress : null
  readonly property real lifetimeTokens: host ? host.lifetimeTokens : 0
  readonly property int graduations: host ? host.graduations : 0
  readonly property string displayName: host ? host.displayName : "—"
  readonly property real hatchThreshold: host ? host.hatchThreshold : 0
  readonly property real tokensIntoStage: host ? host.tokensIntoStage : 0
  readonly property string currentSprite: host && host.currentSprite ? host.currentSprite : ""

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

  // Uma linha por agente com uso registrado, só com o limite mais apertado.
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

  function refresh() {
    if (host && typeof host.refresh === "function") host.refresh()
  }

  // Abre o painel rico do omarchy.agents, que é quem tem os números detalhados.
  function openAgents() {
    if (bar) bar.run("omarchy-shell omarchy.agents toggle")
    close()
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
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onReturnRequested: root.refresh()
      onActivateRequested: root.refresh()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "a" || t === "A") root.openAgents()
      }

      Column {
        id: column
        anchors.fill: parent
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
            }

            Text {
              anchors.centerIn: parent
              visible: !heroSprite.visible
              textFormat: Text.PlainText
              text: root.hatched ? "󰐝" : "󰪯"
              color: Qt.darker(root.contentForeground, 1.4)
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

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.displayName
              color: root.contentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
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
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: root.graduations > 0
              textFormat: Text.PlainText
              text: root.graduations + (root.graduations === 1 ? " graduado" : " graduados")
              color: Qt.darker(root.contentForeground, 1.6)
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
            foreground: root.contentForeground
            onClicked: root.refresh()
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
            color: root.contentForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g,
                           root.contentForeground.b, 0.15)

            Rectangle {
              height: parent.height
              width: Math.min(parent.width, Math.max(parent.height, parent.width * root.barFraction))
              radius: parent.radius
              color: root.contentForeground

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
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // ---------- Linha evolutiva ----------
        // Formas futuras aparecem esmaecidas: dá para ver no que o bicho vai
        // virar sem perder de vista em que estágio ele está agora.
        Column {
          width: parent.width
          visible: root.line.length > 1
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Linha evolutiva"
            foreground: root.contentForeground
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
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Column {
                  spacing: Style.space(1)

                  AnimatedImage {
                    source: formRow.modelData && formRow.modelData.sprite
                            ? "file://" + formRow.modelData.sprite : ""
                    visible: source != ""
                    // Só o estágio atual anima. Três GIFs em loop ao mesmo tempo
                    // dão um painel inquieto e gastam GPU sem motivo.
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
                    color: formRow.current ? root.contentForeground
                                           : Qt.darker(root.contentForeground, formRow.reached ? 1.4 : 1.9)
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
          foreground: root.contentForeground
        }

        // ---------- De onde vêm os tokens ----------
        // Resumo, não dashboard: "Detalhes" abre o omarchy.agents, que é quem
        // tem os números completos.
        Column {
          width: parent.width
          visible: root.agentRows.length > 0
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "Agentes"
            foreground: root.contentForeground
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
                color: root.contentForeground
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
                       ? Color.urgent : Qt.darker(root.contentForeground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "r reavalia · a abre os detalhes · Esc fecha"
          color: Qt.darker(root.contentForeground, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
