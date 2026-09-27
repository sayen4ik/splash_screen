# Splash Screen — cloud spiral vortex (Потойбіччя / Beyond)

Flutter prototype of an animated splash screen for the "Потойбіччя" (Beyond)
project: a spiral of cloud puffs streaming out of a logo, looping while the
app loads, then diving into the vortex on exit. Built as a standalone Flutter
app (not yet wired into the real Beyond app) so the look/motion could be
tuned live with sliders before porting it.

## Where things are

- `lib/splash_screen.dart` — **the actual splash screen.** State machine
  (`SplashState`: intro → looping → outro → done), every live-tunable
  parameter (with its current tuned default), the debug slider panel
  (each `_LabeledSlider` also carries a short Ukrainian `description`
  shown under the row — the audience for this panel is a Ukrainian-
  speaking designer, not just future-Claude reading the Dart comments;
  keep new sliders' `description`s in Ukrainian too), and
  the entry point (`SplashDemoScreen`). The demo screen's layout is a `Row`:
  left side is the splash itself rendered inside a fixed phone-sized frame
  (`_phoneWidth`/`_phoneHeight`, 390×844 — iPhone 13/14/15 logical points,
  scaled to fit via `FittedBox` but never stretched off that aspect ratio),
  so it's an accurate, device-shaped preview to show a developer — not the
  raw browser-window canvas. All debug UI (state badge, sliders, Play
  Intro/Trigger buttons) lives in a separate panel on the right and never
  appears inside the phone frame itself. The right panel also has an
  "Assets" section (`_AssetPickerRow`) with one row for the logo and one
  per active cloud sprite slot — the upload button opens the OS/browser's
  native file picker (via the `file_picker` package) so a developer can
  preview their own art without touching code; a row's reset button (only
  shown once something's been uploaded) reverts that slot back to the
  bundled default. Uploaded images are session-only (kept in memory as
  `_customLogoBytes`/`_customCloudImages`), never written to `assets/` or
  `pubspec.yaml` — swapping in a new *permanent* default still means adding
  the file and updating `_cloudAssetPaths`/`assets/logo.png` as before.
  Below the sliders is a "Share params" box (`_configController`): a JSON
  dump of every slider value (`_paramsMap`/`_encodeConfig`) — deliberately
  *not* the uploaded images, since those aren't meant to travel through a
  pasted chat message. "Copy current" fills the box and the clipboard;
  "Apply" (`_applyConfig`) parses whatever's in the box and pushes each
  recognized field onto its slider, clamped into that slider's own min/max
  (a `Slider` throws if handed an out-of-range value, and there's no
  guarantee a pasted-in value already fits) — unrecognized keys are
  ignored and a bad/non-JSON paste shows an inline error instead of
  crashing.
- `lib/cloud_spiral_painter.dart` — `CustomPainter` that draws the cloud
  stream: one continuous logarithmic spiral of cloud sprites anchored at the
  logo's tip, not a set of concentric rings. Read the doc comments at the
  top of the file before changing the math — several non-obvious bugs were
  fixed here (see "Lessons learned" below) and the comments explain why the
  current formulas look the way they do.
- `lib/cloud_spiral_config.dart` — the *non-live* base config (spawn angle,
  radius power curve, particle count, min/max scale factors). The live
  sliders in `splash_screen.dart` multiply on top of these.
- `lib/main.dart` — app entry; shows a picker between the splash demo and
  the old vortex-tuning playground (see below).
- `lib/droste_vortex_painter.dart`, `droste_vortex_config.dart`,
  `spiral_debug_screen.dart`, `checkerboard_painter.dart` — an **earlier,
  now-unused approach** (nested self-similar copies of one spiral image,
  "Droste effect") kept around for reference/comparison. The current splash
  screen does not use these.
- `assets/logo.png` — the center logo (currently a nautilus-spiral 'C').
  Needs a transparent background; the cloud spiral's spawn angle
  (`CloudSpiralConfig.spawnAngleRad`) must point along wherever this logo's
  own tail/tip fades out, so the clouds read as continuing out of the logo
  rather than floating around it.
- `assets/cloud_blob_*.webp` — cloud puff sprites. Only 3 are "active" at
  once (see `_cloudAssetPaths` in `splash_screen.dart`); the rest are past
  sets kept in case of reverting. Multiple images in `_cloudAssetPaths` get
  randomly (but stably per-particle) mixed along the spiral.
- `assets/stars_bg.png` — static starfield background. Drawn once, full
  screen (`BoxFit.cover`, centered), above the base gradient but below the
  spiral/logo — it never animates and is unaffected by the zoom/rotation
  transforms applied to the spiral+logo group.
- `assets/vortex_spiral.png`, `cloud_segment.png` — assets for the unused
  Droste-effect playground, not the splash screen.

## Running / previewing

This is a normal Flutter project (`flutter run`). To preview in the Claude
Code Browser pane, there's a `.claude/launch.json` one level up at
`/Users/tanka/DMC/.claude/launch.json` (shared across all DMC sub-projects)
with a `cloud_spiral_web` config pointing at this folder — use
`preview_start` with that name.

**Before starting a fresh preview, always check nothing is already
listening on the port:**

```bash
lsof -nP -iTCP:8765 -sTCP:LISTEN
```

If something is, `kill -9 <pid>` it first. See "Lessons learned" for why
this matters.

## Current tuned baseline (2026-09-26)

These are the shipped defaults in `splash_screen.dart` — the look the team
landed on after a long live-tuning session. Change them by editing the
`double _xxx = ...` field, not by dragging the slider and forgetting to
save it back (the slider only changes runtime state, not the source).

| Field | Value | UI label | What it does |
|---|---|---|---|
| `_speedMultiplier` | 0.04 | Speed | Loop flow speed |
| `_sizeMultiplier` | 1.82 | Scale Out | Cloud size at the outer edge |
| `_startSizeMultiplier` | 1.02 | Scale In | Cloud size at the logo tip (spawn) |
| `_sizeMidpoint` | 0.5 | Scale Mid | Where (0..1 along `p`) a puff is exactly halfway between Scale In and Scale Out in size — 0.5 is the old plain-linear growth; push toward 0/1 to shift when the size-up happens |
| `_particleCount` | 86 | Count | Base puff count |
| `_particleSpacing` | 1.11 | Spacing | Density (higher = sparser) |
| `_squashFactor` | 0.70 | Squash | Ellipse squash of the spiral |
| `_tiltAngleDeg` | -40.0 | Tilt | Tilt axis of the squash |
| `_turnsMultiplier` | 1.81 | Turns | How many turns the spiral winds |
| `_reachMultiplier` | 2.55 | Reach | How far out the spiral reaches |
| `_innerRadiusMultiplier` | 1.0 | Inner R | Radius of the spiral's very first turn (where puffs spawn) — raise it so the first turn wraps around the logo instead of landing on top of it; the outer end of the radius curve is unaffected |
| `_globalZoom` | 1.91 | Zoom | Overall zoom of spiral+logo together |
| `_fillAmount` | 100.0 | Fill | % of the spiral populated with clouds (intro wipes 0→100) |
| `_rotationDeg` | 0.0 | Rotate | Overall rotation of spiral+logo together |
| `_spawnOffsetX` | 0.0 | Spawn X | Pixel offset of the spiral's own spawn point, horizontal — the logo itself always stays dead center |
| `_spawnOffsetY` | 0.0 | Spawn Y | Pixel offset of the spiral's own spawn point, vertical — the logo itself always stays dead center |

There's also a fixed (non-live) cosmetic tint drawn over the whole splash,
bottom to top: `#E6BAFF` at 40% opacity at the bottom fading to `#E6BAFF`
at 0% (fully transparent) at the top. It sits above the clouds/logo scene
but below the debug slider UI, and isn't affected by any of the sliders
above.

Intro (~1.5s): Fill 0→100%, Rotate 70°→0°, Zoom 1.0→baseline, speed decays
from 7x, logo scales in with a slight tilt (35°→0°) — all eased with
`Curves.easeInOutSine`/`easeOutSine` for a smooth (not abrupt) feel.

Outro (~0.5s): a single "diving into the vortex" move — Zoom baseline→4x
baseline + fade out. Nothing else changes (explicitly requested: don't
speed up the clouds, don't shrink the logo separately, don't add extra
rotation — just zoom + fade).

## Lessons learned (read before debugging "my changes aren't showing up")

**A stale `flutter run -d web-server` process can keep serving old code
forever.** Multiple times this session, edits appeared to have no effect
because an old `flutter run` process from an earlier `preview_start` call
was still bound to port 8765 and silently kept serving its old compiled
JS (`main.dart.lib.js` would come back `304 Not Modified` instead of `200
OK` with new content) — `preview_stop` doesn't always guarantee the
previous process actually died before the next `preview_start` reuses the
port. Always `lsof -nP -iTCP:8765 -sTCP:LISTEN` and `kill -9` before
restarting, and check `read_network_requests` for `main.dart.lib.js` →
`200 OK` (not `304`) after loading, before trusting what you see on
screen.

**The spiral's core geometry must not depend on the live canvas size.**
Early versions computed cloud sizes and the spiral's max radius from
`size.shortestSide`/canvas diagonal directly, so resizing the browser
window changed how things looked near the logo, not just how far the
spiral reached. Fixed by introducing fixed reference constants
(`_referenceShortSide`, `_referenceCornerReach` in
`cloud_spiral_painter.dart`) for anything that should look pixel-identical
regardless of screen size, and a `reachStretch` factor (only ever ≥ 1,
only affects physical distance travelled, never puff size/timing) for
extending the reach on bigger screens.

**"Fill" reveals along life-progress `p`, not physical radius or a
rescaled spiral.** An early "intro" implementation temporarily shrunk
Reach/Turns/Spacing to make the spiral look like it was growing from
nothing — this reads as the *whole spiral rescaling*, not as clouds
progressively filling in. The fix: the spiral's shape (Reach/Turns/
Spacing) is *always* full-size; `fillAmount` just hides particles whose
`p` (life-progress, which maps monotonically to distance from the logo)
exceeds the fill threshold, with a soft-edged band. This is what makes the
intro read as "clouds gradually filling up an already-correctly-shaped
spiral" instead of "the spiral itself growing".

