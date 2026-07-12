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
instead of trying to resize the real window.

## Autoloads

Only real global services are Autoload (currently: `PlatformService`).
`GameController` and any future per-run game state must NOT be Autoload —
they belong to the game scene's own tree so they can be reset between runs.

## Class naming gotcha

Godot 4.7 has a **native** `ColorPalette` class. Any passenger/bus color
lookup class must use a different name (e.g. `PassengerPalette`) to avoid a
silent `class_name` collision.
