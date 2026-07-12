# Architecture

## Goals

- One Godot project, one GDScript codebase, running on Android and iOS.
- Game logic has zero knowledge of which platform it's running on.
- UI adapts to any portrait phone aspect ratio without manual per-device
  tuning.

## Display configuration

- Reference resolution: **1080x1920** (portrait).
- `window/stretch/mode = "canvas_items"`, `window/stretch/aspect = "expand"`.
  `expand` was chosen over `keep`: `keep` letterboxes the content to the
  reference aspect ratio (black bars on off-ratio devices), while `expand`
  reflows anchored Controls/Containers to the real device aspect ratio —
  which is what "responsive" means here. All layout must therefore be built
  with anchors and Containers, never fixed pixel positions.
- `get_viewport().get_visible_rect().size` reflects the real window size
  under this configuration (not the reference resolution), which is what
  the debug label and the responsive test plan rely on.

## Input

- Both mouse and touch must work identically, and a single tap/click must
  never trigger the same action twice. Godot's
  `input_devices/pointing/emulate_touch_from_mouse` and
  `emulate_mouse_from_touch` project settings are **both disabled**. Godot
  4's `Control`/`BaseButton` already handles `InputEventMouseButton` and
  `InputEventScreenTouch` natively; with either emulation flag on, one
  physical interaction produces a real event *plus* a synthesized companion
  event, and `BaseButton` reacts to both, firing `pressed` twice. With both
  off, exactly one event reaches the button per tap or click, on any
  platform. This couldn't be verified with a headless input simulation
  (the headless `DisplayServer` on this engine build doesn't run GUI
  pointer picking at all — confirmed while building this), so treat it as
  a reasoned engine-behavior decision to re-check on a real device/editor
  if it's ever revisited, per [CLAUDE.md](../CLAUDE.md).

## Safe area

- `PlatformService.get_safe_area_margins()` wraps
  `DisplayServer.get_display_safe_area()` and returns left/top/right/bottom
  insets. The app shell's `SafeArea` (`MarginContainer`) applies these as
  margin overrides so content never sits under a notch, status bar, or the
  home indicator. On desktop this safely resolves to zero margins.

## Platform isolation

All platform-specific branching (`OS.get_name()`, mobile-only APIs, input
quirks) lives in `scripts/platform/platform_service.gd`, the single
Autoload for this purpose. Game and UI code call into `PlatformService` and
never branch on OS name directly.

## Autoloads

Only real, always-needed global services are Autoload: `PlatformService`,
`SaveManager`, `SettingsManager`, `AudioManager`, `AppRouter` (load order,
top to bottom in `project.godot`, matching their dependency order —
`AudioManager` reads `SettingsManager`'s volumes, `AppRouter` calls
`PlatformService.quit_app()`). Per-run game state (`GameController` and
similar) is intentionally **not** Autoload — it will live inside the game
scene itself so it can be freed and rebuilt cleanly between runs instead of
persisting stale state for the process lifetime.

## Navigation (AppRouter)

`scripts/core/app_router.gd` is the single place that knows how to move
between app-level screens (`enum Screen { MAIN_MENU, LEVEL_SELECT,
SETTINGS }`). It holds a screen stack and a reference to a "screen root"
Control registered by whoever owns the mount point:

- `register_screen_root(container)` — called once by `main_screen.gd`.
- `push_screen(screen)` — appends to the stack and swaps the mounted scene.
- `pop_screen() -> bool` — pops back one screen; returns `false` if already
  at the root screen (nothing to pop).
- `current_screen()` / `can_pop()` — read-only state for the app shell's
  Header to react to (title text, Back button visibility).

Screens (`scenes/menus/*.tscn`) are plain, self-contained scenes with no
reference to AppRouter, each other, or the app shell — they only emit
`Button.pressed` and the app shell/AppRouter reacts. This keeps the "no
direct references between independent scenes" rule from
[CLAUDE.md](../CLAUDE.md) intact.

The Android hardware back button is handled in exactly one place:
`AppRouter._notification(NOTIFICATION_WM_GO_BACK_REQUEST)` (Godot's
built-in cross-platform notification for the OS back gesture/button). It
calls `pop_screen()`; if that returns `false` (already at the root screen),
it falls through to `PlatformService.quit_app()` — a real `get_tree().quit()`
on Android, a deliberate no-op on iOS/desktop (Apple's HIG directs apps to
never quit themselves). The in-app Back button in the Header calls
`AppRouter.pop_screen()` directly, so both paths converge on the same
logic.

## App shell (Milestone 2)

`scenes/app/main.tscn` / `scripts/ui/main_screen.gd`:

```
Main (Control, full rect)
└─ SafeArea (MarginContainer, margins from PlatformService)
   └─ RootVBox (VBoxContainer)
      ├─ Header (ColorRect, fixed min height)
      │  └─ HeaderBar (HBoxContainer)
      │     ├─ BackButton (hidden at the root screen, else pop_screen())
      │     └─ ScreenTitleLabel (current screen's title, from AppRouter)
      ├─ ContentArea (Control, expands to fill remaining space)
      │  └─ ScreenRoot (AppRouter mounts the active screen here)
      └─ Footer (ColorRect, fixed min height, reserved/empty for now)
```

`main_screen.gd` registers `%ScreenRoot` with `AppRouter`, pushes
`Screen.MAIN_MENU` as the initial screen, and keeps the Header in sync via
`AppRouter.screen_changed`. No gameplay logic exists yet; Footer is
reserved for future gameplay controls/bottom navigation.

