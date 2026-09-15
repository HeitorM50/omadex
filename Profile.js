.pragma library

// Perfil do indivíduo: IVs, gênero, habilidade, nível, stats e golpes.
// Portado de Sources/PokeTokenBar/Core/PokemonProfile.swift do PokeTokenBar.
//
// A decisão central: **nada disto é persistido**. Tudo é sorteado de um PRNG
// semeado pelo `companionId`, que já existe e já é estável. O perfil é
// projeção, como o Pokédex — então os indivíduos que já estão no histórico
// ganham perfil retroativo, sem migração, sem arquivo novo e sem backfill.
//
// O preço dessa escolha é que o seed tem de ser realmente estável: se a função
// de hash mudar, os IVs do bicho de alguém mudam sozinhos. Ela é FNV-1a, que é
// especificada, e não o hash da linguagem (que em Swift é aleatório por
// processo — o original tropeçou nisso e teve de escrever o seu).
//
// A natureza é a única exceção: ela é MUTÁVEL (o Mint re-sorteia), então não
// pode sair de um seed. Vem gravada na entrada.

// ---- PRNG ----------------------------------------------------------------

// FNV-1a de 32 bits. `Math.imul` é o que dá multiplicação de 32 bits confiável
// em JS — `*` estoura para double e perde os bits de baixo.
function seedFor(companionId) {
  var s = String(companionId === undefined || companionId === null ? "" : companionId)
  var hash = 0x811c9dc5
  for (var i = 0; i < s.length; i++) {
    hash ^= s.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  // O seed nunca é 0: mulberry32 com estado 0 ainda funciona, mas um id vazio
  // e um id que por acaso zere o hash passariam a ser o mesmo indivíduo.
  return (hash >>> 0) || 0x9e3779b9
}

// mulberry32: 32 bits de estado, distribuição boa o suficiente para sortear
// IVs, e três linhas. O splitmix64 do original não se porta direto porque JS
// não tem inteiro de 64 bits — e o que importa aqui é ser determinístico, não
// ser idêntico ao Swift.
function _rng(seed) {
  var state = seed >>> 0
  return function () {
    state = (state + 0x6d2b79f5) >>> 0
    var t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0)
  }
}

// Cada aspecto tem o seu próprio fluxo. Com um fluxo só, o sorteio do gênero
// desloca o da habilidade, e uma espécie sem gênero (que não consome sorteio)
// passaria a ter outra habilidade que a mesma linha com gênero — acoplamento
// invisível e sem motivo.
var STREAM_IVS = 0
var STREAM_GENDER = 0x9e3779b9
var STREAM_ABILITY = 0xa11b1e5d

// ---- Individualidade -----------------------------------------------------

var STAT_ORDER = ["hp", "attack", "defense", "special-attack",
                  "special-defense", "speed"]

function ivsFor(seed) {
  var next = _rng((seed ^ STREAM_IVS) >>> 0)
  var out = {}
  for (var i = 0; i < STAT_ORDER.length; i++) out[STAT_ORDER[i]] = next() % 32
  return out
}

function ivTotal(ivs) {
  var total = 0
  for (var i = 0; i < STAT_ORDER.length; i++) total += (ivs && ivs[STAT_ORDER[i]]) || 0
  return total
}

// `genderRate` é oitavos de FÊMEA, como a PokéAPI o define; −1 é sem gênero.
function genderFor(seed, genderRate) {
  var rate = Number(genderRate)
  if (!isFinite(rate) || rate < 0) return "genderless"
  var next = _rng((seed ^ STREAM_GENDER) >>> 0)
  return (next() % 8) < rate ? "female" : "male"
}

// A oculta sai em 1/128 — é o número do original, e é o que faz dela um achado
// em vez de um terço das chocagens.
var HIDDEN_ABILITY_RATE = 128

