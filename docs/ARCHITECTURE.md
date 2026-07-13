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

- Levels are authored as JSON under `data/levels/` — five sample levels
  ship today (see the "Level system" section below for the full pipeline:
  `LevelLoader`/`LevelValidator`/`LevelRepository`). JSON is validated
  before use — malformed or missing fields must fail loudly, not silently
  produce a broken level.
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
mutable runtime game state — `RefCounted` has no such surprises).

```
PassengerColor          -- enum Value {RED, BLUE, YELLOW, GREEN, PURPLE}
                           + the one JSON string <-> Value converter
  ↓
PassengerData           -- { color }
BusData                 -- { color, capacity }
  ↓
PassengerQueueData      -- ordered Array[PassengerData] (one waiting line)
  ↓
LevelData               -- { id, name_key, waiting_slot_count, buses,
                           passenger_queues, move_limit, tutorial,
                           difficulty }, from JSON (see "Level system" below)
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
- Every model has an `is_valid()`, and validity composes:
  `LevelData.is_valid()` checks every `BusData.is_valid()` and
  `PassengerQueueData.is_valid()` (which checks every
  `PassengerData.is_valid()`, which checks `PassengerColor.is_valid()`).
  This is a basic *structural* check only, though — the full business-rule
  validation (positive id, capacity balance per color, etc.) is
  `LevelValidator`'s job, run on the raw JSON before a `LevelData` is ever
  built (see "Level system" below).
- `GameState` is the mutable "current play session" derived from a
  `LevelData` via `GameState.from_level()` (which also pops the first bus
  off the queue into `current_bus`). It still isn't a `GameController` —
  no scene drives it yet, it's just the data such a controller will need.
- **`GameStateSnapshot`** is the one place required to hold *only* plain
  data: its `data` field is a `Dictionary` of primitives/Arrays/Dictionaries
  built by `GameStateSnapshot.from_game_state()`, JSON-serializable via
  `to_json_string()`/`from_json_string()`, and turned back into a live
  `GameState` (with real `BusData`/`PassengerQueueData` instances) only by
  `restore_game_state()`. This is what save/undo/replay will serialize —
  never a `GameState` or any model object directly.
- All the `from_dict()`/`from_array()` parsers are defensive: an
  unexpected type at any field (not a String, not a Dictionary, not an
  Array) is skipped rather than crashing the parse, and the resulting
  model simply fails `is_valid()`. Nothing is ever silently coerced into a
  guessed-correct value.

## Passenger scene (Milestone 4)

`scenes/entities/passenger.tscn` / `scripts/entities/passenger.gd` is the
first actual game-entity scene (everything before this was pure data). No
external visual assets: appearance is one rounded `Panel` colored via a
`StyleBoxFlat` built at runtime from `PassengerColor`.

```
Passenger (Control, script=passenger.gd)
├─ Visual (Panel)        -- appearance only, mouse_filter=IGNORE
└─ InputButton (Button)  -- flat, fully transparent stylebox overrides,
                            input only
