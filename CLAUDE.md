# Color Bus — project rules

Godot 4 Standard, typed GDScript, single codebase for Android and iOS.
Portrait, reference resolution 1080x1920, `canvas_items` stretch / `expand`
aspect. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical
design.

## Coding rules

- Every function must declare a return type (`-> void`, `-> int`, ...).
- Every variable should be typed wherever possible.
- Scripts must not exceed 300 lines; split when they grow past that.
- Game logic and the visual/presentation layer must be kept separate.
- Independent scenes communicate via signals, not direct references.
- Avoid fixed, fragile deep node paths (`get_node("A/B/C/D")`); prefer
  `%UniqueName`, exported node references, or signals.
- JSON data must be validated before use — never trust a level file's shape.
- Save files must never contain a Node reference, only plain data.
- Platform checks (`OS.get_name()`, mobile-only APIs, etc.) must not leak
  into gameplay classes — route them through `PlatformService`.
- Run headless verification after any change (see below).
- One Git commit per working feature/milestone.
- Only implement one milestone per task — don't bundle unrelated work.
- Never leave a `.tscn` file that Godot cannot parse.
- Never write secrets (passwords, API keys, signing credentials) into the
  repository.

## Headless verification

Run after every change, before committing:

```bash
./tools/validate.sh
```

This runs the headless import, a GDScript parse check (with Autoloads
registered, unlike `--check-only -s` below), a JSON syntax check, a broken
`res://` reference check, an unused-script report, and a headless main-scene
boot check — see [tools/validation/](tools/validation/) and the README's
"Validating" section. It's also wired up as the VS Code task
**Color Bus: Validate Project**.

`godot --headless --check-only -s <script.gd>` compiles a script in
isolation, without the project's Autoloads registered — a script that
references `PlatformService` (or any other Autoload) will report a false
`Identifier not found` error under `--check-only` even though it runs fine
as part of the actual project (and as part of `tools/validate.sh`, which
loads scripts through the real project context). Only trust bare
`--check-only` for scripts with no Autoload references.

Responsive layout across phone sizes is verified by
`tests/verify_responsive_layout.gd` (see
[docs/RESPONSIVE_TEST_PLAN.md](docs/RESPONSIVE_TEST_PLAN.md)) — the
headless `DisplayServer` on this engine build ignores `--resolution` and
`--window-size`, so that script uses a `SubViewport` per target size
instead of trying to resize the real window. App navigation (MainMenu /
LevelSelect / Settings / back handling) is verified the same way by
`tests/verify_navigation.gd`. Both are run automatically by
`tools/validate.sh`.

