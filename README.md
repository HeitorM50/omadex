# Omadex

A creature in your Omarchy bar that hatches and evolves as you burn AI coding
tokens. A Pokédex, a catch log, Rare Candy for filling rate limits, and a shop
that spends the tokens you have already used.

```
🥚          an egg, incubating
🦀 →        the animated Gen-V sprite once it hatches
```

## Requires `omarchy.agents`

**Omadex collects no usage of its own.** It reads the records that the
first-party `omarchy.agents` plugin writes to
`~/.local/state/omarchy/agents/usage/*.json`.

That plugin must be **enabled and have recorded usage** — which means you need
at least one AI coding CLI (Claude Code, Codex, Fireworks) that has actually
run. Until a record exists, Omadex shows an egg and never hatches. That is not
a failure: there is simply nothing to grow on yet.

`omarchy.agents` ships with Omarchy and self-hides when no usage exists, so if
you see its robot icon in your bar, you are ready.

## Install

```bash
omarchy plugin add https://github.com/HeitorM50/omadex.git --enable
```

Then add it to the bar:

```bash
omarchy bar add io.github.heitorm50.omadex --section right
```

### Dependencies

- **Python 3** — standard library only, no packages to install.
- **Network** — on the first hatch of each species, to fetch its evolution chain
  and sprites from PokéAPI. Cached afterwards; later hatches of a known species
  need no network.
- **`omarchy.agents`** enabled, with recorded usage. See above.

## Remove

```bash
omarchy bar remove io.github.heitorm50.omadex
omarchy plugin remove io.github.heitorm50.omadex
```

Your progress and the sprite cache are left behind on purpose, so a reinstall
picks up where you left off. To erase them too:

```bash
rm -rf ~/.local/state/omarchy/io.github.heitorm50.omadex
rm -rf ~/.cache/omarchy/io.github.heitorm50.omadex
```

Omadex writes nowhere else. The only change it makes to your Omarchy config is
its own widget entry in `shell.json`, which `omarchy bar remove` takes out.

## How it works

The records are a public contract of `omarchy.agents` (`schemaVersion: 1`,
documented at `/usr/share/omarchy/shell/plugins/agents/README.md`). Omadex is a
read-only consumer: it never runs `omarchy-agent-usage-update` and never talks
to the providers' APIs.

### Progress

| | Tokens |
|---|---|
| Egg hatches | 5M |
| Graduation — common | 750M |
| Graduation — uncommon | 1.875B |
| Graduation — rare | 3B |
| Graduation — legendary | 6B |

The cost of stage `i` (0-based) in a `k`-form line is `T · (i+1) / (k(k+1)/2)`.
The sum across all stages is exactly `T`, so graduation lands on the rarity's
total no matter how long the line is.

Everything is multiplied by `difficulty`, which defaults to **0.3**, not 1.0:
the original is balanced for ~253M tokens/day, and at ~50M/day a common
graduation would take about 15 days. At 0.3 it takes about 5. Use `1.0` for the
original balance.

Rarity comes from PokéAPI's `capture_rate` (`≤45` rare, `≤120` uncommon, else
common; `is_legendary`/`is_mythical` forces legendary), and hatching is weighted
by that same number — a legendary lands roughly 1 in 95. Lines you have already
collected are weighted at half, so the Pokédex fills instead of repeating.

### The counter only grows

The records are **not** a reliable lifetime total: the Codex collector only
reads session files touched in the last 30 days, and the Fireworks one asks its
billing API for 30 days. Summing `modelUsage` on every read would give a total
that *shrinks* when sessions age out — and a creature that de-evolves.

So Omadex keeps the last total seen per agent and accumulates only positive
deltas. A record that shrinks, zeroes, or is rewritten contributes nothing,
never negative.

Counting starts at zero by default: on the first run your existing lifetime
total only sets the ruler, so the first creature does not graduate instantly.
Turn on `seedFromExisting` to let it count.

### Pokédex and history

The popout has five tabs: **Companion**, **Pokédex**, **History**, **Bag**, and
**Shop**.

The Pokédex is **not a file** — it is projected from the catch log. Two
persisted collections would drift out of sync; one cannot.

A species enters the dex the moment your companion reaches it, and stays
forever. The dex records species **reached**, not the whole line: a creature
that graduated without evolving does not grant its evolution. That is the
difference between collecting what you raised and what you could have raised.

### Shiny

