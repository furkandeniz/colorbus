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

- Both mouse and touch must work identically. Godot's
  `input_devices/pointing/emulate_touch_from_mouse` and
  `emulate_mouse_from_touch` are both enabled so gameplay code only ever
  needs to handle one input path (see `_gui_input`/`InputEventScreenTouch`
  handling in UI/game code, added as gameplay lands).

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

Only real, always-needed global services are Autoload. As of this
milestone that's just `PlatformService`. Per-run game state
(`GameController` and similar) is intentionally **not** Autoload — it will
live inside the game scene itself so it can be freed and rebuilt cleanly
between runs instead of persisting stale state for the process lifetime.

## App shell (Milestone 1)

`scenes/app/main.tscn` / `scripts/ui/main_screen.gd`:

```
Main (Control, full rect)
└─ SafeArea (MarginContainer, margins from PlatformService)
   └─ RootVBox (VBoxContainer)
      ├─ Header (ColorRect, fixed min height)
      ├─ ContentArea (Control, expands to fill remaining space)
      │  └─ DebugLabel (shows current viewport size, live-updates on resize)
      └─ Footer (ColorRect, fixed min height)
```

No gameplay logic exists yet. This scene only proves the responsive shell:
safe area, header/content/footer proportions, and live resize handling.

## Data

- Levels are authored as JSON under `data/levels/` and loaded through a
  loader in `scripts/data/` (added when gameplay lands). JSON is validated
  before use — malformed or missing fields must fail loudly, not silently
  produce a broken level.
- Local saves use `user://` exclusively, and store plain data only (no Node
  references), per [CLAUDE.md](../CLAUDE.md).

## Testing

- `tests/` holds a dependency-free GDScript test runner for pure-logic code
  (added as gameplay logic lands).
- Responsive layout is verified by actually booting the app shell headlessly
  at several window sizes and reading back computed Control rects — see
  [RESPONSIVE_TEST_PLAN.md](RESPONSIVE_TEST_PLAN.md). Screenshots are not
  used for this (headless environments generally can't reliably grab GPU
  framebuffers), so verification is numeric: rects must tile the viewport
  with no gaps/overlaps and no negative sizes at every target resolution.
