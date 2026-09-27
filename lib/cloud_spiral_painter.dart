import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cloud_spiral_config.dart';

/// Draws the cloud stream as individual [config.particleCount] copies of the
/// same arc-shaped cloud sprite, each at its own point along ONE logarithmic
/// spiral path anchored at the logo's tip (see [CloudSpiralConfig]). Unlike a
/// set of concentric rings, every particle's (radius, angle) pair lies on
/// that single curve, so the stream reads as one continuous curl that starts
/// at the tip and winds outward — not a symmetric halo detached from the
/// logo.
///
/// Each particle's life-progress `p` (0 = just spawned at the tip, 1 = fully
/// grown at the outer edge) is `frac(t / loopSeconds + i / effectiveCount)`:
/// evenly staggered in progress-space so the whole 0..1 loop is always
/// fully tiled, continuously looping, so particles are always fading in
/// right at the tip and fading out at the edge — never popping in or out,
/// and never leaving a gap (see [particleSpacing]).
class CloudSpiralPainter extends CustomPainter {
  CloudSpiralPainter({
    required this.images,
    required this.config,
    required this.timeSeconds,
    this.sizeMultiplier = 1.0,
    this.startSizeMultiplier = 1.0,
    this.sizeMidpoint = 0.5,
    this.particleSpacing = 1.0,
    this.squashFactor = 1.0,
    this.tiltAngleRad = 0.0,
    this.turnsMultiplier = 1.0,
    this.reachMultiplier = 1.0,
    this.innerRadiusMultiplier = 1.0,
    this.fillAmount = 1.0,
    this.spawnOffset = Offset.zero,
    int? particleCount,
  }) : assert(images.isNotEmpty, 'CloudSpiralPainter needs at least one image'),
       particleCount = particleCount ?? config.particleCount;

  /// One or more cloud sprite variants. When there's more than one, each
  /// particle is assigned a variant via a seed derived from its own stable
  /// index (see `paint`) — not re-rolled every frame — so a given puff
  /// never flickers between variants as it travels, but different puffs
  /// along the spiral read as a varied mix instead of one repeated stamp.
  final List<ui.Image> images;
  final CloudSpiralConfig config;

  /// Continuously increasing elapsed time (seconds); does not need to be
  /// pre-wrapped, each particle's own phase already wraps via `%`.
  final double timeSeconds;

  /// Live multiplier on top of [config.maxScaleFactor] — the size clouds
  /// reach once they've traveled all the way out to the edge, i.e. the ones
  /// reading as "closest to camera".
  final double sizeMultiplier;

  /// Live multiplier on top of [config.minScaleFactor] — the size clouds
  /// start at right at the logo tip. Together with [sizeMultiplier] this
  /// controls how much clouds grow over their trip (a big gap between the
  /// two reads as puffs visibly ballooning outward; a small gap reads as
  /// near-uniform size along the whole spiral).
  final double startSizeMultiplier;

  /// Where, along life-progress `p` (0 = logo tip, 1 = outer edge), a
  /// particle sits exactly halfway between [startSizeMultiplier] and
  /// [sizeMultiplier] in size. 0.5 (default) means the size grows evenly —
  /// a plain linear interpolation, halfway there at `p` = 0.5. Push it
  /// toward 0 to make puffs balloon up to full size quickly (right after
  /// spawning) and then hold that size for the rest of the trip; push it
  /// toward 1 to keep puffs small for most of the trip and have them only
  /// balloon up right at the end. Implemented as Perlin's "bias" remap of
  /// `p` before it's used for size (only size — radius/angle/opacity still
  /// use the raw `p`, so this never changes the spiral's shape or pacing,
  /// only how the size grows along it).
  final double sizeMidpoint;

  /// Live control over how far apart consecutive puffs sit along the
  /// spiral. 1.0 = [particleCount]'s own default density; less
  /// packs them closer together (denser — internally draws *more* puffs
  /// to keep the loop fully tiled at that density); more spreads them
  /// further apart (sparser — draws fewer). Always covers the full 0..1
  /// loop by construction (see `effectiveCount` below), so unlike a plain
  /// multiplier on the stagger step, this never leaves a permanently
  /// uncovered stretch of the spiral.
  final double particleSpacing;

