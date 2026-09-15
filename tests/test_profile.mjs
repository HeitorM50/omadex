#!/usr/bin/env node
// Perfil do indivíduo: IVs, gênero, habilidade, nível, stats e golpes.
//
// A decisão que estes testes travam: NADA disso é persistido. Tudo é sorteado
// de um PRNG semeado pelo `companionId`, que já existe e já é estável. O perfil
// é projeção, como o Pokédex — então os indivíduos que já estão no histórico
// ganham perfil retroativo, sem migração de arquivo.
//
// Consequência que um teste tem de garantir: o mesmo companionId produz sempre
// o mesmo indivíduo. Se isso quebrar, os IVs do bicho de alguém mudam sozinhos.

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir, homedir } from 'node:os'
import { join } from 'node:path'

const PLUGIN = join(homedir(), '.config/omarchy/plugins/io.github.heitorm50.omapkdex')
const dir = mkdtempSync(join(tmpdir(), 'ptb-prof-'))
const shim = join(dir, 'profile.mjs')
writeFileSync(shim,
  readFileSync(join(PLUGIN, 'Profile.js'), 'utf8').replace(/^\.pragma library\s*/m, '')
  + '\nexport { seedFor, ivsFor, ivTotal, genderFor, abilityFor, levelFor,'
  + ' natureModifier, statsFor, movesFor, NATURES, STAT_ORDER, statLabel,'
  + ' genderLabel, natureLabel, abilityLabel, statScaleMax, profileFor };\n')
const P = await import(shim)