function abilityFor(seed, abilities) {
  var list = Array.isArray(abilities) ? abilities.filter(function (a) { return a && a.name }) : []
  if (list.length === 0) return null

  var normais = list.filter(function (a) { return a.isHidden !== true })
  var ocultas = list.filter(function (a) { return a.isHidden === true })
  var next = _rng((seed ^ STREAM_ABILITY) >>> 0)

  var sorteioOculta = next() % HIDDEN_ABILITY_RATE === 0
  if (ocultas.length > 0 && (sorteioOculta || normais.length === 0))
    return ocultas[next() % ocultas.length]
  if (normais.length > 0)
    return normais[next() % normais.length]
  return ocultas[0]
}

// ---- Nível ---------------------------------------------------------------

// Nível também é derivado, não guardado. `thresholds` são os limiares de cada
// estágio na dificuldade vigente (vêm do Balance.js, que é quem sabe da
// dificuldade e do bônus de 2×) — assim esta função não depende de nada.
var LEVEL_MIN = 5
var LEVEL_MAX = 100

function levelFor(o) {
  var d = o || {}
  if (d.graduated === true) return LEVEL_MAX

  var th = Array.isArray(d.thresholds) ? d.thresholds : []
  var total = 0
  for (var i = 0; i < th.length; i++) total += Math.max(0, Number(th[i]) || 0)
  if (total <= 0) return LEVEL_MIN

  var stage = Math.max(0, d.stage | 0)
  var earned = Math.max(0, Number(d.tokensIntoStage) || 0)
  for (var j = 0; j < Math.min(stage, th.length); j++)
    earned += Math.max(0, Number(th[j]) || 0)

  var fraction = Math.min(1, earned / total)
  return Math.min(LEVEL_MAX, LEVEL_MIN + Math.floor((LEVEL_MAX - LEVEL_MIN) * fraction))
}

// ---- Naturezas -----------------------------------------------------------

// As 25 da série principal. A tabela é a mesma do original
// (PokemonNature.modifier(for:)): cada uma sobe um stat em 10% e desce outro,
// menos as cinco neutras. HP nunca é afetado.
var NATURES = [
  "hardy", "lonely", "brave", "adamant", "naughty",
  "bold", "docile", "relaxed", "impish", "lax",
  "timid", "hasty", "serious", "jolly", "naive",
  "modest", "mild", "quiet", "bashful", "rash",
  "calm", "gentle", "sassy", "careful", "quirky"
]

var NATURE_PAIRS = {
  lonely: ["attack", "defense"],
  brave: ["attack", "speed"],
  adamant: ["attack", "special-attack"],
  naughty: ["attack", "special-defense"],
  bold: ["defense", "attack"],
  relaxed: ["defense", "speed"],
  impish: ["defense", "special-attack"],
  lax: ["defense", "special-defense"],
  timid: ["speed", "attack"],
  hasty: ["speed", "defense"],
  jolly: ["speed", "special-attack"],
  naive: ["speed", "special-defense"],
  modest: ["special-attack", "attack"],
  mild: ["special-attack", "defense"],
  quiet: ["special-attack", "speed"],
  rash: ["special-attack", "special-defense"],
  calm: ["special-defense", "attack"],
  gentle: ["special-defense", "defense"],
  sassy: ["special-defense", "speed"],
  careful: ["special-defense", "special-attack"]
  // hardy, docile, serious, bashful e quirky são neutras: não entram na tabela.
}

function natureModifier(nature, stat) {
  var pair = NATURE_PAIRS[String(nature || "").toLowerCase()]
  if (!pair) return 1
  if (stat === pair[0]) return 1.1
  if (stat === pair[1]) return 0.9
  return 1
}

// ---- Stats calculados ----------------------------------------------------

// A fórmula da série principal, com EVs em zero (o original também não os
// modela: não há nada no plugin que treine stat).
function statsFor(baseStats, ivs, level, nature) {
  if (!baseStats || typeof baseStats !== "object") return []
  var lvl = Math.max(1, Math.min(LEVEL_MAX, level | 0))
  var out = []

  for (var i = 0; i < STAT_ORDER.length; i++) {
    var name = STAT_ORDER[i]
    var base = Number(baseStats[name])
    if (!isFinite(base)) continue
    var iv = Math.max(0, Math.min(31, (ivs && ivs[name]) | 0))
    var value
    if (name === "hp") {
      // HP tem fórmula própria e nenhuma natureza o afeta.
      value = Math.floor((2 * base + iv) * lvl / 100) + lvl + 10
    } else {
      var neutro = Math.floor((2 * base + iv) * lvl / 100) + 5
      value = Math.floor(neutro * natureModifier(nature, name))
    }
    out.push({ name: name, base: base, iv: iv, value: value })
  }
  return out
}