```

- **Input is a Button, appearance is a Panel** — deliberately split so the
  Button (input) can be completely invisible while the Panel (visual)
  never has to deal with click/press state. This reuses the same
  single-fire-per-tap guarantee as every other button in the project (see
  the Input section above) instead of hand-rolling a second, riskier
  click-detection path for this one scene.
- **Three independent states**, each with its own setter, all funneling
  into `_update_visual()`: `selectable` (`set_selectable()`), `disabled`
  (`set_disabled()`, backed by `_disabled_override`), `is_moving`
  (`set_moving()`, set automatically by `move_to()`). `can_be_selected()`
  is `selectable and not disabled and not is_moving and` a valid
  `PassengerColor`. A passenger that can't currently be selected *for any
  reason* renders muted (`Color.lerp` toward gray) rather than only
  visually reacting to one specific flag — "not selectable right now"
  should always look the same regardless of which state caused it.
- **`configure(color)`** is the one entry point for setting the color from
  outside; it only touches the `color` field, then calls
  `_update_visual()` — data mutation and visual redraw are always two
  separate method calls, never inlined together, per
  [CLAUDE.md](../CLAUDE.md).
- `_update_visual()` guards with `if not is_node_ready(): return` —
  `configure()`/the setters can legitimately be called right after
  `instantiate()` + `add_child()`, before `_ready()` has run and the
  `@onready var _visual`/`_input_button` are resolved. `_ready()` calls
  `_update_visual()` itself once the node is actually ready, so nothing is
  lost — this just avoids a null-reference crash on the common
  "instance, add to tree, configure immediately" call pattern.
- **`move_to(target_position, duration)`** is the foundation for board
  movement: creates a `Tween`, animates `position`, sets `is_moving` true
  for the duration. Nothing calls it yet — no waiting-area/bus scene exists
  to decide *when* or *where* a passenger should move.
- `passenger_selected(passenger)` fires from `_on_pressed()` (connected to
  the InputButton's `pressed`) only when `can_be_selected()` is true.

## PassengerQueue scene (Milestone 5)

`scenes/game/passenger_queue.tscn` / `scripts/game/passenger_queue.gd`
stacks `Passenger` tokens vertically and enforces "only the front one is
selectable." It `extends VBoxContainer` directly rather than wrapping one —
one node, one array, no separate container reference to keep in sync.

```
PassengerQueue (VBoxContainer, script=passenger_queue.gd)
├─ Passenger  (front -- selectable)
├─ Passenger  (not selectable)
└─ Passenger  (not selectable)
```

- **`configure(colors: Array[int])`** rebuilds the queue from a list of
  `PassengerColor.Value`s (front = `colors[0]`), safe to call more than
  once on the same instance (clears first). This mirrors `Passenger`'s own
  `configure(color: int)` — the queue takes primitive typed data, not a
  `PassengerQueueData`, keeping the view layer decoupled from the data
  layer (a future `GameController`/`WaitingArea` bridges the two).
- **Data order and visual order can never drift apart** because there's
  only one collection: `_passengers: Array[Passenger]`, and every mutation
  (`configure()`, `_on_remove_finished()`, `_clear()`) adds/removes from
  both the array *and* the container's children together, in the same
  place. There's no separate index to fall out of sync.
- **Only the front is selectable**: `_refresh_selectable()` is the one
  place that calls `Passenger.set_selectable()`, setting it `true` for
  index 0 and `false` for everything else — and `false` for *everyone*,
  including index 0, while the queue is locked.
- **Removing the front advances the queue automatically**: `remove_front()`
  locks the queue, fades the front passenger out (a `Tween` on
  `modulate:a`), and only once that finishes does
  `_on_remove_finished()` actually erase it from `_passengers`, unlock, and
  call `_refresh_selectable()` again — which makes the new `_passengers[0]`
  selectable without any extra code path.
- **Locking during animation**: `_is_locked` blocks `remove_front()`
  entirely (a second call while locked is a no-op) and blocks *all*
  selection via `_refresh_selectable()`. This is what stops a rapid
  double-tap or a double `remove_front()` call from ever removing the same
  passenger twice — reinforced by a `_removed_passengers` dictionary guard
  as defense in depth.
- **`queue_emptied`** fires from `_on_remove_finished()` exactly when
  `_passengers` becomes empty after a removal — not proactively checked
  anywhere else.
- `passenger_selected(passenger)` is simply forwarded from whichever
  child's own `passenger_selected` fired (connected per-passenger in
  `configure()`); the queue doesn't filter it beyond what `Passenger`
  itself already gates via `can_be_selected()`.
- `PassengerColor.to_rgb(value)` was added here to give `Passenger` and
  `Bus` (below) the exact same color mapping from one place — it was a
  private `_color_to_rgb()` duplicated in `passenger.gd` until `Bus`
  needed the identical mapping; now both call the shared one.

## Bus and BusQueue scenes (Milestone 6)

`scenes/entities/bus.tscn` / `scripts/entities/bus.gd` and
`scenes/game/bus_queue.tscn` / `scripts/game/bus_queue.gd` mirror
Passenger/PassengerQueue's split (single entity view + composite queue
view), but a `Bus` has no click/tap surface of its own — boarding is
driven programmatically, since passengers are what get tapped, not buses.
"Business logic and visual layer separated" here means `configure()` /
`board_passenger()` / `set_active()` only ever mutate data and call
`_update_visual()` — no view code makes a boarding decision, and no
gameplay code touches a StyleBox.

```
Bus (Control, script=bus.gd)
├─ Visual (Panel)          -- body color, muted when inactive/completed
├─ CountLabel (Label)      -- "current/capacity" text
└─ FillBar (ProgressBar)   -- fill indicator, same color as Visual
```

- **`configure(color, capacity)`** always starts a fresh bus (0 passengers,
  not completed) — a `Bus` is configured once per bus, never "topped up".
- **`can_accept(color)`** is the single same-color check: active, not
  completed, has room, and the color actually matches. `board_passenger()`
  calls it first and does nothing (returns `false`) if it fails — a wrong
  color, a full bus, an inactive bus, and an already-completed bus are all
  rejected the exact same way, by the exact same gate.
- **The fill indicator** (`FillBar`, a `ProgressBar` with `show_percentage
  = false`) and `CountLabel` are driven by `current_passengers`/`capacity`
  in `_update_visual()`, colored via `PassengerColor.to_rgb()` like
  everything else — no textures, same technique as `Passenger`.
- **`bus_completed`** fires exactly once, the instant `current_passengers`
  reaches `capacity` inside `board_passenger()` — never again afterward,
  since `can_accept()` already blocks a completed bus from boarding anyone
  else.

```
BusQueue (HBoxContainer, script=bus_queue.gd)
├─ Bus  (active_index -- active)
├─ Bus  (not active)
└─ Bus  (not active)
```

- **Buses are never removed on completion** (unlike PassengerQueue's
  passengers, which physically leave) — a completed `Bus` stays visible,
  marked completed, and `BusQueue` just advances `_active_index` to the
  next one. This matches the literal requirement ("mark it completed, the
  next one becomes active"), not a removal.
- **`configure(bus_data_list: Array[BusData])`** takes external `BusData`
  the same way `PassengerQueue.configure()` takes raw colors — the queue
  view stays decoupled from anything that decides what buses exist (a
  future `GameController`/`LevelData` bridges the two).
- `_on_bus_completed(bus)` guards `if bus != active_bus(): return` — only
  the currently active bus completing can ever advance the queue, so a
  stale signal from a bus that isn't active (shouldn't normally happen,
  since inactive buses reject boarding via `can_accept()`) can't
  double-advance it.
- **`active_bus_changed`** fires both on the initial `configure()` (index 0
  becoming active) and every time `_active_index` advances.
  **`bus_queue_completed`** fires once `_active_index` moves past the last
  bus — i.e. every bus has completed in sequence.

## WaitingSlot and WaitingArea scenes (Milestone 7)

`scenes/entities/waiting_slot.tscn` / `scripts/entities/waiting_slot.gd` is
a single position holding at most one `Passenger`; `scenes/game/
waiting_area.tscn` / `scripts/game/waiting_area.gd` is a row of them
(default 3, resizable via `configure(slot_count)`, e.g. from
`LevelData.waiting_area.slot_count()`). Unlike `PassengerQueue` (a strict
FIFO where only the front is ever touched), a `WaitingArea` allows adding
to the first empty slot, finding/removing *any* waiting passenger by
color, and always compacts the rest left afterward — closer to a small
parking/holding row than a line.

```
WaitingArea (HBoxContainer, script=waiting_area.gd)
├─ WaitingSlot  (holds a Passenger, or empty)
├─ WaitingSlot
└─ WaitingSlot
```

- **`_occupancy: Array[int]`** (one `PassengerColor.Value` or
  `PassengerColor.INVALID` per slot) is the single source of truth — safe,
  plain data, never a set of Node references, directly satisfying "use
  safe data instead of Node references." Every mutation
  (`add_passenger()`, `remove_passenger_at()`, `configure()`) updates
  `_occupancy` first; `_render_slot()`/the loop in `remove_passenger_at()`
  then make the actual `Passenger` nodes match it. Compaction is
  implemented as **re-deriving what should be on screen from data**, not
  as moving existing `Passenger` nodes between `WaitingSlot`s — simpler and
  more robust than reparenting live nodes mid-animation-adjacent logic,
  at the cost of recreating a few `Passenger` instances on every removal
  (acceptable here since nothing requires preserving a specific instance
  across a compaction, unlike `PassengerQueue`'s fade-out).
- **`WaitingSlot` makes no decisions** — `is_empty()`/`get_color()`/
  `set_passenger()`/`clear()` are its whole surface. `WaitingArea` owns
  every rule (first-empty-slot placement, arrival order, compaction,
  capacity); this keeps "business logic and visual layer separated"
  literal, not just a comment.
- **`get_slot_color(index)`** and **`find_first_slot_of_color(color)`**
  return plain data (a color, a slot index) rather than a `Passenger`
  reference — the safe way to query the area's contents without touching
  a Node at all.
- **Signals**: `passenger_added(color, slot_index)` /
  `passenger_removed(color, slot_index)` fire on every successful
  add/remove; `waiting_area_full` fires the instant the last empty slot
  fills; `waiting_area_emptied` fires the instant the last passenger is
  removed. `passenger_selected(passenger, slot_index)` also forwards each
  slot's `Passenger.passenger_selected` — not explicitly required by this
  milestone's spec, but added for consistency with `PassengerQueue` (which
  has the same signal) and because a `WaitingArea` with literally no way
  to react to a tap would be a real gap given where this project is
  headed (a `GameController` will need it to know which waiting passenger
  was selected).
- **Responsive/safe-area compliance** here just means "behave like a
  normal Godot Container": `WaitingArea` is an `HBoxContainer` (reflows on
  its own), and `WaitingSlot` uses `custom_minimum_size` rather than
  fixed/absolute positions — so it drops into the existing `SafeArea` /
  responsive app shell (see the "App shell" section above) without any
  extra work once something actually places it there.

## Level system (Milestone 8)

`data/levels/*.json` is the on-disk format; `scripts/data/level_loader.gd`,
`level_validator.gd`, and `level_repository.gd` are the pipeline that turns
a file into a trustworthy `LevelData` — or a descriptive, non-crashing
error if it isn't one.

```
level_NN.json
  ↓ (raw text)
LevelLoader.load_level(path)
  ├─ file missing / unreadable / invalid JSON  -> LevelLoadResult (level=null, errors=[...])
  ├─ LevelValidator.validate(dict, path)        -> LevelValidationResult
  │    invalid                                  -> LevelLoadResult (level=null, errors=validation.errors)
  │    valid
  ↓
LevelData.from_dict(dict)                       -> LevelLoadResult (level=LevelData, errors=[])
```

- **JSON schema** (all 8 fields required): `id` (positive int), `name_key`
  (non-empty string, a localization key -- never raw display text, per
  the same convention as the menu screens), `waiting_slot_count` (int > 0,
  matches `WaitingArea.configure()`), `buses` (array of `{color,
  capacity}`), `passenger_queues` (array of arrays of `{color}`, matches
  `PassengerQueueData`/`PassengerQueue.configure()`), `move_limit` (int
  ≥ 0), `tutorial` (bool), `difficulty` (int).
- **`LevelValidator.validate(data, source_label)`** never touches
  `LevelData` at all — it works purely on the raw `Dictionary`, and
  collects *every* applicable error in one pass (not just the first) into
  a `LevelValidationResult`, each entry already formatted as
  `"<source_label>: <field.path> - <message>"` (e.g. `"res://data/levels/
  level_03.json: buses[1].capacity - must be positive (got 0)"`) — this is
  the literal "errors need a descriptive filename and field path"
  requirement. Structural checks (required fields present, right types)
  run first; the four business rules only run once those pass, since
  reporting a capacity-balance mismatch on top of an already-malformed
  `buses` array would just be noise:
  - `id` positive, `waiting_slot_count` > 0.
  - Every bus color is a recognized `PassengerColor` and every capacity is
    positive.
  - Every passenger color (in every queue) is a recognized
    `PassengerColor` — an unknown color anywhere fails the whole level.
  - Total passenger count across all queues equals total bus capacity,
    **and** each individual color's passenger count equals that color's
    total bus capacity (checked over the union of colors appearing on
    either side, so a color with passengers but no matching bus is caught
    too, not just an overall-total mismatch).
- **`LevelLoader.load_level(path) -> LevelLoadResult`** is the only place
  that touches the filesystem/JSON parser for a level. A missing file, a
  file that isn't valid JSON, or a `LevelValidator` failure all produce a
  `LevelLoadResult` with `level = null` and a populated `errors` array —
  never an exception, never a partially-built `LevelData`. `LevelData.
  from_dict()` is only ever called after validation passes, so **a raw
  JSON `Dictionary` never reaches a game scene** — only a validated,
  typed `LevelData` does (the literal "don't hand raw JSON dicts to game
  scenes" requirement).
- **`LevelRepository`** enumerates `data/levels/*.json` (sorted by
  filename) and loads them independently — `load_all_levels()` returns one
  `LevelLoadResult` per file, so one broken level file never prevents the
  other four from loading; `load_level_by_id(id)` searches for a specific
  level and returns a `LevelLoadResult` with a descriptive "no level
  defines id N" error (not a crash) if none matches.
- **The 5 sample levels** (`data/levels/level_01.json` .. `level_05.json`)
  go easy to hard: 1 color/1 bus (`tutorial: true`) up to all 5 colors
  across 5 buses and a 6-slot waiting area, `difficulty` 1 through 5 and
  `move_limit` increasing alongside. Every one is balanced (validated by
  `tests/verify_level_loading.gd`, which also intentionally breaks a copy
  of a valid level in four different ways under `user://` to prove each
  rejection path actually rejects, without ever touching the real files).

## GameScreen and GameController (Milestone 9)

`scenes/game/game_screen.tscn` / `scripts/game/game_screen.gd` is the
actual gameplay screen, pushed via `AppRouter.start_level(id)` (a fourth
`Screen.GAME`, plus a `pending_level_id` field GameScreen reads in
`_ready()` — the only screen so far that needs a parameter, so this is a
minimal addition rather than a general `push_screen(screen, data)` API).
`scripts/game/game_controller.gd` (`GameController`, **never Autoload** —
constructed by `GameScreen` in `_ready()` and freed with it, a genuinely
fresh state machine every level) is the play-session state machine.
`scripts/game/game_rules.gd` (`GameRules`) carries the stateless decision
logic (legal-move / auto-board / win checks) so `GameController` stays
focused on *sequencing*, not *deciding* — this is the "delegate as much as
possible to helper classes" split.

```
GameScreen._ready()
  → LevelRepository.load_level_by_id(pending_level_id)
  → builds empty BusQueue/WaitingArea/PassengerQueue×N view nodes
      (GameController never instantiates a scene itself)
  → GameAnimator.new(%AnimationLayer)
  → GameController.new(level, bus_queue, waiting_area, passenger_queues, animator)
  → controller.start()
```

- **States**: `LOADING`, `PLAYING`, `MOVING_PASSENGER`, `WON`, `LOST`,
  `PAUSED`. `state_changed(state)` drives `GameScreen`'s Win/Lose popups
  and the Pause button's enabled state — `GameScreen` never decides
  anything itself, only reacts.
- **The one player input path**: `GameController` connects to every
  `PassengerQueue.passenger_selected` (never to
  `WaitingArea.passenger_selected` — per the rules, only a queue's front
  passenger is ever actionable; a waiting passenger only moves again via
  auto-boarding, below). `_on_queue_passenger_selected()` is a no-op unless
  `state == PLAYING`, which is the single guard that satisfies both "no
  new selection during animation" and "the same passenger can't be
  processed twice" (reinforced further down by `PassengerQueue`'s own lock
  and `Passenger`'s own `selectable` flag).
- **Routing a selected passenger**: if the active bus `can_accept()` its
  color, it boards the bus; otherwise, if the waiting area has room, it
  goes there; otherwise the move is **rejected** — `queue.take_front()`
  only ever runs for an accepted move, so a rejected passenger stays
  exactly where it was. See "Milestone 10" below for how the actual flight
  is awaited before `board_passenger()`/`add_passenger()` runs.
- **Auto-boarding**: as of Milestone 10 this is an explicit, awaited
  `_run_auto_board_cascade()` called directly by `start()` and by
  `_on_queue_passenger_selected()` after every player move (**not** a
  `BusQueue.active_bus_changed` signal handler any more — see below for
  why). It boards every matching waiting passenger in FIFO order
  (`WaitingArea.find_first_slot_of_color()` always returns the
  earliest-added match) before anything else happens.
- **Win**: `GameRules.is_level_won()` is just `bus_queue.active_bus() ==
  null` — sufficient on its own given `LevelValidator` guarantees total
  passengers equals total bus capacity, so every passenger must already be
  boarded by the time every bus has completed in sequence.
- **Loss — the important, explicitly-required nuance**: a rejected move
  (waiting area full + color mismatch) does **not** by itself mean the
  level is lost. `GameRules.has_any_legal_move()` sweeps every queue's
  *current* front passenger and asks whether at least one of them either
  matches the active bus or would fit in the waiting area; only when
  **none** of them do is the level actually `LOST`. This check runs after
  *every* mutating event (a rejected move, a successful move, an
  auto-board pass) — not just rejections — because a *successful* move can
  itself be the one that closes off the last remaining option (tested
  explicitly: filling the last waiting slot with a now-permanently-
  mismatched color traps whatever's left).
- **A real bug integration testing caught**: `GameController.start()`
  configures the waiting area and passenger queues *before* the bus queue,
  not after. `BusQueue.configure()` synchronously emits
  `active_bus_changed` the moment it becomes non-empty — and
  `GameController` is already connected to that signal by the time
  `start()` runs it, so configuring the bus queue first meant the very
  first `_check_game_over()` pass ran against still-empty passenger
  queues and wrongly concluded "no legal move" (a transient, then
  self-corrected, `LOST` flash on every single level load). Reordering
  fixed it — but see the next point too.
- **A second, related bug**: because `board_passenger()`/a completing bus
  can synchronously cascade all the way through `active_bus_changed` ->
  auto-board -> `_check_game_over()` -> `WON`/`LOST` *before* the original
  call site regains control, `_on_queue_passenger_selected()` and
  `start()` must never unconditionally set `state = PLAYING` afterward —
  only if the state isn't already `WON`/`LOST`. Both call sites now guard
  on that explicitly; skipping this guard silently reverts a real win/loss
  back to "still playing" the instant the winning/losing move itself
  finishes processing.
- **Debug logging**: `GameController._debug_log()` gates every print
  behind `OS.is_debug_build()` — silent in a release export, verbose (one
  line per state transition) everywhere else, including every headless
  test run.

## Animation (Milestone 10)

Every gameplay animation (passenger flights, waiting-area compaction, bus
entrance/celebration/exit, rejected-tap feedback, win/lose popup entrance)
was added without changing any existing rule — `GameRules`'s three
functions and every state transition in `GameController` are unchanged in
*meaning*, only in *when* they run relative to a Tween.

- **Container-vs-animation conflict**: Godot Containers
  (`PassengerQueue`'s `VBoxContainer`, `BusQueue`/`WaitingArea`'s
  `HBoxContainer`) overwrite a child's `position`/`size` every layout
  pass, so animating `position` directly on a child of a Container
  silently does nothing (the container resets it next frame). Properties
  that are always safe regardless of Container parent: `rotation`,
  `scale`, `modulate`, `custom_minimum_size`, `pivot_offset` — these drive
  every *in-place* animation (`Passenger.play_rejected_feedback()`'s
  rotation shake, `Bus._play_entrance_animation()`/
  `_play_completion_celebration()`'s scale pulse and fade+shrink exit).
  `WaitingSlot` is *not* itself a Container, so `Passenger.
  play_slide_in_from_right()` (the compaction slide) can animate local
  `position` directly.
- **Cross-parent flight via an overlay layer**: any animation that has to
  visually cross between locations (queue → bus, queue → waiting slot,
  waiting slot → bus) reparents the passenger onto `GameScreen`'s
  `%AnimationLayer` (a plain full-rect `Control`, `mouse_filter = IGNORE`,
  not a Container) first, preserving `global_position` across the
  reparent, then tweens `global_position` freely. `GameAnimator`
  (`scripts/game/game_animator.gd`, never Autoload — one instance per
  `GameScreen`, constructed alongside `GameController`) owns this:
  `fly_passenger_to(passenger, target, base_duration)`.
- **Take/animate/finish pattern**: rather than a view component instantly
  freeing a removed node internally, each gained a "take" variant that
  detaches the live node *without* freeing it and *locks* immediately —
  `PassengerQueue.take_front()` (paired with `finish_external_removal()`
  once the flight lands) and `WaitingArea.take_passenger_at()` (already
  synchronous/self-contained, since only the *visual* removal is
  deferred). The lock is what satisfies "the same passenger must not be
  re-selectable during animation": `take_front()` sets `_is_locked = true`
  and calls `_refresh_selectable()` *before* detaching anything, so even
  the newly-promoted front passenger isn't selectable until
  `finish_external_removal()` runs.
- **Sequencing rule**: `board_passenger()`/`add_passenger()` (the actual
  game-state mutation) only ever runs *after* `await
  _animator.fly_passenger_to(...)` resolves — never before — which is
  what satisfies "game state must not update incorrectly before animation
  completes". The routing-to-waiting-area path additionally hides the
  real destination `Passenger` (`modulate.a = 0`) the instant
  `WaitingArea.add_passenger()` creates it, since that call is
  synchronous and would otherwise show a visible duplicate next to the
  still-flying one; it's revealed once the flight lands.
- **Auto-board is no longer signal-driven**: Milestone 9's
  `_on_active_bus_changed()` (connected to `BusQueue.active_bus_changed`)
  ran the whole auto-board pass *synchronously inside* whatever call
  completed a bus, which made it impossible to `await` a flight per
  passenger without racing the signal cascade. It's now
  `_run_auto_board_cascade()`, an explicit loop called with `await`
  directly by `start()` and by `_on_queue_passenger_selected()` — same
  FIFO rule, same trigger points, just genuinely awaitable.
- **Timeout-safe tween awaiting**: `GameAnimator._await_tween()` races
  `tween.finished` against a `SceneTreeTimer.timeout` (duration + 0.5s
  margin) using a shared one-element `Array[bool]` flag, so a Tween that
  never fires `finished` for any reason (a killed tween, a freed target)
  can't hang the awaiting coroutine forever — the concrete mechanism
  behind "an animation failure must not lock the game". Verified directly
  in `tests/verify_game_animations.gd` by `kill()`-ing a tween before it
  can finish and confirming the await still resolves.
- **Reduce motion**: `SettingsManager.reduce_motion` (persisted, no
  settings-panel UI yet — `settings_panel.tscn` is still a placeholder)
  scales every duration via `AnimationConfig.duration()` down by
  `REDUCE_MOTION_SCALE` (0.15, not zero — the Tween still needs to
  actually finish and fire `finished`). `AnimationConfig`
  (`scripts/game/animation_config.gd`) is the single place every
  animation's base duration lives.
- **No particle systems anywhere**: every animation is a plain property
  `Tween` (position/scale/rotation/modulate) — satisfies "don't use
  excessive particles on low-performance devices" by construction, not by
  a runtime toggle. `tests/verify_game_animations.gd` statically greps the
  animation-related scripts to keep it that way.
- **A genuinely nasty Godot gotcha found here**: referencing an Autoload
  singleton by its bare name (`SettingsManager.reduce_motion`,
  `AudioManager.play_sfx(...)`) anywhere in a `class_name` script's
  source — or in a `--script` entry point — corrupts that class's
  compiled form for the rest of the headless process, and does **not**
  self-heal with a fresh `--import` (unlike the already-documented
  "brand-new class needs an import" gotcha). `AnimationConfig.
  _reduce_motion()` and `GameController._play_sfx()` work around it by
  reaching the singleton via `Engine.get_main_loop().root.
  get_node_or_null("/root/Name")` (a NodePath *string*, not a bare
  identifier) plus `.get()`/`.set()`/`.call()`. See
  [CLAUDE.md](../CLAUDE.md) for the full writeup.

## Audio

`AudioManager` (`scripts/core/audio_manager.gd`) is a plumbing-only
foundation: `register_sfx()`/`register_music()` associate a key with an
`AudioStream`, and `play_sfx()`/`play_music()` no-op safely if nothing is
registered under that key. No audio assets exist yet
(`assets/audio/` is empty), so nothing actually plays yet — that's
expected. `GameController` already calls `play_sfx()` at the real trigger
points (`"passenger_board_bus"`, `"passenger_to_waiting"`) added in
Milestone 10, so wiring up real `AudioStream`s later is just
`register_sfx()` calls, no further code changes. Master volume is wired to
the engine's built-in "Master" bus and reacts live to
`SettingsManager.settings_changed`. As of Milestone 11, `play_sfx()`/
`play_music()` also no-op outright when `SaveManager.sound_enabled`/
`music_enabled` is false — the only place those two toggles are actually
consulted; nothing else needs to check them separately.

## Save and progress (Milestone 11)

`SaveManager` (`scripts/data/save_manager.gd`, Autoload, plain data only —
no Node/Object reference ever touches `user://save.json`) is local
persistence for level progress and a few user-facing toggles.

- **Schema**: `save_version` (int), `highest_unlocked_level` (int, level
  `id`s are 1-indexed and contiguous per `LevelRepository`'s sample set —
  a fresh save starts at `1`), `completed_levels` (`Array[int]`),
  `level_stars` (`Dictionary`, **always keyed by `String(level_id)`** —
  see below), `music_enabled`/`sound_enabled`/`vibration_enabled` (all
  default `true`), `first_launch_completed` (bool), `last_played_level`
  (int, `0` = none yet).
- **String keys for `level_stars`, deliberately**: a `Dictionary` with int
  keys round-tripped through `JSON.stringify()`/`JSON.parse()` always
  comes back with **String** keys (a JSON object's keys are always
  strings) — reading it back with the original int key would silently
  miss every entry that was ever saved to disk. Both
  `get_stars_for_level()` and `record_level_result()` convert with
  `str(level_id)` on every access so an in-memory-only value and a
  freshly-loaded one behave identically; there's no separate "the ints
  are for fresh sessions, the strings are for loaded ones" split to get
  wrong.
- **Never downgrading a star result**: `record_level_result(level_id,
  stars)` is safe to call on every replay of an already-completed
  level — it always keeps `max(previous_stars, stars)`, so a sloppier
  second playthrough can never erase a better first one.
- **Unlocking**: `record_level_result()` also sets
  `highest_unlocked_level = max(highest_unlocked_level, level_id + 1)` —
  winning level *N* unlocks level *N+1*, immediately, in the same call
  that records the star result (no separate "sync progress" step
  anywhere).
- **Star rating**: `GameRules.calculate_stars(moves_made, move_limit)`
  (pure, stateless, same home as `has_any_legal_move()`/`is_level_won()`)
  rates 3 stars at ≤50% of `move_limit`, 2 at ≤75%, 1 otherwise — a win
  always earns **at least 1 star**, even over the limit, since
  `move_limit` isn't currently a loss condition (see Milestone 9) and
  finishing at all shouldn't be worth zero. `GameController._check_game_over()`
  calls `GameRules.calculate_stars()` and hands the result to
  `SaveManager.record_level_result()` the instant `WON` is reached.
- **Atomic-ish write**: `save_data()` writes the full JSON payload to a
  sibling `save.json.tmp` file first, then `DirAccess.rename()`s it over
  `save.json` — an OS-level rename on every platform this project targets,
  so a crash or power loss mid-write can never leave a half-written,
  corrupt `save.json` in place; readers only ever see either the fully-old
  or fully-new file.
- **Corrupt file / missing file handling**: `load_data()` treats a missing
  file, an unreadable file, invalid JSON, and valid-JSON-but-not-an-object
  identically — reset to fresh defaults, **then immediately persist those
  defaults** (so a corrupt file self-heals on the very next launch instead
  of hitting the same corruption forever) — never a crash.
- **Migration hook, not yet exercised for real**: `_migrate(data)` reads
  `data["save_version"]` (defaulting to `0` for a file with no version
  field at all) and loops `_migrate_step()` until the data is
  `CURRENT_SAVE_VERSION`. Only the `0 -> 1` step exists today (stamps the
  version, no shape change needed since v1 is this milestone's first-ever
  schema) — a future schema change adds another `match` arm to
  `_migrate_step()` that actually transforms the dict's shape;
  `load_data()`/`save_data()` themselves never need to change.
- **`GameController` reaching `SaveManager`**: `GameController` is a
  `class_name` script, so it reaches `SaveManager` the same NodePath-string
  way `_play_sfx()` already reaches `AudioManager` (see Milestone 10's
  writeup and CLAUDE.md) — `_record_level_result()` never writes the bare
  `SaveManager` identifier anywhere in its source.
- **LevelSelect**: reads `SaveManager.is_level_unlocked(id)`/
  `get_stars_for_level(id)` per level and renders accordingly — a locked
  level gets a disabled `Button` and a `"level.locked"` status label
  instead of a star count. `LevelSelect` never decides progress itself,
  only reflects whatever `SaveManager` already has.
- **`MainMenu`'s Play button**: resumes `SaveManager.get_last_played_level()`
  if there is one, otherwise starts `get_highest_unlocked_level()` (level 1
  on a fresh save) — replacing Milestone 9's placeholder that always
  opened LevelSelect. `MainMenu._ready()` also calls
  `SaveManager.mark_first_launch_complete()` (a no-op after the first
  call) — simply reaching the main menu at all counts as "launched before"
  for now; there's no dedicated first-launch/onboarding UI yet, just the
  persisted flag for one to read later.
- **`GameScreen`/`MainMenu` reach `SaveManager` directly**: unlike
  `GameController`, neither of these scripts has a `class_name` — they're
  loaded as part of instancing their `.tscn` (during another script's
  `_initialize()`), which the CLAUDE.md gotcha explicitly carves out as
  safe, same as their existing direct `AppRouter`/`PlatformService`
  references.

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
- The Passenger scene is verified by `tests/verify_passenger.gd`: all 5
  colors, the selectable/disabled/moving gates (and that each one blocks
  `passenger_selected`), and the `move_to()` Tween foundation actually
  reaching its target and clearing `is_moving`. Since real click/tap
  simulation isn't possible headlessly, "pressing" is simulated by calling
  the private `_on_pressed()` directly — same approach and same limitation
  as the navigation test above. A separate, non-automated
  `scenes/entities/passenger_test.tscn` exists for a human to actually
  click through in the editor.
- PassengerQueue is verified by `tests/verify_passenger_queue.gd`: only the
  front is ever selectable, removing it advances the queue and promotes
  the next one, the last removal emits `queue_emptied`, a queue can't be
  double-removed (two `remove_front()` calls only ever remove one
  passenger), and nothing is selectable while locked mid-animation. A
  separate, non-automated `scenes/game/passenger_queue_test.tscn` shows
  three queues side by side for manual clicking. Building this test
  surfaced a real GDScript gotcha, not a PassengerQueue bug — see
  [CLAUDE.md](../CLAUDE.md)'s "GDScript lambda closures capture by value"
  section.
- Bus is verified by `tests/verify_bus.gd`: a wrong color is rejected, a
  correct color is accepted, capacity is never exceeded, `bus_completed`
  fires exactly once when full (not again on further attempts), and an
  inactive bus rejects boarding outright. No manual test scene this time —
  a `Bus` has no click surface, so there's nothing a human would click
  through that the automated test doesn't already exercise directly.
- BusQueue is verified by `tests/verify_bus_queue.gd`: only the first bus
  is active after `configure()`, filling the active bus advances
  `active_bus()` to the next one and fires `active_bus_changed`,
  completing every bus in sequence fires `bus_queue_completed`, completed
  buses stay in the queue rather than being removed, and a stale
  `bus_completed` from a non-active bus doesn't advance anything.
- WaitingArea is verified by `tests/verify_waiting_area.gd`: adding lands
  in the first empty slot, adding to a full area is rejected outright,
  a color can be found by its slot index, removing (from the front *and*
  from the middle) always compacts everything after it left with no gaps,
  the slot count is resizable both directly and via a real
  `LevelData.waiting_slot_count`, and `waiting_area_full`/
  `waiting_area_emptied`/`passenger_added`/`passenger_removed` all fire at
  exactly the right moments — not one slot early or late.
- The level system is verified by `tests/verify_level_loading.gd`: a valid
  level loads successfully, a level missing a required field is rejected
  with an error naming both that field and the source file, an unknown
  color is rejected, a total-passenger/total-capacity mismatch is
  rejected, loading a file that doesn't exist fails gracefully (not a
  crash), and all 5 real sample levels under `data/levels/` load and
  validate, in id order, with strictly increasing difficulty. The broken-
  level cases write temporary files under `user://test_levels/` (cleaned
  up afterward) rather than ever touching the real `data/levels/` files.
- GameController/GameRules are verified by `tests/verify_game_controller.gd`:
  a full level-1 playthrough reaching `WON`; a mismatched color routing to
  the waiting area instead of boarding; FIFO auto-boarding on an
  active-bus change (including one where the auto-board itself wins the
  level); a rejected move that does *not* end the game while a legal move
  exists elsewhere, vs. a *successful* move that reveals a genuine
  deadlock; that a passenger can't be processed twice from two
  back-to-back taps; and — the actual "playable via MainMenu" proof — all
  5 sample levels reaching `PLAYING` through the real
  `main.tscn` -> `AppRouter.start_level()` -> `GameScreen` stack, not just
  `GameController` exercised in isolation. Real click/tap simulation isn't
  possible headlessly (see the Input section above), so "tapping" calls
  `Passenger._on_pressed()` directly, same as every other test here. Since
  Milestone 10 every move now runs a real, awaited `GameAnimator` flight
  instead of an instant fade, so this test's `_await_settle()` helper polls
  until `GameController.state` actually leaves `MOVING_PASSENGER` (bounded
  by `MAX_SETTLE_FRAMES`) rather than waiting a guessed fixed delay.
- The Milestone 10 animation infrastructure is verified by
  `tests/verify_game_animations.gd`: `AnimationConfig.duration()` honors
  `SettingsManager.reduce_motion`; `PassengerQueue.take_front()` locks the
  whole queue immediately (not just the one passenger) so nothing —
  including the newly-promoted front — is re-selectable until
  `finish_external_removal()` runs; `GameAnimator._await_tween()`'s
  timeout safety net resolves even when a `Tween` is `kill()`-ed before it
  ever fires `finished`; a real `fly_passenger_to()` flight lands on its
  target's center and reparents onto the overlay animation layer; an
  unselectable tap's `play_rejected_feedback()` shake animates rotation
  without ever emitting `passenger_selected`; and a static grep confirms
  no gameplay script reaches for a particle system.
- The Milestone 11 save system is verified by `tests/verify_save_manager.gd`:
  first-launch defaults (and that a default save file is actually written
  to disk, not just held in memory); a save/reload round trip for every
  field (progress, toggles, first-launch, last-played); a corrupt
  `save.json` falling back to fresh defaults instead of crashing, and
  self-healing the file on disk so the next load doesn't hit the same
  corruption; winning a level unlocking the next one; a worse replay never
  downgrading an earlier best star result; and `music_enabled`/
  `sound_enabled`/`vibration_enabled` surviving a reload. `SaveManager`
  owns the one real path (`user://save.json`) under test — this backs up
  whatever's genuinely on disk before mutating it and restores it
  afterward, the same spirit as `verify_level_loading.gd`'s temp-file
  approach, just necessarily against the real path since that *is* the
  thing being tested.
- LevelSelect is verified by `tests/verify_level_select.gd`: all 5 sample
  levels are listed; a locked level renders a disabled `Button` and a
  `"level.locked"` status label instead of a star count; tapping an
  unlocked level's real `Button.pressed` signal (not a direct method call)
  opens `GameScreen` with the correct level id; winning that level through
  actual gameplay (the same tap-front-twice flow as
  `verify_game_controller.gd`'s level-1 test) unlocks the next level
  immediately; and progress survives a simulated app restart —
  `SaveManager.load_data()` re-reading `save.json` from disk exactly like
  a cold launch would, followed by rebuilding LevelSelect and confirming
  the unlock and star count are still there. Also backs up/restores the
  real `save.json`, same as `verify_save_manager.gd`.
