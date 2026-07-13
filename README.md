# Color Bus

Portrait passenger/bus color-matching puzzle game. Single Godot 4 project,
single GDScript codebase shared by Android and iOS.

## Status

Milestone 13: Android export infrastructure. `export_presets.cfg` (local,
git-ignored -- see the Android build section below) defines a debug APK
preset (package id temporarily `com.furkandeniz.colorbus`, portrait via
the existing `display/window/handheld/orientation` project setting,
architecture `arm64-v8a`) and a release AAB preset (uses Godot's Gradle
build, since AAB output requires it; no keystore is configured, so a real
release build fails until a developer supplies their own -- deliberately,
per "never commit signing secrets"). The debug preset builds and installs
cleanly with the project's already-installed toolchain (Java 17, Android
SDK platform-tools/platforms/build-tools) using Godot's precompiled export
templates, no Gradle/NDK/CMake needed. Verified end-to-end on a headless
Android emulator: install, launch, and `adb logcat` all confirm the app
boots to a running main loop with zero crashes/ANRs. See the Android
build section below for every command, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for why min/target SDK are
left at Godot's own template defaults rather than overridden.

Milestone 12: 20 MVP levels, controlled-designed (not random) across 5
difficulty tiers -- two colors (1-3), three colors + waiting area (4-7),
four colors + a more complex, repeated-color bus queue (8-12), five colors
+ longer queues (13-16), and five colors with a tight waiting area +
adversarially-ordered bus queue (17-20). Every level's total passenger
count and per-color passenger count exactly match total/per-color bus
capacity (`LevelValidator`'s existing balance rule), so no level has an
unused color. `tools/level_solver.gd` (`LevelSolver`) is a real
solvability checker: it models the exact `GameController`/`GameRules`
mechanics as pure data and searches every reachable game state via BFS
(deduplicated by a canonical state hash, bounded by
`MAX_EXPLORED_STATES` so a pathological level can never hang the search),
reporting whether at least one winning move sequence exists and, if so,
the true minimum move count. `tools/validation/check_level_solvability.gd`
runs it against every level under `data/levels/` and is wired into
`tools/validate.sh` as its own gating step -- all 20 shipped levels are
BFS-proven solvable. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for
the state model and why "which queue to tap next" is the only real
decision the solver has to search over.

Milestone 11: local save and level progression. `SaveManager`
(`scripts/data/save_manager.gd`) persists `user://save.json`: which level is
the furthest unlocked, which are completed and their best star rating
(1-3, never downgraded by a worse replay -- see `record_level_result()`),
`music_enabled`/`sound_enabled`/`vibration_enabled`, first-launch status,
and the last-played level. Writes are write-to-temp-then-rename (so a
crash mid-write can't corrupt the file), a `save_version` field plus a
`_migrate()` step function exist for a future schema change, and a
missing/corrupt file always falls back to (and persists) fresh defaults
rather than crashing. `LevelSelect` now reads real progress: locked levels
show a disabled button, unlocked/completed ones show their star count, and
winning a level unlocks the next one immediately, with no separate "sync"
step. `GameRules.calculate_stars()` rates a win 1-3 stars from
`moves_made` vs. the level's `move_limit` (a win always earns at least 1
star). `MainMenu`'s Play button now resumes the last-played level (or the
furthest unlocked one on a fresh save) instead of always opening
LevelSelect. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the save
schema and migration design.

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
- Java 17 (Android build) -- Godot 4.7's official requirement; newer JDKs
  work but 17 is what's verified here
- Android SDK: `platform-tools` >= 35.0.0, at least one recent platform
  (`android-35`/`android-36`), a matching `build-tools` version, and
  `cmdline-tools` -- see the Android build section below for exact
  versions verified against this project
- Xcode + Command Line Tools (iOS build, macOS only)

## Project layout

