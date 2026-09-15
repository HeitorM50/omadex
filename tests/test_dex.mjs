#!/usr/bin/env node
// Projeção do Pokédex sobre o catch log.
//
// O dex não é um arquivo: é derivado das entradas da coleção. Estes testes
// carregam o Collection.js real (tirando o `.pragma library`, que é sintaxe de
// QML) para não haver uma segunda cópia da lógica aqui.

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { homedir } from 'node:os'

const PLUGIN = join(homedir(), '.config/omarchy/plugins/io.github.heitorm50.omapkdex')

const dir = mkdtempSync(join(tmpdir(), 'ptb-dex-'))
const shim = join(dir, 'collection.mjs')
writeFileSync(shim,
  readFileSync(join(PLUGIN, 'Collection.js'), 'utf8').replace(/^\.pragma library\s*/m, '')
  + '\nexport { dexEntries, catchLogRows, dexStats, speciesReached, ownsSpecies, dexCell, hasGraduatedLine, visibleShiny, individualsOf };\n')
const C = await import(shim)

let fails = 0
const eq = (label, got, want) => {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  const ok = g === w
  if (!ok) fails++
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}: ${g}${ok ? '' : `  (esperado ${w})`}`)
}

// Uma entrada de catch log. `line` carrega id e nome de cada forma, porque o
// dex precisa nomear espécies que o companion alcançou mas que nunca foram a
// forma base de nada.
const entry = (o = {}) => ({
  companionId: o.companionId ?? 'c1',
  speciesId: o.speciesId ?? 341,
  name: o.name ?? 'corphish',
  rarity: o.rarity ?? 'common',
  // O factory tem de repassar TODO campo que algum teste passa: um campo
  // esquecido aqui é um teste que passa sem exercitar nada.
  nature: o.nature ?? null,
  shiny: o.shiny ?? false,
  line: o.line ?? [{ id: 341, name: 'corphish' }, { id: 342, name: 'crawdaunt' }],
  hatchedAt: o.hatchedAt ?? 1000,
  graduatedAt: o.graduatedAt ?? null,
  releasedAt: o.releasedAt ?? null,
  finalStage: o.finalStage ?? 0,
  // Campos do Ditto: o factory tem de repassá-los, senão um teste que passa
  // `dittoDisguise: true` é silenciosamente ignorado.
  dittoDisguise: o.dittoDisguise ?? false,
  dittoRevealed: o.dittoRevealed ?? false,
})
const col = (...entries) => ({ schemaVersion: 1, entries })

console.log('--- espécies alcançadas vêm de line[0..finalStage] ---')
eq('estágio 0 alcança só a base', C.speciesReached(entry({ finalStage: 0 })).map(s => s.id), [341])
eq('estágio 1 alcança as duas', C.speciesReached(entry({ finalStage: 1 })).map(s => s.id), [341, 342])
eq('finalStage além da linha não estoura',
   C.speciesReached(entry({ finalStage: 9 })).map(s => s.id), [341, 342])
eq('linha vazia devolve nada', C.speciesReached(entry({ line: [] })), [])

console.log('\n--- dex: uma célula por espécie ---')
eq('coleção vazia', C.dexEntries(col()), [])
eq('uma entrada no estágio 0 dá uma célula',
   C.dexEntries(col(entry())).map(d => d.id), [341])
eq('evoluída dá duas células',
   C.dexEntries(col(entry({ finalStage: 1 }))).map(d => d.id), [341, 342])
eq('a célula carrega o nome',
   C.dexEntries(col(entry({ finalStage: 1 }))).map(d => d.name), ['corphish', 'crawdaunt'])

console.log('\n--- dex: espécie repetida vira uma célula só, com contagem ---')
const repetida = col(entry({ companionId: 'a', hatchedAt: 1000 }),
                     entry({ companionId: 'b', hatchedAt: 2000 }))
eq('uma célula', C.dexEntries(repetida).map(d => d.id), [341])
eq('contagem de indivíduos', C.dexEntries(repetida)[0].count, 2)

console.log('\n--- dex: shiny é grudento por espécie ---')
const misto = col(entry({ companionId: 'a', shiny: false }),
                  entry({ companionId: 'b', shiny: true }))
eq('a espécie fica marcada shiny', C.dexEntries(misto)[0].shiny, true)
eq('sem nenhum shiny, não marca', C.dexEntries(col(entry()))[0].shiny, false)

console.log('\n--- dex: shiny só conta para as espécies realmente alcançadas ---')
// Um shiny que parou no estágio 0 não dá o ✨ na evolução que ele nunca virou.
const paradoShiny = col(entry({ shiny: true, finalStage: 0 }),
                        entry({ companionId: 'b', shiny: false, finalStage: 1 }))
const porId = Object.fromEntries(C.dexEntries(paradoShiny).map(d => [d.id, d]))
eq('a base é shiny', porId[341].shiny, true)
eq('a evolução não é', porId[342].shiny, false)

console.log('\n--- dex: ordenado por número ---')
const fora = col(entry({ companionId: 'a', speciesId: 25, line: [{ id: 25, name: 'pikachu' }] }),
                 entry({ companionId: 'b', speciesId: 1, line: [{ id: 1, name: 'bulbasaur' }] }))
eq('ordem crescente', C.dexEntries(fora).map(d => d.id), [1, 25])

console.log('\n--- catch log: mais recente primeiro ---')
const log3 = col(entry({ companionId: 'a', hatchedAt: 1000 }),
                 entry({ companionId: 'c', hatchedAt: 3000 }),
                 entry({ companionId: 'b', hatchedAt: 2000 }))
eq('ordenado por chocagem desc', C.catchLogRows(log3).map(r => r.companionId), ['c', 'b', 'a'])
eq('a entrada aberta é marcada',
   C.catchLogRows(col(entry({ graduatedAt: null })))[0].current, true)
eq('a fechada não', C.catchLogRows(col(entry({ graduatedAt: 9999 })))[0].current, false)

console.log('\n--- estatísticas do cabeçalho ---')
const stats = C.dexStats(col(entry({ companionId: 'a', finalStage: 1 }),
                             entry({ companionId: 'b', shiny: true }),
                             entry({ companionId: 'c', speciesId: 25, line: [{ id: 25, name: 'pikachu' }] })))
eq('espécies distintas', stats.species, 3)   // 341, 342, 25
eq('espécies shiny', stats.shiny, 1)         // só corphish
eq('indivíduos', stats.individuals, 3)

console.log('\n--- a célula expõe os sprites que tem ---')
// A mesma espécie pode ter sido possuída normal e shiny; a célula carrega os
// dois caminhos para a view escolher (e poder alternar no clique).
const comSprites = col(
  entry({ companionId: 'a', shiny: false,
          line: [{ id: 341, name: 'corphish', sprite: '/s/341.gif' }] }),
  entry({ companionId: 'b', shiny: true,
          line: [{ id: 341, name: 'corphish', sprite: '/s/341-shiny.gif' }] }))
eq('sprite normal', C.dexEntries(comSprites)[0].sprite, '/s/341.gif')
eq('sprite shiny', C.dexEntries(comSprites)[0].shinySprite, '/s/341-shiny.gif')
eq('sem shiny, shinySprite é vazio',
   C.dexEntries(col(entry({ line: [{ id: 341, name: 'corphish', sprite: '/s/341.gif' }] })))[0].shinySprite, '')

console.log('\n--- dados malformados não derrubam a projeção ---')
eq('entries ausente', C.dexEntries({ schemaVersion: 1 }), [])
eq('coleção nula', C.dexEntries(null), [])
// `line: undefined` cairia no default do factory (`??`), então o campo tem de
// ser removido de verdade para exercitar a entrada sem linha.
const semLinha = entry(); delete semLinha.line
eq('entrada sem line', C.dexEntries(col(semLinha)), [])
eq('catch log tolera entrada sem line', C.catchLogRows(col(semLinha))[0].sprite, '')
eq('forma sem id é ignorada',
   C.dexEntries(col(entry({ line: [{ name: 'sem id' }, { id: 7, name: 'squirtle' }], finalStage: 1 })))
    .map(d => d.id), [7])
eq('catch log de coleção nula', C.catchLogRows(null), [])
eq('stats de coleção nula', C.dexStats(null),
   { species: 0, shiny: 0, individuals: 0,
     byRarity: { common: 0, uncommon: 0, rare: 0, legendary: 0 } })

console.log('\n--- ownsSpecies: fixar no bar exige ter a espécie ---')
const um = col(entry({ finalStage: 1 }))
eq('tem a base', C.ownsSpecies(um, 341), true)
eq('tem a evolução alcançada', C.ownsSpecies(um, 342), true)
eq('não tem o que nunca criou', C.ownsSpecies(um, 25), false)
eq('não tem a forma não alcançada',
   C.ownsSpecies(col(entry({ finalStage: 0 })), 342), false)
eq('coleção nula', C.ownsSpecies(null, 341), false)

console.log('\n--- dexCell: a célula de uma espécie, para o bar ---')
eq('devolve a célula', C.dexCell(um, 342).name, 'crawdaunt')
eq('espécie ausente devolve nulo', C.dexCell(um, 25), null)
eq('coleção nula', C.dexCell(null, 341), null)

console.log('\n--- hasGraduatedLine no JS bate com o do helper ---')
eq('aberta não conta', C.hasGraduatedLine(col(entry({ finalStage: 1 })), 341), false)
eq('graduada no fim conta',
   C.hasGraduatedLine(col(entry({ finalStage: 1, graduatedAt: 9 })), 341), true)
eq('graduada sem chegar ao fim não conta',
   C.hasGraduatedLine(col(entry({ finalStage: 0, graduatedAt: 9 })), 341), false)
eq('liberada não conta',
   C.hasGraduatedLine(col(entry({ finalStage: 1, graduatedAt: null,
                                 releasedAt: 9 })), 341), false)

console.log('\n--- o ✨ de um Ditto disfarçado fica escondido no dex e no histórico ---')
// O README e o helper prometem que o brilho fica escondido EM TODA PARTE até a
// revelação. O bar e a aba Companion respeitavam; o dex e o histórico não,
// porque a projeção não sabia do disfarce.
const disfarcado = col(entry({ shiny: true, dittoDisguise: true,
                               dittoRevealed: false }))
eq('a célula do dex não brilha', C.dexEntries(disfarcado)[0].shiny, false)
eq('a linha do histórico não brilha', C.catchLogRows(disfarcado)[0].shiny, false)
eq('e não conta nas estatísticas', C.dexStats(disfarcado).shiny, 0)

const revelado = col(entry({ shiny: true, dittoDisguise: true,
                             dittoRevealed: true }))
eq('depois de revelar, brilha no dex', C.dexEntries(revelado)[0].shiny, true)
eq('e no histórico', C.catchLogRows(revelado)[0].shiny, true)
eq('e conta nas estatísticas', C.dexStats(revelado).shiny, 1)

const normalShiny = col(entry({ shiny: true }))
eq('shiny sem disfarce nenhum brilha', C.dexEntries(normalShiny)[0].shiny, true)

console.log('\n--- visibleShiny é a mesma regra do helper ---')
eq('shiny + disfarçado', C.visibleShiny({ shiny: true, dittoDisguise: true }), false)
eq('shiny + revelado',
   C.visibleShiny({ shiny: true, dittoDisguise: true, dittoRevealed: true }), true)
eq('shiny sem disfarce', C.visibleShiny({ shiny: true }), true)
eq('não shiny', C.visibleShiny({ shiny: false, dittoDisguise: true }), false)
eq('vazio', C.visibleShiny({}), false)
eq('nulo', C.visibleShiny(null), false)

console.log('\n--- a célula carrega a raridade, para os chips de filtro ---')
// A raridade é da espécie BASE e vale para a linha inteira: uma espécie
// pertence a uma única linha evolutiva, então não há de onde vir outra.
const raro = col(entry({ rarity: 'rare', finalStage: 1 }))
eq('a base leva a raridade da entrada', C.dexEntries(raro)[0].rarity, 'rare')
eq('a evolução herda a mesma', C.dexEntries(raro)[1].rarity, 'rare')
eq('raridade ausente cai em comum',
   C.dexEntries(col(entry({ rarity: undefined })))[0].rarity, 'common')
// Duas entradas da mesma espécie não podem discordar; se discordarem (estado
// escrito à mão), a primeira vista manda — o importante é ser estável, não
// alternar a cada releitura.
const discordante = col(entry({ companionId: 'a', rarity: 'rare' }),
                        entry({ companionId: 'b', rarity: 'common' }))
eq('a primeira raridade vista vence', C.dexEntries(discordante)[0].rarity, 'rare')

console.log('\n--- contagem por raridade: é o número em cada chip ---')
const mista = col(
  entry({ companionId: 'a', rarity: 'common', finalStage: 1 }),        // 341, 342
  entry({ companionId: 'b', speciesId: 25, rarity: 'rare',
          line: [{ id: 25, name: 'pikachu' }] }),
  entry({ companionId: 'c', speciesId: 144, rarity: 'legendary',
          line: [{ id: 144, name: 'articuno' }] }))
eq('conta ESPÉCIES, não indivíduos', C.dexStats(mista).byRarity,
   { common: 2, uncommon: 0, rare: 1, legendary: 1 })
eq('coleção vazia zera as quatro', C.dexStats(col()).byRarity,
   { common: 0, uncommon: 0, rare: 0, legendary: 0 })
eq('coleção nula também', C.dexStats(null).byRarity,
   { common: 0, uncommon: 0, rare: 0, legendary: 0 })
// A mesma espécie chocada duas vezes é UMA no chip.
eq('espécie repetida conta uma vez', C.dexStats(repetida).byRarity.common, 1)

console.log('\n--- individualsOf: os indivíduos por trás de uma célula do dex ---')
// Uma célula do Pokédex pode ser a mesma espécie de vários indivíduos. O perfil
// precisa de cada um deles, e só dos que REALMENTE alcançaram aquela forma.
const tres = col(
  entry({ companionId: 'a', nature: 'bold', finalStage: 1, hatchedAt: 1000,
          graduatedAt: 1500 }),
  entry({ companionId: 'b', nature: 'jolly', finalStage: 0, hatchedAt: 2000 }),
  entry({ companionId: 'c', speciesId: 25, line: [{ id: 25, name: 'pikachu' }],
          hatchedAt: 3000 }))
eq('a base tem dois indivíduos',
   C.individualsOf(tres, 341).map(i => i.companionId), ['b', 'a'])
eq('a evolução tem só quem chegou lá',
   C.individualsOf(tres, 342).map(i => i.companionId), ['a'])
eq('espécie de outra linha não se mistura',
   C.individualsOf(tres, 25).map(i => i.companionId), ['c'])
eq('espécie que ninguém teve', C.individualsOf(tres, 999), [])
eq('coleção nula', C.individualsOf(null, 341), [])

console.log('\n--- a linha do indivíduo carrega o que o perfil precisa ---')
const [novo, velho] = C.individualsOf(tres, 341)
eq('mais recente primeiro', [novo.companionId, velho.companionId], ['b', 'a'])
eq('natureza', novo.nature, 'jolly')
eq('sem natureza gravada fica nula',
   C.individualsOf(col(entry({ companionId: 'x' })), 341)[0].nature, null)
eq('o aberto é o companion de agora', novo.current, true)
eq('o graduado não', velho.current, false)
eq('graduado é marcado como graduado', velho.graduated, true)
eq('o estágio alcançado', velho.finalStage, 1)
eq('o tamanho da linha', velho.lineLength, 2)
eq('a raridade', velho.rarity, 'common')
eq('a data de chocagem', velho.hatchedAt, 1000)
// Liberado não é graduado: o nível dele é o que o estágio prova, não 100.
const liberado = col(entry({ companionId: 'r', finalStage: 1, releasedAt: 9 }))
eq('liberado não conta como graduado',
   C.individualsOf(liberado, 342)[0].graduated, false)
eq('e também não é o companion de agora',
   C.individualsOf(liberado, 342)[0].current, false)
eq('e é marcado como liberado', C.individualsOf(liberado, 342)[0].released, true)
// O shiny escondido do Ditto continua escondido aqui.
eq('shiny de Ditto disfarçado não aparece',
   C.individualsOf(col(entry({ shiny: true, dittoDisguise: true })), 341)[0].shiny,
   false)

console.log(fails ? `\n${fails} FALHA(S)` : '\nTodos os testes passaram')
process.exit(fails ? 1 : 0)
