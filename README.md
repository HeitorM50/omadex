<h1 align="center">OmaPkDex</h1>

<p align="center">
  <b>Your AI tokens, hatched into a companion.</b><br>
  A creature in your Omarchy bar that hatches and evolves as you burn AI coding
  tokens — with a Pokédex, a profile for every individual, Rare Candy for
  filling rate limits, and a shop that spends the tokens you already used.
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/1.gif" width="76" alt="Bulbasaur">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/25.gif" width="76" alt="Pikachu">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/341.gif" width="76" alt="Corphish">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/628.gif" width="76" alt="Braviary">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/144.gif" width="76" alt="Articuno">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/132.gif" width="76" alt="Ditto">
</p>

<p align="center">
  <img alt="Omarchy bar widget" src="https://img.shields.io/badge/Omarchy-bar%20widget-1b1b1f">
  <img alt="Quickshell QML" src="https://img.shields.io/badge/Quickshell-QML-1b1b1f">
  <img alt="Python 3, stdlib only" src="https://img.shields.io/badge/Python%203-stdlib%20only-1b1b1f">
  <img alt="570 assertions" src="https://img.shields.io/badge/tests-570%20assertions-1b1b1f">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-1b1b1f">
</p>

<p align="center">
  <img src="docs/screenshots/companion.png" width="420" alt="The Companion tab: Braviary at stage 2/2, with its progress bar and evolution line">
</p>

> [!IMPORTANT]
> **OmaPkDex collects no usage of its own.** It reads the records that the
> first-party **`omarchy.agents`** plugin writes to
> `~/.local/state/omarchy/agents/usage/*.json`.
>
> That plugin must be **enabled and have recorded usage** — so you need at least
> one AI coding CLI (Claude Code, Codex, Fireworks) that has actually run. Until
> a record exists, OmaPkDex shows an egg and never hatches. That is not a
> failure: there is simply nothing to grow on yet.
>
> `omarchy.agents` ships with Omarchy and self-hides when there is no usage, so
> if you see its robot icon in your bar, you are ready.

## Install

```bash
omarchy plugin add https://github.com/HeitorM50/omapkdex.git --enable
```

`--enable` asks where to place it in the bar. To move it later:

```bash
omarchy plugin enable io.github.heitorm50.omapkdex --section right
```

## Update

```bash
omarchy plugin update io.github.heitorm50.omapkdex
omarchy restart shell
```

**The restart is not optional.** `omarchy plugin update` ends with
`rescanPlugins`, which is enough for the helper and the JSON, but the QML engine
keeps a component cache that neither the hot-reload nor a rescan clears
reliably — the panel would keep running the old code with no warning at all.