```
assets/            art, audio, fonts (by category)
data/levels/        JSON level definitions (20 MVP levels, easy to hard)
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
tools/level_solver.gd  LevelSolver: BFS-based level solvability checker
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
    and all 20 MVP levels load and validate, strictly increasing in
    difficulty (`tests/verify_level_loading.gd`)
16. GameController integration checks -- a full level playthrough reaching
    WON, mismatched-color routing to the waiting area, FIFO auto-boarding
    on an active-bus change (including one that wins the level), a
    rejected move that doesn't end the game vs. one that reveals a real
    deadlock, double-tap protection, and all 20 MVP levels reaching
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
18. SaveManager checks -- first-launch defaults (and that a default save is
    actually written to disk), a save/reload round trip for every field, a
    corrupt save file falling back to fresh defaults instead of crashing
    (and self-healing the file on disk), winning a level unlocking the
    next one, a worse replay never downgrading an earlier best star
    result, and music/sound/vibration toggles surviving a reload
    (`tests/verify_save_manager.gd`)
19. LevelSelect checks -- all 20 MVP levels are listed, a locked level
    shows a disabled button with no star count, tapping an unlocked
    level's real `Button.pressed` signal opens `GameScreen` with the
    correct level id, winning that level through real gameplay unlocks the
    next one immediately, and progress (unlock state and stars) survives a
    simulated app restart (`SaveManager.load_data()` re-reading
    `save.json` from disk) (`tests/verify_level_select.gd`)
20. Level solvability checks -- `LevelSolver`'s BFS search runs against
    every level under `data/levels/` and confirms all 20 MVP levels are
    solvable, reporting the true minimum move count for each
    (`tools/validation/run_level_solvability.gd`, wrapping
    `tools/validation/check_level_solvability.gd`)

Exits 0 only if every step above passes except the informational unused-
script report. See `tools/validation/` for the individual checks and
[CLAUDE.md](CLAUDE.md) for when to run this.

## Android build

### One-time toolchain setup

Set these in your shell profile (adjust paths to your own install):

```bash
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"   # or wherever you installed the SDK
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$JAVA_HOME/bin"
```

Verify the toolchain matches Godot 4.7's official Android export
requirements (docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html):

```bash
java -version                                    # need OpenJDK 17
adb --version                                    # platform-tools >= 35.0.0
sdkmanager --list_installed                      # need platforms;android-35 (or newer) + a matching build-tools
```

Then, in the Godot editor (**Editor > Editor Settings > Export > Android**,
a one-time machine-global setting, not part of the project), set:

- **Java SDK Path** -> `$JAVA_HOME`
- **Android SDK Path** -> `$ANDROID_HOME` (must contain `platform-tools/adb`)

### Export presets

`export_presets.cfg` is **git-ignored** (along with `*.keystore`/`*.jks`)
because Godot writes keystore paths/passwords into it in plain text the
moment you fill them into the export dialog -- never something to commit,
even for the debug keystore. Recreate it locally via **Project > Export...**
in the editor, or copy `export_presets.cfg.example` (committed, contains no
secrets -- every keystore field is intentionally blank) to
`export_presets.cfg` and adjust paths for your machine. It defines two
presets:

- **`Android`** -- debug APK, `com.furkandeniz.colorbus` (temporary package
  id -- change before any real release), portrait (from the project's
  `display/window/handheld/orientation` setting, not a per-preset field),
  `arm64-v8a` only, using Godot's precompiled export templates
  (`gradle_build/use_gradle_build=false`) -- no Gradle/NDK/CMake required.
  Min/target SDK are left at Godot's own template defaults rather than
  overridden, since overriding either **requires** `use_gradle_build=true`
  (Godot raises a hard export error otherwise) -- see
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **`Android (Release AAB)`** -- release, Android App Bundle format. AAB
  output itself requires `gradle_build/use_gradle_build=true` (a separate
  Godot requirement from the min/target SDK one above), which additionally
  needs the Android Gradle build template installed
  (**Project > Install Android Build Template**, not done here -- it adds
  a full Gradle project under `res://android/` that's normally committed
  once installed) and network access for Gradle to resolve dependencies.
  `keystore/release`, `keystore/release_user`, and `keystore/release_password`
  are **deliberately blank** -- exporting this preset for real fails
  until you point it at your own keystore; that failure is correct
  behavior, not a bug. Generate one with:

  ```bash
  keytool -v -genkey -keystore /path/outside/this/repo/release.keystore -alias colorbus -keyalg RSA -validity 10000
  ```

  Never generate or store a release keystore inside this repository, and
  never fill its path/password into a version-controlled file. The debug
  keystore (Godot's own, autogenerated, password always `"android"`) is
  fine to reference locally since it only ever signs non-distributable
  debug builds -- but the two must never be confused: only the release
  keystore's signature is accepted by the Play Store / matches previously
  published app updates.

### Building the debug APK

```bash
mkdir -p exports/android
godot --headless --path . --export-debug "Android" exports/android/colorbus.apk
```

Produces a signed `exports/android/colorbus.apk` (and a `.idsig` file)
using the debug keystore configured in Editor Settings.

### Installing and running it

```bash
adb devices -l                       # lists connected devices/emulators

# No device connected? Create/start an emulator:
avdmanager list avd                                          # see what already exists
emulator -avd <avd_name> -no-window -no-audio -no-boot-anim &  # boot it headlessly
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 5; done

adb install -r exports/android/colorbus.apk
adb shell am start -n com.furkandeniz.colorbus/com.godot.game.GodotAppLauncher

# Check for a launch crash:
adb logcat -d | grep -iE "FATAL EXCEPTION|AndroidRuntime: FATAL|ANR in|has died"
adb shell pidof com.furkandeniz.colorbus   # non-empty = still running, not crashed
```

A `-no-window` emulator (no attached display) may fail to present frames
to `screencap`/a real display surface (harmless `Couldn't present to
Vulkan queue` log lines) even though the app itself is running fine --
that's a headless-emulator display limitation, not a crash; the
logcat/`pidof` checks above are the actual signal to trust, not a
screenshot.

## Development rules

See [CLAUDE.md](CLAUDE.md) for the coding rules this project follows
(typed GDScript, 300-line script limit, no Node refs in save data, etc).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical design
and [docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md) for how
layout is verified across screen sizes.
