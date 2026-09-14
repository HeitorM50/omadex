#!/usr/bin/env python3
"""Resiliência: o que acontece quando a rede falha no meio de uma operação.

Esta suíte existe porque todos os outros stubs substituem as chamadas de rede
por lambdas que sempre funcionam — e foi essa lacuna que deixou passar o bug
mais grave do plugin: uma falha de rede na chocagem deixava o estado afirmando
coisas que o companion.json não sustentava.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import urllib.error

PLUGIN = os.path.expanduser(
    '~/.config/omarchy/plugins/io.github.heitorm50.omapkdex/bin/omapkdex-sync')
REAL_USAGE = os.path.expanduser('~/.local/state/omarchy/agents/usage')
MODULE = 'io.github.heitorm50.omapkdex'

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


def sem_rede(*a, **kw):
    raise urllib.error.URLError("rede fora")


class Sandbox:
    def __enter__(self):
        self.dir = tempfile.mkdtemp(prefix='ptb-res-')
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

    def has(self, n):
        return os.path.exists(os.path.join(self.state, n))

    def write(self, n, d):
        with open(os.path.join(self.state, n), 'w', encoding='utf-8') as h:
            json.dump(d, h)

    def bump(self, agent, tokens):
        f = os.path.join(self.usage, f'{agent}.json')
        with open(f, encoding='utf-8') as h:
            d = json.load(h)
        m = d.setdefault('modelUsage', {}).setdefault('t', {})
        m['outputTokens'] = m.get('outputTokens', 0) + tokens
        with open(f, 'w', encoding='utf-8') as h:
            json.dump(d, h)

    def put_state(self, ps, **kw):
        s = dict(ps.DEFAULT_STATE)
        s.update(candySeeded=True)
        s.update(kw)
        self.write('state.json', s)

    def put_companion(self, cid='c1'):
        self.write('companion.json', {
            "schemaVersion": 1, "companionId": cid, "baseSpeciesId": 341,
            "name": "corphish", "rarity": "common", "shiny": False,
            "nature": "jolly", "captureRate": 205, "hatchedAt": 1000,
            "dittoDisguise": False, "dittoRevealed": False,
            "evolutionLine": [{"id": 341, "name": "corphish", "sprite": "/s/341.gif"},
                              {"id": 342, "name": "crawdaunt", "sprite": "/s/342.gif"}],
        })

    def ids(self, ps):
        return [e['companionId'] for e in ps.load_collection()['entries']]

    def abertas(self, ps):
        return [e for e in ps.load_collection()['entries']
                if e.get('graduatedAt') is None and e.get('releasedAt') is None]


def rodar(fn, *a):
    """Roda e devolve o código, tratando exceção como o main() do helper trata."""
    try:
        return fn(*a)
    except Exception:
        return 1


# ---------------------------------------------------------------------------

print("--- 1. primeira chocagem falha: nada de graduação fantasma ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_state(ps)
    ps.cmd_absorb(['0.3'])                  # marca a régua
    sb.bump('claude', 2_000_000)            # > 1.5M do limiar do ovo
    ps.load_index = sem_rede
    rodar(ps.cmd_absorb, ['0.3'])

    sb.bump('claude', 900_000_000)          # uso pesado, rede ainda fora
    rodar(ps.cmd_absorb, ['0.3'])
    s = sb.read('state.json')
    eq("não graduou nada", s['graduations'], 0)
    eq("coleção vazia", len(ps.load_collection()['entries']), 0)
    eq("sem companion, não fica marcado como chocado", s['hatched'], False)
    eq("o progresso não é perdido", s['tokensIntoStage'] > 0, True)

print("\n--- 2. graduação com chocagem falhando: sem entrada duplicada ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion('g1')
    sb.put_state(ps, hatched=True, stage=1)
    col = ps.empty_collection()
    ps.sync_open_entry(col, sb.read('companion.json'), 1100)
    ps.record_stage(col, 1)
    ps.save_collection(col)

    ps.cmd_absorb(['0.3'])                  # régua
    sb.bump('claude', 160_000_000)          # > 150M do estágio 1 -> gradua
    ps.load_index = sem_rede
    rodar(ps.cmd_absorb, ['0.3'])
    eq("graduou uma vez", sb.read('state.json')['graduations'], 1)
    eq("uma entrada, fechada", len(sb.ids(ps)), 1)

    # a absorção seguinte não pode ressuscitar o graduado
    sb.bump('claude', 10_000_000)
    rodar(ps.cmd_absorb, ['0.3'])
    ids = sb.ids(ps)
    eq("ainda uma entrada", len(ids), 1)
    eq("sem companionId duplicado", len(ids), len(set(ids)))
    eq("nenhuma entrada aberta (é ovo)", len(sb.abertas(ps)), 0)

print("\n--- 3. compra de ovo com pré-sorteio falhando ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion('e1')
    sb.put_state(ps, hatched=True, stage=1, tokensIntoStage=40_000_000,
                 lifetimeTokens=5_000_000_000)
    col = ps.empty_collection()
    ps.sync_open_entry(col, sb.read('companion.json'), 1100)
    ps.record_stage(col, 1)
    ps.save_collection(col)

    ps.load_index = sem_rede
    rodar(ps.cmd_buy, ['egg', '1.0', 'rare'])
    s = sb.read('state.json')
    eq("cobrou o ovo raro", s['spentTokens'], 4_000_000_000)
    eq("o grau pago sobrevive para a próxima tentativa", s['eggTier'], 'rare')
    eq("voltou a ser ovo", s['hatched'], False)
    eq("companion do descartado não fica para trás", sb.has('companion.json'), False)

    e = ps.load_collection()['entries'][0]
    eq("a entrada foi liberada", e['releasedAt'] is not None, True)
    eq("e não graduada", e['graduatedAt'], None)

    # e a absorção seguinte não recria o liberado
    sb.bump('claude', 5_000_000)
    rodar(ps.cmd_absorb, ['0.3'])
    ids = sb.ids(ps)
    eq("uma entrada só", len(ids), 1)
    eq("sem duplicata", len(ids), len(set(ids)))

print("\n--- 4. sync_open_entry nunca reabre um companionId conhecido ---")
ps_m = load_helper()
comp = {"companionId": "x1", "baseSpeciesId": 341, "name": "corphish",
        "rarity": "common", "shiny": False, "hatchedAt": 1,
        "evolutionLine": [{"id": 341, "name": "corphish", "sprite": ""},
                          {"id": 342, "name": "crawdaunt", "sprite": ""}]}
for estado, campo in (("graduada", "graduatedAt"), ("liberada", "releasedAt")):
    col = ps_m.empty_collection()
    ps_m.sync_open_entry(col, comp, 100)
    col['entries'][0][campo] = 500
    eq(f"entrada {estado} não é reaberta", ps_m.sync_open_entry(col, comp, 900), False)
    eq(f"segue com uma entrada ({estado})", len(col['entries']), 1)

print("\n--- 5. advance_stages não roda sem companion ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_state(ps, hatched=True, stage=0, tokensIntoStage=0)   # sem companion.json
    ps.cmd_absorb(['0.3'])
    sb.bump('claude', 900_000_000)
    ps.load_index = sem_rede
    rodar(ps.cmd_absorb, ['0.3'])
    s = sb.read('state.json')
    eq("não graduou", s['graduations'], 0)
    eq("estágio intocado", s['stage'], 0)

print("\n--- 6. o lock não pendura uma compra para sempre ---")
with Sandbox() as sb:
    import fcntl
    ps = load_helper()
    sb.put_companion()
    sb.put_state(ps, hatched=True, lifetimeTokens=5_000_000_000)
    os.makedirs(ps.state_dir(), exist_ok=True)
    trava = open(ps.lock_path(), 'w')
    fcntl.flock(trava, fcntl.LOCK_EX)
    import time as _t
    t0 = _t.monotonic()
    rc = ps.cmd_buy(['mint', '1.0'])
    gasto = _t.monotonic() - t0
    eq("devolve erro em vez de pendurar", rc, 1)
    eq(f"desiste rápido ({gasto:.1f}s)", gasto < 15, True)
    eq("não cobrou", sb.read('state.json')['spentTokens'], 0)
    fcntl.flock(trava, fcntl.LOCK_UN); trava.close()
    eq("com o lock livre, compra normalmente", ps.cmd_buy(['mint', '1.0']), 0)

print("\n--- 7. o disfarce do Ditto vai para a entrada da coleção ---")
ps_m = load_helper()
disf = dict(comp, companionId="d1", shiny=True,
            dittoDisguise=True, dittoRevealed=False)
e = ps_m.entry_from_companion(disf, now=1)
eq("guarda que está disfarçado", e['dittoDisguise'], True)
eq("guarda que não revelou", e['dittoRevealed'], False)
eq("o shiny bruto é preservado (ele É shiny)", e['shiny'], True)
e2 = ps_m.entry_from_companion(dict(comp, companionId="d2"), now=1)
eq("companion normal marca falso", e2['dittoDisguise'], False)

print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
