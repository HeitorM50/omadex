.pragma library

// Projeção do Pokédex sobre o catch log.
//
// Não existe arquivo de Pokédex. A coleção persistida em collection.json é uma
// lista de indivíduos chocados, e o dex de espécies é derivado dela na hora de
// desenhar. Duas coleções persistidas dessincronizariam; uma não tem como.
//
// Funções puras, sem estado e sem IO — é o que permite testá-las fora do QML
// (tests/test_dex.mjs).

// As espécies que este indivíduo realmente alcançou.
//
// `finalStage` é o índice da forma mais avançada que ele chegou a ser, então a
// linha inteira NÃO conta: um Corphish que graduou sem evoluir não dá o
// Crawdaunt no dex. É a diferença entre colecionar o que você criou e
// colecionar o que você poderia ter criado.
function speciesReached(entry) {
  if (!entry || !Array.isArray(entry.line)) return []
  var last = Math.min(Math.max(0, entry.finalStage | 0), entry.line.length - 1)
  var out = []
  for (var i = 0; i <= last; i++) {
    var form = entry.line[i]
    if (form && form.id) out.push(form)
  }
  return out
}

// O shiny que pode ser MOSTRADO — a mesma regra do `visible_shiny` do helper.
//
// Um Ditto ainda disfarçado esconde o brilho em toda parte, dex e histórico
// incluídos: revelar o Ditto e o shiny juntos é o ponto alto do easter egg, e
// mostrar o ✨ na célula antes disso entrega a surpresa. A entrada guarda o
// shiny bruto (ele É shiny) e o estado de disfarce; quem decide é aqui.
function visibleShiny(entry) {
  var e = entry || {}
  if (e.shiny !== true) return false
  if (e.dittoDisguise === true && e.dittoRevealed !== true) return false
  return true
}

function entriesOf(collection) {
  return collection && Array.isArray(collection.entries) ? collection.entries : []
}

// Uma célula por espécie já possuída, em ordem de número da Pokédex.
//
// `shiny` é grudento por espécie: basta um indivíduo shiny daquela espécie para
// a célula ganhar o ✨ para sempre. Mas só vale para as espécies que aquele
// indivíduo alcançou — um shiny que parou na forma base não marca a evolução.
function dexEntries(collection) {
  var all = entriesOf(collection)
  var byId = {}

  for (var i = 0; i < all.length; i++) {
    var entry = all[i]
    var forms = speciesReached(entry)
    var isShiny = visibleShiny(entry)

    for (var f = 0; f < forms.length; f++) {
      var form = forms[f]
      var cell = byId[form.id]
      if (!cell) {
        cell = byId[form.id] = {
          id: form.id,
          name: form.name || String(form.id),
          shiny: false,
          count: 0,
          sprite: "",
          shinySprite: ""
        }
      }
      cell.count += 1
      if (isShiny) cell.shiny = true
      // O sprite de um indivíduo shiny é a arte shiny daquela espécie; o de um
      // normal é a arte normal. Guardamos os dois para a view poder alternar.
      if (form.sprite) {
        if (isShiny) { if (!cell.shinySprite) cell.shinySprite = form.sprite }
        else if (!cell.sprite) cell.sprite = form.sprite
      }
    }
  }

  var cells = []
  for (var key in byId) cells.push(byId[key])
  cells.sort(function (a, b) { return a.id - b.id })
  return cells
}

// Uma linha por indivíduo, do mais recente para o mais antigo.
function catchLogRows(collection) {
  var rows = entriesOf(collection).map(function (entry) {
    var forms = speciesReached(entry)
    var latest = forms.length ? forms[forms.length - 1] : null
    return {
      companionId: entry.companionId,
      speciesId: entry.speciesId,
      name: entry.name || "",
      finalName: latest ? (latest.name || String(latest.id)) : (entry.name || ""),
      sprite: latest && latest.sprite ? latest.sprite : "",
      rarity: entry.rarity || "common",
      shiny: visibleShiny(entry),
      hatchedAt: entry.hatchedAt || 0,
      graduatedAt: entry.graduatedAt || null,
      finalStage: entry.finalStage | 0,
      forms: forms.length,
      lineLength: Array.isArray(entry.line) ? entry.line.length : 0,
      // A entrada aberta é o companion de agora — a view o destaca em vez de
      // deixá-lo indistinguível dos que já graduaram.
      current: entry.graduatedAt === null || entry.graduatedAt === undefined
    }
  })
  rows.sort(function (a, b) { return b.hatchedAt - a.hatchedAt })
  return rows
}

// Os números do cabeçalho do Pokédex.
function dexStats(collection) {
  var cells = dexEntries(collection)
  var shiny = 0
  for (var i = 0; i < cells.length; i++) if (cells[i].shiny) shiny++
  return {
    species: cells.length,
    shiny: shiny,
    individuals: entriesOf(collection).length
  }
}

// Você tem esta espécie? Só conta o que o companion de fato alcançou — a mesma
// regra do dex. Fixar no bar algo que você nunca criou seria mentir sobre a
// coleção.
function ownsSpecies(collection, speciesId) {
  var all = entriesOf(collection)
  for (var i = 0; i < all.length; i++) {
    var forms = speciesReached(all[i])
    for (var f = 0; f < forms.length; f++) if (forms[f].id === speciesId) return true
  }
  return false
}

// A célula do dex de uma espécie, para o bar desenhar o representativo sem
// reprojetar a grade inteira.
function dexCell(collection, speciesId) {
  var cells = dexEntries(collection)
  for (var i = 0; i < cells.length; i++) if (cells[i].id === speciesId) return cells[i]
  return null
}

// Espelha `has_graduated_line` do helper: a linha desta espécie base já foi
// levada até o fim E graduada. Liberada por compra de ovo não conta.
//
// Aqui é só para o painel mostrar a cápsula de 2×; a conta que vale, a que muda
// o limiar, é a do helper.
function hasGraduatedLine(collection, baseSpeciesId) {
  var all = entriesOf(collection)
  for (var i = 0; i < all.length; i++) {
    var entry = all[i]
    if (entry.speciesId !== baseSpeciesId) continue
    if (entry.graduatedAt === null || entry.graduatedAt === undefined) continue
    var line = entry.line
    if (!Array.isArray(line) || line.length === 0) continue
    if ((entry.finalStage | 0) >= line.length - 1) return true
  }
  return false
}

// ---- Formatação ----------------------------------------------------------

// Data curta para a linha do catch log. Epoch em segundos.
function formatDate(seconds) {
  var n = Number(seconds) || 0
  if (n <= 0) return ""
  var d = new Date(n * 1000)
  var pad = function (v) { return v < 10 ? "0" + v : String(v) }
  return pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + "/" + d.getFullYear()
}
