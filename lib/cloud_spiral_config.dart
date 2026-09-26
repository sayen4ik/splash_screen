import 'dart:math' as math;

/// Parameters for the tip-anchored cloud spiral: every particle spawns at
/// the exact same point — the outer tip/tail of the 'C' logo — and travels
/// outward along a spiral path as its life-progress `p` goes 0 -> 1, then
/// wraps back to 0. Because every particle shares that one spawn point and
/// angle, the whole stream reads as one continuous curl coming out of the
/// letter, not a symmetric ring floating around it.
class CloudSpiralConfig {
  /// Angle (radians, screen space: 0 = right, +pi/2 = down) of the logo's
  /// outer tip, measured from the logo's own center. Found by locating the
  /// farthest faint (fading-tail) pixel of assets/logo.png from its
  /// bounding-box center — currently a nautilus-spiral logo whose tail
  /// fades out toward the upper-left.
  final double spawnAngleRad;

  /// Radius (logical px) where particles are born. Deliberately a little
  /// *inside* the logo's own on-screen radius so the first puff overlaps
  /// the tip instead of leaving a gap.
  final double spawnRadius;

  /// Radius (logical px, independent of screen size — the painter scales
  /// it by the canvas' shortest side) where particles fade out and wrap.
  final double maxRadiusFactor;

  /// How many full turns (in units of 2*pi) a particle sweeps as p goes
  /// 0 -> 1. Magnitude = tighter coiling near the tip and more overlapping
  /// rings further out. Sign = winding direction; negative matches this
  /// logo's own curl (the drawn 'C' stroke winds clockwise as it goes from
  /// its outer tail inward to the tiny eye, so continuing outward from the
  /// tail in the same rotational sense winds counter-clockwise).
  final double totalTurns;

  /// Power in r(p) = spawnRadius + (rMax - spawnRadius) * p^power. > 1
  /// keeps particles lingering near the tip early (tight coil hugging the
  /// logo) before accelerating outward (spiral loosens near the edge).
  final double radiusPower;

  /// Number of cloud sprites alive at once, evenly staggered in `p`.
  final int particleCount;

  /// Seconds for one particle to travel spawnRadius -> maxRadius.
  final double loopSeconds;

  /// Sprite width range (as a factor of the canvas' shortest side) at
  /// p=0 and p=1.
  final double minScaleFactor;
  final double maxScaleFactor;

  const CloudSpiralConfig({
    this.spawnAngleRad = -150 * math.pi / 180,
    this.spawnRadius = 22,
    this.maxRadiusFactor = 0.65,
    this.totalTurns = -2.6,
    this.radiusPower = 1.5,
    this.particleCount = 60,
    this.loopSeconds = 6.0,
    this.minScaleFactor = 0.07,
    this.maxScaleFactor = 0.62,
  });

  static const CloudSpiralConfig initial = CloudSpiralConfig();
}
