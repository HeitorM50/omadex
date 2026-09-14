#!/usr/bin/env python3
"""Ditto disfarçado: o easter egg.

1 em 128 chocagens comuns de linha com 2+ formas é secretamente um Ditto. Ele
se revela no lugar da primeira evolução. Enquanto disfarçado, o shiny fica
escondido — é a parte fácil de errar.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile

PLUGIN = os.path.expanduser(
    '~/.config/omarchy/plugins/io.github.heitorm50.poketokenbar/bin/poke-sync')
REAL_USAGE = os.path.expanduser('~/.local/state/omarchy/agents/usage')
MODULE = 'io.github.heitorm50.poketokenbar'

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


class Sandbox:
    def __enter__(self):
        self.dir = tempfile.mkdtemp(prefix='ptb-ditto-')
        self.old = os.environ.get('XDG_STATE_HOME')
        os.environ['XDG_STATE_HOME'] = self.dir
        self.usage = os.path.join(self.dir, 'omarchy', 'agents', 'usage')
        os.makedirs(self.usage)
        self.state = os.path.join(self.dir, 'omarchy', MODULE)
        os.makedirs(self.state)
        for f in os.listdir(REAL_USAGE):
            shutil.copy(os.path.join(REAL_USAGE, f), self.usage)
        return self

    def __exit__(self, *a):
        if self.old is None:
            os.environ.pop('XDG_STATE_HOME', None)
        else:
            os.environ['XDG_STATE_HOME'] = self.old
        shutil.rmtree(self.dir, ignore_errors=True)

    def read(self, n):
        with open(os.path.join(self.state, n), encoding='utf-8') as h:
            return json.load(h)

    def write(self, n, d):
        with open(os.path.join(self.state, n), 'w', encoding='utf-8') as h:
            json.dump(d, h)

    def bump(self, agent, tokens):
        """Soma tokens ao record, para o absorb ter delta real de verdade."""
        f = os.path.join(self.usage, f'{agent}.json')
        with open(f, encoding='utf-8') as h:
            d = json.load(h)
        m = d.setdefault('modelUsage', {}).setdefault('test-model', {})
        m['outputTokens'] = m.get('outputTokens', 0) + tokens
        with open(f, 'w', encoding='utf-8') as h:
            json.dump(d, h)

    def marcar_regua(self, ps):
        """Roda um absorb só para fixar lastSeen, sem conceder nada."""
        ps.cmd_absorb(['0.3'])

    def put_state(self, **kw):
        s = {"schemaVersion": 1, "lifetimeTokens": 0, "lastSeen": {}, "stage": 0,
             "tokensIntoStage": 0, "hatched": False, "graduations": 0,
             "spentTokens": 0, "inventory": {}, "candyWindows": {},
             "candySeeded": True, "eggTier": None}
        s.update(kw)
        self.write('state.json', s)


ps_mod = load_helper()

print("--- a condição do disfarce ---")
eq("denominador", ps_mod.DITTO_RATE, 128)
eq("Ditto é a espécie 132", ps_mod.DITTO_SPECIES_ID, 132)


class Roll:
    """rng com randrange fixo, para decidir o sorteio."""
    def __init__(self, v):
        self.v = v

    def randrange(self, n):
        self.bound = n
        return self.v


eq("comum com 2 formas e sorteio 0 -> disfarça",
   ps_mod.roll_ditto("common", 2, Roll(0)), True)
eq("sorteio 1 -> não", ps_mod.roll_ditto("common", 2, Roll(1)), False)
eq("linha de 1 forma nunca disfarça",
   ps_mod.roll_ditto("common", 1, Roll(0)), False)
eq("incomum não disfarça", ps_mod.roll_ditto("uncommon", 2, Roll(0)), False)
eq("raro não disfarça", ps_mod.roll_ditto("rare", 3, Roll(0)), False)
eq("lendário não disfarça", ps_mod.roll_ditto("legendary", 2, Roll(0)), False)
r = Roll(0)
ps_mod.roll_ditto("common", 2, r)
eq("sorteia sobre DITTO_RATE", r.bound, 128)

# A regra "shiny escondido enquanto disfarçado" é de exibição, então vive onde é
# aplicada: em Collection.js (projeção do dex e do histórico) e no BarWidget
# (que lê o companion direto). Coberta em tests/test_dex.mjs.

print("\n--- a chocagem grava o disfarce ---")


def stub(ps, rate=205, species=((341, 'corphish'), (342, 'crawdaunt'))):
    ps.load_index = lambda **kw: [{'id': species[0][0], 'name': species[0][1],
                                  'captureRate': rate, 'isLegendary': False,
                                  'isMythical': False}]
    ps.evolution_line = lambda base_id: [{'id': i, 'name': n} for i, n in species]
    ps.hydrate_sprites = lambda forms, shiny=False: [
        dict(f, sprite=f"/fake/{f['id']}.gif") for f in forms]
    return ps


with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: True
    ps.roll_shiny = lambda rng=None, denominator=64: False
    sb.put_state()
    ps.cmd_hatch([])
    c = sb.read('companion.json')
    eq("disfarce gravado", c['dittoDisguise'], True)
    eq("ainda não revelado", c.get('dittoRevealed', False), False)
    eq("a espécie visível é a do disfarce", c['baseSpeciesId'], 341)

print("\n--- a revelação acontece no lugar da primeira evolução ---")
with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: True
    ps.roll_shiny = lambda rng=None, denominator=64: True     # shiny escondido
    sb.put_state()
    ps.cmd_hatch([])
    disfarce = sb.read('companion.json')
    eq("chocou disfarçado e shiny", (disfarce['dittoDisguise'], disfarce['shiny']),
       (True, True))
    eq("o disfarce está registrado", disfarce['dittoDisguise'], True)

    # A linha do Ditto: uma forma só.
    ps.evolution_line = lambda base_id: [{'id': 132, 'name': 'ditto'}]
    ps.load_index = lambda **kw: [{'id': 132, 'name': 'ditto', 'captureRate': 35,
                                   'isLegendary': False, 'isMythical': False}]

    # Marca a régua, depois entrega um delta REAL que cruza o limiar: o absorb
    # só roda a progressão quando há tokens novos, como o original.
    sb.marcar_regua(ps)
    sb.put_state(hatched=True, stage=0, tokensIntoStage=70_000_000,
                 lastSeen=sb.read('state.json')['lastSeen'],
                 candySeeded=True)
    sb.bump('claude', 10_000_000)     # 70M + 10M = 80M > 75M do estágio 0
    ps.cmd_absorb(['0.3'])

    c = sb.read('companion.json')
    s = sb.read('state.json')
    eq("revelou-se Ditto", c['baseSpeciesId'], 132)
    eq("marcado como revelado", c['dittoRevealed'], True)
    eq("o shiny sobreviveu", c['shiny'], True)
    eq("e consta revelado", c['dittoRevealed'], True)
    eq("linha de uma forma", len(c['evolutionLine']), 1)
    eq("raridade recalculada (capture_rate 35 = rare)", c['rarity'], 'rare')
    eq("voltou ao estágio 0 da linha nova", s['stage'], 0)
    eq("o excedente da evolução foi carregado", s['tokensIntoStage'], 5_000_000)

print("\n--- a nature sobrevive à revelação ---")
with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: True
    ps.roll_shiny = lambda rng=None, denominator=64: False
    sb.put_state()
    ps.cmd_hatch([])
    nature = sb.read('companion.json')['nature']
    ps.evolution_line = lambda base_id: [{'id': 132, 'name': 'ditto'}]
    ps.load_index = lambda **kw: [{'id': 132, 'name': 'ditto', 'captureRate': 35,
                                   'isLegendary': False, 'isMythical': False}]
    sb.marcar_regua(ps)
    sb.put_state(hatched=True, stage=0, tokensIntoStage=70_000_000,
                 lastSeen=sb.read('state.json')['lastSeen'], candySeeded=True)
    sb.bump('claude', 10_000_000)
    ps.cmd_absorb(['0.3'])
    eq("mesma nature", sb.read('companion.json')['nature'], nature)

print("\n--- um companion normal não é afetado ---")
with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: False
    ps.roll_shiny = lambda rng=None, denominator=64: False
    sb.put_state()
    ps.cmd_hatch([])
    eq("sem disfarce", sb.read('companion.json')['dittoDisguise'], False)
    sb.marcar_regua(ps)
    sb.put_state(hatched=True, stage=0, tokensIntoStage=70_000_000,
                 lastSeen=sb.read('state.json')['lastSeen'], candySeeded=True)
    sb.bump('claude', 10_000_000)
    ps.cmd_absorb(['0.3'])
    c = sb.read('companion.json')
    eq("evoluiu normalmente, sem virar Ditto", c['baseSpeciesId'], 341)
    eq("estágio 1", sb.read('state.json')['stage'], 1)

print("\n--- a revelação não gradua a espécie do disfarce ---")
with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: True
    ps.roll_shiny = lambda rng=None, denominator=64: False
    sb.put_state()
    ps.cmd_hatch([])
    ps.evolution_line = lambda base_id: [{'id': 132, 'name': 'ditto'}]
    ps.load_index = lambda **kw: [{'id': 132, 'name': 'ditto', 'captureRate': 35,
                                   'isLegendary': False, 'isMythical': False}]
    sb.marcar_regua(ps)
    sb.put_state(hatched=True, stage=0, tokensIntoStage=70_000_000,
                 lastSeen=sb.read('state.json')['lastSeen'], candySeeded=True)
    sb.bump('claude', 10_000_000)
    ps.cmd_absorb(['0.3'])
    eq("nenhuma graduação", sb.read('state.json')['graduations'], 0)
    col = sb.read('collection.json')
    abertas = [e for e in col['entries'] if e['graduatedAt'] is None
               and e.get('releasedAt') is None]
    eq("uma entrada aberta só", len(abertas), 1)
    eq("a entrada aberta agora é do Ditto", abertas[0]['speciesId'], 132)

print("\n--- a revelação libera o ✨ na entrada da coleção ---")
with Sandbox() as sb:
    ps = stub(load_helper())
    ps.roll_ditto = lambda rarity, forms, rng=None: True
    ps.roll_shiny = lambda rng=None, denominator=64: True
    sb.put_state()
    ps.cmd_hatch([])
    e = ps.load_collection()['entries'][0]
    eq("entrada nasce disfarçada", e['dittoDisguise'], True)
    eq("e não revelada", e['dittoRevealed'], False)
    eq("com o shiny bruto guardado", e['shiny'], True)

    ps.evolution_line = lambda b: [{'id': 132, 'name': 'ditto'}]
    ps.load_index = lambda **kw: [{'id': 132, 'name': 'ditto', 'captureRate': 35,
                                   'isLegendary': False, 'isMythical': False}]
    sb.marcar_regua(ps)
    sb.put_state(hatched=True, stage=0, tokensIntoStage=70_000_000,
                 lastSeen=sb.read('state.json')['lastSeen'], candySeeded=True)
    sb.bump('claude', 10_000_000)
    ps.cmd_absorb(['0.3'])

    e = ps.load_collection()['entries'][0]
    eq("a entrada passa a constar revelada", e['dittoRevealed'], True)
    eq("o disfarce continua registrado (é a história dele)", e['dittoDisguise'], True)
    eq("shiny preservado", e['shiny'], True)


print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
