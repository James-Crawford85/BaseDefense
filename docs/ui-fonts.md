# Steel Tide — UI Fonts

Fonts used in the in-game UI art (`assets/ui/InGameUI_Example.png`), for matching
the live HUD to the mockup.

| UI element | Font | Weight |
|------------|------|--------|
| `$30` (money) | Rajdhani | Bold |
| `LV 1` | Rajdhani | SemiBold |
| `WAVE 1 / 100` | Rajdhani | Bold |
| `KILLS 7` | Rajdhani | Bold |
| `BUILD` | Rajdhani | Bold |
| `GATLING / GUARD / CANNON` (tower names) | Rajdhani | SemiBold |
| `$120` (tower cost) | Rajdhani | Medium |
| `100 / 100` (bar values) | Rajdhani | SemiBold |
| Tiny technical text | Share Tech Mono | Regular |
| Major alerts (e.g. "WAVE INCOMING") | Oxanium | Bold |

## Notes for wiring these up

- **Rajdhani**, **Share Tech Mono**, and **Oxanium** are all free Google Fonts
  under the SIL Open Font License (OFL) — safe to bundle and ship commercially.
- Get the `.ttf` files from fonts.google.com and drop them in `assets/fonts/`.
  Rajdhani ships as separate weight files (Rajdhani-Bold / -SemiBold / -Medium).
- To apply: load each as a `FontFile`, then set per-label via
  `add_theme_font_override("font", font)` (+ `font_size`). Best done once as a
  shared helper in the HUD so every label pulls from the same set.
- Rajdhani is a condensed techy sans (the primary HUD face); Share Tech Mono is
  the monospace flavour text; Oxanium is the chunky alert face.

This is reference for the Stage B HUD restyle (matching fonts + segmented bars +
button art to the mockup).
