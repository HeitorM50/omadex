#!/usr/bin/env python3
"""Testa cmd_absorb contra os records reais, num XDG_STATE_HOME temporário."""
import importlib.machinery, importlib.util, json, os, shutil, tempfile

PLUGIN = os.path.expanduser('~/.config/omarchy/plugins/io.github.heitorm50.poketokenbar/bin/poke-sync')
REAL = os.path.expanduser('~/.local/state/omarchy/agents/usage')
MODULE = 'io.github.heitorm50.poketokenbar'

fails = 0
def eq(label, got, want):
    global fails
    ok = got == want
    if not ok: fails += 1
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got}" + ("" if ok else f"  (esperado {want})"))

def load_helper():
    loader = importlib.machinery.SourceFileLoader('ps', PLUGIN)
    spec = importlib.util.spec_from_loader('ps', loader)
    mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)
    return mod

class Sandbox:
    def __enter__(self):
        self.dir = tempfile.mkdtemp(prefix='ptb-')
        self.old = os.environ.get('XDG_STATE_HOME')
        os.environ['XDG_STATE_HOME'] = self.dir
        self.usage = os.path.join(self.dir, 'omarchy', 'agents', 'usage')
        os.makedirs(self.usage)
        self.state = os.path.join(self.dir, 'omarchy', MODULE)
        os.makedirs(self.state)
        for f in os.listdir(REAL):
            shutil.copy(os.path.join(REAL, f), self.usage)
        return self
    def __exit__(self, *a):
        if self.old is None: os.environ.pop('XDG_STATE_HOME', None)
        else: os.environ['XDG_STATE_HOME'] = self.old
        shutil.rmtree(self.dir, ignore_errors=True)

    def record(self, agent):
        with open(os.path.join(self.usage, f'{agent}.json'), encoding='utf-8') as h:
            return json.load(h)
    def put_record(self, agent, data):
        with open(os.path.join(self.usage, f'{agent}.json'), 'w', encoding='utf-8') as h:
            json.dump(data, h)
    def read_state(self):
        with open(os.path.join(self.state, 'state.json'), encoding='utf-8') as h:
            return json.load(h)
    def put_state(self, **kw):
        s = {"schemaVersion":1,"lifetimeTokens":0,"lastSeen":{},"stage":0,
             "tokensIntoStage":0,"hatched":False,"graduations":0}
        s.update(kw)
        with open(os.path.join(self.state, 'state.json'), 'w', encoding='utf-8') as h:
            json.dump(s, h)
    def put_companion(self, rarity, forms):
        data = {"schemaVersion":1,"baseSpeciesId":1,"name":forms[0],"rarity":rarity,
                "captureRate":255,
                "evolutionLine":[{"id":i+1,"name":n} for i,n in enumerate(forms)]}
        with open(os.path.join(self.state, 'companion.json'), 'w', encoding='utf-8') as h:
            json.dump(data, h)

def bump(rec, n):
    rec = json.loads(json.dumps(rec))
    rec['modelUsage'].setdefault('test-model', {})
    rec['modelUsage']['test-model']['outputTokens'] = \
        rec['modelUsage']['test-model'].get('outputTokens', 0) + n
    return rec

print("--- 1. primeira absorção marca a régua e não conta o histórico ---")
with Sandbox() as sb:
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    s = sb.read_state()
    eq("lifetimeTokens", s['lifetimeTokens'], 0)
    eq("não chocou", s['hatched'], False)
    eq("claude marcado", s['lastSeen']['claude'] > 1_000_000_000, True)

print("\n--- 2. delta positivo acumula e choca (limiar 1.5M em dif 0.3) ---")
with Sandbox() as sb:
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    sb.put_record('claude', bump(sb.record('claude'), 2_000_000))
    ps.cmd_absorb(['0.3'])
    s = sb.read_state()
    eq("lifetime", s['lifetimeTokens'], 2_000_000)
    eq("chocou", s['hatched'], True)
    eq("excedente = 2M - 1.5M", s['tokensIntoStage'], 500_000)
    eq("estágio 0", s['stage'], 0)

