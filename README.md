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
```

## Running

```bash
godot --path . --editor          # open in the editor
godot --headless --path . --import   # (re)import assets after pulling changes
```

## Development rules

See [CLAUDE.md](CLAUDE.md) for the coding rules this project follows
(typed GDScript, 300-line script limit, no Node refs in save data, etc).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical design
and [docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md) for how
layout is verified across screen sizes.
