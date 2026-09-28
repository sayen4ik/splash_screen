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
  Intro/Trigger/To Start buttons) lives in a separate panel on the right
  and never appears inside the phone frame itself.
  **Responsive layout:** `build()` splits the phone frame (`phoneArea`) and
  the sidebar contents (`controlsPanel`) into local variables, then a
  `LayoutBuilder` picks between two arrangements at `_mobileBreakpoint`
  (700px): **wide** — the original fixed `Row` (phone + a fixed 360px
  `controlsPanel` column), unchanged. **narrow** (real phones opening this
  demo on themselves, where a fixed 360px sidebar would crush the phone
  preview) — a `Stack`: `phoneArea` fills the whole viewport,
  `_MobileTriggerBar` pins just the two most-used triggers (Play Intro /
  Trigger App Loaded) to the bottom so they're reachable and their effect
  is visible without opening anything, `controlsPanel` (same widget as the
  desktop sidebar, not a fork of it) slides in from the left inside an
  `AnimatedPositioned` at up to 320px wide with a semi-transparent
  background (so the canvas keeps showing through while tuning sliders —
  same idea as Rive's own inspector panel), and `_PanelToggleButton` (a
  small circular arrow, top-left, rotates 180° when open) toggles
  `_controlsPanelOpen`. Because `controlsPanel` is reused verbatim between
  both layouts, any new control added to the sidebar automatically shows
  up on mobile too — don't wrap it in a second `SingleChildScrollView`
  when embedding it (it already has its own internal `Expanded` +
  scrollview for the slider section; double-wrapping it in another
  scrollview throws "RenderFlex children have non-zero flex but incoming
  height constraints are unbounded" because the inner `Expanded` no longer
  has a bounded parent). The row of trigger buttons inside `controlsPanel`
  uses `Wrap` rather than `Row` specifically so it doesn't overflow at the
  mobile panel's narrower width (320px minus padding) even though it fits
  fine in the desktop sidebar's 360px.
  The right panel also has an
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
- `lib/main.dart` — app entry; shows a picker between the splash demo,
  the old vortex-tuning playground, and the standalone curtain-reveal
  prototype (see below).