print("\n--- 3. RECORD QUE ENCOLHE: lifetime não cai, estágio não regride ---")
with Sandbox() as sb:
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    sb.put_record('claude', bump(sb.record('claude'), 100_000_000))
    ps.cmd_absorb(['0.3'])
    before = sb.read_state()
    # a janela de 30 dias do Codex descarta sessões: modelUsage encolhe
    shrunk = sb.record('codex')
    for m in shrunk['modelUsage']:
        for k in shrunk['modelUsage'][m]:
            shrunk['modelUsage'][m][k] //= 3
    sb.put_record('codex', shrunk)
    ps.cmd_absorb(['0.3'])
    after = sb.read_state()
    eq("lifetime inalterado", after['lifetimeTokens'], before['lifetimeTokens'])
    eq("estágio inalterado", after['stage'], before['stage'])
    eq("hatched inalterado", after['hatched'], before['hatched'])
    # e voltar ao tamanho real não deve recontar o histórico do codex
    sb.put_record('codex', sb.record('codex'))
    ps.cmd_absorb(['0.3'])
    eq("sem recontagem", sb.read_state()['lifetimeTokens'], before['lifetimeTokens'])

print("\n--- 4. record que zera (CLI desinstalada) ---")
with Sandbox() as sb:
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    z = sb.record('codex'); z['modelUsage'] = {}
    sb.put_record('codex', z)
    ps.cmd_absorb(['0.3'])
    eq("sem delta negativo", sb.read_state()['lifetimeTokens'], 0)

print("\n--- 5. progressão de estágios de um common de 3 formas (37.5/75/112.5M) ---")
with Sandbox() as sb:
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    sb.put_state(lastSeen=sb.read_state()['lastSeen'], hatched=True, stage=0, tokensIntoStage=0)
    for step, (add, want_stage) in enumerate([(37_000_000, 0), (600_000, 1),
                                              (75_000_000, 2), (112_500_000, 2)]):
        sb.put_record('claude', bump(sb.record('claude'), add))
        ps.cmd_absorb(['0.3'])
        s = sb.read_state()
        if step == 3:
            eq("graduou na 4a etapa", s['graduations'], 1)
            eq("voltou a ser ovo", s['hatched'], False)
        else:
            eq(f"etapa {step}: estágio", s['stage'], want_stage)

print("\n--- 6. lock impede dois absorvedores simultâneos ---")
with Sandbox() as sb:
    import fcntl
    ps = load_helper(); sb.put_companion('common', ['a','b','c'])
    ps.cmd_absorb(['0.3'])
    sb.put_record('claude', bump(sb.record('claude'), 5_000_000))
    lock = open(os.path.join(sb.state, 'absorb.lock'), 'w')
    fcntl.flock(lock, fcntl.LOCK_EX)
    rc = ps.cmd_absorb(['0.3'])          # deve desistir, não bloquear
    eq("retorna 0 sem absorver", (rc, sb.read_state()['lifetimeTokens']), (0, 0))
    fcntl.flock(lock, fcntl.LOCK_UN); lock.close()
    ps.cmd_absorb(['0.3'])
    eq("absorve depois do lock liberado", sb.read_state()['lifetimeTokens'], 5_000_000)



# =========================================================================
# Coleção e shiny — integração com cmd_hatch e cmd_absorb.
#
# A rede é cortada trocando pick_species / evolution_line / hydrate_sprites por
# fakes: o que está sob teste aqui é o acoplamento entre chocar, progredir e o
# catch log, não a PokéAPI.
# =========================================================================

def stub_network(ps, species_id=341, name='corphish', rate=205, line=None):
    line = line or [(341, 'corphish'), (342, 'crawdaunt')]
    ps.load_index = lambda **kw: [{'id': species_id, 'name': name,
                                   'captureRate': rate,
                                   'isLegendary': False, 'isMythical': False}]
    ps.pick_species = lambda entries, floor=None: entries[0]
    ps.evolution_line = lambda base_id: [{'id': i, 'name': n} for i, n in line]
    ps.hydrate_sprites = lambda forms, shiny=False: [
        dict(f, sprite=f"/fake/{f['id']}{'-shiny' if shiny else ''}.gif") for f in forms]
    return ps


