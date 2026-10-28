# Project Architecture & Guidelines

## Core Principles
1. **Target platform**: Poki (wasm-web). Small download (release zip ≈1.4 MB), instant start, portrait (mobile) and landscape (desktop).
2. **GUI only**: there are no game objects with sprites. Everything is drawn by one GUI component (`main/gui/game.gui`) whose nodes are created from code. The `.gui` file only declares the atlas (`game`) and the font (`main`); `adjust_reference` is `ADJUST_REFERENCE_DISABLED`.
3. **Virtual canvas**: `main/modules/layout.lua` maps the window to 720x1280 (portrait, aspect < 0.9) or 1600x900 (landscape) virtual units. The render script uses the same module for the GUI projection. Input: `x = action.x / display.width * vw`.
4. **Logic in pure Lua**: `session.lua`, `board.lua`, `levels.lua`, `rng.lua`, `config.lua` use no Defold API and run in `tools/sim.lua` (LuaJIT). Views never change game state directly; they call session functions and animate `s.events`.
5. **Determinism**: levels use `rng.lua` (Park-Miller), never `math.random` (HTML5 runs Lua 5.1, desktop LuaJIT). `math.random` is allowed only for visual effects.
6. **Rebuildable views**: on resize or orientation change the whole screen is rebuilt from state (`app.rebuild`). Delayed view callbacks go through `ui.after`, which drops them after a rebuild. Never compare GUI nodes with `==` after they might be deleted (Defold raises "Deleted node"); compare tokens.
7. **Poki SDK** (`main/modules/poki.lua`): `gameplay_start` on the first successful tap of a level (idempotent), `gameplay_stop` on pause / result popups / menu, `commercial_break` before a level starts (from level 3), `rewarded` for rush order, second chance, x2 coins and empty boosters. Input and the session update are paused while an ad is active.
8. **Localization**: every visible string comes from `main/modules/i18n.lua` (en, ru, es, pt, de, fr, tr). Glyphs must exist in `main/assets/fonts/main.font` (`tools/gen_font.js`).

## Defold 1.14 API notes
- Node factories are `gui.new_box_node` / `gui.new_text_node`.
- `gui.get_text_metrics_from_node` is gone: use `resource.get_text_metrics(gui.get_font_resource("main"), text)` (`ui.text_width`).
- The DF font material is tagged `gui`, so the single `gui` predicate draws text too.

## Directory Structure
- `main/modules/` game rules, economy, save, SDK wrappers.
- `main/gui/` views (`game_view`, `menu_view`, `cafe_view`, `popups`), helpers (`ui.lua`), generated `sprite_sizes.lua`.
- `main/assets/` generated PNGs + `game.atlas`, OGG/WAV sounds (`main/sounds.go` is generated too), Nunito Black font.
- `main/game.appmanifest` trims the HTML5 engine (no physics, particles, profiler, Basis, ...). Do not use an excluded engine feature without editing it.
- `tools/` asset generators, `sim.lua`, `web_smoke.js`, build scripts.

## Mandatory Rule for Agents
Before changing the code read this file and [docs/KNOWLEDGE_BASE.md](docs/KNOWLEDGE_BASE.md). Balance changes go through `tools/sim.lua`. Record every gameplay, balance, UI or monetization change in the knowledge base change log. Regenerate assets with the tools instead of editing generated files (`game.atlas`, `sprite_sizes.lua`, `main.font`, `sounds.go`, PNG/OGG/WAV).
