# Responsive layout test plan

## Target resolutions (portrait, logical px)

| Device class            | Resolution  |
|--------------------------|-------------|
| Small Android (older)    | 360 x 640   |
| iPhone X/11 Pro/12 mini  | 375 x 812   |
| iPhone 12/13/14          | 390 x 844   |
| Common Android (Pixel)   | 412 x 915   |
| iPhone 14/15/16 Pro Max  | 430 x 932   |

## What "correct" means

At every resolution above, `scenes/app/main.tscn` must satisfy all of:

1. `Header`, `ContentArea`, `Footer` stack top-to-bottom with no gap and no
   overlap: `header.bottom == content.top` and `content.bottom == footer.top`.
2. The three rects together exactly fill the viewport width and height
   (`header.top == 0`, `footer.bottom == viewport.height`, all widths ==
   `viewport.width`).
3. No rect has a negative width or height (would indicate a broken
   container/anchor setup).
4. No GDScript errors/warnings are printed during boot at any resolution.

## How it's run

Headless, command-line only (no GPU screenshot capture — this environment
cannot reliably grab framebuffers from a headless/software-rendered run,
and Screen Recording permission for `screencapture` can't be granted here
either).

**Note:** the headless `DisplayServer` on this engine build ignores both
`--resolution` and `--window-size` — the real window always reports a
fixed 1920x1920 no matter what's passed. Resizing `SceneTree.root` at
runtime doesn't work either (same fixed size). So resolutions are instead
tested with a `SubViewport`, whose `size` can be set directly regardless of
the real window/display server. `tests/verify_responsive_layout.gd`
instances `main.tscn` fresh inside a `SubViewport` of each target size,
which drives the exact same anchor/Container layout code a real device of
that size would run, then reads back `%Header` / `%ContentArea` /
`%Footer` global rects and checks them against the pass criteria above.

```bash
godot --headless --path . --script res://tests/verify_responsive_layout.gd
```

Exit code 0 = all 5 resolutions passed, non-zero = at least one failed
(see printed per-resolution `ok=` lines for which one).

## Result log (last verified 2026-07-14, Godot 4.7.stable — re-run as part of the Milestone 15 cross-platform audit)

| Resolution | header | content | footer | Result |
|---|---|---|---|---|
| 360x640 | (0,0)-(360,160) | (0,160)-(360,420) | (0,420)-(360,640) | PASS |
| 375x812 | (0,0)-(375,160) | (0,160)-(375,592) | (0,592)-(375,812) | PASS |
| 390x844 | (0,0)-(390,160) | (0,160)-(390,624) | (0,624)-(390,844) | PASS |
| 412x915 | (0,0)-(412,160) | (0,160)-(412,695) | (0,695)-(412,915) | PASS |
| 430x932 | (0,0)-(430,160) | (0,160)-(430,712) | (0,712)-(430,932) | PASS |

All 5: no gaps, no overlaps, rects exactly tile the viewport, zero error
output. Overall result: **PASS**.
