# MVP end-to-end test report (Milestone 16)

End-to-end test of the Color Bus MVP with placeholder graphics, run
2026-07-14 against Godot 4.7.stable. Covers all 23 requested scenarios,
two real bugs found and fixed, a new automated regression test file, a
fresh Android + iOS Simulator build, and known limitations.

## Scenario coverage

| # | Scenario | Verified by | Result |
|---|---|---|---|
| 1 | Temiz kurulum (clean install) | `verify_save_manager.gd` first-launch defaults + this task's fresh Android install | ✅ |
| 2 | Ana menü açılışı (main menu opens) | `verify_navigation.gd` | ✅ |
| 3 | Bölüm seçim ekranı (level select) | `verify_level_select.gd` | ✅ |
| 4 | İlk bölüm başlatma (start first level) | `verify_game_controller.gd` | ✅ |
| 5 | Yolcu seçimi (passenger selection) | `verify_passenger_queue.gd`, `verify_game_controller.gd` | ✅ |
| 6 | Doğru otobüse bindirme (board correct bus) | `verify_bus.gd`, `verify_game_controller.gd` | ✅ |
| 7 | Bekleme alanına gönderme (send to waiting area) | `verify_waiting_area.gd`, `verify_game_controller.gd` | ✅ |
| 8 | Bekleme alanından otomatik bindirme (auto-board) | `verify_game_controller.gd` auto-board cascade checks | ✅ |
| 9 | Otobüs değişimi (bus change) | `verify_bus_queue.gd`'s `_test_advances_to_next_bus()` | ✅ |
| 10 | Kazanma (winning) | `verify_game_controller.gd` full playthrough, `verify_mvp_end_to_end.gd` (levels 1 and 20) | ✅ |
| 11 | Kaybetme (losing) | `verify_game_controller.gd` deadlock check | ✅ |
| 12 | Tekrar oynama (replay) | `verify_mvp_end_to_end.gd`'s `_test_replay_resets_state()` | ✅ |
| 13 | Sonraki bölüm (next level) | `verify_mvp_end_to_end.gd`'s `_test_next_level_button_progresses()` | ✅ |
| 14 | Uygulamayı kapatıp tekrar açma (relaunch) | `verify_save_manager.gd` save/reload round-trip | ✅ |
| 15 | İlerleme kaydı (progress save) | `verify_save_manager.gd`, `verify_level_select.gd` | ✅ |
| 16 | Ses ayarı (sound setting) | `verify_mvp_end_to_end.gd`'s `_test_settings_panel_toggles_persist()` (new UI, see below) | ✅ |
| 17 | Titreşim ayarı (vibration setting) | same as above | ✅ |
| 18 | Android geri tuşu (Android back button) | `verify_navigation.gd` | ✅ |
| 19 | iOS safe area | `verify_mvp_end_to_end.gd`'s `_test_safe_area_popups_are_inside_safe_area_container()`; `docs/CROSS_PLATFORM_AUDIT.md` | ✅ |
| 20 | Hızlı art arda dokunma (rapid repeated taps) | `verify_mvp_end_to_end.gd`'s `_test_rapid_multi_queue_taps_process_only_one()` | ✅ |
| 21 | Animasyon sırasında ekran değiştirme (screen change mid-animation) | `verify_mvp_end_to_end.gd`'s `_test_screen_change_mid_animation_does_not_error()` (regression test for bug #1 below) | ✅ |
| 22 | Son bölüm tamamlama (last level completion) | `verify_mvp_end_to_end.gd`'s `_test_last_level_completion()`, using `LevelSolver.find_winning_moves()` | ✅ |
| 23 | Bozuk save dosyası (corrupt save file) | `verify_save_manager.gd`'s `_test_corrupt_save_file()` | ✅ |
| 24 | Geçersiz level dosyası (invalid level file) | `verify_level_loading.gd`'s `_test_missing_field_rejected()`/`_test_invalid_color_rejected()`/others | ✅ |