let fails = 0
const eq = (label, got, want) => {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  const ok = g === w
  if (!ok) fails++
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}: ${g}${ok ? '' : `  (esperado ${w})`}`)
}
const ok = (label, cond) => eq(label, !!cond, true)

// Corphish, da PokéAPI (conferido na API).
const CORPHISH = {
  baseStats: { hp: 43, attack: 80, defense: 65,
               'special-attack': 50, 'special-defense': 35, speed: 35 },
  genderRate: 4,
  abilities: [
    { name: 'hyper-cutter', slot: 1, isHidden: false },
    { name: 'shell-armor', slot: 2, isHidden: false },
    { name: 'adaptability', slot: 3, isHidden: true }
  ],
  moves: [
    { name: 'bubble', level: 1 }, { name: 'harden', level: 1 },
    { name: 'vicegrip', level: 7 }, { name: 'leer', level: 10 },
    { name: 'bubblebeam', level: 13 }, { name: 'protect', level: 17 },
    { name: 'knock-off', level: 20 }, { name: 'taunt', level: 25 },
    { name: 'night-slash', level: 30 }, { name: 'crabhammer', level: 35 },
    { name: 'swords-dance', level: 40 }, { name: 'guillotine', level: 50 }
  ]
}

console.log('--- o mesmo companionId dá sempre o mesmo indivíduo ---')
eq('seed é estável', P.seedFor('a1b2c3'), P.seedFor('a1b2c3'))
ok('ids diferentes dão seeds diferentes', P.seedFor('a1b2c3') !== P.seedFor('a1b2c4'))
eq('IVs estáveis', P.ivsFor(P.seedFor('a1b2c3')), P.ivsFor(P.seedFor('a1b2c3')))
ok('id vazio ainda produz algo determinístico',
   JSON.stringify(P.ivsFor(P.seedFor(''))) === JSON.stringify(P.ivsFor(P.seedFor(''))))

console.log('\n--- IVs: seis valores de 0 a 31 ---')
{
  const ivs = P.ivsFor(P.seedFor('c1'))
  eq('as seis chaves', Object.keys(ivs).sort(),
     ['attack', 'defense', 'hp', 'special-attack', 'special-defense', 'speed'])
  ok('todos na faixa', Object.values(ivs).every(v => Number.isInteger(v) && v >= 0 && v <= 31))
  eq('ivTotal soma os seis', P.ivTotal(ivs),
     Object.values(ivs).reduce((a, b) => a + b, 0))
}
{
  // Mil indivíduos: a distribuição tem de cobrir a faixa, não cair sempre no
  // mesmo valor (um PRNG mal semeado devolve o mesmo primeiro número).
  const primeiros = []
  for (let i = 0; i < 1000; i++) primeiros.push(P.ivsFor(P.seedFor('id' + i)).hp)
  const distintos = new Set(primeiros).size
  ok(`o HP de 1000 indivíduos usa muitos valores (${distintos})`, distintos > 25)
  ok('e chega perto dos extremos',
     Math.min(...primeiros) <= 1 && Math.max(...primeiros) >= 30)
}

console.log('\n--- gênero: gender_rate é oitavos de FÊMEA ---')
eq('−1 é sem gênero', P.genderFor(P.seedFor('c1'), -1), 'genderless')
{
  const rate0 = [], rate8 = []
  for (let i = 0; i < 200; i++) {
    rate0.push(P.genderFor(P.seedFor('m' + i), 0))
    rate8.push(P.genderFor(P.seedFor('m' + i), 8))
  }
  eq('rate 0 é sempre macho', [...new Set(rate0)], ['male'])
  eq('rate 8 é sempre fêmea', [...new Set(rate8)], ['female'])
  // rate 4 é metade a metade; com 200 amostras, longe de 0 e de 200.
  let femeas = 0
  for (let i = 0; i < 200; i++) if (P.genderFor(P.seedFor('m' + i), 4) === 'female') femeas++
  ok(`rate 4 fica perto da metade (${femeas}/200)`, femeas > 60 && femeas < 140)
}
eq('rótulo de gênero', [P.genderLabel('male'), P.genderLabel('female'),
                        P.genderLabel('genderless'), P.genderLabel(null)],
   ['♂ Male', '♀ Female', 'Genderless', '—'])

console.log('\n--- habilidade: a oculta é rara (1/128), como no original ---')
{
  const a = P.abilityFor(P.seedFor('c1'), CORPHISH.abilities)
  ok('devolve uma das da espécie',
     CORPHISH.abilities.some(x => x.name === a.name))
  eq('estável', P.abilityFor(P.seedFor('c1'), CORPHISH.abilities), a)

  let ocultas = 0
  for (let i = 0; i < 2000; i++)
    if (P.abilityFor(P.seedFor('h' + i), CORPHISH.abilities).isHidden) ocultas++
  // 2000/128 ≈ 16 esperadas. A faixa é folgada de propósito: o teste é sobre a
  // ordem de grandeza, não sobre o valor exato de um sorteio.
  ok(`oculta aparece pouco (${ocultas}/2000)`, ocultas > 2 && ocultas < 45)

  eq('espécie sem habilidade nenhuma', P.abilityFor(P.seedFor('c1'), []), null)
  // Só a oculta cadastrada: não há slot normal para cair, e devolver null
  // esconderia a única habilidade que a espécie tem.
  eq('só oculta ainda devolve algo',
     P.abilityFor(P.seedFor('c1'), [{ name: 'x', slot: 3, isHidden: true }]).name, 'x')
}

console.log('\n--- nível: derivado do crescimento, nunca guardado ---')
// 5 é o nível de saída (o do original), 100 a graduação.
const TH = [75000000, 150000000]        // comum de 2 formas em dificuldade 0.3
eq('ovo recém-chocado é nível 5',
   P.levelFor({ thresholds: TH, stage: 0, tokensIntoStage: 0 }), 5)
eq('graduado é 100',
   P.levelFor({ thresholds: TH, stage: 0, tokensIntoStage: 0, graduated: true }), 100)
eq('metade do caminho',
   P.levelFor({ thresholds: TH, stage: 1, tokensIntoStage: 37500000 }),
   5 + Math.floor(95 * (75000000 + 37500000) / 225000000))
eq('no último token antes de graduar, 99 ou 100',
   P.levelFor({ thresholds: TH, stage: 1, tokensIntoStage: 149999999 }) >= 99, true)
eq('nunca passa de 100',
   P.levelFor({ thresholds: TH, stage: 5, tokensIntoStage: 999999999 }), 100)
eq('liberado mostra o nível que o estágio prova',
   P.levelFor({ thresholds: TH, stage: 1, tokensIntoStage: 0 }),
   5 + Math.floor(95 * 75000000 / 225000000))
eq('limiares vazios não estouram',
   P.levelFor({ thresholds: [], stage: 0, tokensIntoStage: 100 }), 5)

console.log('\n--- naturezas: 25, cinco delas neutras ---')
eq('são 25', P.NATURES.length, 25)
eq('naughty sobe ataque', P.natureModifier('naughty', 'attack'), 1.1)
eq('naughty desce defesa especial', P.natureModifier('naughty', 'special-defense'), 0.9)
eq('naughty não mexe no resto', P.natureModifier('naughty', 'speed'), 1)
{
  const neutras = P.NATURES.filter(n =>
    P.STAT_ORDER.every(s => P.natureModifier(n, s) === 1))
  eq('as cinco neutras', neutras, ['hardy', 'docile', 'serious', 'bashful', 'quirky'])
  // Toda natureza não neutra sobe exatamente uma e desce exatamente uma.
  const erradas = P.NATURES.filter(n => {
    const sobe = P.STAT_ORDER.filter(s => P.natureModifier(n, s) === 1.1).length
    const desce = P.STAT_ORDER.filter(s => P.natureModifier(n, s) === 0.9).length
    return !((sobe === 0 && desce === 0) || (sobe === 1 && desce === 1))
  })
  eq('nenhuma natureza mal formada', erradas, [])
}
eq('natureza desconhecida é neutra', P.natureModifier('inventada', 'attack'), 1)
eq('natureza nula é neutra', P.natureModifier(null, 'attack'), 1)
// HP nunca é afetado por natureza na série principal.
eq('nenhuma natureza mexe no HP',
   P.NATURES.filter(n => P.natureModifier(n, 'hp') !== 1), [])

console.log('\n--- stats calculados: a fórmula da série principal ---')
// Corphish nível 50, IV 31 em tudo, natureza naughty (+atq / −def.esp).
// Conferido à mão: HP = floor((2×43+31)×50/100) + 50 + 10 = 58 + 60 = 118.
{
  const ivs = { hp: 31, attack: 31, defense: 31,
                'special-attack': 31, 'special-defense': 31, speed: 31 }
  const s = P.statsFor(CORPHISH.baseStats, ivs, 50, 'naughty')
  const byName = Object.fromEntries(s.map(x => [x.name, x.value]))
  eq('ordem canônica', s.map(x => x.name), P.STAT_ORDER)
  eq('HP', byName.hp, 118)
  eq('ataque com +10%', byName.attack, 110)
  eq('defesa neutra', byName.defense, 85)
  // (2×50+31)×50/100 = 65 (truncado), +5 = 70.
  eq('ataque especial neutro', byName['special-attack'], 70)
  eq('defesa especial com −10%', byName['special-defense'], 49)
  // (2×35+31)×50/100 = 50 (truncado), +5 = 55.
  eq('velocidade neutra', byName.speed, 55)
  eq('a linha carrega base e IV', [s[0].base, s[0].iv], [43, 31])
}
{
  // Nível 5, IV 0: o piso, para conferir que nada fica negativo nem zero.
  const zero = { hp: 0, attack: 0, defense: 0,
                 'special-attack': 0, 'special-defense': 0, speed: 0 }
  const s = P.statsFor(CORPHISH.baseStats, zero, 5, 'hardy')
  ok('todos positivos', s.every(x => x.value > 0))
  eq('HP no nível 5', s[0].value, Math.floor((2 * 43 + 0) * 5 / 100) + 5 + 10)
}
eq('base stats ausentes devolvem lista vazia', P.statsFor(null, {}, 50, 'hardy'), [])
eq('rótulos curtos dos stats',
   P.STAT_ORDER.map(P.statLabel), ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'])

console.log('\n--- golpes: os quatro últimos aprendidos até o nível ---')
eq('nível 5 pega só os de nível 1',
   P.movesFor(CORPHISH.moves, 5).map(m => m.name), ['bubble', 'harden'])
eq('nível 20 pega os quatro últimos',
   P.movesFor(CORPHISH.moves, 20).map(m => m.name),
   ['leer', 'bubblebeam', 'protect', 'knock-off'])
eq('e nunca mais de quatro', P.movesFor(CORPHISH.moves, 100).length, 4)
eq('nível 100 pega os quatro do fim',
   P.movesFor(CORPHISH.moves, 100).map(m => m.name),
   ['night-slash', 'crabhammer', 'swords-dance', 'guillotine'])
eq('ordenados por nível', P.movesFor(CORPHISH.moves, 100).map(m => m.level),
   [30, 35, 40, 50])
eq('golpe acima do nível não entra',
   P.movesFor(CORPHISH.moves, 12).map(m => m.name).includes('bubblebeam'), false)
eq('espécie sem learnset', P.movesFor([], 50), [])
eq('learnset nulo', P.movesFor(null, 50), [])
{
  // O mesmo golpe em dois níveis (acontece na PokéAPI entre version groups):
  // vale o MENOR, que é quando ele foi aprendido.
  const dup = [{ name: 'tackle', level: 1 }, { name: 'tackle', level: 20 }]
  eq('golpe repetido conta uma vez', P.movesFor(dup, 50).map(m => m.name), ['tackle'])
  eq('e pelo nível em que foi aprendido', P.movesFor(dup, 50)[0].level, 1)
}

console.log('\n--- rótulos: slug da PokéAPI virando texto de tela ---')
eq('natureza', P.natureLabel('naughty'), 'Naughty')
eq('natureza ausente é travessão, não vazio', P.natureLabel(null), '—')
eq('habilidade com hífen', P.abilityLabel('hyper-cutter'), 'Hyper Cutter')
eq('habilidade de uma palavra', P.abilityLabel('defiant'), 'Defiant')
eq('golpe com três partes', P.abilityLabel('double-edge'), 'Double Edge')
eq('habilidade ausente', P.abilityLabel(''), '—')

console.log('\n--- escala das barras de stat ---')
// Piso em 300: fixar no teto teórico (255 de base, ~700 calculado) faria todo
// Pokémon de início desenhar barras minúsculas.
eq('piso de 300', P.statScaleMax([{ value: 50 }, { value: 120 }]), 300)
eq('arredonda para a centena acima', P.statScaleMax([{ value: 412 }]), 500)
eq('centena exata fica', P.statScaleMax([{ value: 400 }]), 400)
eq('lista vazia', P.statScaleMax([]), 300)
eq('nulo', P.statScaleMax(null), 300)

console.log('\n--- profileFor junta tudo para a view ---')
{
  const p = P.profileFor(
    { companionId: 'c1', nature: 'naughty' },
    CORPHISH,
    { thresholds: TH, stage: 1, tokensIntoStage: 37500000 })
  eq('nível', p.level, P.levelFor({ thresholds: TH, stage: 1, tokensIntoStage: 37500000 }))
  eq('natureza vem da entrada', p.nature, 'naughty')
  eq('IVs batem com o seed', p.ivs, P.ivsFor(P.seedFor('c1')))
  eq('gênero', p.gender, P.genderFor(P.seedFor('c1'), 4))
  ok('habilidade', p.ability && p.ability.name)
  eq('stats na ordem', p.stats.map(s => s.name), P.STAT_ORDER)
  ok('golpes até o nível', p.moves.every(m => m.level <= p.level))
  eq('sem natureza gravada fica nulo, não inventado',
     P.profileFor({ companionId: 'c1' }, CORPHISH, { thresholds: TH }).nature, null)
  // Sem os dados da espécie (cache ainda não baixado) o perfil existe pela
  // metade em vez de estourar: IVs e nível não dependem de rede.
  const semDetalhes = P.profileFor({ companionId: 'c1', nature: 'bold' }, null,
                                   { thresholds: TH, stage: 0, tokensIntoStage: 0 })
  eq('sem detalhes ainda dá IVs', semDetalhes.ivs, P.ivsFor(P.seedFor('c1')))
  eq('e nível', semDetalhes.level, 5)
  eq('mas sem stats', semDetalhes.stats, [])
  eq('e sem gênero resolvido', semDetalhes.gender, null)
}

console.log(fails ? `\n${fails} FALHA(S)` : '\nTodos os testes passaram')
process.exit(fails ? 1 : 0)
