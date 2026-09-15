#!/usr/bin/env python3
"""Subcomando `details`: os dados de espécie que o perfil do indivíduo usa.

Uma consulta GraphQL traz stats base, habilidades, learnset, gênero e a
descrição; o resultado é normalizado para a forma que o Profile.js consome e
cacheado para sempre (são dados imutáveis).

Sem rede: as duas buscas são substituídas por funções que devolvem payloads
fixos, ou que levantam — é a única forma de exercitar o fallback e a falha.
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


class Cache:
    """XDG_CACHE_HOME temporário — o details é cache, não estado."""

    def __enter__(self):
        self.dir = tempfile.mkdtemp(prefix='ptb-det-')
        self.old = os.environ.get('XDG_CACHE_HOME')
        os.environ['XDG_CACHE_HOME'] = self.dir
        return self

    def __exit__(self, *a):
        if self.old is None:
            os.environ.pop('XDG_CACHE_HOME', None)
        else:
            os.environ['XDG_CACHE_HOME'] = self.old
        shutil.rmtree(self.dir, ignore_errors=True)


# Payload real da PokéAPI para o Corphish, reduzido. A forma é a que a consulta
# de fato devolve (conferida contra a API, não inventada).
PAYLOAD = {
    "data": {
        "pokemon": [{
            "id": 341, "name": "corphish", "height": 6, "weight": 115,
            "pokemontypes": [{"type": {"name": "water"}}],
            "pokemonstats": [
                {"base_stat": 43, "stat": {"name": "hp"}},
                {"base_stat": 80, "stat": {"name": "attack"}},
                {"base_stat": 65, "stat": {"name": "defense"}},
                {"base_stat": 50, "stat": {"name": "special-attack"}},
                {"base_stat": 35, "stat": {"name": "special-defense"}},
                {"base_stat": 35, "stat": {"name": "speed"}},
            ],
            "pokemonabilities": [
                {"is_hidden": False, "slot": 1, "ability": {"name": "hyper-cutter"}},
                {"is_hidden": False, "slot": 2, "ability": {"name": "shell-armor"}},
                {"is_hidden": True, "slot": 3, "ability": {"name": "adaptability"}},
            ],
            "pokemonmoves": [
                {"level": 1, "move": {"name": "bubble"}},
                {"level": 7, "move": {"name": "vicegrip"}},
            ],
        }],
        "pokemonspecies": [{
            "gender_rate": 4, "capture_rate": 205,
            "pokemonspeciesnames": [{"genus": "Ruffian Pokémon"}],
            "pokemonspeciesflavortexts": [
                # A PokéAPI devolve o texto com quebras de linha do jogo e um
                # \f separando páginas. Renderizar isso cru abre buracos na
                # coluna estreita do painel.
                {"flavor_text": "CORPHISH were originally foreign\nPOKéMON."
                                "\x0cThis POKéMON is very hardy."}
            ],
        }],
    }
}

ps = load_helper()

print("--- normalização: a forma que o Profile.js consome ---")
d = ps.normalize_details_graphql(PAYLOAD, 341)
eq("espécie", d['speciesId'], 341)
eq("nome", d['name'], 'corphish')
eq("gênero em oitavos", d['genderRate'], 4)
eq("capture rate", d['captureRate'], 205)
eq("tipos em ordem de slot", d['types'], ['water'])
eq("genus", d['genus'], 'Ruffian Pokémon')
eq("stats base por nome", d['baseStats'],
   {'hp': 43, 'attack': 80, 'defense': 65, 'special-attack': 50,
    'special-defense': 35, 'speed': 35})
eq("habilidades com slot e oculta", d['abilities'],
   [{'name': 'hyper-cutter', 'slot': 1, 'isHidden': False},
    {'name': 'shell-armor', 'slot': 2, 'isHidden': False},
    {'name': 'adaptability', 'slot': 3, 'isHidden': True}])
eq("golpes com o nível", d['moves'],
   [{'name': 'bubble', 'level': 1}, {'name': 'vicegrip', 'level': 7}])
eq("o flavor text vira uma linha só",
   d['flavorText'],
   'CORPHISH were originally foreign POKéMON. This POKéMON is very hardy.')

print("\n--- payload degenerado não vira cache corrompido ---")
eq("sem pokemon", ps.normalize_details_graphql({"data": {"pokemon": [],
                                                "pokemonspecies": []}}, 341), None)
eq("sem data", ps.normalize_details_graphql({}, 341), None)
eq("nulo", ps.normalize_details_graphql(None, 341), None)
semespecie = {"data": {"pokemon": PAYLOAD['data']['pokemon'], "pokemonspecies": []}}
d2 = ps.normalize_details_graphql(semespecie, 341)
eq("espécie ausente ainda dá stats", d2['baseStats']['hp'], 43)
eq("e gênero desconhecido é −1 (sem gênero), não 0 (macho)", d2['genderRate'], -1)
eq("sem descrição", d2['flavorText'], '')

print("\n--- cache: busca uma vez, lê para sempre ---")
with Cache():
    ps = load_helper()
    chamadas = []

    def falso_graphql(species_id):
        chamadas.append(species_id)
        return PAYLOAD

    ps.fetch_details_graphql = falso_graphql
    eq("primeira chamada busca", ps.cmd_details(['341']), 0)
    eq("bateu na rede uma vez", chamadas, [341])
    eq("escreveu o cache", os.path.exists(ps.details_path(341)), True)
    with open(ps.details_path(341), encoding='utf-8') as h:
        eq("o cache é a forma normalizada", json.load(h)['baseStats']['attack'], 80)

    eq("segunda chamada não busca", ps.cmd_details(['341']), 0)
    eq("e a rede não foi tocada de novo", chamadas, [341])

print("\n--- GraphQL fora cai para a REST ---")
with Cache():
    ps = load_helper()
    rest = []

    def graphql_quebrado(species_id):
        raise urllib.error.URLError('sem rede')

    def falso_rest(species_id):
        rest.append(species_id)
        return dict(ps.normalize_details_graphql(PAYLOAD, species_id), name='via-rest')

    ps.fetch_details_graphql = graphql_quebrado
    ps.fetch_details_rest = falso_rest
    eq("o subcomando ainda sai bem", ps.cmd_details(['341']), 0)
    eq("a REST foi usada", rest, [341])
    with open(ps.details_path(341), encoding='utf-8') as h:
        eq("e o cache veio dela", json.load(h)['name'], 'via-rest')

print("\n--- as duas fora: falha visível, sem cache mentiroso ---")
with Cache():
    ps = load_helper()

    def quebrado(species_id):
        raise urllib.error.URLError('sem rede')

    ps.fetch_details_graphql = quebrado
    ps.fetch_details_rest = quebrado
    eq("sai com erro", ps.cmd_details(['341']) != 0, True)
    # Cachear um resultado vazio faria a view mostrar um perfil sem stats para
    # sempre, sem nunca tentar de novo.
    eq("e não escreve cache nenhum", os.path.exists(ps.details_path(341)), False)

print("\n--- o cache só conta se for ARQUIVO ---")
with Cache():
    ps = load_helper()
    chamadas = []

    def falso(species_id):
        chamadas.append(species_id)
        return PAYLOAD

    ps.fetch_details_graphql = falso
    # Um diretório com o nome do cache satisfazia `os.path.exists` e o
    # subcomando devolvia 0 sem escrever nada. O QML relia, falhava, disparava o
    # helper de novo — laço infinito de processos. Encontrado rodando de verdade.
    os.makedirs(ps.details_path(341))
    eq("diretório no lugar do arquivo não passa por cache",
       ps.main(['details', '341']), 1)
    eq("e a busca foi tentada", chamadas, [341])

print("\n--- argumentos ---")
with Cache():
    ps = load_helper()
    ps.fetch_details_graphql = lambda species_id: PAYLOAD
    eq("sem id devolve uso", ps.cmd_details([]), 2)
    eq("id não numérico devolve uso", ps.cmd_details(['abc']), 2)
    eq("id fora da faixa é recusado", ps.cmd_details(['99999']), 2)

print("\n--- o host é da allowlist ---")
eq("graphql está liberado", ps.check_host(ps.GRAPHQL_ENDPOINT), ps.GRAPHQL_ENDPOINT)
eq("api rest está liberada", ps.check_host(ps.API + '/pokemon/341'),
   ps.API + '/pokemon/341')

print(f"\n{fails} FALHA(S)" if fails else "\nTodos os testes passaram")
raise SystemExit(1 if fails else 0)