One hatch in **64** comes out shiny. A shiny keeps its colors through the whole
evolution line, and the ✨ shows on the name, the history row, and the dex cell.
On the cell it marks the *species*: it means "I have owned this one shiny", and
it stays even while the cell shows the normal artwork. A species owned both ways
swaps artwork on click.

### Economy

The tokens you have already burned are currency: your wallet is the lifetime
total minus what you have spent.

Filling a rate-limit window pays **Rare Candy** — 5 for a weekly cap, 1 for a
session cap. Using one injects 100M of growth. The moment you hit the ceiling
becomes the moment your creature grows.

| | Price | Effect |
|---|---|---|
| Mint | 100M | rerolls its nature |
| Rare Candy | 500M | +100M of growth |
| Egg | 1B | release the current one and start over |
| Uncommon Egg | 2.5B | guarantees Uncommon or better |
| Shiny Charm | 3B | shiny odds 1/64 → 1/48, forever |
| Rare Egg | 4B | guarantees Rare or better |

Two numbers that look arbitrary and are not. Rare Candy costs **5× what it
delivers** because tokens serve as both the growth meter *and* the wallet;
pricing it at its XP value would make buying it free growth. And graded eggs are
priced off the graduation table, not off probability — by probability, two
Uncommon Eggs would beat one Rare Egg on every axis and the higher tier would
become strictly inferior.

Buying an egg **releases** your current creature: it stays in the Pokédex and
history with the forms it reached, but does not count as a graduation and does
not pay the 2× bonus. The real cost is losing the progress you had banked.

### A creature that reacts

Your companion reads your rhythm: idle, working, focused, tired near a limit,
asleep with no usage. Hatching and evolving get a flash and a pop, and the egg
wobbles from 90% of its threshold. A celebration is **stored**, so a hatch that
happened while the popout was closed is still celebrated next time you open it.

A line you have already graduated grows **2× faster**, with a capsule in the
panel explaining why the bar is moving quickly.

And rarely — one common hatch in 128, on a line with two or more forms — what
you are raising is secretly something else, and reveals itself instead of
evolving. Its shiny stays hidden until then.

### Pinning a species to the bar

The star on a Pokédex cell pins that species to the bar, independent of the
companion you are raising. The panel keeps showing the real creature and its
progress — only the bar stops following, and a ★ on the sprite says so.

## Architecture

```
BarWidget.qml      watches and orchestrates; writes nothing
Panel.qml          popout shell: tabs, keyboard, lifecycle
CompanionView.qml  \
DexView.qml         > one tab each, presentation only
CatchLogView.qml   /
BagView.qml        |
ShopView.qml       /
Balance.js         read-side math (thresholds, progress, prices, formatting)
Collection.js      the Pokédex projection over the catch log
bin/omadex-sync    the only writer: PokéAPI, sprites, and all state mutation
```

State mutation lives in the helper, not in QML, because **the bar instantiates
one widget per monitor**: two widgets accumulating the same delta would count it
twice, and `state.json` would have two writers. With the rule in the helper,
behind a `flock`, the number of monitors stops mattering — and the logic becomes
testable in Python instead of mirrored between QML and a test.

### Files written

| Path | Written by |
|---|---|
| `~/.local/state/omarchy/<id>/state.json` | `omadex-sync absorb` |
| `~/.local/state/omarchy/<id>/companion.json` | `omadex-sync hatch` |
| `~/.local/state/omarchy/<id>/collection.json` | `absorb`, `hatch`, `buy`, `use` |
| `~/.cache/omarchy/<id>/sprites/` | `omadex-sync` |
| `~/.cache/omarchy/<id>/base-species.json` | `omadex-sync index` |

### The helper

```bash
bin/omadex-sync index                   # rebuild the 329 base-species index
bin/omadex-sync hatch [tier]            # roll a species and resolve its line
bin/omadex-sync sprites <ids...>        # (re)download sprites
bin/omadex-sync absorb <dif> [seed]     # accumulate tokens, advance progress
bin/omadex-sync buy <item> <dif> [tier] # rareCandy|mint|shinyCharm|egg
bin/omadex-sync use <item> <dif>        # rareCandy|mint
```

Sprites are the animated Gen-V GIFs from
`raw.githubusercontent.com/PokeAPI/sprites`, falling back to the static PNG when
a species has no animation. Downloaded once and cached. The species index comes
from PokéAPI's GraphQL endpoint (0.7s) with a REST fallback (~60s) if it is
down.

## Interaction

