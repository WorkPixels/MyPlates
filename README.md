# MyPlates

A clean, lightweight, highly customizable nameplate addon for World of Warcraft supporting **Classic Era**, **The Burning Crusade Classic (Anniversary)**, and **World of Warcraft: Forever (Midnight 12.0+ engine)**.

## Features

- **Dynamic Plate Width**: Automatically adjusts the health bar width so Level text, Threat percentage, and Health values never overlap.
- **DoT Kill Prediction ("Will It Die")**:
  - Live calculation projecting total remaining damage from active Damage-over-Time spells and bleeds.
  - Automatically captures tick damage via combat log monitoring (`SPELL_PERIODIC_DAMAGE`) and debuff tooltips.
  - Displays a **Skull marker** and highlights the bar with a lethal color when remaining DoT damage is mathematically guaranteed to kill the target.
  - Ghost overlay prediction bar illustrating the exact portion of the mob's health that will be depleted by DoTs.
  - Optional toggle to include party and raid members' DoT damage.
  - Strict unit aura isolation across multi-mob encounters.
- **Threat & Tank Indicators**:
  - Clear percentage display centered between level and health text.
  - Configurable threat coloring (Tank and DPS modes).
- **Target Highlights & Customization**:
  - Custom target border glow with adjustable color and thickness.
  - Sleek target brackets `[ ]`.
  - Elite dragon textures (Normal Elite, Rare, Rare Elite).
  - Configurable status bar textures and typography.
- **Aura Tracking**:
  - Native Midnight / Forever C-engine `AuraContainer` support.
  - Filtering for player-only debuffs and configurable icon limits.

## Slash Commands

```text
/mp         Open settings panel
/mp reset   Reset settings to defaults
/mp debug   Show runtime diagnostics
/mp test    Preview test aura icons
```

## Installation

Copy the `MyPlates` folder into your World of Warcraft directory:
`World of Warcraft\_forever_\Interface\AddOns\` (or `_anniversary_`, `_classic_`, etc.)
