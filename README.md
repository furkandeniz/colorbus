# Color Bus

Portrait passenger/bus color-matching puzzle game. Single Godot 4 project,
single GDScript codebase shared by Android and iOS.

## Status

Milestone 10: the game animates. Every passenger move (queue -> bus, queue
-> waiting slot, waiting slot -> bus via auto-board), waiting-area
compaction, a bus filling up and exiting, a new bus arriving, a rejected
tap, and the win/lose popups all have real Godot `Tween`-driven animation,
without changing any existing rule. `GameAnimator`
(`scripts/game/game_animator.gd`, never Autoload -- constructed once per
`GameScreen` alongside `GameController`) owns every cross-location "flying"
passenger animation via a take/animate/finish pattern (`PassengerQueue.
take_front()`/`finish_external_removal()`, `WaitingArea.take_passenger_at()`)
so a passenger mid-flight can never be re-selected and game state never
advances before its animation actually finishes. `AnimationConfig`
(`scripts/game/animation_config.gd`) centralizes every duration and honors
`SettingsManager.reduce_motion` (persisted, no UI toggle yet). Every
animation is a plain property `Tween` (position/scale/rotation/modulate) --
no particle systems anywhere. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the animation
architecture and a genuinely nasty Godot gotcha it uncovered.

Milestone 9: the game actually plays. `GameScreen`/`GameController` (never
Autoload -- owned solely by the GameScreen instance) wire together
everything from Milestones 3-8: a level loads, buses/queues/the waiting
area get built, tapping a queue's front passenger routes it to the active
bus (if it matches) or the waiting area (if there's room), a new active bus
auto-boards matching waiting passengers in FIFO order, and the level is won
or lost (via real deadlock detection, not just "waiting area is full") as
appropriate. All 5 sample levels are playable end to end via MainMenu ->
Levels -> tap a level. `AppRouter` gained a fourth screen (`GAME`) and
`start_level(id)`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the
full flow and two real bugs integration testing caught along the way.
`LevelLoader`/`LevelValidator`/`LevelRepository` load, validate (with
descriptive per-field errors) and enumerate `data/levels/*.json`.
`SaveManager`, `SettingsManager` and `AudioManager` exist as service
foundations. `scenes/entities/passenger.tscn`/`bus.tscn`/`waiting_slot.tscn`
and `scenes/game/passenger_queue.tscn`/`bus_queue.tscn`/`waiting_area.tscn`
are the gameplay view layer; `PassengerColor`/`PassengerData`/`BusData`/
`PassengerQueueData`/`LevelData`/`GameState`/`GameStateSnapshot` are the
pure-data layer.

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
data/levels/        JSON level definitions (5 sample levels, easy to hard)
docs/                architecture and process docs
exports/             local export output (git-ignored)
scenes/app/          root/app-shell scenes
scenes/entities/     passenger.tscn, bus.tscn, waiting_slot.tscn
                     (+ passenger_test.tscn)
scenes/game/         game_screen.tscn (the real gameplay screen),
                     passenger_queue.tscn, bus_queue.tscn, waiting_area.tscn
                     (+ passenger_queue_test.tscn)
scenes/menus/        main_menu.tscn, level_select.tscn (lists all levels),
                     settings_panel.tscn
scenes/ui/           reusable UI components
scripts/core/        AppRouter, AudioManager, other cross-cutting services
scripts/data/        SaveManager, SettingsManager, PassengerColor, LevelData,
                     LevelLoader, LevelValidator, LevelRepository
scripts/entities/    PassengerData, BusData (data) + Passenger, Bus,
                     WaitingSlot (views)
scripts/game/        PassengerQueueData, GameState(Snapshot), PassengerQueue,
                     BusQueue, WaitingArea, GameController, GameRules,
                     GameAnimator, AnimationConfig, GameScreen
scripts/platform/    PlatformService and platform-specific code
scripts/ui/          UI scripts (MainMenu, app shell, LevelSelect)
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
12. Bus checks -- wrong color rejected, correct color accepted, capacity
    never exceeded, and completion fires exactly once when full
    (`tests/verify_bus.gd`)
13. BusQueue checks -- only the first bus is active, filling it advances to
    the next (`active_bus_changed`), and completing the last bus completes
    the queue (`bus_queue_completed`) (`tests/verify_bus_queue.gd`)
14. WaitingArea checks -- adding to the first empty slot, rejecting
    additions once full, finding a passenger by color, left-compaction
    after a removal, a dynamic slot count (including one derived from
    `LevelData`), and the full/emptied/added/removed signals
    (`tests/verify_waiting_area.gd`)
15. Level loading/validation checks -- a valid level loads, a missing
    field/unknown color/capacity mismatch are each rejected with a
    descriptive error, a nonexistent file fails gracefully (not a crash),
    and all 5 sample levels load and validate
    (`tests/verify_level_loading.gd`)
16. GameController integration checks -- a full level playthrough reaching
    WON, mismatched-color routing to the waiting area, FIFO auto-boarding
    on an active-bus change (including one that wins the level), a
    rejected move that doesn't end the game vs. one that reveals a real
    deadlock, double-tap protection, and all 5 sample levels reaching
    PLAYING through the real MainMenu -> LevelSelect -> AppRouter stack
    (`tests/verify_game_controller.gd`)
17. Gameplay animation checks -- `AnimationConfig.duration()` honors
    `SettingsManager.reduce_motion`, `PassengerQueue.take_front()` locks
    the queue so nothing is re-selectable mid-flight until
    `finish_external_removal()`, `GameAnimator`'s timeout safety net
    resolves a `Tween` that never fires `finished`, a real
    `fly_passenger_to()` flight lands on its target and reparents onto the
    overlay animation layer, an unselectable tap's rejected-feedback shake
    plays without emitting selection, and no gameplay animation touches a
    particle system (`tests/verify_game_animations.gd`)

Exits 0 only if every step above passes except the informational unused-
script report. See `tools/validation/` for the individual checks and
[CLAUDE.md](CLAUDE.md) for when to run this.

## Development rules

See [CLAUDE.md](CLAUDE.md) for the coding rules this project follows
(typed GDScript, 300-line script limit, no Node refs in save data, etc).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical design
and [docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md) for how
layout is verified across screen sizes.