(Scenario list had 23 bullet items in the request; "Restart mid-animation"
was folded in as its own regression test alongside #21 since it's the
same failure class — see bug #2 below.)

## Bugs found and fixed

### Bug 1: animation interrupted by screen navigation

Tapping a passenger starts an awaited flight animation
(`GameAnimator.fly_passenger_to()`). Backing out to the main menu while
that flight was still in progress crashed with `SCRIPT ERROR: Invalid
call. Nonexistent function 'finish_external_removal' in base 'previously
freed'`. `AppRouter._show_current()` frees the old `GameScreen` (and
everything under it — `BusQueue`/`WaitingArea`/`PassengerQueue`) the
moment a new screen is pushed, but the suspended
`GameController._on_queue_passenger_selected()` coroutine resumes after
the `await` and tries to call methods on now-freed objects.

**Fix**: added `GameController._is_still_alive()` (checks
`_bus_queue`/`_waiting_area` validity) plus targeted
`is_instance_valid(queue)`/`is_instance_valid(active_bus)` guards
immediately after every `await _animator.fly_passenger_to(...)` call,
returning early instead of touching a freed node. See
`scripts/game/game_controller.gd`.

### Bug 2: animation interrupted by Restart

Found while confirming the fix above, via a second reproduction: tapping
a passenger then immediately pressing Restart mid-flight crashed with
`SCRIPT ERROR: Invalid call. Nonexistent function 'board_passenger' in
base 'previously freed'`. Unlike screen navigation, Restart does **not**
free the `BusQueue`/`WaitingArea` container nodes — it calls
`.configure()` on them, which frees and rebuilds their *children*
in place. So bug 1's container-level `_is_still_alive()` check alone
returned `true` (containers are fine) while the *specific*
`active_bus`/`queue` instances the suspended coroutine still held had
already been freed and replaced.

**Fix**: added the same `is_instance_valid()` granularity to the specific
object references, not just the containers, including inside
`_run_auto_board_cascade()`'s loop. This is a general lesson recorded in
CLAUDE.md: whole-screen teardown and same-screen reconfiguration require
different validity-check granularities, and both must be checked
wherever a coroutine resumes after an `await`.

Both fixes were confirmed via disposable reproduction scripts before and
after, then validated against the full `tools/validate.sh` suite with no
regressions.

## New: Settings UI

`scenes/menus/settings_panel.tscn` was a bare placeholder — the
`SaveManager.music_enabled`/`sound_enabled`/`vibration_enabled` flags were
already fully functional (Milestone 11) but had no UI to toggle them, so
scenarios 16/17 ("Ses ayarı"/"Titreşim ayarı") had nothing to actually
exercise. Added three `CheckButton` rows (Music/Sound/Vibration), backed
by `scripts/ui/settings_panel.gd`, which only reflects and edits
`SaveManager` state — no new state of its own. Confirmed the toggles
reflect saved state on open, edit `SaveManager` on toggle, and persist
across a reload.

## New: `LevelSolver.find_winning_moves()`

To actually *complete* level 20 (5 colors, only 2 waiting slots,
adversarial ordering) inside an automated test, extended
`tools/level_solver.gd`'s existing BFS with backpointer tracking so a
concrete winning tap sequence (queue indices) can be reconstructed and
played back through a real `GameController`, instead of hand-deriving a
fragile sequence by hand.

## New test file

`tests/verify_mvp_end_to_end.gd` — boots the real app through
`main.tscn`/`AppRouter`, 8 test functions / 26 checks, all passing:
replay reset, restart-mid-animation regression, screen-change-mid-animation
regression, Next Level button progression, settings toggle persistence,
safe-area popup structure, rapid multi-queue tap handling, and a full
level-20 completion via `LevelSolver`. Wired into `tools/validate.sh` as
step 17/17.

## Full validation

```
./tools/validate.sh
```

All 17 steps pass, confirmed on a full run with zero script errors,
`Nonexistent function`, or `previously freed` occurrences anywhere in the
output.

## Build verification

### Android

```
godot --headless --path . --export-debug "Android" exports/android/colorbus.apk
```

Built successfully (27.3 MB, signed with the configured debug keystore).
Installed and launched on the existing `ColorBus_Test` emulator (Pixel 6
profile, API 34, arm64-v8a) via `adb install -r` + `adb shell am start -n
com.furkandeniz.colorbus/com.godot.game.GodotAppLauncher`. Logcat confirms
a clean boot to a running main loop, correct safe-area-aware layout:

```
[ColorBus] viewport=1080 x 2400
[ColorBus] header_rect=[P: (0.0, 128.0), S: (1080.0, 160.0)]
[ColorBus] content_rect=[P: (0.0, 288.0), S: (1080.0, 1892.0)]
[ColorBus] footer_rect=[P: (0.0, 2180.0), S: (1080.0, 220.0)]
```

`adb shell pidof com.furkandeniz.colorbus` returned a live PID; a full
logcat grep for `FATAL EXCEPTION`/`AndroidRuntime: FATAL`/`ANR in`/
`has died` returned nothing — zero crashes. Three transient `Couldn't
present to Vulkan queue (VkResult error 5)` lines appeared at startup
only; this is a known headless-emulator display-surface quirk already
documented from Milestone 13 (`adb exec-out screencap` reliably comes
back solid black under this same `-no-window` emulator regardless of GPU
backend), not an app-level bug — trust logcat/pidof over a screenshot
for crash detection in this environment.

### iOS

```
godot --headless --path . --export-debug "iOS" exports/ios/colorbus.ipa
cd exports/ios && xcodebuild -project colorbus.xcodeproj -scheme colorbus \
  -configuration Debug -sdk iphonesimulator \
  ARCHS=x86_64 VALID_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Xcode project generation and the Simulator build both **succeed**
(94 MB `.app`), exactly as established in Milestones 14/15. A temporary
placeholder Team ID (`ABCDE12345`) was used only for the duration of this
export and immediately reverted to blank in `export_presets.cfg`
afterward — never committed. Installing the built `.app` onto the
`ColorBus_iOS_Test` Simulator (iPhone 16, iOS 26.5) still fails with the
same, unchanged, confirmed-upstream blocker
([godotengine/godot#118161](https://github.com/godotengine/godot/issues/118161)):
the official 4.7 export templates' Simulator slice of `libgodot.a` is
x86_64-only despite claiming universal arm64+x86_64 support, and this
Apple Silicon host has no Rosetta path for Simulator app binaries. Not a
new regression — re-confirmed unchanged from Milestones 14/15.

## Known limitations

- **iOS Simulator install blocker**: [godotengine/godot#118161](https://github.com/godotengine/godot/issues/118161) — an open upstream Godot 4.7 bug, not fixable from this repository. Xcode project generation and building both work; only installing/running on an Apple Silicon Simulator is blocked.
- **No settings UI for reduce-motion**: `SettingsManager.reduce_motion` is fully functional and honored by `AnimationConfig.duration()`, but has no toggle in `SettingsPanel` (out of scope — not in the requested scenario list).
- **No real release signing configured**: Android has only a debug keystore (no release AAB/keystore); iOS has no Apple Developer Team ID, code-signing identity, or provisioning profile on this machine. Both are real per-developer credentials, never fabricated or stored in the repo.
- **`move_limit` doesn't trigger a loss on its own** — it's tracked and feeds star ratings, but only a genuine deadlock (no legal move anywhere) ends a level as `LOST`, per the original Milestone 9 design decision.
- **No dedicated first-launch/onboarding screen** — `first_launch_completed` is persisted and set the first time the main menu is reached, but nothing branches on it yet.
- **`AudioManager` SFX/music are silent no-ops** — every trigger point is wired and gated correctly by the sound/music settings, but `assets/audio/` is intentionally empty (no placeholder audio assets, by design from an earlier milestone).
- **Placeholder-only app icon** — `assets/icons/app_icon_1024.png` is a generated dot-pattern placeholder, not final art.
- **No physical device testing** — Android verified on an emulator only, iOS not verified running at all (blocked by the issue above); neither has been tested on a real phone/tablet.

## Summary

Two real bugs found and fixed (both animation-interrupted-by-navigation
class, differing in validity-check granularity needed), one missing UI
surface built (Settings toggles), one new solver capability added
(winning-move reconstruction for automated last-level completion), and
one new regression test file covering every scenario not already
exercised by an existing test. All 17 `tools/validate.sh` steps pass.
Android build verified end-to-end (install, launch, clean logcat).
iOS build succeeds; running it on this machine remains blocked by an
external, already-documented upstream defect.