Your Pokémon, your Pokédex and your history survive an update untouched: state
written by an older version is read as-is, and fields added since (the recorded
difficulty, an individual's nature) are treated as absent rather than
back-filled with a guess.

<details>
<summary><b>If you installed it before it was called OmaPkDex</b></summary>

The plugin was briefly `io.github.heitorm50.poketokenbar` and then
`io.github.heitorm50.omadex`. A plugin id is the folder name *and* the key the
bar uses, so pulling a new manifest id into an old folder leaves the bar
pointing at a widget that no longer exists — it vanishes with no error.

Reinstalling under the new id and carrying your save across is the fix. Check
which one you have first:

```bash
ls -d ~/.config/omarchy/plugins/io.github.heitorm50.*
```

If it is not `...omapkdex`, then — with `<old>` being the folder you just saw:

```bash
mv ~/.local/state/omarchy/<old> ~/.local/state/omarchy/io.github.heitorm50.omapkdex
mv ~/.cache/omarchy/<old>       ~/.cache/omarchy/io.github.heitorm50.omapkdex
omarchy plugin remove <old> --yes
omarchy plugin add https://github.com/HeitorM50/omapkdex.git --enable
omarchy restart shell
```

The state directory is keyed by the plugin id, which is why it moves: your
tokens, your Pokédex and your history live there, and a fresh id would start
you on an egg.

</details>

<details>
<summary><b>Dependencies, and how to remove it</b></summary>

- **Python 3** — standard library only, nothing to install.
- **Network** — on the first hatch of each species, to fetch its evolution chain
  and sprites from PokéAPI. Cached afterwards; later hatches of a known species
  need no network.
- **`omarchy.agents`** enabled, with recorded usage. See the note above.

```bash
omarchy plugin remove io.github.heitorm50.omapkdex
```

Your progress and the sprite cache are left behind on purpose, so a reinstall
picks up where you left off. To erase them too:

```bash
rm -rf ~/.local/state/omarchy/io.github.heitorm50.omapkdex
rm -rf ~/.cache/omarchy/io.github.heitorm50.omapkdex
```

OmaPkDex writes nowhere else. The only change it makes to your Omarchy config is
its own widget entry in `shell.json`, which `omarchy plugin remove` takes out
along with the folder.

</details>

## The six tabs

<table>
<tr>
<td width="44%" align="center"><img src="docs/screenshots/pokedex.png" width="330" alt="The Pokédex tab"></td>
<td width="56%" valign="top">

### 📕 Pokédex

Every species your companion **reaches** lands here and stays, with its number in the corner. The chips filter by rarity and count the species you own in each; a rarity you have none of is greyed out rather than hidden, because it tells you what is still out there.

The dex is **not a file** — it is projected from the catch log, so the two can never drift apart.

</td>
</tr>
<tr>
<td width="56%" valign="top">

### 🔬 A profile for every individual

Open a species to inspect each creature you raised: **level, gender, nature, ability, IVs, calculated stats and learned moves**, plus the species entry.

Nothing about an individual is stored — it is rolled from that creature's own id — so two Corphish are different animals, and they stay that way.

The numbers are the real ones: stats use the main-series formula with the rolled IVs and the nature modifier, and the moveset is the four most recently learned level-up moves at that level, from the **Black 2/White 2** learnset.

</td>
<td width="44%" align="center"><img src="docs/screenshots/profile.png" width="330" alt="A Pokémon profile with stats, IVs and moves"></td>
</tr>
<tr>
<td width="44%" align="center"><img src="docs/screenshots/history.png" width="330" alt="The History tab"></td>
<td width="56%" valign="top">

### 📜 History

The individuals rather than the species — every creature you raised, newest first, with the current one at the top. Released and graduated are different fates, and the log says which.

</td>
</tr>
<tr>
<td width="56%" valign="top">

### 🛍️ Shop and 🎒 Bag

The tokens you already burned are currency: your wallet is the lifetime total minus what you have spent.

Filling a rate-limit window pays **Rare Candy** — the moment you hit the ceiling becomes the moment your creature grows.

</td>
<td width="44%" align="center"><img src="docs/screenshots/shop.png" width="330" alt="The Shop tab"></td>
</tr>
<tr>
<td width="44%" align="center"><img src="docs/screenshots/settings.png" width="330" alt="The Settings tab"></td>
<td width="56%" valign="top">

### ⚙️ Settings

Growth difficulty and shop prices, **0.1× to 2.0×**, independently — showing what each costs in real tokens rather than just a multiplier. "150M to graduate" says something that "0.3×" does not.

Changing growth **never costs you progress**: the fraction of the current stage is preserved.

</td>
</tr>
</table>

## How it grows

<table align="center">
<tr>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/0.png" height="72" alt="An egg: you do not know what is inside yet"></td>
<td align="center">→</td>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/627.gif" height="72" alt="Rufflet"></td>
<td align="center">→</td>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/628.gif" height="72" alt="Braviary"></td>
<td align="center">→</td>
<td align="center">🎓</td>
</tr>
<tr>
<td align="center"><sub><b>1.5M</b><br>to hatch</sub></td>
<td></td>
<td align="center"><sub><b>75M</b><br>to evolve</sub></td>
<td></td>
<td align="center"><sub><b>150M</b><br>to graduate</sub></td>
<td></td>
<td align="center"><sub>into the<br>Pokédex</sub></td>
</tr>
</table>

<p align="center"><i>a common two-form line at the default <code>0.3×</code> difficulty</i></p>

You start on an egg — the species is a surprise until it hatches, and the
leftover tokens carry into the hatchling. From there each stage has its own
threshold, and graduating retires the creature into your Pokédex and starts a
new egg.

**Rarity decides the whole cost**, and the total does not depend on how long the
evolution line is:

<table>
<tr>
<th></th><th>Rarity</th><th>Until graduation<br><sub>at 1.0× difficulty</sub></th><th>A 2-form line</th><th>Hatch odds</th>
</tr>
<tr>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/19.gif" width="56" alt="Rattata"></td>
<td><b>Common</b></td><td>750M</td><td>250M + 500M</td><td align="right">85%</td>
</tr>
<tr>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/102.gif" width="56" alt="Exeggcute"></td>
<td><b>Uncommon</b></td><td>1.875B</td><td>625M + 1.25B</td><td align="right">1 in 14</td>
</tr>
<tr>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/1.gif" width="56" alt="Bulbasaur"></td>
<td><b>Rare</b></td><td>3B</td><td>1B + 2B</td><td align="right">1 in 14</td>
</tr>
<tr>
<td align="center"><img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/144.gif" width="56" alt="Articuno"></td>
<td><b>Legendary</b></td><td>6B</td><td>2B + 4B</td><td align="right">1 in 129</td>
</tr>
</table>

The cost of stage `i` (0-based) in a `k`-form line is `T · (i+1) / (k(k+1)/2)`.
The sum across every stage is exactly `T`, so graduation lands on the rarity's
total whether the line has one form or three — only the instalments change, with
later stages costing proportionally more.

Everything is multiplied by `difficulty`, which defaults to **0.3**, not 1.0:
the original is balanced for ~253M tokens/day, and at ~50M/day a common
graduation would take about 15 days. At 0.3 it takes about 5.

Rarity itself comes from PokéAPI's `capture_rate` (`≤45` rare, `≤120` uncommon,
else common; `is_legendary`/`is_mythical` forces legendary), and hatching is
weighted by that same number — which is literally how easy the species is to
catch in the games, so the odds above fall out of the game's own data (measured
over the 329 base species in the index). Lines you have already collected are weighted at half, so
the Pokédex fills instead of repeating.