A related gotcha for any *new* standalone `--script` entry point (not one
`load()`ed from inside another script's `_initialize()`): the entry
script's own top-level code is compiled before Autoloads exist as global
identifiers, so referencing `AppRouter`/`PlatformService`/etc. by their bare
name there fails the same way `--check-only -s` does. Work around it with
`get_node("/root/AutoloadName")` (see the top of
`tests/verify_navigation.gd`) instead of the bare name; scripts loaded
*during* `_initialize()` (like `main_screen.gd`, loaded as part of
instancing `main.tscn`) don't have this restriction.

Similarly: right after adding a **new** `class_name` script, running a
`--script` entry point that uses that class as a *type annotation*
(`var x: NewClass`, `-> NewClass`) fails with `Could not find type "X" in
the current scope` until the project has been re-imported (`godot
--headless --path . --import`, step 1 of `tools/validate.sh`) at least
once — the global class registry is populated at scan/import time, not
freshly discovered by a bare `--script` run. If a brand-new class's tests
fail this way, import first and retry before assuming the class itself is
broken.

A stronger, non-transient version of the same problem: **never write the
bare name of an Autoload singleton anywhere in the source of a
`class_name` script** (static method, instance method, doesn't matter),
and never in a `--script` entry point either. `godot --headless --script`
eagerly parses/validates every `class_name` script (and the entry script
itself) to build the global class table *before* Autoloads are attached
under `/root` — merely naming the identifier (e.g. `SettingsManager.
reduce_motion`) anywhere in that source, even inside a method that's
never called during this validation, corrupts that class's compiled form
for the rest of the process: later calls to an affected method fail with
`Nonexistent function` (as if the method didn't exist), or the whole class
falls back to a wrong base type (`Trying to assign value of type 'Control'
to a variable of type 'passenger.gd'`), and this does **not** self-heal
with a fresh `--import` — re-importing a project registers the class fine
(the import step has its own tolerant reload path) but every subsequent
cold `--script` process re-triggers the exact same corruption on first
touch. The only real fix is to never reference the Autoload by bare name
from a `class_name` script's source at all — reach it via NodePath string
instead: `Engine.get_main_loop().root.get_node_or_null("/root/SettingsManager")`
(and `.get("prop")`/`.set("prop", v)`/`.call("method", ...)` instead of typed
member access), since string literals aren't resolved as identifiers during
that early pass. See `AnimationConfig._reduce_motion()` in
`scripts/game/animation_config.gd` and `GameController._play_sfx()` in
`scripts/game/game_controller.gd` for the pattern, and
`tests/verify_game_animations.gd`'s `_get_reduce_motion()`/
`_set_reduce_motion()` for the same trick from a test entry script. (Found
while wiring `AnimationConfig`/`AudioManager` into `Passenger`, `Bus`, and
`GameController` for the animation milestone.)

## Autoloads

Only real global services are Autoload: `PlatformService`, `SaveManager`,
`SettingsManager`, `AudioManager`, `AppRouter`. `GameController`
(`scripts/game/game_controller.gd`) and `GameAnimator`
(`scripts/game/game_animator.gd`) are deliberately **not** Autoload —
both are plain `RefCounted` constructed by `GameScreen` in `_ready()` and
freed with it, so every level start is a genuinely fresh state machine and
animator, not persisted process-lifetime state.

## Input handling

`input_devices/pointing/emulate_touch_from_mouse` and
`emulate_mouse_from_touch` are both **off** in project.godot. Godot 4's
`BaseButton`/`Control` natively handle both `InputEventMouseButton` and
`InputEventScreenTouch` without emulation; with both flags on, a single tap
or click generates a real event *and* a synthesized companion event, and a
`Button` reacts to both, firing `pressed` twice. Don't turn these back on
without re-verifying `pressed` still fires exactly once per interaction on
both mouse and touch — this project's headless environment can't simulate
GUI pointer input to re-check it automatically (see the note in
`tests/verify_navigation.gd`), so this needs an actual device/editor check.

## GDScript lambda closures capture by value

A local variable reassigned *inside* a lambda (`func() -> void: flag =
true`) does **not** propagate back to the enclosing function's variable —
GDScript captures locals by value, so the lambda mutates its own private
copy. This silently breaks the common test idiom "connect a signal to a
lambda that flips a bool for later assertion." It only works by accident
for reference types (`Array`/`Dictionary`/`Object`) because the *copy* is
still a reference to the same underlying object, so `received.append(x)`
or `state_dict["done"] = true` do work. When a test needs to observe
whether a signal fired via a captured flag, wrap it: `var flag: Array =
[false]`, lambda does `flag[0] = true`, caller checks `flag[0]` — never a
bare `var flag: bool`. (Found and fixed in
`tests/verify_passenger_queue.gd`.)

## Synchronous signal cascades can finish a state machine mid-call

A signal emitted from deep inside a call (e.g. `Bus.board_passenger()` ->
`bus_completed` -> `BusQueue`'s handler -> `active_bus_changed` ->
`GameController`'s handler -> auto-board -> another bus completing ->
`_check_game_over()` -> `WON`) all runs **synchronously**, fully resolving
before control returns to the original call site. Any caller that
unconditionally sets state back to something like `PLAYING` right after
that call (`board_passenger(color); state = PLAYING`) will silently stomp
a `WON`/`LOST` that was *already* reached inside the cascade. Guard every
such post-action state write with "only if not already terminal"
(`if state != WON and state != LOST: state = PLAYING`). Also affects
setup order: if a handler is connected before the objects it reacts to are
fully configured (e.g. connecting to `BusQueue.active_bus_changed` before
the passenger queues have any passengers in them), the first synchronous
emission can run against still-empty state and reach the wrong
conclusion — configure everything the handler might inspect *before*
configuring whatever can emit the signal that triggers it. (Found and
fixed in `GameController.start()`/`_on_queue_passenger_selected()` via
`tests/verify_game_controller.gd`.)

## Class naming gotcha

Godot 4.7 has a **native** `ColorPalette` class. Any passenger/bus color
lookup class must use a different name (e.g. `PassengerPalette`) to avoid a
silent `class_name` collision.

## project.godot enum-hint settings are typed by their declaration, not their editor label

`display/window/handheld/orientation` (and similarly-declared settings)
show as a friendly string dropdown ("Landscape", "Portrait", ...) in the
editor's Project Settings UI, but the property is registered as
`Variant::INT` with `PROPERTY_HINT_ENUM` in Godot's own C++ source
(`core/config/project_settings.cpp`) — the on-disk/`project.godot` value
must be the **integer** ordinal (`1` = Portrait), never the display
string (`"portrait"`). A string value doesn't error anywhere; it silently
survives as `"portrait"` and then evaluates to `0` (Landscape) wherever
engine or export-plugin code does `int(get_project_setting(...))` on it —
this project shipped with the wrong string form from Milestone 1 through
Milestone 13 with nothing catching it (only became visible via the
generated iOS `Info.plist` in Milestone 14; Android happened to still
look right). When hand-editing `project.godot` for any enum-hint setting
you didn't set via the editor UI, check the setting's actual declared
`Variant` type in Godot's source first — don't assume the human-readable
label string is the stored value.

## iOS export template gotcha (Godot 4.7, Apple Silicon)

The official 4.7.stable iOS export templates have a confirmed, open
upstream bug ([godotengine/godot#118161](https://github.com/godotengine/godot/issues/118161)):
`libgodot.ios.{debug,release}.xcframework`'s `ios-arm64_x86_64-simulator`
slice claims (in the xcframework's own `Info.plist` manifest) to be a
universal arm64+x86_64 binary, but the actual `libgodot.a` is x86_64-only
(`lipo -info` confirms — `Non-fat file ... architecture: x86_64`, no
arm64 object code at all, verified directly on the freshly-downloaded
template zip, not just the exported project). Building the generated
Xcode project for `-sdk iphonesimulator` on an Apple Silicon Mac normally
fails to *link* (`Undefined symbols ... "_main"`) because Xcode tries to
select the (missing) arm64 simulator objects. Forcing
`ARCHS=x86_64 VALID_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO` gets it to build
successfully — but a current iOS Simulator runtime on Apple Silicon then
refuses to *install* that x86_64-only `.app` at all (`Failed to find
matching arch for input file`; no Rosetta-translation path for Simulator
app binaries in this environment). There is no project-side fix for
this — it needs an upstream Godot template fix, or a from-source
`libgodot` xcframework build (out of scope for a normal export task).
Re-check `xcrun simctl list runtimes` behavior and this issue's status
before assuming a future iOS Simulator build attempt is broken for some
other reason.
