.pragma library

// Economia de tokens do companion, portada de PokemonBalance
// (Sources/PokeTokenBar/Core/CompanionModel.swift:104-127 do PokeTokenBar).
//
// A propriedade que importa: para uma dada raridade, o total de tokens até a
// graduação é o mesmo independente de quantas formas a linha evolutiva tem. Uma
// linha de 1 forma e uma de 3 custam T; o que muda é só o parcelamento, com
// estágios mais altos custando proporcionalmente mais.

// Tokens para o ovo chocar. Existe para dar expectativa em vez de já começar
// com um Pokémon na cara do usuário; o excedente é transferido para o filhote.
var EGG_HATCH_THRESHOLD = 5000000

// Total até a graduação, por raridade.
var GRADUATION_TOTAL = {
  common: 750000000,
  uncommon: 1875000000,
  rare: 3000000000,
  legendary: 6000000000
}

// Faixa do multiplicador de dificuldade. Abaixo de 1 é mais rápido que o
// padrão, acima é mais lento.
var DIFFICULTY_MIN = 0.1
var DIFFICULTY_MAX = 2.0
var DIFFICULTY_DEFAULT = 1.0

function graduationTotal(rarity) {
  return GRADUATION_TOTAL[rarity] || GRADUATION_TOTAL.common
}

// O multiplicador vem do shell.json, que é editável à mão — 0, negativo e NaN
// chegam de verdade, e um multiplicador 0 zeraria todos os limiares (divisão por
// zero no progresso, loop de evolução degenerado).
function clampDifficulty(value) {
  var n = Number(value)
  if (!isFinite(n)) return DIFFICULTY_DEFAULT
  return Math.min(Math.max(n, DIFFICULTY_MIN), DIFFICULTY_MAX)
}

// Custo do estágio stageIndex (0-based) numa linha de totalForms formas.
//
//   custo(i) = T * (i+1) / (k*(k+1)/2)
//
// A soma sobre todos os estágios é exatamente T, então a graduação cai no total
// prometido pela raridade sem depender do tamanho da linha.
function phaseThreshold(rarity, totalForms, stageIndex, difficulty) {
  var k = Math.max(1, totalForms | 0)
  var i = Math.max(0, stageIndex | 0) + 1
  if (i > k) i = k

  var denom = (k * (k + 1)) / 2
  var base = Math.round(graduationTotal(rarity) * i / denom)
  return Math.max(1, Math.round(base * clampDifficulty(difficulty)))
}

// Limiar do ovo, também sujeito à dificuldade.
function hatchThreshold(difficulty) {
  return Math.max(1, Math.round(EGG_HATCH_THRESHOLD * clampDifficulty(difficulty)))
}

// Progresso dentro do estágio atual, dados os tokens acumulados desde que o
// estágio começou. Devolve tudo o que o painel e o bar precisam desenhar.
function progress(rarity, totalForms, stageIndex, tokensIntoStage, difficulty) {
  var k = Math.max(1, totalForms | 0)
  var threshold = phaseThreshold(rarity, k, stageIndex, difficulty)
  var into = Math.max(0, tokensIntoStage)
  return {
    threshold: threshold,
    tokens: into,
    remaining: Math.max(0, threshold - into),
    fraction: threshold > 0 ? Math.min(1, into / threshold) : 0,
    complete: into >= threshold,
    isFinalStage: stageIndex >= k - 1
  }
}

// A mutação da progressão (acumular deltas, avançar estágios, graduar) NÃO
// vive aqui: é do `bin/poke-sync absorb`, o único escritor do state.json.
// Duplicá-la em JS criaria duas implementações da mesma regra para divergir.
// Este arquivo é matemática de leitura: limiares, progresso e formatação.

// ---- Formatação ----------------------------------------------------------

// Compacto no estilo do original ("200.7M"). O bar tem pouquíssimo espaço e um
// número de 10 dígitos empurraria os outros widgets.
function formatTokens(n) {
  var v = Number(n) || 0
  if (v >= 1e12) return (v / 1e12).toFixed(2) + "T"
  if (v >= 1e9) return (v / 1e9).toFixed(2) + "B"
  if (v >= 1e6) return (v / 1e6).toFixed(1) + "M"
  if (v >= 1e3) return (v / 1e3).toFixed(1) + "K"
  return String(Math.round(v))
}

function rarityLabel(rarity) {
  switch (rarity) {
    case "legendary": return "Lendário"
    case "rare": return "Raro"
    case "uncommon": return "Incomum"
    default: return "Comum"
  }
}

// Nome da espécie como a PokéAPI devolve ("mr-mime") virando exibível.
function speciesLabel(name) {
  var s = String(name || "").trim()
  if (!s) return "???"
  return s.split("-").map(function (part) {
    return part.length ? part.charAt(0).toUpperCase() + part.slice(1) : part
  }).join(" ")
}

// ---- Records do omarchy.agents -------------------------------------------

// Total de tokens de um record de uso, somando as quatro contagens que o
// contrato do omarchy.agents define em modelUsage.
function recordTokens(record) {
  if (!record || typeof record !== "object") return 0
  var usage = record.modelUsage
  if (!usage || typeof usage !== "object") return 0

  var total = 0
  for (var model in usage) {
    var m = usage[model]
    if (!m || typeof m !== "object") continue
    total += (m.inputTokens || 0)
    total += (m.outputTokens || 0)
    total += (m.cacheCreationInputTokens || 0)
    total += (m.cacheReadInputTokens || 0)
  }
  return total
}

// O limite de janela mais apertado do record, para a linha de status do painel.
function tightestLimit(record) {
  if (!record || !Array.isArray(record.limits)) return null
  var worst = null
  for (var i = 0; i < record.limits.length; i++) {
    var limit = record.limits[i]
    if (!limit || typeof limit.percent !== "number") continue
    if (!worst || limit.percent > worst.percent) worst = limit
  }
  return worst
}
