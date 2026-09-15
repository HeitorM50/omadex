import QtQuick
import qs.Commons
import qs.Ui
import "Balance.js" as Balance

// Aba "Settings": os dois multiplicadores da economia.
//
// Eles já existem nas settings do widget (shell.json, editáveis pela tela de
// settings do Omarchy); esta aba os traz para onde eles significam algo. Um
// "0.3×" sozinho não diz nada — "75M para evoluir" diz, e é por isso que cada
// slider mostra o efeito em tokens de verdade, calculado com as mesmas funções
// que a barra e a loja usam.
//
// Escreve só no `released`. No `moved` seria uma escrita no shell.json por pixel
// de arraste; é o mesmo motivo do botão Save do original, sem o botão.
Column {
  id: root

  property var host: null
  property var bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal optionRequested(string key, real value)

  readonly property real difficulty: host ? host.difficulty : 1.0
  readonly property real shopDifficulty: host ? host.shopDifficulty : 1.0
  readonly property bool hatched: host ? host.hatched === true : false
  readonly property string rarity: host ? host.rarity : "common"
  readonly property int stage: host ? host.stage : 0
  readonly property int totalForms: host ? host.totalForms : 1
  readonly property bool growthBoost: host ? host.growthBoost === true : false

  // A faixa é 0.1–2.0 em passos de 0.1, e o slider é INDEXADO: o `valueFromX`
  // do PanelSlider só arredonda quando `integer` é verdadeiro, então um slider
  // em reais entregaria 0.4732. Vinte paradas inteiras dão o passo exato.
  readonly property int stops: 20

  function indexOf(value) {
    return Math.max(0, Math.min(stops - 1, Math.round(value * 10) - 1))
  }

  function valueOf(index) {
    return (Math.max(0, Math.min(stops - 1, index)) + 1) / 10
  }

  // O limiar do que a pessoa está criando AGORA, na dificuldade que o slider
  // está mostrando. É o número que ela quer prever antes de soltar o mouse.
  function growthPreview(value) {
    if (!hatched)
      return Balance.formatTokens(Balance.hatchThreshold(value)) + " to hatch"
    var t = Balance.phaseThreshold(rarity, totalForms, stage, value,
                                   growthBoost ? 2 : 1)
    return Balance.formatTokens(t) + (stage >= totalForms - 1 ? " to graduate"
                                                              : " to evolve")
  }

  function shopPreview(value) {
    return Balance.formatTokens(Balance.shopPrice("rareCandy", value)) + " a candy"
           + "  ·  " + Balance.formatTokens(Balance.shopPrice("egg:", value)) + " an egg"
  }

  spacing: Style.space(10)

  // ---------- Crescimento ----------
  Column {
    width: parent.width
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: label.implicitHeight

      Text {
        id: label
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: "Growth difficulty"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.valueOf(growthSlider.liveValue).toFixed(1) + "×"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    PanelSlider {
      id: growthSlider
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: root.stops - 1
      step: 1
      integer: true
      value: root.indexOf(root.difficulty)
      onReleased: function (v) {
        root.optionRequested("difficulty", root.valueOf(v))
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      // Segue o arraste: `liveValue` muda antes da escrita, então a previsão
      // responde ao dedo e não ao arquivo.
      text: root.growthPreview(root.valueOf(growthSlider.liveValue))
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // ---------- Loja ----------
  Column {
    width: parent.width
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: shopLabel.implicitHeight

      Text {
        id: shopLabel
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: "Shop prices"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.valueOf(shopSlider.liveValue).toFixed(1) + "×"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    PanelSlider {
      id: shopSlider
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: root.stops - 1
      step: 1
      integer: true
      value: root.indexOf(root.shopDifficulty)
      onReleased: function (v) {
        root.optionRequested("shopDifficulty", root.valueOf(v))
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.shopPreview(root.valueOf(shopSlider.liveValue))
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  PanelSeparator { foreground: root.foreground }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    // Isto precisa estar escrito: sem a garantia, mexer no slider parece
    // arriscado o suficiente para ninguém mexer. E ela é real — o helper
    // reescala o progresso quando a dificuldade muda.
    text: "Changing growth keeps the progress you already have: the fraction of "
          + "the current stage is preserved, so nothing evolves or graduates "
          + "just because you moved the slider."
    color: Qt.darker(root.foreground, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: "Below 1× is faster and cheaper. The 0.3× growth default is tuned for "
          + "~50M tokens a day; 1.0× is the original PokeTokenBar balance."
    color: Qt.darker(root.foreground, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
