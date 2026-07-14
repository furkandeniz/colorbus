# Cross-platform audit (Milestone 15)

Full Android/iOS cross-platform audit of the codebase, run 2026-07-14
against Godot 4.7.stable. Covers the 11 checklist items below, the one
real bug found and fixed, build verification on both platforms, a save
format compatibility check, and a responsive-UI re-verification.

## Checklist results

| # | Check | Result |
|---|---|---|
| 1 | `OS.get_name()` scattered across game classes | ✅ Clean — exactly one call site, inside `PlatformService._detect_platform()`. Nothing else references it. |
| 2 | Duplicated Android/iOS game logic | ✅ Clean — no platform-suffixed files (`*android*`/`*ios*`) anywhere under `scripts/`; no `PlatformKind`/`is_mobile()` branching outside `PlatformService` itself. Single shared codebase, as designed. |
| 3 | UI depending on a fixed device resolution | ✅ Clean — every scene uses anchors/Containers exclusively; the only literal pixel sizes are intentional fixed token sizes (`Bus`/`Passenger`/`WaitingSlot`'s `custom_minimum_size`) inside a Container that itself lays out responsively. Re-verified by `tests/verify_responsive_layout.gd` across 5 phone resolutions (see [RESPONSIVE_TEST_PLAN.md](RESPONSIVE_TEST_PLAN.md)) — all still tile with no gaps/overlaps. |
| 4 | Buttons outside the safe area | 🔧 **Found and fixed** — see below. |
| 5 | Mouse/touch double-firing the same action | ✅ Clean — `input_devices/pointing/emulate_touch_from_mouse`/`emulate_mouse_from_touch` both resolve to `false` at runtime (confirmed via a live `ProjectSettings.get_setting()` check, not just reading the file). No script anywhere handles `_gui_input`/`_input`/`_unhandled_input`/`InputEventMouseButton`/`InputEventScreenTouch` directly — every interaction goes through `Button.pressed`, which Godot 4 already fires exactly once per tap/click with both emulation flags off. |
| 6 | Platform-dependent save paths outside `user://` | ✅ Clean — every persistence path (`SaveManager`, `SettingsManager`, and both their test files) is `user://save.json`/`user://settings.json`/`user://test_levels/`. No `OS.get_data_dir()`, `get_user_data_dir()`, `globalize_path()`, or hardcoded absolute paths anywhere. |
| 7 | Filename case-sensitivity issues | ✅ Clean — programmatically cross-checked every `res://...` reference in every `.gd`/`.tscn`/`.tres`/`.cfg` file against the actual on-disk filename (case-sensitive compare over a case-insensitive index). Zero mismatches. This matters because macOS's default filesystem is case-insensitive but Android/iOS export/runtime filesystems are case-sensitive — a mismatch here would work fine in the editor and silently fail to load a resource on-device. |
| 8 | Android dependency that won't work on iOS | ✅ Found, already correctly guarded — `Input.vibrate_handheld()` (Android-only in Godot) is called from exactly one place, `PlatformService.vibrate()`, behind `if current_platform == PlatformKind.ANDROID`. iOS/desktop fall through as a documented no-op. |
| 9 | iOS dependency that won't work on Android | ✅ Clean — nothing iOS-specific exists in the codebase today; `PlatformService.quit_app()`'s Android-only `get_tree().quit()` is the mirror-image case of #8, already correctly guarded. |
| 10 | Platform code leaking outside `PlatformService` | ✅ Clean — confirmed together with #1/#2: every `OS.*`/`PlatformKind`/platform-branch reference in the entire `scripts/` tree lives inside `scripts/platform/platform_service.gd`. |
| 11 | High memory / unnecessary node generation on mobile | ✅ Reviewed, no issues — zero `_process()`/`_physics_process()` overrides anywhere in the project (everything is signal/event-driven, no per-frame allocation hot path). Every `.instantiate()` call site has a matching `queue_free()`/cascading-free path (verified by cross-referencing all `instantiate()`/`queue_free()` call sites). `WaitingArea`'s compaction re-render (fresh `Passenger` instances rather than reparenting) only touches slots from the removed index onward, not the whole row, and is bounded by the largest level's waiting-slot count (≤22) — not a meaningful concern for a turn-based, human-paced puzzle game. |

## Bug found and fixed: popup buttons outside the safe area

`scenes/game/game_screen.tscn`'s `WinPopup` and `LosePopup` (containing
`WinNextButton`/`WinMenuButton`/`LoseRetryButton`/`LoseMenuButton`) were
direct children of the `GameScreen` root — **siblings of `SafeArea`**, not
descendants of it — anchored to the full `0,0`-`1,1` screen rect.
`GameScreen._apply_safe_area()` only ever applied
`PlatformService.get_safe_area_margins()` to `%SafeArea` itself, so the
win/lose popups (and their buttons) rendered across the *entire* screen,
including under a notch, status bar, or home-indicator area, on any device
with a non-zero safe area inset.

