import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'droste_vortex_config.dart';

/// Draws the Droste-effect vortex: the same [image] painted over and over,
/// every copy centered on the exact same canvas point, each one scaled down
/// by [DrosteVortexConfig.nestScale] from the previous. Because the source
/// image already tapers to a point at its own geometric center, stacking a
/// smaller copy of itself there reads as "the picture contains itself"
/// rather than as a separately assembled spiral.
///
/// Continuously growing [DrosteVortexConfig.baseScale] toward `1/nestScale`
/// is a seamless loop: at that exact scale, level `n`'s content coincides
/// pixel-for-pixel with where level `n-1` started, because it's literally
/// the same source image — so the animation can wrap back to `baseScale=1`
/// with no visible pop.
///
/// The number of levels is *not* a fixed config value: it always keeps
/// drawing until a level is sub-pixel. A fixed cap would run out of levels
/// near the end of every dive loop (once `baseScale` has grown toward
/// `1/nestScale`, the innermost configured level is already standing in for
/// what used to be one level shallower, so a fixed count leaves nothing left
/// to reveal at the very center) — that's what read as the cloud "vanishing"
/// with a hard-edged cutoff right before each loop reset.
///
/// The same problem exists in the *outward* direction and needs the mirror
/// fix: drawing also starts a couple of levels *before* 0 (i.e. copies
/// bigger than the nominal outermost one). Without them, the picture at
/// `baseScale` approaching `1/nestScale` is dominated by a single huge,
/// heavily-magnified copy filling the whole frame (everywhere the smaller
/// levels on top don't fully cover, since the source image isn't opaque
/// edge-to-edge) — and the instant that copy's index rolls over at the loop
/// reset, all of that magnified fill vanishes at once, reading as the cloud
/// disappearing off the outside edge. Pre-drawing the next-bigger level from
/// the start means it's already there the whole time, so nothing pops.
class DrosteVortexPainter extends CustomPainter {
  DrosteVortexPainter({
    required this.image,
    required this.config,
    this.baseSizeFactor = 0.9,
  });

  final ui.Image image;
  final DrosteVortexConfig config;

  /// Size of the outermost (level 0) copy, as a fraction of the canvas's
  /// shortest side, before [DrosteVortexConfig.baseScale] is applied.
  final double baseSizeFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final aspect = image.width / image.height;
    final baseSize = size.shortestSide * baseSizeFactor;
    final baseW = baseSize;
    final baseH = baseSize / aspect;

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // Start two levels *before* 0 (bigger than nominal) so there's always a
    // next-bigger copy already present as baseScale grows — see the class
    // doc. Level 0 (nominal largest) drawn first among the "normal" ones,
    // deeper levels on top, matching the manual Illustrator composite where
    // the smaller copy sits above. No upper bound on the inner end either:
    // the sub-pixel break is what stops it, so there's always a reserve
    // level ready at the center too.
    const outwardReserveLevels = 2;
    for (int level = -outwardReserveLevels; level < 60; level++) {
      final scale = config.baseScale * math.pow(config.nestScale, level);
      final angle = config.globalRotationRad + level * config.rotationStepRad;
      final w = baseW * scale;
      final h = baseH * scale;

      // Once a level is smaller than a pixel there's nothing left to draw,
      // and every further (inner) level would be smaller still.
      if (level >= 0 && w < 0.5 && h < 0.5) break;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawImageRect(
        image,
        srcRect,
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DrosteVortexPainter oldDelegate) => true;
}
