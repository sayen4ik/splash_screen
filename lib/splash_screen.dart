import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'cloud_spiral_config.dart';
import 'cloud_spiral_painter.dart';

enum SplashState { intro, looping, outro, done }

/// Full splash-screen lifecycle demo: Intro (logo + cloud spiral fade/scale
/// in) -> Looping (indefinite loading, clouds stream out of the logo tip
/// forever, logo breathes) -> Outro (triggered externally, the stream
/// accelerates and the whole scene fades) -> a mock main-app screen. The
/// spiral's own clock never stops or resets across state changes — only
/// opacity/scale/speed are modulated — so there's no visible restart or pop
/// at a state boundary.
class SplashDemoScreen extends StatefulWidget {
  const SplashDemoScreen({super.key});

  @override
  State<SplashDemoScreen> createState() => _SplashDemoScreenState();
}

class _SplashDemoScreenState extends State<SplashDemoScreen>
    with SingleTickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 1500);
  static const _outroDuration = Duration(milliseconds: 500);
  static const _config = CloudSpiralConfig.initial;

  // Outro choreography: diving INTO the vortex — the whole composition
  // (spiral + logo together, as one piece) zooms in dramatically while the
  // scene fades, over `_outroDuration`. The cloud stream's own flow-speed is
  // untouched (stays at the normal LOOPING pace). Nothing else (Fill,
  // Reach/Turns/Spacing, logo scale/rotation) changes — it's one simple
  // zoom+fade, not a rewind of the intro reveal.
  static const _outroZoomEndFactor = 4.0;

  // Intro choreography: the spiral's shape (Reach/Turns/Spacing) is always
  // the full LOOPING one — never animated — and only `_fillAmount` (see
  // CloudSpiralPainter) reveals it gradually from the logo tip outward, like
  // a wipe. Overall rotation eases from `_introRotationStartDeg` down to the
  // baseline `_rotationDeg`, and zoom grows from 1.0 (no zoom) up to the
  // baseline `_globalZoom`, all together over `_introDuration`. Flow-speed
  // decays from a fast "just formed" whirl down to the calm baseline pace on
  // top of that.
  static const _introSpeedBoost = 7.0;
  static const _introLogoTiltDeg = 35.0;
  static const _introRotationStartDeg = 70.0;

  List<ui.Image>? _cloudImages;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  SplashState _state = SplashState.intro;
  double _stateElapsedSec = 0;

  double _spiralTimeSec = 0;
  double _breathe = 0; // 0..1, drives the logo glow pulse

  // Baseline defaults below are the settings the team landed on after
  // hand-tuning every knob live (2026-09-26) — this is the look new
  // sessions should start from, not a neutral 1.0 for every slider.

  /// Live speed knob for the LOOPING stream (1.0 = config's own pace).
  /// Scales how fast `_spiralTimeSec` advances, so dragging it changes how
  /// quickly clouds travel from the logo tip to the edge without touching
  /// [CloudSpiralConfig.loopSeconds] itself.
  double _speedMultiplier = 0.05;

  /// Live size knob for the *outer* (far/near-camera) clouds — the ones
  /// that have traveled furthest from the logo tip.
  double _sizeMultiplier = 1.82;

  /// Live size knob for the clouds right at the logo tip (spawn size).
  /// Together with `_sizeMultiplier` this sets how much clouds grow over
  /// their trip out — a bigger gap between the two reads as puffs visibly
  /// ballooning outward as they travel.
  double _startSizeMultiplier = 1.0;

  /// Base number of puffs `_particleSpacing` scales the density from
  /// (overrides [CloudSpiralConfig.particleCount] live).
  double _particleCount = 60;

  /// Live knob for how far apart consecutive puffs sit along the spiral
  /// (1.0 = evenly fills the whole loop, as before).
  double _particleSpacing = 1.41;

  /// Live ellipse-squash knob (1.0 = perfect circle, less = flatter oval),
  /// for the tilted-tunnel "distort" look.
  double _squashFactor = 0.70;

  /// Live tilt angle (degrees) of the squash axis.
  double _tiltAngleDeg = -40.0;

  /// Live multiplier on the spiral's turn count.
  double _turnsMultiplier = 1.76;

  /// Live multiplier on how far out the spiral reaches (1.0 = the canvas'
  /// own corner distance, so it fills a tall portrait screen edge to edge).
  double _reachMultiplier = 2.55;

  /// Live overall zoom: scales the whole composition (spiral + logo)
  /// together around screen center, on top of every other knob above —
  /// for making the entire splash bigger/smaller as one piece, as opposed
  /// to `_sizeMultiplier` which only grows the individual outer puffs.
  double _globalZoom = 1.91;

  /// Live fill amount (0–100%): how much of the always-full-size spiral is
  /// populated with clouds, from the logo tip outward — 0 = no clouds, 100 =
  /// the whole spiral. Baseline is 100 (fully filled, as in LOOPING); the
  /// intro animates its own copy of this from 0 up to whatever this is set
  /// to (see `effectiveFill` in build()).
  double _fillAmount = 100.0;

  /// Live overall rotation (degrees) of the whole composition — spiral AND
  /// logo together, as one rigid piece — around screen center. Unlike
  /// `_tiltAngleDeg`, which only tilts the spiral's own squash axis, this
  /// spins everything, logo included.
  double _rotationDeg = 0.0;

  /// Cloud sprite variants to pick from — add more paths here (and to
  /// pubspec.yaml's assets list) to have particles randomly (but stably,
  /// see [CloudSpiralPainter]) mix between several cloud shapes instead of
  /// stamping the same one everywhere.
  static const _cloudAssetPaths = [
    'assets/cloud_blob_10.webp',
    'assets/cloud_blob_11.webp',
    'assets/cloud_blob_12.webp',
  ];

  @override
  void initState() {
    super.initState();
    _loadImages();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    final loaded = await Future.wait(_cloudAssetPaths.map(_loadOneImage));
    if (!mounted) return;
    setState(() => _cloudImages = loaded);
  }

  Future<ui.Image> _loadOneImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (_state == SplashState.done) return;

    setState(() {
      _stateElapsedSec += dt;
      _breathe = (_breathe + dt * 0.6) % 1.0;

      double speedNow = _speedMultiplier;
      if (_state == SplashState.intro) {
        final introEase = Curves.easeOutSine.transform(
          (_stateElapsedSec * 1000 / _introDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          ),
        );
        speedNow = ui.lerpDouble(
          _speedMultiplier * _introSpeedBoost,
          _speedMultiplier,
          introEase,
        )!;
      }
      _spiralTimeSec += dt * speedNow;

      if (_state == SplashState.intro &&
          _stateElapsedSec * 1000 >= _introDuration.inMilliseconds) {
        _state = SplashState.looping;
        _stateElapsedSec = 0;
      } else if (_state == SplashState.outro &&
          _stateElapsedSec * 1000 >= _outroDuration.inMilliseconds) {
        _state = SplashState.done;
        _stateElapsedSec = 0;
      }
    });
  }

  void _playIntro() {
    setState(() {
      _state = SplashState.intro;
      _stateElapsedSec = 0;
    });
  }

  void _triggerExit() {
    if (_state != SplashState.looping) return;
    setState(() {
      _state = SplashState.outro;
      _stateElapsedSec = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final introT = (_stateElapsedSec * 1000 / _introDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final outroT = (_stateElapsedSec * 1000 / _outroDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final sceneOpacity = switch (_state) {
      SplashState.intro => Curves.easeOutSine.transform(introT),
      SplashState.looping => 1.0,
      SplashState.outro => 1.0 - Curves.easeInSine.transform(outroT),
      SplashState.done => 0.0,
    };
    final logoEase = Curves.easeOutBack.transform(introT);
    final outroEase = Curves.easeInSine.transform(outroT);
    final logoScale = switch (_state) {
      SplashState.intro => 0.8 + 0.2 * logoEase,
      _ => 1.0,
    };
    // The logo arrives slightly tilted and rights itself into the upright
    // orientation it holds for the rest of the LOOPING state — so it reads
    // as settling into place along with the spiral, not just popping in.
    final logoRotationRad = switch (_state) {
      SplashState.intro => (_introLogoTiltDeg * (1 - logoEase)) * math.pi / 180,
      _ => 0.0,
    };
    final glowBlur = 25 + 15 * (0.5 - 0.5 * math.cos(_breathe * 2 * math.pi));

    // The spiral's own shape (Reach/Turns/Spacing) never changes — only how
    // much of it is revealed, from the logo tip outward, via `fillAmount`.
    final introGrowEase = Curves.easeInOutSine.transform(introT);
    final effectiveFill = _state == SplashState.intro
        ? ui.lerpDouble(0.0, _fillAmount / 100, introGrowEase)!
        : _fillAmount / 100;
    final effectiveRotationDeg = _state == SplashState.intro
        ? ui.lerpDouble(_introRotationStartDeg, _rotationDeg, introGrowEase)!
        : _rotationDeg;
    final effectiveZoom = switch (_state) {
      SplashState.intro => ui.lerpDouble(1.0, _globalZoom, introGrowEase)!,
      SplashState.outro => ui.lerpDouble(
        _globalZoom,
        _globalZoom * _outroZoomEndFactor,
        outroEase,
      )!,
      _ => _globalZoom,
    };

    if (_state == SplashState.done) {
      return _MainAppMock(onReplay: _playIntro);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0314),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: sceneOpacity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0B0314),
                        Color(0xFF2E2054),
                        Color(0xFF8C6FD9),
                        Color(0xFFEDE6FF),
                      ],
                      stops: [0.0, 0.45, 0.78, 1.0],
                    ),
                  ),
                ),
                // Overall zoom + rotation knobs: scale/spin the spiral +
                // logo together as one rigid piece (not the full-bleed
                // background gradient, so shrinking/rotating this never
                // leaves unfilled screen edges).
                Transform.rotate(
                  angle: effectiveRotationDeg * math.pi / 180,
                  child: Transform.scale(
                    scale: effectiveZoom,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cloudImages != null)
                          CustomPaint(
                            painter: CloudSpiralPainter(
                              images: _cloudImages!,
                              config: _config,
                              timeSeconds: _spiralTimeSec,
                              sizeMultiplier: _sizeMultiplier,
                              startSizeMultiplier: _startSizeMultiplier,
                              particleSpacing: _particleSpacing,
                              squashFactor: _squashFactor,
                              tiltAngleRad: _tiltAngleDeg * math.pi / 180,
                              turnsMultiplier: _turnsMultiplier,
                              reachMultiplier: _reachMultiplier,
                              fillAmount: effectiveFill,
                              particleCount: _particleCount.round(),
                            ),
                            size: Size.infinite,
                          ),
                        Center(
                          child: Transform.rotate(
                            angle: logoRotationRad,
                            child: Transform.scale(
                              scale: logoScale,
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB48CFF)
                                          .withValues(alpha: 0.85),
                                      blurRadius: glowBlur,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Image.asset('assets/logo.png'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(top: 48, left: 16, child: _StateBadge(state: _state)),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.62,
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LabeledSlider(
                      label: 'Speed',
                      value: _speedMultiplier,
                      min: 0.01,
                      max: 0.1,
                      onChanged: (v) => setState(() => _speedMultiplier = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Scale',
                      value: _sizeMultiplier,
                      min: 0.3,
                      max: 6.0,
                      onChanged: (v) => setState(() => _sizeMultiplier = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Scale In',
                      value: _startSizeMultiplier,
                      min: 0.1,
                      max: 4.0,
                      onChanged: (v) =>
                          setState(() => _startSizeMultiplier = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Count',
                      value: _particleCount,
                      min: 10,
                      max: 200,
                      unit: '',
                      onChanged: (v) => setState(() => _particleCount = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Spacing',
                      value: _particleSpacing,
                      min: 0.3,
                      max: 3.0,
                      onChanged: (v) => setState(() => _particleSpacing = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Squash',
                      value: _squashFactor,
                      min: 0.3,
                      max: 1.0,
                      onChanged: (v) => setState(() => _squashFactor = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Tilt',
                      value: _tiltAngleDeg,
                      min: -60,
                      max: 60,
                      unit: '°',
                      onChanged: (v) => setState(() => _tiltAngleDeg = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Turns',
                      value: _turnsMultiplier,
                      min: 0.5,
                      max: 6.0,
                      onChanged: (v) => setState(() => _turnsMultiplier = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Reach',
                      value: _reachMultiplier,
                      min: 0.5,
                      max: 6.0,
                      onChanged: (v) => setState(() => _reachMultiplier = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Zoom',
                      value: _globalZoom,
                      min: 0.3,
                      max: 5.0,
                      onChanged: (v) => setState(() => _globalZoom = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Fill',
                      value: _fillAmount,
                      min: 0,
                      max: 100,
                      unit: '%',
                      onChanged: (v) => setState(() => _fillAmount = v),
                    ),
                    const SizedBox(height: 8),
                    _LabeledSlider(
                      label: 'Rotate',
                      value: _rotationDeg,
                      min: -180,
                      max: 180,
                      unit: '°',
                      onChanged: (v) => setState(() => _rotationDeg = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _playIntro,
                          child: const Text('Play Intro'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _state == SplashState.looping
                              ? _triggerExit
                              : null,
                          child: const Text('Trigger App Loaded (Exit)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final SplashState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        'State: ${state.name.toUpperCase()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = 'x',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;

  bool get _isWholeNumberUnit => unit == '°' || unit == '%' || unit.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: _isWholeNumberUnit
                    ? (max - min).round().clamp(1, 100000)
                    : ((max - min) * 100).round().clamp(200, 100000),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${value.toStringAsFixed(_isWholeNumberUnit ? 0 : 2)}$unit',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainAppMock extends StatelessWidget {
  const _MainAppMock({required this.onReplay});

  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16161C),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Main App Screen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onReplay,
              child: const Text('Replay splash'),
            ),
          ],
        ),
      ),
    );
  }
}