  /// Ellipse squash (Photoshop-"Distort"-style): 1.0 = perfect circle,
  /// less flattens it into an oval along the axis perpendicular to
  /// [tiltAngleRad], mimicking a tunnel seen at an angle.
  final double squashFactor;

  /// Rotation (radians) of the squash axis, so the oval can be tilted
  /// instead of only ever squashed horizontally/vertically.
  final double tiltAngleRad;

  /// Live multiplier on [config.totalTurns]' magnitude (sign/direction is
  /// always kept from the config). More turns packs the coils closer
  /// together in angle at a given radius, filling in gaps; fewer turns
  /// spreads them thinner.
  final double turnsMultiplier;

  /// Live multiplier on how far out the spiral reaches, applied against the
  /// fixed *reference* corner distance (see `_referenceCornerReach`) — not
  /// the live canvas size — so this always means the same absolute reach
  /// regardless of screen size; `reachStretch` is what adapts that to the
  /// actual live canvas.
  final double reachMultiplier;

  /// Live multiplier on [config.spawnRadius] — how far from the spiral's
  /// own center the very first turn sits. Raising this pushes the whole
  /// radius curve's *starting* point outward (the r(p) formula still ends
  /// at the same outer `rMaxRef` regardless — see `paint`), which is what
  /// you want when the innermost turn is landing on top of the logo
  /// instead of wrapping around it. 1.0 = [config.spawnRadius] unchanged.
  final double innerRadiusMultiplier;

  /// Live override for [config.particleCount] — the base density
  /// `particleSpacing` scales from. Defaults to the config's own value.
  final int particleCount;

  /// How much of the (always full-size) spiral is populated with clouds,
  /// from the logo tip outward: 0.0 = no clouds at all, 0.5 = only the
  /// inner half of the spiral (by life-progress `p`, which — since Reach/
  /// Turns/Spacing never change — maps directly to physical distance from
  /// the tip) is drawn, 1.0 = the whole spiral. Unlike animating Reach/
  /// Turns/Spacing, the spiral's own shape and density never change; this
  /// only reveals or hides a leading portion of it, like a wipe.
  final double fillAmount;

  /// Pixel offset of the spiral's own center away from the canvas' center.
  /// The logo (drawn separately, in `splash_screen.dart`) always stays
  /// dead center — this only moves where the spiral winds out *from*, for
  /// cases where it should spawn near the logo rather than exactly through
  /// it. Positive x moves right, positive y moves down. Applied in the
  /// same local coordinate space the painter already works in, *before*
  /// the live zoom/rotation transform that wraps the spiral and the logo
  /// as one rigid piece — so the offset scales/rotates along with
  /// everything else instead of fighting it.
  final Offset spawnOffset;

