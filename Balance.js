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
// `growthMultiplier` DIVIDE o limiar: 2 significa "cresce duas vezes mais
// rápido". Ele existe aqui porque o helper o aplica, e este arquivo é a leitura
// do que o helper escreve — sem o parâmetro, a barra mostrava o dobro do que
// faltava e o Pokémon evoluía com ela pela metade.
function phaseThreshold(rarity, totalForms, stageIndex, difficulty, growthMultiplier) {
  var k = Math.max(1, totalForms | 0)
  var i = Math.max(0, stageIndex | 0) + 1
  if (i > k) i = k

  var denom = (k * (k + 1)) / 2
  var base = Math.round(graduationTotal(rarity) * i / denom)
  var scaled = Math.round(base * clampDifficulty(difficulty))
  var mult = Math.max(1, growthMultiplier | 0)
  return Math.max(1, Math.round(scaled / mult))
}

// Limiar do ovo, também sujeito à dificuldade.
function hatchThreshold(difficulty) {
  return Math.max(1, Math.round(EGG_HATCH_THRESHOLD * clampDifficulty(difficulty)))
}

// Progresso dentro do estágio atual, dados os tokens acumulados desde que o
// estágio começou. Devolve tudo o que o painel e o bar precisam desenhar.
function progress(rarity, totalForms, stageIndex, tokensIntoStage, difficulty,
                  growthMultiplier) {
  var k = Math.max(1, totalForms | 0)
  var threshold = phaseThreshold(rarity, k, stageIndex, difficulty, growthMultiplier)
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
// vive aqui: é do `bin/omapkdex-sync absorb`, o único escritor do state.json.
// Duplicá-la em JS criaria duas implementações da mesma regra para divergir.
// Este arquivo é matemática de leitura: limiares, progresso e formatação.

// ---- Economia ------------------------------------------------------------
//
// Os preços têm de sair do MESMO lugar que o helper usa, senão a loja mostra um
// número e o `omapkdex-sync buy` cobra outro. Estas constantes são as mesmas de
// bin/omapkdex-sync, e tests/test_shop.mjs trava as duas listas no mesmo valor.

var RARE_CANDY_PRICE = 500000000
var MINT_PRICE = 100000000
var SHINY_CHARM_PRICE = 3000000000
var FRESH_EGG_PRICE = 1000000000

var BASE_PRICES = {
  mint: MINT_PRICE,
  rareCandy: RARE_CANDY_PRICE,
  shinyCharm: SHINY_CHARM_PRICE
}

// Passivo: comprado uma vez, vale para sempre, não se consome.
var PASSIVE_ITEMS = { shinyCharm: true }

// Ordem em que a bag lista, independente da ordem do objeto de inventário.
var BAG_ORDER = ["rareCandy", "mint", "shinyCharm"]

function eggPrice(tier) {
  if (!tier) return FRESH_EGG_PRICE
  // A razão sai da tabela de graduação, não da de probabilidade — ver o
  // comentário no helper.
  return Math.round(FRESH_EGG_PRICE * graduationTotal(tier) / graduationTotal("common"))
}

function shopPrice(key, shopDifficulty) {
  var base
  if (String(key).indexOf("egg") === 0) {
    var tier = String(key).split(":")[1] || null
    base = eggPrice(tier)
  } else {
    base = BASE_PRICES[key] || 0
  }
  return Math.max(0, Math.round(base * clampDifficulty(shopDifficulty)))
}

function availableTokens(state) {
  if (!state) return 0
  var lifetime = Number(state.lifetimeTokens) || 0
  var spent = Number(state.spentTokens) || 0
  return Math.max(0, lifetime - spent)
}

function itemLabel(key) {
  switch (key) {
    case "rareCandy": return "Rare Candy"
    case "mint": return "Mint"
    case "shinyCharm": return "Shiny Charm"
    case "egg:": return "Egg"
    case "egg:uncommon": return "Uncommon Egg"
    case "egg:rare": return "Rare Egg"
    default: return key
  }
}

function itemGlyph(key) {
  switch (key) {
    case "rareCandy": return "🍬"
    case "mint": return "🌿"
    case "shinyCharm": return "✨"
    default: return "🥚"
  }
}

function itemHint(key) {
  switch (key) {
    case "rareCandy": return "+" + formatTokens(100000000) + " of growth"
    case "mint": return "rerolls its nature"
    case "shinyCharm": return "shiny odds 1/64 → 1/48, forever"
    case "egg:": return "release the current one and start over"
    case "egg:uncommon": return "guarantees Uncommon or better"
    case "egg:rare": return "guarantees Rare or better"
    default: return ""
  }
}

// A loja é UMA lista em ordem de preço, itens e ovos juntos — como no original.
// O passivo já comprado afunda para o fim em vez de sair da lista, para a
// pessoa ver que já tem.
function shopEntries(inventory, shopDifficulty, wallet) {
  var inv = inventory || {}
  var saldo = wallet === undefined ? null : wallet
  var keys = ["mint", "rareCandy", "shinyCharm", "egg:", "egg:uncommon", "egg:rare"]

  var rows = keys.map(function (key) {
    var price = shopPrice(key, shopDifficulty)
    var owned = PASSIVE_ITEMS[key] === true && inv[key] === true
    return {
      key: key,
      label: itemLabel(key),
      hint: itemHint(key),
      glyph: itemGlyph(key),
      price: price,
      owned: owned,
      passive: PASSIVE_ITEMS[key] === true,
      isEgg: String(key).indexOf("egg") === 0,
      tier: String(key).indexOf("egg") === 0 ? (String(key).split(":")[1] || null) : null,
      affordable: saldo === null ? true : saldo >= price
    }
  })

  rows.sort(function (a, b) {
    if (a.owned !== b.owned) return a.owned ? 1 : -1
    return a.price - b.price
  })
  return rows
}

// A bag lista só o que se tem. Contagem zero e charm falso não aparecem — uma
// linha "0x Rare Candy" é ruído.
function bagEntries(inventory) {
  var inv = inventory || {}
  var rows = []
  for (var i = 0; i < BAG_ORDER.length; i++) {
    var key = BAG_ORDER[i]
    var passive = PASSIVE_ITEMS[key] === true
    if (passive) {
      if (inv[key] !== true) continue
      rows.push({ key: key, label: itemLabel(key), hint: itemHint(key),
                  glyph: itemGlyph(key), count: null, passive: true,
                  usable: false })
    } else {
      var n = Number(inv[key]) || 0
      if (n <= 0) continue
      rows.push({ key: key, label: itemLabel(key), hint: itemHint(key),
                  glyph: itemGlyph(key), count: n, passive: false,
                  usable: true })
    }
  }
  return rows
}

// ---- Humor do companion --------------------------------------------------
//
// O companion reage ao ritmo de uso. Os cortes de tokens/min são os do original
// (UsageStore.burnTier); a taxa em si vem do helper, que a mede entre duas
// absorções.

function burnTier(tokensPerMinute) {
  var r = Number(tokensPerMinute) || 0
  if (r <= 1000) return "idle"
  if (r < 100000) return "normal"
  if (r < 400000) return "fast"
  return "blazing"
}

// A partir de quanto de um limite de janela o companion fica cansado.
var TIRED_AT = 0.9

// Por PRIORIDADE, não por combinação — a ordem é a do original
// (CompanionStore.computeState) e é o que torna o resultado previsível:
// ovo > evento recente > perto do limite > sem uso > ritmo.
function mood(state, todayTokens, worstLimitPercent, recentEvent) {
  if (!state || state.hatched !== true) return "egg"
  if (recentEvent) return "levelUp"
  if ((Number(worstLimitPercent) || 0) >= TIRED_AT) return "tired"
  if ((Number(todayTokens) || 0) <= 0) return "sleep"

  var tier = burnTier(state.burnRate)
  if (tier === "idle") return "idle"
  if (tier === "normal") return "working"
  return "focus"
}

function moodLabel(m) {
  switch (m) {
    case "egg": return "incubating"
    case "working": return "working"
    case "focus": return "focused"
    case "tired": return "tired"
    case "sleep": return "asleep"
    case "levelUp": return "grew!"
    default: return "idle"
  }
}

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
    case "legendary": return "Legendary"
    case "rare": return "Rare"
    case "uncommon": return "Uncommon"
    default: return "Common"
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

// Tooltip do bar.
//
// Existe como função pura por causa de um bug: quando havia espécie fixada, o
// bar mostrava o NOME dela colado no ESTÁGIO do companion real —
// "Corphish · estágio 2/2", que é contradição, porque o Corphish É o estágio 1.
// Quem olhava não tinha como saber em que estágio estava.
//
// A regra que este texto garante: a espécie fixada nunca aparece na mesma linha
// que um estágio ou um progresso. Ela é anunciada como fixada, e o companion
// real é nomeado junto do seu próprio estágio.
function barTooltip(o) {
  var d = o || {}
  var parts = []
  var pinned = String(d.pinnedName || "")
  var companion = String(d.companionName || "—")

  if (pinned) {
    parts.push(pinned + " ★ pinned to the bar")
    // "Companion:" nomeia de quem é o estágio. Sem esse prefixo o leitor
    // atribui o número à espécie da linha de cima.
    parts.push("Companion: " + companion
               + (d.hatched
                  ? "  ·  " + rarityLabel(d.rarity)
                    + "  ·  stage " + ((d.stage | 0) + 1) + "/" + Math.max(1, d.totalForms | 0)
                  : ""))
  } else {
    parts.push(companion)
    if (d.hatched) {
      parts.push(rarityLabel(d.rarity)
                 + "  ·  stage " + ((d.stage | 0) + 1) + "/" + Math.max(1, d.totalForms | 0))
    }
  }

  if (d.hatched) {
    parts.push(formatTokens(d.remaining) + " tokens to "
               + (d.isFinalStage ? "graduate" : "evolve"))
  } else {
    parts.push(formatTokens(d.hatchRemaining) + " tokens to hatch")
  }

  if ((Number(d.todayTokens) || 0) > 0)
    parts.push("Today: " + formatTokens(d.todayTokens))

  return parts.join("\n")
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