// A escala das barras: múltiplo de 100 acima do maior stat, com piso em 300.
// Fixar em 255 (o teto teórico de base stat) faria todo Pokémon de início
// desenhar barras minúsculas.
function statScaleMax(stats) {
  var maior = 300
  for (var i = 0; i < (stats || []).length; i++)
    maior = Math.max(maior, stats[i].value || 0)
  var resto = maior % 100
  return resto === 0 ? maior : maior + (100 - resto)
}

// ---- Golpes --------------------------------------------------------------

var MOVE_SLOTS = 4

// Os quatro últimos golpes de nível aprendidos até `level` — o mesmo critério
// do `levelUpMoves(through:)` do original. Um golpe que aparece em mais de um
// nível (acontece na PokéAPI entre version groups) vale pelo MENOR, que é
// quando ele foi de fato aprendido.
function movesFor(moves, level) {
  var lvl = Math.max(1, level | 0)
  var melhor = {}

  for (var i = 0; i < (Array.isArray(moves) ? moves.length : 0); i++) {
    var m = moves[i]
    if (!m || !m.name) continue
    var at = Math.max(0, m.level | 0)
    if (at > lvl) continue
    if (melhor[m.name] === undefined || at < melhor[m.name]) melhor[m.name] = at
  }

  var rows = []
  for (var name in melhor) rows.push({ name: name, level: melhor[name] })
  rows.sort(function (a, b) {
    if (a.level !== b.level) return a.level - b.level
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })
  return rows.slice(-MOVE_SLOTS)
}

// ---- Rótulos -------------------------------------------------------------

function statLabel(name) {
  switch (name) {
    case "hp": return "HP"
    case "attack": return "Atk"
    case "defense": return "Def"
    case "special-attack": return "SpA"
    case "special-defense": return "SpD"
    case "speed": return "Spe"
    default: return name
  }
}

function genderLabel(gender) {
  switch (gender) {
    case "male": return "♂ Male"
    case "female": return "♀ Female"
    case "genderless": return "Genderless"
    default: return "—"
  }
}

function natureLabel(nature) {
  var s = String(nature || "")
  if (!s) return "—"
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function abilityLabel(name) {
  var s = String(name || "")
  if (!s) return "—"
  return s.split("-").map(function (p) {
    return p.length ? p.charAt(0).toUpperCase() + p.slice(1) : p
  }).join(" ")
}

// ---- Tudo junto ----------------------------------------------------------

// `details` é o que o `omapkdex-sync details` cacheia; `ctx` é o contexto de
// crescimento (limiares, estágio, tokens) que só o widget tem.
//
// Sem `details` — cache ainda não baixado, ou rede fora — o perfil existe pela
// metade em vez de estourar: IVs, nível e natureza não dependem de rede, e são
// justamente o que a pessoa quer ver primeiro.
function profileFor(entry, details, ctx) {
  var e = entry || {}
  var seed = seedFor(e.companionId)
  var ivs = ivsFor(seed)
  var nature = e.nature ? String(e.nature) : null
  var level = levelFor(ctx || {})

  if (!details) {
    return {
      seed: seed, level: level, nature: nature, ivs: ivs, ivTotal: ivTotal(ivs),
      gender: null, ability: null, stats: [], moves: [], scaleMax: 300
    }
  }

  var stats = statsFor(details.baseStats, ivs, level, nature)
  return {
    seed: seed,
    level: level,
    nature: nature,
    ivs: ivs,
    ivTotal: ivTotal(ivs),
    gender: genderFor(seed, details.genderRate),
    ability: abilityFor(seed, details.abilities),
    stats: stats,
    moves: movesFor(details.moves, level),
    scaleMax: statScaleMax(stats)
  }
}