**`particleSpacing` must change the draw count, not just the phase step.**
Scaling the per-particle stagger step directly (rather than deriving how
many particles to draw) leaves a permanently uncovered stretch of the
0..1 progress loop when spacing < 1 — this silently rotates through the
spiral over time and reads as an intermittent "gap" bug. Fixed by deriving
`effectiveCount = particleCount / particleSpacing` and always spacing that
many particles evenly across the full loop.

**Fading an image's opacity via `Paint.colorBlendMode`/`Paint.color` on
`drawImageRect` does not work the way you'd expect** — those blend the
*image* against whatever is already drawn on the canvas, not against a
desired opacity. It rendered solid opaque rectangles instead of a fade.
The reliable fix is `canvas.saveLayer(bounds, Paint()..color =
Color.fromRGBO(0,0,0,opacity))` around the `drawImageRect` call.

## Adding new assets

**New logo:** drop the PNG (transparent background) in `assets/logo.png`,
update `pubspec.yaml` if the filename changes, then re-derive
`spawnAngleRad` in `cloud_spiral_config.dart` — find the angle (screen
space, 0 = right, +90° = down) that the logo's own tail/tip fades out
toward, measured from the image's own center, so newly-spawned clouds
continue the same curve instead of leaving a visible seam.

**New cloud sprites:** drop PNG/WebP (transparent background) files in
`assets/`, add them to `pubspec.yaml`'s `assets:` list, and list up to a
few of them in `_cloudAssetPaths` in `splash_screen.dart`. More than one
path there makes particles randomly (but stably per-particle) mix between
variants.