  // Reference "design" scale for everything that should look pixel-identical
  // no matter what the actual canvas size is: puff sizes and the spiral's
  // core shape near the logo. Only `reachStretch` below is allowed to depend
  // on the live canvas size — so resizing the window (or running on a
  // bigger/smaller device) reveals more or less of the same unchanging
  // picture instead of rescaling the whole thing, which is what made the
  // near-logo geometry visibly shift whenever the browser window changed.
  static const double _referenceShortSide = 780;
  static const double _referenceCornerReach = 800;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero) + spawnOffset;
    final liveCornerReach =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    // Only grows past 1 once the live canvas is actually bigger than the
    // reference — a smaller canvas just shows less of the same picture
    // (cropped by the viewport), never a shrunk one.
    final reachStretch = math.max(1.0, liveCornerReach / _referenceCornerReach);
    final rMaxRef =
        _referenceCornerReach * config.maxRadiusFactor * reachMultiplier;
    final sMin =
        _referenceShortSide * config.minScaleFactor * startSizeMultiplier;
    final sMax = _referenceShortSide * config.maxScaleFactor * sizeMultiplier;

    // Deriving the draw count from `particleSpacing` (rather than just
    // scaling the stagger step by it) is what guarantees full coverage: a
    // fixed particle count with a shrunk step leaves the tail of the 0..1
    // loop with no particle ever reaching it — a permanent gap that
    // silently rotates through the spiral over time. Spacing < 1 packs
    // puffs closer by drawing more of them at the same even 1/N step;
    // spacing > 1 spreads them out by drawing fewer.
    final effectiveCount = (particleCount / particleSpacing).round().clamp(
      4,
      400,
    );
    // Each slot's image variant is picked from a seed on its own stable
    // index `i` (not re-rolled with the ambient time), so a given puff
    // keeps the same sprite for its whole trip out from the tip, while
    // different puffs along the spiral still read as a varied mix.
    final particles = List.generate(effectiveCount, (i) {
      final p = ((timeSeconds / config.loopSeconds) + i / effectiveCount) % 1.0;
      final imageIndex = images.length == 1
          ? 0
          : (math.Random(i).nextInt(images.length));
      return (p: p, imageIndex: imageIndex);
    })..sort((a, b) => a.p.compareTo(b.p));

    // Photoshop-"Distort"-style oval tilt: rotate to the squash axis, flatten
    // one axis, rotate back. Wrapping the whole loop in this means each
    // particle's own position AND its tangent-aligned rotation both get
    // distorted together, so the ring reads as one coherent tilted tunnel
    // instead of a circle with mismatched sprite rotations.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tiltAngleRad);
    canvas.scale(1.0, squashFactor);
    canvas.rotate(-tiltAngleRad);
    canvas.translate(-center.dx, -center.dy);

    for (final particle in particles) {
      final p = particle.p;
      final image = images[particle.imageIndex];
      final aspect = image.height / image.width;
      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      // `p` alone (unaffected by reachStretch) still drives everything about
      // a particle's lifecycle — angle, size growth, opacity fade — so the
      // *pacing* and *core shape* feel identical on every screen. Only the
      // physical distance a fully-grown (p near 1) particle ends up at
      // stretches on a bigger canvas, via `pExt`.
      final pExt = p * reachStretch;
      final spawnRadius = config.spawnRadius * innerRadiusMultiplier;
      final r =
          spawnRadius +
          (rMaxRef - spawnRadius) * math.pow(pExt, config.radiusPower);
      final angle =
          config.spawnAngleRad +
          config.totalTurns * turnsMultiplier * 2 * math.pi * p;
      final w = sMin + (sMax - sMin) * _bias(p, sizeMidpoint);
      final h = w * aspect;

      double opacity;
      if (p < 0.08) {
        opacity = Curves.easeOut.transform(p / 0.08);
      } else if (p > 0.75) {
        opacity = 1 - Curves.easeIn.transform((p - 0.75) / 0.25);
      } else {
        opacity = 1;
      }

      // Wipe reveal: a soft-edged cutoff on `p` itself, not on physical
      // radius, so it stays correct regardless of reachStretch/squash/tilt.
      const fillEdgeBand = 0.06;
      final revealFactor = fillAmount >= 1.0
          ? 1.0
          : (1.0 - ((p - fillAmount) / fillEdgeBand)).clamp(0.0, 1.0);
      opacity *= revealFactor;

      final clampedOpacity = opacity.clamp(0.0, 1.0);
      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;

      canvas.save();
      canvas.translate(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      canvas.rotate(angle + math.pi / 2);
      // saveLayer + a translucent black paint is the reliable way to fade an
      // image's own alpha further: Paint.color/blendMode on drawImageRect
      // blend the image against whatever is already on the canvas, not
      // against a desired opacity, and misusing it that way rendered solid
      // opaque boxes instead of a fade.
      final needsLayer = clampedOpacity < 0.999;
      if (needsLayer) {
        canvas.saveLayer(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Paint()..color = Color.fromRGBO(0, 0, 0, clampedOpacity),
        );
      }
      canvas.drawImageRect(
        image,
        srcRect,
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        paint,
      );
      if (needsLayer) canvas.restore();
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CloudSpiralPainter oldDelegate) => true;
}

/// Ken Perlin's "bias" remap: a monotonic curve on `t` in [0, 1] such that
/// `bias(0.5, b) == b` — i.e. `b` is exactly where the curve crosses the
/// midpoint. `b == 0.5` is the identity (`bias(t, 0.5) == t`), which is why
/// [CloudSpiralPainter.sizeMidpoint]'s default of 0.5 reproduces the old
/// plain-linear size growth exactly. `b` is clamped away from the 0/1 ends
/// to avoid the division blowing up there.
double _bias(double t, double b) {
  final clampedB = b.clamp(0.001, 0.999);
  return t / ((1 / clampedB - 2) * (1 - t) + 1);
}