def read_collection(sb):
    with open(os.path.join(sb.state, 'collection.json'), encoding='utf-8') as h:
        return json.load(h)


def read_companion(sb):
    with open(os.path.join(sb.state, 'companion.json'), encoding='utf-8') as h:
        return json.load(h)


print("\n--- 7. cmd_hatch grava shiny no companion e abre a entrada ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    ps.roll_shiny = lambda rng=None: True
    ps.cmd_hatch([])
    comp = read_companion(sb)
    eq("companion marcado shiny", comp['shiny'], True)
    eq("sprites shiny na linha", comp['evolutionLine'][0]['sprite'].endswith('-shiny.gif'), True)
    col = read_collection(sb)
    eq("uma entrada na coleção", len(col['entries']), 1)
    eq("entrada shiny", col['entries'][0]['shiny'], True)
    eq("entrada aberta", col['entries'][0]['graduatedAt'], None)

print("\n--- 8. chocagem normal não marca shiny ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    ps.roll_shiny = lambda rng=None: False
    ps.cmd_hatch([])
    eq("companion normal", read_companion(sb)['shiny'], False)
    eq("entrada normal", read_collection(sb)['entries'][0]['shiny'], False)
    eq("sprite normal", read_companion(sb)['evolutionLine'][0]['sprite'].endswith('/341.gif'), True)

print("\n--- 9. hatch rodado duas vezes não deixa duas entradas abertas ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    ps.roll_shiny = lambda rng=None: False
    ps.cmd_hatch([])
    ps.cmd_hatch([])
    col = read_collection(sb)
    abertas = [e for e in col['entries'] if e['graduatedAt'] is None]
    eq("exatamente uma aberta", len(abertas), 1)
    eq("a anterior ficou no log, fechada", len(col['entries']), 2)

print("\n--- 10. avanço de estágio é registrado na entrada aberta ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    ps.roll_shiny = lambda rng=None: False
    ps.cmd_hatch([])
    ps.cmd_absorb(['0.3'])                       # marca a régua
    sb.put_state(lastSeen=sb.read_state()['lastSeen'],
                 hatched=True, stage=0, tokensIntoStage=0)
    sb.put_record('claude', bump(sb.record('claude'), 80_000_000))
    ps.cmd_absorb(['0.3'])                       # 80M > 75M do estágio 0
    eq("estado no estágio 1", sb.read_state()['stage'], 1)
    eq("entrada registra o estágio 1", read_collection(sb)['entries'][0]['finalStage'], 1)

print("\n--- 11. graduação fecha a entrada e abre a do ovo novo ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    ps.roll_shiny = lambda rng=None: False
    ps.cmd_hatch([])
    ps.cmd_absorb(['0.3'])
    sb.put_state(lastSeen=sb.read_state()['lastSeen'],
                 hatched=True, stage=0, tokensIntoStage=0)
    # linha de 2 formas, comum, dif 0.3 -> 75M + 150M = 225M até graduar
    sb.put_record('claude', bump(sb.record('claude'), 230_000_000))
    ps.cmd_absorb(['0.3'])
    eq("graduou", sb.read_state()['graduations'], 1)
    col = read_collection(sb)
    fechadas = [e for e in col['entries'] if e['graduatedAt'] is not None]
    abertas = [e for e in col['entries'] if e['graduatedAt'] is None]
    eq("uma fechada", len(fechadas), 1)
    eq("fechada no último estágio", fechadas[0]['finalStage'], 1)
    eq("uma aberta (o ovo novo)", len(abertas), 1)

print("\n--- 12. coleção é semeada a partir de um companion pré-existente ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    sb.put_companion('common', ['corphish', 'crawdaunt'])   # sem collection.json
    eq("não havia coleção", os.path.exists(os.path.join(sb.state, 'collection.json')), False)
    ps.cmd_absorb(['0.3'])
    col = read_collection(sb)
    eq("o companion em andamento virou entrada", len(col['entries']), 1)
    eq("aberta", col['entries'][0]['graduatedAt'], None)
    eq("shiny ausente lê False", col['entries'][0]['shiny'], False)

print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