## Data

- Levels are authored as JSON under `data/levels/` (no files exist yet --
  the loader described below is ready, but no level content has been
  authored, and no scene loads a level yet). JSON is validated before use —
  malformed or missing fields must fail loudly, not silently produce a
  broken level.
- Local saves use `user://` exclusively, and store plain data only (no Node
  references), per [CLAUDE.md](../CLAUDE.md). `SaveManager`
  (`scripts/data/save_manager.gd`) is the loader/writer foundation
  (`user://save.json`) — no game-progress fields exist yet.
- `SettingsManager` (`scripts/data/settings_manager.gd`) persists app-level
  preferences (audio volumes, language) separately from game saves, in
  `user://settings.json`. Both managers treat a missing or corrupt file as
  "use defaults", never as a crash.

## Typed data models (Milestone 3)

Pure data, no visual/Node reference anywhere, all `RefCounted` (chosen over
`Resource`: these are loaded from JSON and mutated freely during play, and
`Resource`'s default by-path caching/sharing semantics are the wrong fit for
mutable runtime game state — `RefCounted` has no such surprises). No
Passenger/Bus/Game *scene* exists yet; these are the data layer only.

```
PassengerColor          -- enum Value {RED, BLUE, YELLOW, GREEN, PURPLE}
                           + the one JSON string <-> Value converter
  ↓
PassengerData           -- { color }
BusData                 -- { color, capacity }
  ↓
PassengerQueueData      -- ordered Array[PassengerData] (one waiting line)
  ↓
WaitingAreaData         -- Array[PassengerQueueData] (all the waiting slots)
  ↓
LevelData               -- { level_id, waiting_area, bus_queue }, from JSON
  ↓
GameState               -- LevelData + in-progress play state (current_bus,
                           moves_made, is_complete, is_failed)
  ↓
GameStateSnapshot       -- GameState frozen into a plain Dictionary
```

- **PassengerColor** (`scripts/data/passenger_color.gd`) is the single
  central place JSON color strings become typed values.
  `PassengerColor.from_string()` returns `PassengerColor.INVALID` (`-1`,
  not a valid `Value`) for anything unrecognized — it never guesses or
  silently falls back to a default color. Every other model's `is_valid()`
  ultimately bottoms out in `PassengerColor.is_valid()`, so an unrecognized
  color string anywhere in a level makes that whole level fail validation
  rather than loading with a wrong/blank color.
- Every model has an `is_valid()`, and validity composes: `LevelData.is_valid()`
  checks `WaitingAreaData.is_valid()`, which checks every
  `PassengerQueueData.is_valid()`, which checks every
  `PassengerData.is_valid()`, which checks `PassengerColor.is_valid()`. One
  bad color anywhere fails the whole chain.
- `GameState` is the mutable "current play session" derived from a
  `LevelData` via `GameState.from_level()` (which also pops the first bus
  off the queue into `current_bus`). It still isn't a `GameController` —
  no scene drives it yet, it's just the data such a controller will need.
- **`GameStateSnapshot`** is the one place required to hold *only* plain
  data: its `data` field is a `Dictionary` of primitives/Arrays/Dictionaries
  built by `GameStateSnapshot.from_game_state()`, JSON-serializable via
  `to_json_string()`/`from_json_string()`, and turned back into a live
  `GameState` (with real `BusData`/`WaitingAreaData` instances) only by
  `restore_game_state()`. This is what save/undo/replay will serialize —
  never a `GameState` or any model object directly.
- All the `from_dict()`/`from_array()` parsers are defensive: an
  unexpected type at any field (not a String, not a Dictionary, not an
  Array) is skipped rather than crashing the parse, and the resulting
  model simply fails `is_valid()`. Nothing is ever silently coerced into a
  guessed-correct value.

## Audio

`AudioManager` (`scripts/core/audio_manager.gd`) is a plumbing-only
foundation: `register_sfx()`/`register_music()` associate a key with an
`AudioStream`, and `play_sfx()`/`play_music()` no-op safely if nothing is
registered under that key. No audio assets exist yet
(`assets/audio/` is empty), so nothing plays yet — that's expected. Master
volume is wired to the engine's built-in "Master" bus and reacts live to
`SettingsManager.settings_changed`.

## Testing

- `tests/` holds a dependency-free GDScript test runner for pure-logic code
  (added as gameplay logic lands).
- Responsive layout is verified by actually booting the app shell headlessly
  at several window sizes and reading back computed Control rects — see
  [RESPONSIVE_TEST_PLAN.md](RESPONSIVE_TEST_PLAN.md). Screenshots are not
  used for this (headless environments generally can't reliably grab GPU
  framebuffers), so verification is numeric: rects must tile the viewport
  with no gaps/overlaps and no negative sizes at every target resolution.
- App navigation is verified by `tests/verify_navigation.gd`, which drives
  `AppRouter` directly (push/pop, and simulating
  `NOTIFICATION_WM_GO_BACK_REQUEST`) and checks `%ScreenRoot`'s mounted
  scene, Header title, and Back button visibility at each step — real
  click/tap simulation isn't possible headlessly here (see the Input
  section above), so this exercises the same code path a button's
  `pressed` signal calls, not the button press itself.
- The typed data models are verified by `tests/verify_data_models.gd`:
  valid/invalid construction and round-tripping for all 8 models, plus a
  recursive check that `GameStateSnapshot.data` genuinely contains no
  `Object` (no stray model/Node reference hiding in the "pure data").