**Fix**: reparented both `WinPopup` and `LosePopup` to be children of
`SafeArea` (a `MarginContainer`) instead of the `GameScreen` root. A
`MarginContainer` applies the same margined rect to every direct child,
so both popups (and everything inside them) now automatically respect
the same safe-area insets as the rest of the gameplay UI, with no new
code needed — `_apply_safe_area()` already covers them by construction.

**A second bug this fix itself introduced, then caught by testing**: in
Godot's `.tscn` text format, a `[node ... parent="X"]` line is a path
**from the scene root**, not from whichever node is literally named `X`.
Changing only `WinPopup`/`LosePopup`'s own `parent=` line left every
*descendant* (`Background`, `Center`, `Panel`, `VBox`, `TitleLabel`, all
4 buttons) still pointing at the stale unqualified `parent="WinPopup"` /
`"LosePopup..."` paths, which no longer resolved now that those nodes
weren't at the scene root anymore — Godot silently failed to attach them
at all (`Node not found: "Center/Panel" (relative to
".../SafeArea/LosePopup")`), which then null-crashed `GameScreen._ready()`
(`Invalid access to property or key 'pressed' on a base object of type
'null instance'`) the instant any level was loaded. Every descendant path
needed the `SafeArea/` prefix added. Caught immediately by
`tools/validate.sh`'s `verify_game_controller.gd` step, which actually
boots `GameScreen` through the real `AppRouter` stack for all 20 levels —
a bare `.tscn` parse check would not have caught this. See the new
CLAUDE.md gotcha ("`.tscn` `parent=` paths are scene-root-relative, not
name-relative") for the general lesson.

No other scene had this pattern — `MainMenu`/`LevelSelect`/`SettingsPanel`
have no popups of their own (they're mounted *through* `main.tscn`'s own
outer `SafeArea` via `%ScreenRoot`, which already covers them), and every
other game-view component (`BusQueue`/`WaitingArea`/`PassengerQueue`/etc.)
is a plain child of `GameScreen`'s already-safe-framed layout, not a
separate full-screen overlay.

## Build verification

### Android

```
godot --headless --path . --export-debug "Android" exports/android/colorbus.apk
```

Built successfully (signed with the configured debug keystore). Installed
and launched on the existing `ColorBus_Test` emulator (Pixel 6 profile,
API 34, arm64-v8a) via `adb install -r` + `adb shell am start -n
com.furkandeniz.colorbus/com.godot.game.GodotAppLauncher`. Logcat confirms
a clean boot to a running main loop:

```
[ColorBus] viewport=1080 x 2400
[ColorBus] header_rect=[P: (0.0, 128.0), S: (1080.0, 160.0)]
[ColorBus] content_rect=[P: (0.0, 288.0), S: (1080.0, 1892.0)]
[ColorBus] footer_rect=[P: (0.0, 2180.0), S: (1080.0, 220.0)]
```

Note the header starting at `y=128`, not `0` — this emulator profile
simulates a display cutout, and `PlatformService.get_safe_area_margins()`
is correctly picking up a non-zero top inset and applying it, live
confirmation the safe-area system (and, by extension, this milestone's
fix) is actually doing something real, not just passing in the abstract.
`adb shell pidof com.furkandeniz.colorbus` returned a live PID after
launch; `grep -iE "FATAL EXCEPTION|AndroidRuntime: FATAL|ANR in|has died"`
against the full logcat buffer returned nothing. No crash.

### iOS

```
godot --headless --path . --export-debug "iOS" exports/ios/colorbus.ipa
cd exports/ios && xcodebuild -project colorbus.xcodeproj -scheme colorbus \
  -configuration Debug -sdk iphonesimulator -derivedDataPath build/DerivedData \
  -destination "generic/platform=iOS Simulator" \
  ARCHS=x86_64 VALID_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Xcode project generation and the Simulator build both **succeed** exactly
as established in Milestone 14. Installing the built `.app` onto the
`ColorBus_iOS_Test` Simulator (iPhone 16, iOS 26.5) still fails with the
same, unchanged, confirmed-upstream blocker
([godotengine/godot#118161](https://github.com/godotengine/godot/issues/118161)):
the official 4.7 export templates' Simulator slice of `libgodot.a` is
x86_64-only despite claiming universal arm64+x86_64 support, so the
`ARCHS=x86_64` workaround is required to link at all, and this specific
Apple Silicon host then refuses to install the resulting x86_64-only
binary (no Rosetta path for Simulator apps here). This is a pre-existing,
already-documented external limitation (see `docs/ARCHITECTURE.md`'s "iOS
export (Milestone 14)" section and CLAUDE.md) — re-confirmed unchanged
during this audit, not a new regression, and not something fixable from
this repository.

## Save format compatibility

`SaveManager` has zero platform branching (confirmed as part of checklist
items #1/#2/#10 above) — `user://save.json` is written via
`JSON.stringify()` and read via `JSON.parse()`, both pure, platform-agnostic
Godot APIs, so the schema is identical by construction regardless of
platform. Verified empirically rather than just by reasoning: pulled the
actual `save.json` the Android build wrote on-device
(`adb shell run-as com.furkandeniz.colorbus cat files/save.json`) and
diffed it against a fresh default save produced by the same code running
headlessly on macOS:

```
Android:  {"completed_levels":[],"first_launch_completed":true,"highest_unlocked_level":1,"last_played_level":0,"level_stars":{},"music_enabled":true,"save_version":1,"sound_enabled":true,"vibration_enabled":true}
macOS:    {"completed_levels":[],"first_launch_completed":false,"highest_unlocked_level":1,"last_played_level":0,"level_stars":{},"music_enabled":true,"save_version":1,"sound_enabled":true,"vibration_enabled":true}
```

Identical key set, identical ordering, identical types — the only
difference (`first_launch_completed`) is expected: the Android instance
had already been launched once (flipping that flag via
`MainMenu._ready()`), the macOS one was a fresh default. This is the same
`SaveManager` code iOS would run, so the same guarantee extends there
too, even though the iOS binary couldn't be installed to demonstrate it
literally running (see above).

## Responsive UI

Re-ran `tests/verify_responsive_layout.gd` (5 phone resolutions spanning
small Android through iPhone Pro Max) — all still pass with no gaps,
overlaps, or negative-size rects; full per-resolution numbers are in
[RESPONSIVE_TEST_PLAN.md](RESPONSIVE_TEST_PLAN.md)'s result log (updated
to reflect this re-run).

## Full validation

`tools/validate.sh` (all 16 steps, including the fixed `game_screen.tscn`)
passes end-to-end after the fix, confirmed on two consecutive runs (not a
fluke). See [README.md](../README.md)'s "Validating" section for exactly
what each step checks.

## Summary

One real, user-facing bug found and fixed (popup buttons ignoring the
safe area) plus the `.tscn` reparenting mistake that same fix briefly
introduced and testing caught immediately. Every other checklist item was
already clean, reflecting the platform-isolation discipline
(`PlatformService`-only platform code, no branching in game logic,
`user://`-only persistence) established since Milestone 2. Android is
fully verified end-to-end (build, install, launch, logs, safe-area
margins actually applying). iOS builds successfully but can't be verified
*running* on this machine due to an external, upstream Godot template
defect, unrelated to this project's own code.
