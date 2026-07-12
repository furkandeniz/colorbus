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

## Autoloads

Only real global services are Autoload: `PlatformService`, `SaveManager`,
`SettingsManager`, `AudioManager`, `AppRouter`. `GameController` and any
future per-run game state must NOT be Autoload — they belong to the game
scene's own tree so they can be reset between runs.

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

## Class naming gotcha

Godot 4.7 has a **native** `ColorPalette` class. Any passenger/bus color
lookup class must use a different name (e.g. `PassengerPalette`) to avoid a
silent `class_name` collision.
