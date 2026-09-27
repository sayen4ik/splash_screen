import 'package:flutter/material.dart';

/// Reusable "theater curtain" reveal, extracted from the standalone
/// prototype (`curtain_reveal_demo.dart`) so it can sit on top of the
/// real splash's phone frame. Two panels split down the middle, each
/// clipped along a curved (quadratic Bezier) edge; the top of that edge
/// moves on a faster curve than the bottom, so mid-animation the
/// boundary bows before straightening out once both catch up.
///
/// Plays automatically once mounted: first the fold texture fades in on
/// top of the still-uncut screenshot (turning it "into" curtains, over
/// [fadeMs]), then the panels part (over [durationMs]). Calls
/// [onComplete] once fully open, so the caller can remove this widget
/// from the tree (it doesn't remove itself — once open, both panels sit
/// off-screen via overshoot, so it's visually a no-op left in place, but
/// the caller decides whether that's fine or whether to unmount it).
class CurtainOverlay extends StatefulWidget {
  const CurtainOverlay({
    super.key,
    required this.width,
    required this.height,
    this.fadeMs = 150,
    this.durationMs = 1695,
    this.arcStrength = 0.16,
    this.topLead = 0.0,
    this.onComplete,
  });

  final double width;
  final double height;
  final double fadeMs;
  final double durationMs;
  final double arcStrength;
  final double topLead;
  final VoidCallback? onComplete;

  @override
  State<CurtainOverlay> createState() => _CurtainOverlayState();
}

class _CurtainOverlayState extends State<CurtainOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _openController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.fadeMs.round()),
    );
    _openController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs.round()),
    );
    _fadeController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _openController.forward(from: 0).whenComplete(() {
        widget.onComplete?.call();
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _openController.dispose();
    super.dispose();
  }

  Curve get _topCurve => Curves.easeOutExpo;

  Curve get _bottomCurve {
    final startDelay = (widget.topLead * 0.6).clamp(0.0, 0.85);
    return Interval(startDelay, 1.0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_fadeController, _openController]),
        builder: (context, _) {
          final t = _openController.value;
          final topT = _topCurve.transform(t);
          final bottomT = _bottomCurve.transform(t);
          final textureOpacity = _fadeController.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              _CurtainPanel(
                side: _CurtainSide.left,
                topT: topT,
                bottomT: bottomT,
                arcStrength: widget.arcStrength,
                textureOpacity: textureOpacity,
                width: widget.width,
                height: widget.height,
              ),
              _CurtainPanel(
                side: _CurtainSide.right,
                topT: topT,
                bottomT: bottomT,
                arcStrength: widget.arcStrength,
                textureOpacity: textureOpacity,
                width: widget.width,
                height: widget.height,
              ),
            ],
          );
        },
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
      // to only its own half of the shape, both line up continuously
      // across the seam.
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
