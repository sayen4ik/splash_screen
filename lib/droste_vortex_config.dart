import 'dart:math' as math;

/// Parameters for the "Droste" vortex: the same spiral image is drawn over
/// and over (as many times as are still visible — see [DrosteVortexPainter]),
/// always centered on the same point, each copy scaled down by [nestScale]
/// from the previous one (and optionally rotated by [rotationStepDeg]).
/// Because the image already looks like a spiral converging to its own
/// geometric center, nesting a smaller copy of itself at that same center
/// reads as "the picture contains itself" — the classic Droste effect —
/// instead of an artificially assembled chain.
class DrosteVortexConfig {
  /// Scale ratio between one nested level and the next (0 < nestScale < 1).
  final double nestScale;

  /// Rotation applied at every nested level, in degrees. 0 keeps every
  /// level in the same orientation, matching the source image exactly.
  final double rotationStepDeg;

  /// Overall scale of the outermost (level 0) copy.
  final double baseScale;

  /// Overall rotation of the outermost (level 0) copy, in degrees.
  final double globalRotationDeg;

  const DrosteVortexConfig({
    this.nestScale = 0.17,
    this.rotationStepDeg = 0,
    this.baseScale = 1.0,
    this.globalRotationDeg = 0,
  });

  static const DrosteVortexConfig initial = DrosteVortexConfig();

  double get rotationStepRad => rotationStepDeg * math.pi / 180;
  double get globalRotationRad => globalRotationDeg * math.pi / 180;

  DrosteVortexConfig copyWith({
    double? nestScale,
    double? rotationStepDeg,
    double? baseScale,
    double? globalRotationDeg,
  }) {
    return DrosteVortexConfig(
      nestScale: nestScale ?? this.nestScale,
      rotationStepDeg: rotationStepDeg ?? this.rotationStepDeg,
      baseScale: baseScale ?? this.baseScale,
      globalRotationDeg: globalRotationDeg ?? this.globalRotationDeg,
    );
  }

  String toDartLiteral() {
    String f(double v) => v.toStringAsFixed(3);
    return 'const DrosteVortexConfig(\n'
        '  nestScale: ${f(nestScale)},\n'
        '  rotationStepDeg: ${f(rotationStepDeg)},\n'
        '  baseScale: ${f(baseScale)},\n'
        '  globalRotationDeg: ${f(globalRotationDeg)},\n'
        ');';
  }
}