<details>
<summary><b>Why the counter only ever grows</b></summary>

The records are **not** a reliable lifetime total: the Codex collector only
reads session files touched in the last 30 days, and the Fireworks one asks its
billing API for 30 days. Summing `modelUsage` on every read would give a total
that *shrinks* when sessions age out — and a creature that de-evolves.

So OmaPkDex keeps the last total seen per agent and accumulates only positive
deltas. A record that shrinks, zeroes, or is rewritten contributes nothing,
never negative.

Counting starts at zero by default: on the first run your existing lifetime
total only sets the ruler, so the first creature does not graduate instantly.
Turn on `seedFromExisting` to let it count.

</details>

## ✨ Shiny

<p align="center">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/1.gif" width="76" alt="Bulbasaur">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/1.gif" width="76" alt="Shiny Bulbasaur">
  &nbsp;&nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/133.gif" width="76" alt="Eevee">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/133.gif" width="76" alt="Shiny Eevee">
</p>

One hatch in **64** comes out shiny — **1 in 48** once you own the Shiny Charm.
A shiny keeps its colors through the whole evolution line, and the ✨ shows on
the name, the history row and the dex cell. On a cell it marks the *species*: it
means "I have owned this one shiny", and it stays even while the cell shows the
normal artwork. A shiny individual's profile shows its own colors.

