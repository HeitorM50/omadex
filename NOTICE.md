# Atribuição

## PokeTokenBar

A ideia, o balanceamento da economia de tokens e a mecânica de companion
(chocar, evoluir pela linha real, graduar) vêm do **PokeTokenBar** de
chattymin — https://github.com/chattymin/PokeTokenBar — licenciado MIT.

O original é um app macOS nativo (Swift 6, SwiftUI/AppKit, `NSStatusItem`) e não
tem porte para Linux. Este plugin reimplementa a camada de companion em QML e
Python para o shell Quickshell do Omarchy, lendo os records de uso do
`omarchy.agents` em vez de coletar uso por conta própria.

Constantes portadas verbatim de `Sources/PokeTokenBar/Core/CompanionModel.swift`:
o limiar de chocagem, a tabela de totais de graduação por raridade, a fórmula de
parcelamento por estágio, os limiares de `capture_rate` para raridade e a faixa
do multiplicador de dificuldade.

## PokéAPI

Espécies, linhas evolutivas e sprites vêm da PokéAPI — https://pokeapi.co/ —
e do repositório de sprites https://github.com/PokeAPI/sprites.

## Pokémon

Projeto de fã, não-comercial e não oficial. Pokémon e os nomes de personagens
são marcas registradas da Nintendo, Creatures Inc. e GAME FREAK inc. Este
plugin não é afiliado, patrocinado nem endossado por nenhuma delas.
