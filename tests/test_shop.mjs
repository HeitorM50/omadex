#!/usr/bin/env node
// Lógica de exibição da loja e da bag.
//
// Carrega o Balance.js real (tirando o `.pragma library`, sintaxe de QML) para
// não haver uma segunda cópia dos preços aqui — eles têm de sair do mesmo lugar
// que o painel usa.

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir, homedir } from 'node:os'
import { join } from 'node:path'

const PLUGIN = join(homedir(), '.config/omarchy/plugins/io.github.heitorm50.poketokenbar')

const dir = mkdtempSync(join(tmpdir(), 'ptb-shop-'))
const shim = join(dir, 'balance.mjs')
writeFileSync(shim,
  readFileSync(join(PLUGIN, 'Balance.js'), 'utf8').replace(/^\.pragma library\s*/m, '')
  + '\nexport { shopEntries, bagEntries, availableTokens, shopPrice, eggPrice, itemLabel, burnTier, mood, moodLabel, barTooltip, phaseThreshold, progress };\n')
const B = await import(shim)

let fails = 0
const eq = (label, got, want) => {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  const ok = g === w
  if (!ok) fails++
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}: ${g}${ok ? '' : `  (esperado ${w})`}`)
}

console.log('--- carteira ---')
eq('saldo', B.availableTokens({ lifetimeTokens: 1000, spentTokens: 400 }), 600)
eq('nunca negativo', B.availableTokens({ lifetimeTokens: 10, spentTokens: 99 }), 0)
eq('estado nulo', B.availableTokens(null), 0)

console.log('\n--- preços batem com os do helper ---')
eq('mint', B.shopPrice('mint', 1), 100000000)
eq('rareCandy', B.shopPrice('rareCandy', 1), 500000000)
eq('shinyCharm', B.shopPrice('shinyCharm', 1), 3000000000)
eq('ovo simples', B.eggPrice(null), 1000000000)
eq('ovo incomum', B.eggPrice('uncommon'), 2500000000)
eq('ovo raro', B.eggPrice('rare'), 4000000000)
eq('a dificuldade da loja escala', B.shopPrice('rareCandy', 2), 1000000000)

console.log('\n--- a loja é uma lista única em ordem de preço ---')
const lista = B.shopEntries({}, 1)
eq('ordem crescente de preço', lista.map(e => e.price),
   [100000000, 500000000, 1000000000, 2500000000, 3000000000, 4000000000])
eq('as chaves na ordem', lista.map(e => e.key),
   ['mint', 'rareCandy', 'egg:', 'egg:uncommon', 'shinyCharm', 'egg:rare'])

console.log('\n--- o passivo já comprado vai para o fim ---')
const comCharm = B.shopEntries({ shinyCharm: true }, 1)
eq('shinyCharm no fim', comCharm[comCharm.length - 1].key, 'shinyCharm')
eq('marcado como possuído', comCharm[comCharm.length - 1].owned, true)
eq('os outros seguem em ordem', comCharm.slice(0, -1).map(e => e.key),
   ['mint', 'rareCandy', 'egg:', 'egg:uncommon', 'egg:rare'])

console.log('\n--- affordable depende do saldo ---')
const pobre = B.shopEntries({}, 1, 200000000)
eq('mint cabe', pobre.find(e => e.key === 'mint').affordable, true)
eq('candy não cabe', pobre.find(e => e.key === 'rareCandy').affordable, false)
const rico = B.shopEntries({}, 1, 99000000000)
eq('tudo cabe', rico.every(e => e.affordable || e.owned), true)

console.log('\n--- a bag lista só o que se tem ---')
eq('vazia', B.bagEntries({}), [])
eq('uma candy', B.bagEntries({ rareCandy: 1 }).map(e => [e.key, e.count]),
   [['rareCandy', 1]])
const bag = B.bagEntries({ rareCandy: 3, mint: 1, shinyCharm: true })
eq('ordem estável', bag.map(e => e.key), ['rareCandy', 'mint', 'shinyCharm'])
eq('o passivo não tem contagem', bag.find(e => e.key === 'shinyCharm').count, null)
eq('o passivo é marcado', bag.find(e => e.key === 'shinyCharm').passive, true)
eq('contagem zero não aparece', B.bagEntries({ rareCandy: 0 }), [])
eq('charm falso não aparece', B.bagEntries({ shinyCharm: false }), [])

console.log('\n--- rótulos e usabilidade ---')
eq('candy tem rótulo', B.itemLabel('rareCandy').length > 0, true)
eq('ovo simples', B.itemLabel('egg:').length > 0, true)
eq('ovo raro difere do simples', B.itemLabel('egg:rare') !== B.itemLabel('egg:'), true)
eq('candy é usável', B.bagEntries({ rareCandy: 1 })[0].usable, true)
eq('charm não é usável',
   B.bagEntries({ shinyCharm: true }).find(e => e.key === 'shinyCharm').usable, false)

console.log('\n--- dados malformados não derrubam ---')
eq('inventário nulo na loja', B.shopEntries(null, 1).length, 6)
eq('inventário nulo na bag', B.bagEntries(null), [])
eq('dificuldade absurda é clampeada', B.shopPrice('mint', 999), 200000000)
eq('dificuldade NaN cai no padrão', B.shopPrice('mint', NaN), 100000000)

console.log('\n--- tiers de queima, os cortes do original ---')
eq('1000 ainda é ocioso', B.burnTier(1000), 'idle')
eq('1001 é normal', B.burnTier(1001), 'normal')
eq('99999 é normal', B.burnTier(99999), 'normal')
eq('100000 é rápido', B.burnTier(100000), 'fast')
eq('399999 é rápido', B.burnTier(399999), 'fast')
eq('400000 é blazing', B.burnTier(400000), 'blazing')
eq('zero é ocioso', B.burnTier(0), 'idle')
eq('nulo é ocioso', B.burnTier(null), 'idle')

console.log('\n--- humor, por prioridade ---')
const st = (o = {}) => ({ hatched: true, burnRate: 0, ...o })

eq('sem chocar é ovo', B.mood(st({ hatched: false }), 0, 0), 'egg')
eq('evento recente ganha de tudo',
   B.mood(st({ burnRate: 999999 }), 0, 0.99, true), 'levelUp')
eq('limite alto deixa cansado', B.mood(st({ burnRate: 200000 }), 5e6, 0.95), 'tired')
eq('sem uso hoje é sono', B.mood(st(), 0, 0.1), 'sleep')
eq('ocioso com uso hoje', B.mood(st({ burnRate: 10 }), 5e6, 0.1), 'idle')
eq('trabalhando', B.mood(st({ burnRate: 50000 }), 5e6, 0.1), 'working')
eq('focado', B.mood(st({ burnRate: 200000 }), 5e6, 0.1), 'focus')
eq('blazing também é focado', B.mood(st({ burnRate: 900000 }), 5e6, 0.1), 'focus')
eq('estado nulo', B.mood(null, 0, 0), 'egg')

console.log('\n--- o limite só cansa a partir de 90% ---')
eq('89% não cansa', B.mood(st({ burnRate: 10 }), 5e6, 0.89), 'idle')
eq('90% cansa', B.mood(st({ burnRate: 10 }), 5e6, 0.90), 'tired')

console.log('\n--- todo humor tem rótulo ---')
for (const m of ['egg', 'idle', 'working', 'focus', 'tired', 'sleep', 'levelUp'])
  eq(`rótulo de ${m}`, B.moodLabel(m).length > 0, true)

console.log('\n--- tooltip do bar: sem espécie fixada ---')
const semPin = B.barTooltip({
  hatched: true, companionName: 'Crawdaunt', rarity: 'common',
  stage: 1, totalForms: 2, remaining: 41700000, isFinalStage: true,
  pinnedName: '', todayTokens: 64300000
})
eq('abre com o companion', semPin.split('\n')[0], 'Crawdaunt')
eq('não menciona fixado', semPin.indexOf('fixado') === -1, true)
eq('tem o estágio', semPin.indexOf('estágio 2/2') !== -1, true)

console.log('\n--- tooltip do bar: COM espécie fixada ---')
// O bug: o bar mostrava o nome da fixada com o estágio do companion real, e
// "Corphish · estágio 2/2" é contradição — o Corphish É o estágio 1.
const comPin = B.barTooltip({
  hatched: true, companionName: 'Crawdaunt', rarity: 'common',
  stage: 1, totalForms: 2, remaining: 41700000, isFinalStage: true,
  pinnedName: 'Corphish', todayTokens: 64300000
})
const linhas = comPin.split('\n')
eq('a primeira linha diz que é fixada', linhas[0], 'Corphish ★ fixado no bar')
// O separador é "  ·  " (espaço duplo), como no resto do painel.
eq('o estágio é atribuído ao companion, não à fixada',
   linhas[1], 'Companion: Crawdaunt  ·  Comum  ·  estágio 2/2')
eq('a fixada NUNCA aparece colada num estágio',
   /Corphish[^\n]*estágio/.test(comPin), false)
eq('o progresso continua visível', comPin.indexOf('41.7M') !== -1, true)

console.log('\n--- tooltip do bar: ovo ---')
const ovo = B.barTooltip({
  hatched: false, companionName: 'Ovo', rarity: 'common',
  stage: 0, totalForms: 2, hatchRemaining: 1500000,
  pinnedName: '', todayTokens: 0
})
eq('fala de chocar', ovo.indexOf('até chocar') !== -1, true)
eq('sem estágio', ovo.indexOf('estágio') === -1, true)

console.log('\n--- tooltip do bar: ovo com espécie fixada ---')
const ovoPin = B.barTooltip({
  hatched: false, companionName: 'Ovo', rarity: 'common',
  stage: 0, totalForms: 1, hatchRemaining: 1500000,
  pinnedName: 'Pikachu', todayTokens: 0
})
eq('diz que é fixada', ovoPin.split('\n')[0], 'Pikachu ★ fixado no bar')
eq('e que o companion é um ovo',
   ovoPin.indexOf('Companion: Ovo') !== -1, true)

console.log('\n--- tooltip do bar: dados faltando não quebram ---')
eq('objeto vazio devolve string', typeof B.barTooltip({}), 'string')
eq('nulo devolve string', typeof B.barTooltip(null), 'string')

console.log('\n--- o limiar exibido respeita o bônus de 2x ---')
// O bug: o helper divide o limiar pelo multiplicador quando a linha já graduou,
// mas a UI não recebia o parâmetro — então mostrava o dobro do que falta, e o
// Pokémon evoluía com a barra pela metade.
eq('sem bônus', B.phaseThreshold('common', 2, 0, 0.3, 1), 75000000)
eq('com bônus 2x', B.phaseThreshold('common', 2, 0, 0.3, 2), 37500000)
eq('multiplicador ausente = sem bônus', B.phaseThreshold('common', 2, 0, 0.3), 75000000)
eq('bônus em linha de 3 formas', B.phaseThreshold('rare', 3, 2, 1, 2), 750000000)

console.log('\n--- progress() propaga o bônus ---')
const semB = B.progress('common', 2, 0, 37500000, 0.3, 1)
const comB = B.progress('common', 2, 0, 37500000, 0.3, 2)
eq('sem bônus está na metade', semB.fraction, 0.5)
eq('com bônus está cheio', comB.fraction, 1)
eq('com bônus não falta nada', comB.remaining, 0)
eq('com bônus está completo', comB.complete, true)
eq('o limiar exibido é o do bônus', comB.threshold, 37500000)

console.log(fails ? `\n${fails} FALHA(S)` : '\nTodos os testes passaram')
process.exit(fails ? 1 : 0)