- `lib/curtain_overlay.dart` — reusable "theater curtain" reveal
  (`CurtainOverlay` widget + `CurtainClosedFrame`), extracted from
  `curtain_reveal_demo.dart` so it can sit on top of the real splash's
  phone frame without duplicating risk into the working demo screen.
  Two panels split down the middle, each drawing the same full
  screenshot (`assets/curtain_mock_screenshot.webp` — the Sylpo app
  mock; deliberately a *different* screenshot from the splash's own
  `beyond_home_mock.webp`, confirmed intentional, not a bug to "fix") +
  fold texture (`assets/curtain_fold_texture.webp`) so the seam lines
  up, along a curved (Bezier) edge whose control point is derived from
  the top/bottom edge positions.
  - **`CurtainOverlay(reverse: false)`** (opening): 0→1, panels part;
    fold texture stays at full opacity throughout.
  - **`CurtainOverlay(reverse: true)`** (closing, via "To Start" — see
    below): 1→0, panels rejoin; the fold texture fades OUT (1→0) over
    the motion instead, so the fabric look dies away as the curtain
    settles shut rather than snapping back on. `CurtainClosedFrame` (the
    static resting-closed frame — no clipping/animation needed once
    fully closed, since there's no seam to hide) deliberately has NO
    texture layer, matching that faded-out end state — that's what
    makes the swap from the animating overlay to the static frame
    invisible instead of a pop.
  - **Lead/lag physics** (`_topCurve`/`_bottomCurve`): the top edge
    always *initiates* the motion (leads) and the bottom always
    *catches up* (lags), in **both** directions — a real curtain's top
    is pulled by the rail; the loose bottom fabric always trails. Naively
    reusing the open curves on a reversed controller value flips this
    (whichever edge finishes fastest also finishes the close first, i.e.
    the lagging edge would *overtake* the leading one) — the fix
    re-parametrizes closing as its own `p` = "progress of the current
    motion" (0→1 regardless of direction) and inverts the curve's
    *output* (`1 - curve(p)`), not its input, so the same edge leads
    either way. See the doc comment above `final p = ...` in `build()`
    before touching this.
- In `splash_screen.dart`: a "Починати зі штор" checkbox
  (`_startWithCurtain`) controls whether the curtain is used at all.
  Three booleans track which of the curtain's three looks is current —
  `_curtainClosed` (static `CurtainClosedFrame`, resting shut: true from
  the very first frame, and again once a close finishes), `_showCurtain`
  (an animating `CurtainOverlay` is mounted right now, opening or
  closing), `_curtainReverse` (direction of that animation; meaningless
  while `_showCurtain` is false). "Play Intro" starts an *open* from
  rest; the "To Start (close curtain)" button (enabled only once
  `_state == SplashState.done` and the curtain is fully open-and-gone)
  starts a *close* back to rest, so the whole thing can loop smoothly:
  closed → (Play Intro) → open/intro/looping/outro → done → (To Start)
  → closed → …
- The demo now **opens directly on `SplashState.done`** — just the real
  app's home screen (`assets/beyond_home_mock.webp`), idle, nothing
  animating (plus the closed curtain over it, per above) — rather than
  autoplaying the intro. `SplashState.done` no longer swaps out the
  whole screen for a separate full-screen mock either — the phone frame
  just layers the home-screen image as a static base UNDER
  `splashContent` (bg/starfield/clouds/logo, all under one `Opacity`)
  whenever `_state` is `outro` or `done`. Since `sceneOpacity` already
  eases 1→0 during outro and sits flat at 0 once done, the home screen
  shows through progressively as the scene fades — a crossfade that
  falls out of the existing opacity animation rather than a separate
  abrupt swap. The live-tuning panel (including "Play Intro") stays
  visible throughout.
- `lib/curtain_reveal_demo.dart` — the standalone prototype screen this
  was built and tuned in (own copy of the same clipper/panel logic —
  open-only, no reverse/close mode — plus live sliders for
  Fade/Duration/Arc/Top Lead and an "Open real splash" button). Left
  as-is/self-contained rather than refactored to share code with
  `curtain_overlay.dart`, so tuning it further can't regress the version
  embedded in the real splash; the two have already diverged (this one
  still has the texture fade-*in*-on-open phase that the embedded
  `CurtainOverlay` dropped).
- `lib/droste_vortex_painter.dart`, `droste_vortex_config.dart`,
  `spiral_debug_screen.dart`, `checkerboard_painter.dart` — an **earlier,
  now-unused approach** (nested self-similar copies of one spiral image,
  "Droste effect") kept around for reference/comparison. The current splash
  screen does not use these.
- `assets/logo.png` — the center logo (currently a white nautilus-spiral
  'C', updated 2026-09-28 from the earlier purple-tinted version — same
  shape/tail direction, so `spawnAngleRad` didn't need re-deriving).
  Needs a transparent background; the cloud spiral's spawn angle
  (`CloudSpiralConfig.spawnAngleRad`) must point along wherever this logo's
  own tail/tip fades out, so the clouds read as continuing out of the logo
  rather than floating around it.
- `assets/cloud_blob_*.webp` — cloud puff sprites. Only 3 are "active" at
  once (see `_cloudAssetPaths` in `splash_screen.dart`); the rest are past
  sets kept in case of reverting. Multiple images in `_cloudAssetPaths` get
  randomly (but stably per-particle) mixed along the spiral. As of
  2026-09-28 all three active slots point at the same new sprite,
  `assets/cloud_blob_19.webp` (a placeholder — "all three clouds like this
  for now" per the team) rather than three distinct variants.
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

## Current tuned baseline (last updated 2026-09-28)

These are the shipped defaults in `splash_screen.dart` — the look the team
landed on after a long live-tuning session. Change them by editing the
`double _xxx = ...` field, not by dragging the slider and forgetting to
save it back (the slider only changes runtime state, not the source).

| Field | Value | UI label | What it does |
|---|---|---|---|
| `_speedMultiplier` | 0.0303 | Speed | Loop flow speed |
| `_sizeMultiplier` | 2.26 | Scale Out | Cloud size at the outer edge |
| `_startSizeMultiplier` | 2.55 | Scale In | Cloud size at the logo tip (spawn) |
| `_sizeMidpoint` | 0.5 | Scale Mid | Where (0..1 along `p`) a puff is exactly halfway between Scale In and Scale Out in size — 0.5 is the old plain-linear growth; push toward 0/1 to shift when the size-up happens |
| `_particleCount` | 40 | Count | Base puff count |
| `_particleSpacing` | 1.3 | Spacing | Density (higher = sparser) |
| `_squashFactor` | 0.7235 | Squash | Ellipse squash of the spiral |
| `_tiltAngleDeg` | -39.0 | Tilt | Tilt axis of the squash |
| `_turnsMultiplier` | 2.76 | Turns | How many turns the spiral winds |
| `_reachMultiplier` | 2.55 | Reach | How far out the spiral reaches |
| `_innerRadiusMultiplier` | 1.95 | Inner R | Radius of the spiral's very first turn (where puffs spawn) — raise it so the first turn wraps around the logo instead of landing on top of it; the outer end of the radius curve is unaffected |
| `_depthSpeedPower` | 1.5 | Depth Spd | Power curve on a puff's real-time pacing (see `CloudSpiralPainter.paint`'s `pRaw`→`p` remap) — above 1.0, puffs near the logo move slowly and accelerate outward (near/far parallax), with a bunching-near-the-tip side effect since puffs stay evenly staggered in raw time |
| `_globalZoom` | 1.91 | Zoom | Overall zoom of spiral+logo together |
| `_fillAmount` | 100.0 | Fill | % of the spiral populated with clouds (intro wipes 0→100) |
| `_rotationDeg` | 0.0 | Rotate | Overall rotation of spiral+logo together |
| `_spawnOffsetX` | 2.0 | Spawn X | Pixel offset of the spiral's own spawn point, horizontal — the logo itself always stays dead center |
| `_spawnOffsetY` | 7.0 | Spawn Y | Pixel offset of the spiral's own spawn point, vertical — the logo itself always stays dead center |
| `_logoScale` | 2.55 | Logo Scale | Size of the logo itself, independent of `_globalZoom` (which scales spiral + logo together) and the intro's own pop-in animation (multiplies on top of this) |
| `_logoOffsetX` | 18.0 | Logo X | Pixel offset of the logo image itself, horizontal — unlike Spawn X (which only moves the spiral's spawn point), this moves the logo |
| `_logoOffsetY` | -34.0 | Logo Y | Pixel offset of the logo image itself, vertical — unlike Spawn Y (which only moves the spiral's spawn point), this moves the logo |

The "Colors" section at the top of the right panel has 4 hex color rows
(`RRGGBB`, no `#`, each next to a live swatch — an invalid hex is just
ignored, leaving the previous color in place):

- **BG Top** / **BG Bottom** (`_bgTopColor`/`_bgBottomColor`, default
  `#07020D`/`#22065A`) — a plain 2-stop `LinearGradient` behind
  everything, always fully opaque (no opacity knob — it's the solid base
  of the whole scene).
- **FG Top** / **FG Bottom** (`_fgTopColor`/`_fgBottomColor`, default
  `#E6BAFF`/`#E6BAFF`) — the cosmetic tint drawn *over* the whole scene
  (above clouds/logo, below the debug UI), also top color → bottom
  color, but each end additionally has its own live opacity slider
  (`_fgTopOpacity`/`_fgBottomOpacity`, 0–100%, default 0%/55%) — unlike
  the background, both hue *and* fade strength are tunable per end here.
  A "FG Top Pos" slider (`_fgTopStop`, 0–95%, default 26%) additionally
  moves the gradient's *top* stop position down toward the bottom — the
  bottom stop always stays pinned at 1.0 (the very bottom of the
  screen); raising it holds FG Top solid over more of the upper screen
  before the blend into FG Bottom starts.

All 7 values are included in "Share params" (`bgTop`/`bgBottom`/`fgTop`/
`fgBottom` as hex strings, `fgTopOpacity`/`fgBottomOpacity`/`fgTopStop`
as numbers) alongside every slider, including `logoScale`/`logoX`/`logoY`.

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

**Reversing an `AnimationController` does not reverse an asymmetric
lead/lag relationship — it flips it.** `curtain_overlay.dart`'s two
edges use different curves so one visibly leads the other (a real
curtain's top, pulled by the rail, always initiates the motion; the
loose bottom always trails). The first attempt at a "closing" mode just
called `.reverse()` on the same controller and fed its value straight
into the same two curves — since whichever curve reaches its target
*fastest* also, when time runs backward, gets back to its *start*
fastest, the edge that led while opening ends up trailing while closing
(and vice versa) instead of leading in both directions. The fix:
re-parametrize the reverse motion as its own `p` = "progress of the
current motion" (0→1 regardless of direction) and invert the curve's
*output* (`1 - curve(p)`), never its input — that keeps the same edge
leading either way. Worth remembering for *any* two-curve asymmetric
animation that needs a working reverse, not just this one.

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
