# Color Bus

Portrait passenger/bus color-matching puzzle game. Single Godot 4 project,
single GDScript codebase shared by Android and iOS.

## Status

Milestone 5: PassengerQueue scene, on top of Milestone 4's reusable
Passenger scene, Milestone 3's typed data models, and Milestone 2's app
navigation shell. MainMenu (Play / Levels / Settings) navigates to
LevelSelect and Settings placeholder screens through `AppRouter`, with
centralized back navigation (in-app Back button and the Android hardware
back button both funnel through the same code path). `SaveManager`,
`SettingsManager` and `AudioManager` exist as service foundations.
`PassengerColor`/`PassengerData`/`BusData`/`PassengerQueueData`/
`WaitingAreaData`/`LevelData`/`GameState`/`GameStateSnapshot` exist as the
pure-data layer for gameplay. `scenes/entities/passenger.tscn` is a
colored, selectable passenger token with no external art.
`scenes/game/passenger_queue.tscn` stacks Passengers vertically, keeps only
the front one selectable, advances automatically when it's removed, and
emits `queue_emptied` once the last one is gone (see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)). No Bus/Game scene, waiting
area, or real gameplay flow exist yet -- PassengerQueue isn't wired into
anything.

## Tech stack

- Godot 4.7, Standard build (no C#/.NET)
- Typed GDScript throughout
- Reference resolution 1080x1920, portrait, `canvas_items` stretch mode with
  `expand` aspect (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for why)
- One codebase for Android and iOS; platform differences are isolated behind
  `PlatformService` (`scripts/platform/platform_service.gd`)
- Mouse/touch input emulation is disabled both ways (see
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)) so a single tap or click
  never fires a button's `pressed` signal twice

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
scenes/entities/     passenger.tscn, passenger_test.tscn (bus scenes later)
scenes/game/         passenger_queue.tscn, passenger_queue_test.tscn
scenes/menus/        menu scenes
scenes/ui/           reusable UI components
scripts/core/        AppRouter, AudioManager, other cross-cutting services
scripts/data/        SaveManager, SettingsManager, PassengerColor, LevelData
scripts/entities/    PassengerData, BusData (data) + Passenger (scene view)
scripts/game/        PassengerQueueData, WaitingAreaData, GameState(Snapshot),
                     PassengerQueue (scene view)
scripts/platform/    PlatformService and platform-specific code
scripts/ui/          UI scripts (MainMenu, app shell)
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
7. Responsive layout check across 5 phone resolutions
   (`tests/verify_responsive_layout.gd`)
8. App navigation check -- MainMenu -> LevelSelect -> back -> Settings ->
   Android back button -> back-at-root (`tests/verify_navigation.gd`)
9. Typed data model checks -- construction, validation and round-tripping
   for all 8 models (`tests/verify_data_models.gd`)
10. Passenger scene checks -- all 5 colors, the selectable/disabled/moving
    gates, and the move_to() Tween foundation (`tests/verify_passenger.gd`)
11. PassengerQueue checks -- only the front passenger is ever selectable,
    removing it advances the queue, the last removal emits `queue_emptied`,
    and a queue can't be double-removed or selected mid-animation
    (`tests/verify_passenger_queue.gd`)

Exits 0 only if every step above passes except the informational unused-
script report. See `tools/validation/` for the individual checks and
[CLAUDE.md](CLAUDE.md) for when to run this.

## Development rules

See [CLAUDE.md](CLAUDE.md) for the coding rules this project follows
(typed GDScript, 300-line script limit, no Node refs in save data, etc).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical design
and [docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md) for how
layout is verified across screen sizes.
