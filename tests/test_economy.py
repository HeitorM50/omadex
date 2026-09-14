#!/usr/bin/env python3
"""Economia: carteira, preços, inventário e concessão de Rare Candy.

Funções puras e sandbox em XDG_STATE_HOME temporário. Sem rede.

O teste que mais importa é o primeiro: usar uma candy não pode aumentar a
carteira. A carteira é lifetimeTokens − spentTokens, então somar o XP da candy
ao lifetime faria de cada candy uma máquina de dinheiro.
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
    """XDG_STATE_HOME temporário com cópias dos records reais."""

    def __enter__(self):
        self.dir = tempfile.mkdtemp(prefix='ptb-eco-')
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

    def read(self, name):
        with open(os.path.join(self.state, name), encoding='utf-8') as h:
            return json.load(h)

    def write(self, name, data):
        with open(os.path.join(self.state, name), 'w', encoding='utf-8') as h:
            json.dump(data, h)

    def put_state(self, **kw):
        s = {"schemaVersion": 1, "lifetimeTokens": 0, "lastSeen": {}, "stage": 0,
             "tokensIntoStage": 0, "hatched": False, "graduations": 0,
             "spentTokens": 0, "inventory": {}, "candyWindows": {},
             "candySeeded": False}
        s.update(kw)
        self.write('state.json', s)

    def put_companion(self, rarity='common', forms=(('corphish', 341), ('crawdaunt', 342)),
                      shiny=False, cid='c1'):
        self.write('companion.json', {
            "schemaVersion": 1, "companionId": cid, "baseSpeciesId": forms[0][1],
            "name": forms[0][0], "rarity": rarity, "shiny": shiny,
            "captureRate": 205, "hatchedAt": 1000,
            "evolutionLine": [{"id": i, "name": n, "sprite": f"/s/{i}.gif"}
                              for n, i in forms],
        })

    def bump(self, agent, tokens):
        """Soma tokens ao record, para o absorb ter delta real."""
        f = os.path.join(self.usage, f'{agent}.json')
        with open(f, encoding='utf-8') as h:
            d = json.load(h)
        m = d.setdefault('modelUsage', {}).setdefault('test-model', {})
        m['outputTokens'] = m.get('outputTokens', 0) + tokens
        with open(f, 'w', encoding='utf-8') as h:
            json.dump(d, h)

    def put_record_limits(self, agent, limits):
        """Reescreve só os limites de um record, preservando o resto."""
        p = os.path.join(self.usage, f'{agent}.json')
        with open(p, encoding='utf-8') as h:
            d = json.load(h)
        d['limits'] = limits
        with open(p, 'w', encoding='utf-8') as h:
            json.dump(d, h)


ps_mod = load_helper()

def stub_network(ps, species=((341, 'corphish'), (342, 'crawdaunt')),
                 rate=205, legendary=False):
    """Corta a rede da chocagem, preservando o filtro de grau do pool."""
    pool = [{'id': species[0][0], 'name': species[0][1], 'captureRate': rate,
             'isLegendary': legendary, 'isMythical': False}]
    ps.load_index = lambda **kw: pool
    ps.evolution_line = lambda base_id: [{'id': i, 'name': n} for i, n in species]
    ps.hydrate_sprites = lambda forms, shiny=False: [
        dict(f, sprite=f"/fake/{f['id']}.gif") for f in forms]
    return ps



# ---------------------------------------------------------------- constantes

print("--- preços, verbatim do original ---")
eq("candy custa 5x o que entrega", ps_mod.RARE_CANDY_PRICE, 5 * ps_mod.RARE_CANDY_XP)
eq("candy XP", ps_mod.RARE_CANDY_XP, 100_000_000)
eq("candy price", ps_mod.RARE_CANDY_PRICE, 500_000_000)
eq("mint price", ps_mod.MINT_PRICE, 100_000_000)
eq("shiny charm price", ps_mod.SHINY_CHARM_PRICE, 3_000_000_000)
eq("shiny charm denominador", ps_mod.SHINY_CHARM_RATE, 48)
eq("candy semanal", ps_mod.CANDY_WEEKLY_GRANT, 5)
eq("ovo simples", ps_mod.egg_price(None), 1_000_000_000)
eq("ovo incomum = 2.5x", ps_mod.egg_price("uncommon"), 2_500_000_000)
eq("ovo raro = 4x", ps_mod.egg_price("rare"), 4_000_000_000)
eq("não se vende ovo lendário", ps_mod.EGG_TIERS, [None, "uncommon", "rare"])

print("\n--- a dificuldade da loja é independente da de crescimento ---")
eq("preço dobra em 2.0", ps_mod.shop_price("rareCandy", 2.0), 1_000_000_000)
eq("preço cai a 10%", ps_mod.shop_price("rareCandy", 0.1), 50_000_000)
eq("ovo também escala", ps_mod.shop_price("egg:rare", 2.0), 8_000_000_000)
eq("limiar de crescimento NÃO muda com a da loja",
   ps_mod.phase_threshold("common", 2, 0, 0.3), 75_000_000)

print("\n--- carteira ---")
eq("saldo = lifetime - spent", ps_mod.available_tokens(
    {"lifetimeTokens": 1_000, "spentTokens": 400}), 600)
eq("nunca negativo", ps_mod.available_tokens(
    {"lifetimeTokens": 100, "spentTokens": 900}), 0)
eq("campos ausentes", ps_mod.available_tokens({}), 0)

# ------------------------------------------------------ o loop de dinheiro

print("\n--- USAR CANDY NÃO PODE AUMENTAR A CARTEIRA ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=600_000_000,
                 inventory={"rareCandy": 1})
    antes = ps.available_tokens(sb.read('state.json'))
    # dificuldade 2.0: limiar do estágio 0 é 500M, então a candy de 100M fica
    # no progresso sem disparar evolução — o que isola o que este teste mede.
    ps.cmd_use(['rareCandy', '2.0'])
    s = sb.read('state.json')
    eq("lifetimeTokens intacto", s['lifetimeTokens'], 600_000_000)
    eq("carteira intacta", ps.available_tokens(s), antes)
    eq("o XP foi para o progresso", s['tokensIntoStage'], 100_000_000)
    eq("candy consumida", s['inventory'].get('rareCandy', 0), 0)

print("\n--- o XP da candy não é escalado pela dificuldade ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, inventory={"rareCandy": 2})
    ps.cmd_use(['rareCandy', '2.0'])
    eq("100M em dificuldade 2.0", sb.read('state.json')['tokensIntoStage'], 100_000_000)

print("\n--- candy pode subir mais de um estágio sem perder o excedente ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    # dif 0.2 numa linha de 2 formas: limiares 50M e 100M. A candy de 100M paga
    # o primeiro e sobra 50M no segundo. (Em 0.1 a linha inteira custa 75M, e a
    # candy graduaria — coberto no teste de graduação por candy.)
    sb.put_state(hatched=True, inventory={"rareCandy": 1})
    ps.cmd_use(['rareCandy', '0.2'])
    s = sb.read('state.json')
    eq("subiu para o estágio 1", s['stage'], 1)
    eq("excedente preservado", s['tokensIntoStage'], 100_000_000 - 50_000_000)

print("\n--- candy que cobre a linha inteira gradua ---")
with Sandbox() as sb2:
    ps2 = load_helper()
    sb2.put_companion()
    sb2.put_state(hatched=True, inventory={"rareCandy": 1})
    # linha toda em dif 0.1 = 25M + 50M = 75M < 100M da candy
    ps2.cmd_use(['rareCandy', '0.1'])
    s2 = sb2.read('state.json')
    eq("graduou", s2['graduations'], 1)
    eq("voltou a ser ovo", s2['hatched'], False)

print("\n--- usar candy sem candy, ou sem companion, falha sem mutar ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, inventory={})
    eq("sem estoque devolve erro", ps.cmd_use(['rareCandy', '0.3']), 1)
    eq("nada mudou", sb.read('state.json')['tokensIntoStage'], 0)
with Sandbox() as sb:
    ps = load_helper()
    sb.put_state(hatched=False, inventory={"rareCandy": 1})   # sem companion
    eq("sem companion devolve erro", ps.cmd_use(['rareCandy', '0.3']), 1)
    eq("candy não foi consumida", sb.read('state.json')['inventory']['rareCandy'], 1)

# ------------------------------------------------------------------ compras

print("\n--- comprar sem saldo falha e não muta nada ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=1_000_000)
    eq("recusa", ps.cmd_buy(['rareCandy', '1.0']), 1)
    s = sb.read('state.json')
    eq("spentTokens intacto", s['spentTokens'], 0)
    eq("inventário intacto", s['inventory'], {})

print("\n--- comprar com saldo desconta e entrega ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=2_000_000_000)
    eq("ok", ps.cmd_buy(['rareCandy', '1.0']), 0)
    s = sb.read('state.json')
    eq("descontou o preço", s['spentTokens'], 500_000_000)
    eq("entregou a candy", s['inventory']['rareCandy'], 1)
    eq("lifetime não mexeu", s['lifetimeTokens'], 2_000_000_000)

print("\n--- Shiny Charm é passivo e de compra única ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=10_000_000_000)
    eq("primeira compra ok", ps.cmd_buy(['shinyCharm', '1.0']), 0)
    eq("marcado como tendo", sb.read('state.json')['inventory']['shinyCharm'], True)
    gasto = sb.read('state.json')['spentTokens']
    eq("segunda compra recusada", ps.cmd_buy(['shinyCharm', '1.0']), 1)
    eq("não cobrou de novo", sb.read('state.json')['spentTokens'], gasto)

print("\n--- o charm muda o denominador, e não é retroativo ---")
eq("sem charm", ps_mod.shiny_denominator({}), 64)
eq("com charm", ps_mod.shiny_denominator({"shinyCharm": True}), 48)
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion(shiny=False)
    sb.put_state(hatched=True, lifetimeTokens=10_000_000_000)
    ps.cmd_buy(['shinyCharm', '1.0'])
    eq("companion já chocado não fica shiny", sb.read('companion.json')['shiny'], False)

print("\n--- Mint troca a nature, e sempre troca ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    comp = sb.read('companion.json'); comp['nature'] = 'hardy'
    sb.write('companion.json', comp)
    sb.put_state(hatched=True, inventory={"mint": 1})
    eq("ok", ps.cmd_use(['mint', '1.0']), 0)
    nova = sb.read('companion.json')['nature']
    eq("mudou", nova != 'hardy', True)
    eq("é uma das 25", nova in ps.NATURES, True)
    eq("mint consumido", sb.read('state.json')['inventory'].get('mint', 0), 0)
eq("são 25 natures", len(ps_mod.NATURES), 25)
eq("sem repetidas", len(set(ps_mod.NATURES)), 25)

# --------------------------------------------------------------------- ovos

print("\n--- comprar ovo descarta o companion como LIBERADO, não graduado ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion(cid='c1')
    sb.put_state(hatched=True, lifetimeTokens=5_000_000_000,
                 tokensIntoStage=40_000_000, stage=1)
    col = ps.empty_collection()
    ps.sync_open_entry(col, sb.read('companion.json'), now=1100)
    ps.record_stage(col, 1)
    ps.save_collection(col)
    eq("ok", ps.cmd_buy(['egg', '1.0']), 0)
    s = sb.read('state.json')
    eq("voltou a ser ovo", s['hatched'], False)
    eq("progresso destruído", s['tokensIntoStage'], 0)
    eq("graduações não subiram", s['graduations'], 0)
    e = sb.read('collection.json')['entries'][0]
    eq("entrada marcada liberada", e['releasedAt'] is not None, True)
    eq("e NÃO graduada", e['graduatedAt'], None)
    eq("guardou o estágio alcançado", e['finalStage'], 1)

print("\n--- liberado não habilita o crescimento 2x; graduado sim ---")
col = ps_mod.empty_collection()
col['entries'] = [{"companionId": "a", "speciesId": 341, "name": "corphish",
                   "rarity": "common", "shiny": False,
                   "line": [{"id": 341, "name": "corphish", "sprite": ""},
                            {"id": 342, "name": "crawdaunt", "sprite": ""}],
                   "hatchedAt": 1, "graduatedAt": None, "releasedAt": 9,
                   "finalStage": 1}]
eq("liberado no último estágio não conta", ps_mod.has_graduated_line(col, 341), False)
col['entries'][0].update(graduatedAt=9, releasedAt=None)
eq("graduado no último estágio conta", ps_mod.has_graduated_line(col, 341), True)
col['entries'][0]['finalStage'] = 0
eq("graduado sem chegar ao fim não conta", ps_mod.has_graduated_line(col, 341), False)
eq("espécie desconhecida", ps_mod.has_graduated_line(col, 25), False)

print("\n--- linha já graduada corta os limiares pela metade ---")
eq("sem bônus", ps_mod.phase_threshold("common", 2, 0, 0.3, 1), 75_000_000)
eq("com bônus 2x", ps_mod.phase_threshold("common", 2, 0, 0.3, 2), 37_500_000)

print("\n--- comprar ovo estando em ovo é recusado ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_state(hatched=False, lifetimeTokens=5_000_000_000)   # sem companion
    eq("recusa", ps.cmd_buy(['egg', '1.0']), 1)
    eq("não cobrou", sb.read('state.json')['spentTokens'], 0)

print("\n--- comprar ovo raro cobra e o pré-sorteio honra o piso ---")
with Sandbox() as sb:
    ps = stub_network(load_helper(), rate=40)      # 40 <= 45, atende 'rare'
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=10_000_000_000)
    eq("ok", ps.cmd_buy(['egg', '1.0', 'rare']), 0)
    eq("cobrou o preço do raro", sb.read('state.json')['spentTokens'], 4_000_000_000)
    eq("voltou a ser ovo", sb.read('state.json')['hatched'], False)
    # O pré-sorteio já resolveu a espécie (chocagem sem rede na hora H), então o
    # grau foi consumido — e o que ele garantiu está no companion pré-sorteado.
    eq("pré-sorteio respeitou o piso", sb.read('companion.json')['rarity'], 'rare')
    eq("grau consumido pelo pré-sorteio", sb.read('state.json')['eggTier'], None)

print("\n--- se o pré-sorteio falha, a garantia sobrevive ---")
with Sandbox() as sb:
    ps = stub_network(load_helper(), rate=205)     # nenhum candidato 'rare'
    sb.put_companion()
    sb.put_state(hatched=True, lifetimeTokens=10_000_000_000)
    eq("a compra em si dá certo", ps.cmd_buy(['egg', '1.0', 'rare']), 0)
    eq("o grau continua valendo", sb.read('state.json')['eggTier'], 'rare')
    eq("cobrou uma vez só", sb.read('state.json')['spentTokens'], 4_000_000_000)

print("\n--- o piso de raridade é um teto de capture_rate ---")
eq("rare <= 45", ps_mod.meets_tier({"captureRate": 45, "isLegendary": False,
                                    "isMythical": False}, "rare"), True)
eq("46 não é rare", ps_mod.meets_tier({"captureRate": 46, "isLegendary": False,
                                       "isMythical": False}, "rare"), False)
eq("lendário passa no piso rare", ps_mod.meets_tier(
    {"captureRate": 3, "isLegendary": True, "isMythical": False}, "rare"), True)
eq("120 é uncommon", ps_mod.meets_tier({"captureRate": 120, "isLegendary": False,
                                        "isMythical": False}, "uncommon"), True)
eq("piso nulo aceita tudo", ps_mod.meets_tier(
    {"captureRate": 255, "isLegendary": False, "isMythical": False}, None), True)

# ------------------------------------------------------------- rare candy

print("\n--- classe da janela: por duração quando há resetsAt, senão pelo label ---")
import datetime as _dt
agora = _dt.datetime.now(_dt.timezone.utc)
longe = (agora + _dt.timedelta(days=5)).isoformat()
perto = (agora + _dt.timedelta(hours=3)).isoformat()
eq("resetsAt a 5 dias = semanal",
   ps_mod.window_class({"label": "qualquer", "resetsAt": longe}), "weekly")
eq("resetsAt a 3 horas = sessão",
   ps_mod.window_class({"label": "qualquer", "resetsAt": perto}), "session")
eq("sem resetsAt, label com week = semanal",
   ps_mod.window_class({"label": "Weekly (7-day)", "resetsAt": ""}), "weekly")
eq("sem resetsAt, label de sessão",
   ps_mod.window_class({"label": "Session (5-hour)", "resetsAt": ""}), "session")
eq("label real do codex", ps_mod.window_class({"label": "5h window", "resetsAt": ""}),
   "session")

print("\n--- a chave da janela é estável e não usa a data ---")
k1 = ps_mod.window_key("claude", {"label": "Weekly (7-day)", "resetsAt": "2026-01-01"})
k2 = ps_mod.window_key("claude", {"label": "Weekly (7-day)", "resetsAt": "2026-09-99"})
eq("mesma chave com datas diferentes", k1, k2)
eq("inclui o agente", k1.startswith("claude:"), True)
eq("resetsAt vazio não quebra",
   ps_mod.window_key("claude", {"label": "Session (5-hour)", "resetsAt": ""}),
   "claude:Session (5-hour)")

print("\n--- a primeira execução semeia sem pagar retroativo ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True)
    sb.put_record_limits('claude', [
        {"label": "Weekly (7-day)", "percent": 1.0, "resetsAt": longe}])
    ps.cmd_absorb(['0.3'])
    s = sb.read('state.json')
    eq("não concedeu", s['inventory'].get('rareCandy', 0), 0)
    eq("marcou como semeado", s['candySeeded'], True)
    eq("janela já registrada", s['candyWindows'].get('claude:Weekly (7-day)'), True)
    ps.cmd_absorb(['0.3'])
    eq("nem na segunda passada", sb.read('state.json')['inventory'].get('rareCandy', 0), 0)

print("\n--- bater o limite depois de semeado concede ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, candySeeded=True)
    sb.put_record_limits('claude', [
        {"label": "Weekly (7-day)", "percent": 0.5, "resetsAt": longe}])
    ps.cmd_absorb(['0.3'])
    eq("a 50% não concede", sb.read('state.json')['inventory'].get('rareCandy', 0), 0)
    sb.put_record_limits('claude', [
        {"label": "Weekly (7-day)", "percent": 1.0, "resetsAt": longe}])
    ps.cmd_absorb(['0.3'])
    eq("a 100% o semanal dá 5", sb.read('state.json')['inventory']['rareCandy'], 5)
    ps.cmd_absorb(['0.3'])
    eq("e não concede de novo", sb.read('state.json')['inventory']['rareCandy'], 5)

print("\n--- sessão dá 1, e rearma quando cai abaixo de 100% ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, candySeeded=True)
    sb.put_record_limits('codex', [
        {"label": "5h window", "percent": 1.0, "resetsAt": perto}])
    ps.cmd_absorb(['0.3'])
    eq("sessão dá 1", sb.read('state.json')['inventory']['rareCandy'], 1)
    sb.put_record_limits('codex', [
        {"label": "5h window", "percent": 0.2, "resetsAt": perto}])
    ps.cmd_absorb(['0.3'])
    eq("rearmou", sb.read('state.json')['candyWindows'].get('codex:5h window'), False)
    sb.put_record_limits('codex', [
        {"label": "5h window", "percent": 1.0, "resetsAt": perto}])
    ps.cmd_absorb(['0.3'])
    eq("a janela nova concede outra", sb.read('state.json')['inventory']['rareCandy'], 2)

print("\n--- percent vem em 0..1, não em 0..100 ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, candySeeded=True)
    sb.put_record_limits('claude', [
        {"label": "Weekly (7-day)", "percent": 0.99, "resetsAt": longe}])
    ps.cmd_absorb(['0.3'])
    eq("0.99 não é 99% de 100 -> não concede",
       sb.read('state.json')['inventory'].get('rareCandy', 0), 0)

# ------------------------------------------------- chocagem com a economia

print("\n--- a chocagem sorteia uma nature ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    sb.put_state()
    ps.cmd_hatch([])
    nature = sb.read('companion.json').get('nature')
    eq("gravou uma nature", nature in ps.NATURES, True)

print("\n--- o Shiny Charm muda o denominador usado na chocagem ---")
with Sandbox() as sb:
    ps = stub_network(load_helper())
    sb.put_state(inventory={"shinyCharm": True})
    visto = {}
    real = ps.roll_shiny
    ps.roll_shiny = lambda rng=None, denominator=64: visto.setdefault('d', denominator) or False
    ps.cmd_hatch([])
    eq("chocou com denominador 48", visto.get('d'), 48)
with Sandbox() as sb:
    ps = stub_network(load_helper())
    sb.put_state(inventory={})
    visto = {}
    ps.roll_shiny = lambda rng=None, denominator=64: visto.setdefault('d', denominator) or False
    ps.cmd_hatch([])
    eq("sem charm, 64", visto.get('d'), 64)

print("\n--- o grau garantido filtra o pool e é consumido na chocagem ---")
with Sandbox() as sb:
    ps = stub_network(load_helper(), rate=205)      # comum: não passa em 'rare'
    sb.put_state(eggTier='rare')
    eq("sem candidato válido, não choca", ps.cmd_hatch([]), 1)
    eq("o grau é preservado para a próxima tentativa",
       sb.read('state.json')['eggTier'], 'rare')
    eq("nenhum companion foi escrito",
       os.path.exists(os.path.join(sb.state, 'companion.json')), False)

with Sandbox() as sb:
    ps = stub_network(load_helper(), rate=40)       # capture_rate 40 <= 45 = rare
    sb.put_state(eggTier='rare')
    eq("com candidato válido, choca", ps.cmd_hatch([]), 0)
    eq("raridade respeita o piso", sb.read('companion.json')['rarity'], 'rare')
    eq("o grau foi consumido", sb.read('state.json')['eggTier'], None)

print("\n--- chocagem sem grau aceita qualquer raridade ---")
with Sandbox() as sb:
    ps = stub_network(load_helper(), rate=255)
    sb.put_state()
    eq("choca", ps.cmd_hatch([]), 0)
    eq("comum", sb.read('companion.json')['rarity'], 'common')

print("\n--- peso de sorteio pela metade em linha já coletada ---")
col = ps_mod.empty_collection()
entries = [{"id": 1, "name": "a", "captureRate": 200,
            "isLegendary": False, "isMythical": False},
           {"id": 2, "name": "b", "captureRate": 200,
            "isLegendary": False, "isMythical": False}]
eq("sem coleção, pesos iguais", ps_mod.hatch_weights(entries, col), [200, 200])
col['entries'] = [{"speciesId": 1, "graduatedAt": 5, "releasedAt": None,
                   "finalStage": 0, "line": [{"id": 1, "name": "a"}]}]
eq("espécie já coletada pesa metade", ps_mod.hatch_weights(entries, col), [100, 200])
eq("peso nunca zera", ps_mod.hatch_weights(
    [{"id": 1, "name": "a", "captureRate": 1, "isLegendary": False,
      "isMythical": False}], col), [1])


print("\n--- taxa de queima: tokens por minuto, para o humor ---")
eq("delta em 2 min", ps_mod.burn_rate(200_000, 120), 100_000)
eq("intervalo zero não divide por zero", ps_mod.burn_rate(100, 0), 0)
eq("intervalo negativo (relógio andou para trás)", ps_mod.burn_rate(100, -5), 0)
eq("sem ganho", ps_mod.burn_rate(0, 60), 0)
# Um intervalo muito longo (máquina suspensa) dilui a taxa a quase nada, o que é
# o comportamento certo: ninguém estava codando.
eq("intervalo de um dia", ps_mod.burn_rate(60_000, 86_400), 41)

print("\n--- o absorb registra a taxa e o instante ---")
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, candySeeded=True)
    ps.cmd_absorb(['0.3'])                     # marca a régua
    primeiro = sb.read('state.json')
    eq("gravou o instante", isinstance(primeiro.get('lastAbsorbAt'), int), True)
    eq("taxa inicial zero", primeiro.get('burnRate'), 0)


print("\n--- a taxa mede o intervalo entre GANHOS, não entre absorções ---")
# Os records do omarchy.agents só são regenerados a cada 900s, então o delta
# chega em rajada. Medir contra a última absorção (a cada 60s) infla a taxa ~15x
# e deixaria o humor travado em "no foco".
with Sandbox() as sb:
    ps = load_helper()
    sb.put_companion()
    sb.put_state(hatched=True, candySeeded=True)
    ps.cmd_absorb(['0.3'])                    # marca a régua, sem ganho
    s1 = sb.read('state.json')
    eq("sem ganho, não marca instante de ganho", s1.get('lastGainAt', 0), 0)

    sb.bump('claude', 60_000_000)
    ps.cmd_absorb(['0.3'])                    # primeiro ganho: sem base, taxa 0
    s2 = sb.read('state.json')
    eq("primeiro ganho não tem intervalo", s2['burnRate'], 0)
    eq("mas registra o instante", s2['lastGainAt'] > 0, True)

    # Uma absorção SEM ganho no meio não pode reiniciar o cronômetro.
    ps.cmd_absorb(['0.3'])
    s3 = sb.read('state.json')
    eq("absorção sem ganho preserva o instante", s3['lastGainAt'], s2['lastGainAt'])
    eq("e não mexe na taxa", s3['burnRate'], s2['burnRate'])


print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
