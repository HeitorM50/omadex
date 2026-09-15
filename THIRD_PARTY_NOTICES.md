# Third-party notices

## Nothing third-party is bundled

This repository contains no third-party code and no third-party data. Every
species, evolution chain, and sprite is fetched over the network the first time
it is needed and cached under
`~/.cache/omarchy/io.github.heitorm50.omapkdex/`. No API key or account is
required.

The screenshots under `docs/screenshots/` and `preview.png` are captures of this
plugin's own interface. Some of them show sprite artwork rendered inside it,
which remains the property of the rights holders named below.

The animated sprites in `README.md` are **not** copies either: they are
`<img>` references to PokéAPI's own sprite repository, loaded by the browser
when the page is viewed — the same source, and the same arrangement, that the
plugin uses at runtime.

## PokéAPI

Species, evolution chains, and capture rates are fetched at runtime from
PokéAPI.

- Upstream: <https://pokeapi.co>, source at <https://github.com/PokeAPI/pokeapi>
- License: BSD-3-Clause

Sprite images are fetched from PokéAPI's sprite repository at
<https://github.com/PokeAPI/sprites>.

## Pokémon

Pokémon character names, designs, sprites, and artwork are trademarks and
copyrighted works of Nintendo, Game Freak, Creatures Inc., and The Pokémon
Company. This plugin is an unofficial, non-commercial fan tool and is not
affiliated with, endorsed by, or sponsored by any of them.

PokéAPI's own license states the same distinction: it licenses its software
under BSD-3-Clause while noting that "Pokémon and Pokémon character names are
trademarks of Nintendo."

## PokeTokenBar

The idea, the token economy balance, and the companion mechanics (hatching,
evolving through the real evolution line, graduating) come from **PokeTokenBar**
by chattymin — <https://github.com/chattymin/PokeTokenBar> — licensed MIT.

The original is a native macOS app (Swift 6, SwiftUI/AppKit, `NSStatusItem`)
with no Linux port. This plugin reimplements the companion layer in QML and
Python for Omarchy's Quickshell, reading the usage records that `omarchy.agents`
already maintains instead of collecting usage on its own.

Balance constants ported verbatim from
`Sources/PokeTokenBar/Core/CompanionModel.swift`: the egg hatch threshold, the
graduation totals per rarity, the per-stage cost formula, the `capture_rate`
ceilings for rarity, the difficulty multiplier range, and the item prices.

## Omarchy

This plugin reads the usage records written by the first-party `omarchy.agents`
plugin, whose record format is documented at
`/usr/share/omarchy/shell/plugins/agents/README.md`. It never writes to those
records and never runs the collectors.