## A creature that reacts

Your companion reads your rhythm: **idle**, **working**, **focused**, **tired**
near a limit, **asleep** with no usage. Hatching and evolving get a flash and a
pop, and the egg wobbles from 90% of its threshold. A celebration is **stored**,
so a hatch that happened while the popout was closed is still celebrated the
next time you open it.

A line you have already graduated grows **2× faster**, with a capsule in the
panel explaining why the bar is moving so quickly.

<p align="center">
  <img src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/132.gif" width="76" alt="Ditto">
</p>

And rarely — one common hatch in **128**, on a line with two or more forms —
what you are raising is secretly something else, and reveals itself instead of
evolving. Its shiny stays hidden until then.

## Economy

<table>
<tr><th>Item</th><th>Price</th><th>Effect</th></tr>
<tr><td>🌿 Mint</td><td align="right">100M</td><td>rerolls its nature</td></tr>
<tr><td>🍬 Rare Candy</td><td align="right">500M</td><td>+100M of growth</td></tr>
<tr><td>🥚 Egg</td><td align="right">1B</td><td>release the current one and start over</td></tr>
<tr><td>🥚 Uncommon Egg</td><td align="right">2.5B</td><td>guarantees Uncommon or better</td></tr>
<tr><td>✨ Shiny Charm</td><td align="right">3B</td><td>shiny odds 1/64 → 1/48, forever</td></tr>
<tr><td>🥚 Rare Egg</td><td align="right">4B</td><td>guarantees Rare or better</td></tr>
</table>

Filling a rate-limit window pays Rare Candy — **5** for a weekly cap, **1** for
a session cap.

<p align="center">
  <img src="docs/screenshots/bag.png" width="420" alt="The Bag tab">
</p>

Two numbers that look arbitrary and are not. Rare Candy costs **5× what it
delivers**, because tokens are both the growth meter *and* the wallet — pricing
it at its XP value would make buying it free growth. And graded eggs are priced
off the graduation table, not off probability: by probability, two Uncommon Eggs
would beat one Rare Egg on every axis, and the higher tier would become strictly
inferior.

Buying an egg **releases** your current creature: it stays in the Pokédex and
the history with the forms it reached, but does not count as a graduation and
does not pay the 2× bonus. The real cost is losing the progress you had banked.

## Inside a profile

Nothing about an individual is stored. The IVs, the gender and the ability slot
are rolled from a generator seeded by that creature's own id, and the level is
the fraction of its growth — so the creatures already in your history got their
profiles retroactively, with no migration and no extra file.

The **nature** is the exception: the Mint rerolls it, so it is mutable and has to
be stored. Individuals that graduated before this version show "—" rather than a
nature they never had.

Stats use the main-series formula — `((2·base + IV) · level)/100 + level + 10`
for HP, the neutral form times the nature modifier for the rest. The learnset is
**Black 2/White 2** because that is the last generation with animated sprites,
which is the same bound as the hatch pool.

Base stats, abilities, the learnset and the species entry come from one PokéAPI
request per species, cached forever. Without that cache the profile still shows
level, nature and IVs: they do not depend on the network.

## Pinning a species to the bar

The star on a Pokédex cell pins that species to the bar, independent of the
companion you are raising. The panel keeps showing the real creature and its
progress — only the bar stops following, and a ★ on the sprite says so.

## Interaction

| Where | What |
|---|---|
| **Bar icon** | left click opens the panel, middle click re-checks usage |
| **Tabs** | `←`/`→` (or `h`/`l`) switch, `1`–`6` jump to one |
| **Panel keys** | `r` re-checks, `a` opens the `omarchy.agents` panel, `Tab` moves to the neighbouring bar popout, `Esc` closes |
| **Pokédex** | hover shows the detail line under the grid; click a cell for the profile; the star pins a species to the bar |
| **IPC** | `omarchy-shell io.github.heitorm50.omapkdex <open\|close\|toggle\|refresh\|hatch\|companion\|dex\|log\|bag\|shop\|settings\|profile>`, plus `profileOf <species number>` |

