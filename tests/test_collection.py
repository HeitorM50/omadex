#!/usr/bin/env python3
"""Coleção (catch log) e sorteio de shiny.

Funções puras: sem rede e sem tocar no estado real. O teste de ponta a ponta
que realmente chama a PokéAPI vive em test_absorb.py.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile

PLUGIN = os.path.expanduser(
    '~/.config/omarchy/plugins/io.github.heitorm50.poketokenbar/bin/poke-sync')

fails = 0


def eq(label, got, want):
    global fails
    ok = got == want
    if not ok:
        fails += 1
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}"
          + ("" if ok else f"  (esperado {want!r})"))


def load_helper():
    loader = importlib.machinery.SourceFileLoader('ps', PLUGIN)
    spec = importlib.util.spec_from_loader('ps', loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class FakeRandom:
    """random.Random com randrange determinístico, para fixar o sorteio."""

    def __init__(self, value):
        self.value = value
        self.calls = 0

    def randrange(self, n):
        self.calls += 1
        self.bound = n
        return self.value


def companion(species_id=341, name='corphish', rarity='common',
              shiny=False, line=None, hatched_at=1000):
    line = line or [(341, 'corphish'), (342, 'crawdaunt')]
    return {
        'schemaVersion': 1,
        'baseSpeciesId': species_id,
        'name': name,
        'rarity': rarity,
        'shiny': shiny,
        'captureRate': 205,
        'evolutionLine': [{'id': i, 'name': n, 'sprite': f'/s/{i}.gif'}
                          for i, n in line],
        'hatchedAt': hatched_at,
    }


ps = load_helper()

print("--- sorteio de shiny (1 em 64) ---")
eq("rng 0 -> shiny", ps.roll_shiny(FakeRandom(0)), True)
eq("rng 1 -> normal", ps.roll_shiny(FakeRandom(1)), False)
eq("rng 63 -> normal", ps.roll_shiny(FakeRandom(63)), False)
r = FakeRandom(0)
ps.roll_shiny(r)
eq("sorteia sobre SHINY_RATE", r.bound, ps.SHINY_RATE)
eq("a taxa é 1 em 64", ps.SHINY_RATE, 64)

print("\n--- distribuição do sorteio em 200k tentativas ---")
import random as _random
rng = _random.Random(20260913)
hits = sum(1 for _ in range(200_000) if ps.roll_shiny(rng))
rate = hits / 200_000
eq("perto de 1/64 (0.0140-0.0173)", 0.0140 < rate < 0.0173, True)
print(f"     taxa observada: 1 em {200_000/hits:.1f}")

print("\n--- caminhos de sprite ---")
normal = ps.sprite_urls(341, shiny=False)
shiny = ps.sprite_urls(341, shiny=True)
eq("normal tenta o gif animado primeiro", '/animated/341.gif' in normal[0][0], True)
eq("normal cai para o png", normal[1][0].endswith('/341.png'), True)
eq("shiny usa a pasta shiny animada", '/animated/shiny/341.gif' in shiny[0][0], True)
eq("shiny cai para o png shiny", shiny[1][0].endswith('/shiny/341.png'), True)
eq("shiny e normal têm cache distinto", ps.sprite_cache_name(341, 'gif', True)
   != ps.sprite_cache_name(341, 'gif', False), True)

print("\n--- entrada da coleção a partir do companion ---")
entry = ps.entry_from_companion(companion(shiny=True), now=1234)
eq("espécie", entry['speciesId'], 341)
eq("nome", entry['name'], 'corphish')
eq("raridade", entry['rarity'], 'common')
eq("shiny", entry['shiny'], True)
# A linha guarda a forma inteira, não só o id: o Pokédex precisa nomear e
# desenhar espécies que nunca foram forma base de nada (um Crawdaunt não aparece
# no índice de chocagem), e não há de onde buscar isso depois.
eq("linha guarda id, nome e sprite",
   entry['line'], [{'id': 341, 'name': 'corphish', 'sprite': '/s/341.gif'},
                   {'id': 342, 'name': 'crawdaunt', 'sprite': '/s/342.gif'}])
eq("formas sem id são descartadas",
   ps.entry_from_companion(
       {'evolutionLine': [{'name': 'sem id'}, {'id': 7, 'name': 'squirtle'}]},
       now=1)['line'],
   [{'id': 7, 'name': 'squirtle', 'sprite': ''}])
eq("nasce aberta", entry['graduatedAt'], None)
eq("começa no estágio 0", entry['finalStage'], 0)
eq("guarda a data de chocagem do companion", entry['hatchedAt'], 1000)

print("\n--- sync_open_entry mantém exatamente uma entrada aberta ---")
col = ps.empty_collection()
c = companion(hatched_at=1000)
eq("primeira sync abre a entrada", ps.sync_open_entry(col, c, now=1100), True)
eq("uma entrada", len(col['entries']), 1)
eq("segunda sync não duplica", ps.sync_open_entry(col, c, now=1200), False)
eq("continua com uma", len(col['entries']), 1)

print("\n--- companion trocado sem graduar fecha a entrada anterior ---")
col = ps.empty_collection()
ps.sync_open_entry(col, companion(hatched_at=1000), now=1100)
ps.sync_open_entry(col, companion(species_id=25, name='pikachu',
                                  line=[(25, 'pikachu')], hatched_at=2000), now=2100)
eq("duas entradas", len(col['entries']), 2)
eq("a antiga foi fechada", col['entries'][0]['graduatedAt'], 2100)
eq("a nova está aberta", col['entries'][1]['graduatedAt'], None)
eq("só uma aberta", sum(1 for e in col['entries'] if e['graduatedAt'] is None), 1)

print("\n--- avanço de estágio é registrado na entrada aberta ---")
col = ps.empty_collection()
ps.sync_open_entry(col, companion(hatched_at=1000), now=1100)
ps.record_stage(col, 1)
eq("finalStage sobe", col['entries'][0]['finalStage'], 1)
ps.record_stage(col, 0)
eq("nunca regride", col['entries'][0]['finalStage'], 1)

print("\n--- graduação fecha a entrada no último estágio ---")
col = ps.empty_collection()
ps.sync_open_entry(col, companion(hatched_at=1000), now=1100)
eq("fecha e devolve True", ps.close_open_entry(col, now=5000, final_stage=1), True)
eq("graduatedAt gravado", col['entries'][0]['graduatedAt'], 5000)
eq("finalStage final", col['entries'][0]['finalStage'], 1)
eq("fechar de novo é no-op", ps.close_open_entry(col, now=6000, final_stage=1), False)

print("\n--- migração: companion v1 sem o campo shiny ---")
legacy = companion()
del legacy['shiny']
entry = ps.entry_from_companion(legacy, now=1234)
eq("shiny ausente lê como False", entry['shiny'], False)

print("\n--- coleção corrompida não derruba o helper ---")
with tempfile.TemporaryDirectory() as d:
    old = os.environ.get('XDG_STATE_HOME')
    os.environ['XDG_STATE_HOME'] = d
    try:
        os.makedirs(ps.state_dir(), exist_ok=True)
        with open(ps.collection_path(), 'w') as h:
            h.write('{ isso não é json')
        col = ps.load_collection()
        eq("volta uma coleção vazia", col['entries'], [])
        with open(ps.collection_path(), 'w') as h:
            h.write('[]')
        eq("json válido do tipo errado também", ps.load_collection()['entries'], [])
    finally:
        if old is None:
            os.environ.pop('XDG_STATE_HOME', None)
        else:
            os.environ['XDG_STATE_HOME'] = old

print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
