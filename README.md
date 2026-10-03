# Cloud spiral splash screen — Потойбіччя (Beyond)

An animated splash screen prototype: a logarithmic spiral of cloud puffs
streaming out of a glowing logo, looping while the app loads, then diving
into the vortex on exit. Built in Flutter and tuned live with a debug
slider panel before porting the final look into the real app.

| Looping | Intro (unfurling) | Outro (diving in) |
|---|---|---|
| ![Looping state](docs/screenshot_looping.jpg) | ![Intro state](docs/screenshot_intro.jpg) | ![Outro state](docs/screenshot_outro.jpg) |

## What it does

- **Intro** (~1.5s) — the spiral wipes in from the logo's tip outward
  (`Fill` 0→100%), the whole composition un-rotates and zooms in
  (70°→0°, 1.0x→baseline), while the flow decelerates from a fast "just
  formed" whirl down to its calm idle pace. The logo scales and rights
  itself in sync.
- **Looping** — an indefinite loading state: clouds continuously stream
  out of the logo's tip along one continuous spiral path (not a set of
  concentric rings), the logo has a subtle breathing glow.
- **Outro** (~0.5s, triggered externally once the app has actually
  loaded) — one simple move: the whole composition (spiral + logo
  together) zooms in dramatically while the scene fades, like diving
  through the vortex.

Cloud sprites: up to 3 variants, each with its own on/off checkbox and
rotation slider in the panel; enabled variants strictly alternate along
the spiral (1, 2, 1, 2… or 1, 2, 3, 1, 2, 3…).

Every visual parameter (cloud size, density, spiral tightness, tilt,
overall zoom/rotation, how much of the spiral is filled, etc.) is a live
slider in the demo screen, so the look can be tuned by eye rather than by
guessing numbers and recompiling.

## Running it

```bash
flutter pub get
flutter run -d chrome   # or any other configured device
```

The app opens on a picker between:

- **Splash screen demo** — the actual splash screen with its debug
  sliders, "Play Intro" and "Trigger App Loaded (Exit)" buttons.
- **Vortex tuning playground** — an earlier, now-unused approach kept
  around for reference (see `CLAUDE.md`).

## More detail

See [`CLAUDE.md`](CLAUDE.md) for the full architecture writeup, the
current tuned baseline values, and a list of non-obvious bugs that were
fixed along the way (useful reading before changing the spiral math).
