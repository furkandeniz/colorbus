# Color Bus

Portrait passenger/bus color-matching puzzle game. Single Godot 4 project,
single GDScript codebase shared by Android and iOS.

## Status

Milestone 1: responsive mobile app shell only (Header / ContentArea / Footer
with safe-area support and a debug viewport-size label). No game mechanics
yet.

## Tech stack

- Godot 4.7, Standard build (no C#/.NET)
- Typed GDScript throughout
- Reference resolution 1080x1920, portrait, `canvas_items` stretch mode with
  `expand` aspect (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for why)
- One codebase for Android and iOS; platform differences are isolated behind
  `PlatformService` (`scripts/platform/platform_service.gd`)

## Requirements

- Godot 4.7 (Standard)
- Godot export templates matching the installed Godot version
- Java 17 (Android build)
- Android SDK (cmdline-tools, platform-tools, build-tools, platform,
  emulator)
- Xcode + Command Line Tools (iOS build, macOS only)

## Project layout

```
assets/            art, audio, fonts (by category)
data/levels/        JSON level definitions
docs/                architecture and process docs
exports/             local export output (git-ignored)
scenes/app/          root/app-shell scenes
scenes/entities/     passenger/bus scene prefabs
scenes/game/         gameplay scenes
scenes/menus/        menu scenes
scenes/ui/           reusable UI components
scripts/core/        cross-cutting utilities
scripts/data/        JSON loading/validation
scripts/entities/    passenger/bus logic
scripts/game/        puzzle/game logic
scripts/platform/    PlatformService and platform-specific code
scripts/ui/          UI scripts
tests/               dependency-free GDScript test runner
tools/validation/    automated project validation checks
```

## Running

```bash
godot --path . --editor          # open in the editor
godot --headless --path . --import   # (re)import assets after pulling changes
```

## Validating

Run every automated check with one command:

```bash
./tools/validate.sh
```

or from VS Code: **Terminal > Run Task... > Color Bus: Validate Project**
(also bound as the default build/test task).

This runs, in order:

1. Headless project import
2. GDScript parse check for every script under `scripts/`, `tools/`, `tests/`
3. JSON syntax check for every file under `data/`
4. Broken `res://` reference check across all `.tscn`/`.tres`/`.gd` files
5. Unused-script report for `scripts/` (informational, doesn't fail the run)
6. Headless boot check of the main scene

Exits 0 only if steps 1-4 and 6 all pass. See `tools/validation/` for the
individual checks and [CLAUDE.md](CLAUDE.md) for when to run this.

## Development rules

See [CLAUDE.md](CLAUDE.md) for the coding rules this project follows
(typed GDScript, 300-line script limit, no Node refs in save data, etc).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical design
and [docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md) for how
layout is verified across screen sizes.