## Settings

Growth difficulty and shop prices have sliders in the **⚙ Settings** tab. The
full set lives in `~/.config/omarchy/shell.json`, in the widget's entry:

```bash
omarchy bar set io.github.heitorm50.omapkdex difficulty 1.0 --json
omarchy bar set io.github.heitorm50.omapkdex showTokens false --json
```

| Key | Default | What it does |
|---|---|---|
| `difficulty` | `0.3` | Multiplies growth thresholds, 0.1–2.0. Changing it rescales banked progress, so nothing evolves for free |
| `shopDifficulty` | `1.0` | Multiplies shop prices, independent of growth |
| `spriteSize` | `22` | Sprite height in the bar, in px |
| `showTokens` | `true` | Show today's tokens next to the sprite |
| `showLimitPercent` | `false` | Show the tightest rate-limit percentage |
| `seedFromExisting` | `false` | Count usage already recorded |
| `representativeSpeciesId` | `0` | Species pinned to the bar; 0 follows the companion |
| `pollSeconds` | `60` | Safety net; records are already watched by event |

## Architecture

The records are a public contract of `omarchy.agents` (`schemaVersion: 1`,
documented at `/usr/share/omarchy/shell/plugins/agents/README.md`). OmaPkDex is
a read-only consumer: it never runs `omarchy-agent-usage-update` and never talks
to the providers' APIs.

```
BarWidget.qml            watches and orchestrates; writes nothing
Panel.qml                popout shell: tabs, keyboard, lifecycle
CompanionView.qml    \
DexView.qml           |
CatchLogView.qml      |  one tab each, presentation only
BagView.qml           |
ShopView.qml          |
SettingsView.qml     /
SpeciesProfileView.qml   the profile of a species and of each individual
Balance.js               read-side math (thresholds, progress, prices, formatting)
Collection.js            the Pokédex projection over the catch log
Profile.js               the individual: IVs, gender, ability, level, stats, moves
bin/omapkdex-sync        the only writer: PokéAPI, sprites, all state mutation
```

State mutation lives in the helper, not in QML, because **the bar instantiates
one widget per monitor**: two widgets accumulating the same delta would count it
twice, and `state.json` would have two writers. With the rule in the helper,
behind a `flock`, the number of monitors stops mattering — and the logic becomes
testable in Python instead of mirrored between QML and a test.

<details>
<summary><b>Files written, and the helper's subcommands</b></summary>

| Path | Written by |
|---|---|
| `~/.local/state/omarchy/<id>/state.json` | `omapkdex-sync absorb` |
| `~/.local/state/omarchy/<id>/companion.json` | `omapkdex-sync hatch` |
| `~/.local/state/omarchy/<id>/collection.json` | `absorb`, `hatch`, `buy`, `use` |
| `~/.cache/omarchy/<id>/sprites/` | `omapkdex-sync` |
| `~/.cache/omarchy/<id>/base-species.json` | `omapkdex-sync index` |
| `~/.cache/omarchy/<id>/details/<species>.json` | `omapkdex-sync details` |

```bash
bin/omapkdex-sync index                   # rebuild the 329 base-species index
bin/omapkdex-sync hatch [tier]            # roll a species and resolve its line
bin/omapkdex-sync sprites <ids...>        # (re)download sprites
bin/omapkdex-sync details <species>       # cache the species data the profile needs
bin/omapkdex-sync absorb <dif> [seed]     # accumulate tokens, advance progress
bin/omapkdex-sync buy <item> <dif> [tier] # rareCandy|mint|shinyCharm|egg
bin/omapkdex-sync use <item> <dif>        # rareCandy|mint
```

