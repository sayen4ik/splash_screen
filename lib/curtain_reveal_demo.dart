import 'package:flutter/material.dart';

import 'splash_screen.dart';

/// Standalone prototype for a "theater curtain" reveal: two panels split
/// down the middle, each clipped along a curved (quadratic Bezier) edge
/// instead of a straight line. The top of that edge is driven by a faster
/// curve than the bottom, so mid-animation the boundary visibly bows (an
/// arc) before straightening out again once both catch up to fully open.
/// Purely a motion/shape prototype — the flat gradient panels stand in for
/// the folded-fabric texture PNG that will eventually replace them, and
/// the "screenshot" behind them is a mock, not a real one.
class CurtainRevealDemo extends StatefulWidget {
  const CurtainRevealDemo({super.key});

  @override
  State<CurtainRevealDemo> createState() => _CurtainRevealDemoState();
}

class _CurtainRevealDemoState extends State<CurtainRevealDemo>
    with TickerProviderStateMixin {
  static const _phoneWidth = 390.0;
  static const _phoneHeight = 844.0;

  // Two-phase timeline: first the fold texture fades in on top of the
  // still-uncut screenshot (turning it "into" curtains), THEN the
  // curtains actually part. Two separate controllers because they run
  // one after the other, not in parallel, and have independently tunable
  // durations.
  late final AnimationController _fadeController;
  late final AnimationController _openController;

  double _fadeMs = 150;
  double _durationMs = 1695;
  // How pronounced the mid-animation bow is (0 = perfectly straight edge).
  double _arcStrength = 0.16;
  // How much of a head start the top edge gets over the bottom edge —
  // 0 means both move together (no arc regardless of _arcStrength), 1 is
  // the most pronounced top-leads-bottom lag.
  double _topLead = 0.0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _fadeMs.round()),
    );
    _openController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs.round()),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _openController.dispose();
    super.dispose();
  }

  void _play() {
    _openController.value = 0;
    _fadeController.duration = Duration(milliseconds: _fadeMs.round());
    _openController.duration = Duration(milliseconds: _durationMs.round());
    _fadeController.forward(from: 0).whenComplete(() {
      if (mounted) _openController.forward(from: 0);
    });
  }

  void _reset() {
    _fadeController.value = 0;
    _openController.value = 0;
  }

  Curve get _topCurve => Curves.easeOutExpo;

  Curve get _bottomCurve {
    final startDelay = (_topLead * 0.6).clamp(0.0, 0.85);
    return Interval(startDelay, 1.0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16161C),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _phoneWidth,
                        height: _phoneHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(48),
                            border: Border.all(
                              color: Colors.white24,
                              width: 8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                _fadeController,
                                _openController,
                              ]),
                              builder: (context, _) {
                                final t = _openController.value;
                                final topT = _topCurve.transform(t);
                                final bottomT = _bottomCurve.transform(t);
                                final textureOpacity = _fadeController.value;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // What's behind the curtain once it's
                                    // fully open — a placeholder for now;
                                    // the screenshot itself lives IN the
                                    // curtain panels below, not here.
                                    const _RevealedBackground(),
                                    _CurtainPanel(
                                      side: _CurtainSide.left,
                                      topT: topT,
                                      bottomT: bottomT,
                                      arcStrength: _arcStrength,
                                      textureOpacity: textureOpacity,
                                      width: _phoneWidth,
                                      height: _phoneHeight,
                                    ),
                                    _CurtainPanel(
                                      side: _CurtainSide.right,
                                      topT: topT,
                                      bottomT: bottomT,
                                      arcStrength: _arcStrength,
                                      textureOpacity: textureOpacity,
                                      width: _phoneWidth,
                                      height: _phoneHeight,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Curtain reveal — motion/shape prototype only',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 340,
            color: const Color(0xFF14101C),
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Curtain reveal (prototype)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _DemoSlider(
                  label: 'Fade',
                  value: _fadeMs,
                  min: 50,
                  max: 1000,
                  unit: 'ms',
                  description:
                      'Скільки триває перетворення скріну на штори, до '
                      'початку розсування',
                  onChanged: (v) => setState(() => _fadeMs = v),
                ),
                const SizedBox(height: 8),
                _DemoSlider(
                  label: 'Duration',
                  value: _durationMs,
                  min: 300,
                  max: 2500,
                  unit: 'ms',
                  onChanged: (v) => setState(() => _durationMs = v),
                ),
                const SizedBox(height: 8),
                _DemoSlider(
                  label: 'Arc',
                  value: _arcStrength,
                  min: 0,
                  max: 1,
                  description: 'Наскільки сильно вигинається край шторки',
                  onChanged: (v) => setState(() => _arcStrength = v),
                ),
                const SizedBox(height: 8),
                _DemoSlider(
                  label: 'Top Lead',
                  value: _topLead,
                  min: 0,
                  max: 1,
                  description: 'Наскільки верх випереджає низ у русі',
                  onChanged: (v) => setState(() => _topLead = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _play,
                      child: const Text('Play'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _reset,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SplashDemoScreen(),
                    ),
                  ),
                  child: const Text('Open real splash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CurtainSide { left, right }

class _CurtainPanel extends StatelessWidget {
  const _CurtainPanel({
    required this.side,
    required this.topT,
    required this.bottomT,
    required this.arcStrength,
    required this.textureOpacity,
    required this.width,
    required this.height,
  });

  final _CurtainSide side;
  final double topT;
  final double bottomT;
  final double arcStrength;
  // 0 = plain screenshot, no fabric look yet; 1 = fully "turned into" a
  // curtain. Ramped by `_fadeController` before the open animation ever
  // starts moving `topT`/`bottomT`.
  final double textureOpacity;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _CurtainClipper(
        side: side,
        topT: topT,
        bottomT: bottomT,
        arcStrength: arcStrength,
      ),
      // Both panels draw the SAME full-size screenshot + fold texture at
      // the SAME position (not shifted per side) — since each is clipped
      // to only its own half of the shape, both the screenshot and the
      // fold pattern line up continuously across the seam. The
      // screenshot moves WITH the curtain (it *is* the curtain), not as a
      // separate static layer underneath.
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/curtain_mock_screenshot.webp',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            Opacity(
              opacity: textureOpacity,
              child: Image.asset(
                'assets/curtain_fold_texture.webp',
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The clip boundary between the visible curtain panel and the revealed
/// screen behind it: a quadratic Bezier from `(edge, 0)` to `(edge, h)`
/// whose top and bottom endpoints are driven by their own progress values
/// (`topT`/`bottomT`) — when they differ, the curve bows instead of
/// staying a straight vertical line.
class _CurtainClipper extends CustomClipper<Path> {
  _CurtainClipper({
    required this.side,
    required this.topT,
    required this.bottomT,
    required this.arcStrength,
  });

  final _CurtainSide side;
  final double topT;
  final double bottomT;
  final double arcStrength;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final half = w / 2;
    final overshoot = w * 0.15;
    final isLeft = side == _CurtainSide.left;
    final closed = half;
    final open = isLeft ? -overshoot : w + overshoot;

    double edgeX(double t) => closed + (open - closed) * t;
    final topX = edgeX(topT);
    final bottomX = edgeX(bottomT);
    final midY = h / 2;
    final controlX = (topX + bottomX) / 2 + (topX - bottomX) * arcStrength;

    final path = Path();
    if (isLeft) {
      path
        ..moveTo(0, 0)
        ..lineTo(topX, 0)
        ..quadraticBezierTo(controlX, midY, bottomX, h)
        ..lineTo(0, h)
        ..close();
    } else {
      path
        ..moveTo(w, 0)
        ..lineTo(topX, 0)
        ..quadraticBezierTo(controlX, midY, bottomX, h)
        ..lineTo(w, h)
        ..close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _CurtainClipper oldClipper) =>
      oldClipper.topT != topT ||
      oldClipper.bottomT != bottomT ||
      oldClipper.arcStrength != arcStrength ||
      oldClipper.side != side;
}

/// Whatever sits behind the curtain once it's fully open — the
/// screenshot lives IN the curtain panels themselves (see
/// `_CurtainPanel`), so this is only ever visible for a moment as the
/// panels finish parting. Just a placeholder color for now; the real
/// flow would swap this for whatever comes after the reveal.
class _RevealedBackground extends StatelessWidget {
  const _RevealedBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF0B0314));
  }
}

/// Minimal local copy of the app's slider-row look — kept private to this
/// file rather than importing `splash_screen.dart`'s private widget.
class _DemoSlider extends StatelessWidget {
  const _DemoSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.description,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${value.toStringAsFixed(unit == 'ms' ? 0 : 2)}$unit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                description!,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