- **Bar icon:** left opens the panel, middle re-checks usage.
- **Panel:** `←`/`→` (or `h`/`l`) switch tabs, `1`–`5` jump to one, `r`
  re-checks, `a` opens the `omarchy.agents` panel, Tab moves to the neighbouring
  bar popout, Esc closes.
- **Pokédex:** hover shows the detail line below the grid; the star pins a
  species to the bar; clicking a species you have owned both ways swaps the
  artwork.
- **IPC:** `omarchy-shell io.github.heitorm50.omadex <open|close|toggle|refresh|hatch|companion|dex|log|bag|shop>`

## Settings

In `~/.config/omarchy/shell.json`, in the widget's entry:

```bash
omarchy bar set io.github.heitorm50.omadex difficulty 1.0 --json
omarchy bar set io.github.heitorm50.omadex showTokens false --json
```

| Key | Default | What it does |
|---|---|---|
| `difficulty` | `0.3` | Multiplies growth thresholds, 0.1–2.0 |
| `shopDifficulty` | `1.0` | Multiplies shop prices, independent of growth |
| `spriteSize` | `22` | Sprite height in the bar, in px |
| `showTokens` | `true` | Show today's tokens next to the sprite |
| `showLimitPercent` | `false` | Show the tightest rate-limit percentage |
| `seedFromExisting` | `false` | Count usage already recorded |
| `representativeSpeciesId` | `0` | Species pinned to the bar; 0 follows the companion |
| `pollSeconds` | `60` | Safety net; records are already watched by event |

## Tests

```bash
tests/test_collection.py   # collection and the shiny roll
tests/test_absorb.py       # accumulation and integration, against real records
tests/test_economy.py      # wallet, prices, candy, eggs, burn rate
tests/test_ditto.py        # the disguise, the hidden shiny, the reveal
tests/test_resilience.py   # what happens when the network fails mid-operation
tests/test_dex.mjs         # the Pokédex projection, ownership, the 2× bonus
tests/test_shop.mjs        # shop list, bag, mood, bar tooltip
```

404 assertions. The ones that matter most:

- **Using a candy does not grow your wallet** (`test_economy.py`): the wallet is
  lifetime minus spent, so adding candy XP to lifetime would make every candy a
  money printer.
- **The first run pays no retroactive candy**: enabling the feature with a
  weekly cap already at 100% would hand out 5 free candies.
- **A record that shrinks** (`test_absorb.py`): the lifetime total must not fall
  and the stage must not regress when sessions age out of the Codex collector's
  30-day window.
- **Two hatches in the same second** do not leave two open history entries. That
  test is what revealed `hatchedAt` — one-second resolution — was unusable as an
  entry identity.
- **The ✨ marks only species actually reached** (`test_dex.mjs`), and stays
  hidden while a disguise is in play, everywhere: bar, panel, dex, and history.
- **A network failure mid-operation** (`test_resilience.py`) leaves no phantom
  graduation, no duplicate entry, and no token charged without delivery. The
  absence of this suite is what let three of those through 349 assertions:
  every other stub replaces the network with functions that always succeed.
- **The threshold the UI shows is the one the helper charges**, with and without
  the 2× bonus (`test_shop.mjs`).

None of them touch the network or your real state.

### Editing the plugin

Saving a file under `~/.config/omarchy/plugins/` reloads the plugin, but the QML
engine keeps a component cache that **neither the hot-reload nor
`omarchy-shell shell rescanPlugins` clears reliably**. A change to a `.qml` file
can keep running the old version with no warning at all — the symptom is new
code that plainly does not execute. To be sure you are testing what is on disk:

```bash
omarchy restart shell
```

## Credit and scope

The idea, the token balance, and the companion mechanics come from
**PokeTokenBar** by [chattymin](https://github.com/chattymin/PokeTokenBar)
(MIT), a native macOS app with no Linux port. This plugin reimplements that
layer for Omarchy's Quickshell, reading `omarchy.agents` records instead of
collecting usage itself.

Left out on purpose: per-individual profiles (IVs, abilities, moves), the
floating desktop pet, and per-day cost in dollars — the records carry no cost
field, and reimplementing a per-model price table would go stale on its own.
Token charts, per-model breakdowns and rate-limit detail are left to
`omarchy.agents`, which already draws them one click away in the bar.

Unofficial, non-commercial fan project. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) — nothing third-party is
bundled in this repository.

## License

MIT, see [LICENSE](LICENSE).