Sprites are the animated Gen-V GIFs from
`raw.githubusercontent.com/PokeAPI/sprites`, falling back to the static PNG when
a species has no animation. Downloaded once and cached. The species index comes
from PokéAPI's GraphQL endpoint (0.7s) with a REST fallback (~60s) if it is
down.

</details>

## Tests

```bash
tests/test_collection.py   # collection and the shiny roll
tests/test_absorb.py       # accumulation and integration, against real records
tests/test_economy.py      # wallet, prices, candy, eggs, burn rate, rescaling
tests/test_ditto.py        # the disguise, the hidden shiny, the reveal
tests/test_resilience.py   # what happens when the network fails mid-operation
tests/test_details.py      # species data: normalization, cache, REST fallback
tests/test_dex.mjs         # the Pokédex projection, ownership, the 2× bonus
tests/test_profile.mjs     # IVs, gender, ability, level, stats, moves
tests/test_shop.mjs        # shop list, bag, mood, bar tooltip
```

**570 assertions**, none of which touch the network or your real state.

<details>
<summary><b>The ones that matter most</b></summary>

- **Using a candy does not grow your wallet** (`test_economy.py`): the wallet is
  lifetime minus spent, so adding candy XP to lifetime would make every candy a
  money printer.
- **Changing difficulty does not evolve anything** (`test_economy.py`): the
  banked tokens are absolute and the thresholds are derived, so lowering the
  multiplier used to graduate a creature for free — 240M of progress against
  thresholds of 75M+150M covers a whole line at once.
- **The same creature always gets the same IVs** (`test_profile.mjs`): the
  profile is projected from a seed, so an unstable hash would change someone's
  Pokémon behind their back.
- **The first run pays no retroactive candy**: enabling the feature with a
  weekly cap already at 100% would hand out 5 free candies.
- **A record that shrinks** (`test_absorb.py`): the lifetime total must not fall
  and the stage must not regress when sessions age out of the Codex collector's
  30-day window.
- **Two hatches in the same second** do not leave two open history entries. That
  test is what revealed `hatchedAt` — one-second resolution — was unusable as an
  entry identity.
- **The ✨ marks only species actually reached** (`test_dex.mjs`), and stays
  hidden while a disguise is in play, everywhere: bar, panel, dex and history.
- **A network failure mid-operation** (`test_resilience.py`) leaves no phantom
  graduation, no duplicate entry, and no token charged without delivery. The
  absence of this suite is what let three of those through 349 assertions:
  every other stub replaces the network with functions that always succeed.
- **The threshold the UI shows is the one the helper charges**, with and without
  the 2× bonus (`test_shop.mjs`).

</details>

<details>
<summary><b>Editing the plugin</b></summary>

Saving a file under `~/.config/omarchy/plugins/` reloads the plugin, but the QML
engine keeps a component cache that **neither the hot-reload nor
`omarchy-shell shell rescanPlugins` clears reliably**. A change to a `.qml` file
can keep running the old version with no warning at all — the symptom is new
code that plainly does not execute. To be sure you are testing what is on disk:

```bash
omarchy restart shell
```

</details>

## Credit and scope

The idea, the token balance and the companion mechanics come from
**PokeTokenBar** by [chattymin](https://github.com/chattymin/PokeTokenBar)
(MIT), a native macOS app with no Linux port. This plugin reimplements that
layer for Omarchy's Quickshell, reading `omarchy.agents` records instead of
collecting usage itself.

Left out on purpose: the floating desktop pet, and per-day cost in dollars — the
records carry no cost field, and reimplementing a per-model price table would go
stale on its own. Token charts, per-model breakdowns and rate-limit detail are
left to `omarchy.agents`, which already draws them one click away in the bar.

Unofficial, non-commercial fan project. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) — nothing third-party is
bundled in this repository; sprites are fetched at runtime and the ones in this
page are loaded from PokéAPI's own repository.

## License

MIT, see [LICENSE](LICENSE).
