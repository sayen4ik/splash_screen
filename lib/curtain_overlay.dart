import 'package:flutter/material.dart';

/// Reusable "theater curtain" reveal, extracted from the standalone
/// prototype (`curtain_reveal_demo.dart`) so it can sit on top of the
/// real splash's phone frame. Two panels split down the middle, each
/// clipped along a curved (quadratic Bezier) edge; the top of that edge
/// moves on a faster curve than the bottom, so mid-animation the
/// boundary bows before straightening out once both catch up.
///
/// The fold texture is fully visible (opacity 1) while opening — the
/// screenshot's "turning into" curtain fabric during an open is treated
/// as already having happened (see [CurtainClosedFrame], the resting
/// look an open starts from). While CLOSING, the texture fades OUT
/// (1 → 0) over the motion instead, so the fabric look dies away as the
/// panels settle shut, ending on the bare merged screenshot rather than
/// popping the texture back on.
///
/// - [reverse] `false` (default): starts fully closed and **opens**
///   (0 → 1), revealing whatever is behind it.
/// - [reverse] `true`: starts fully open and **closes** (1 → 0) back
///   over whatever's currently on screen — the exact same motion played
///   backward, since [Curve]s apply identically regardless of which way
///   the underlying [AnimationController] is running.
///
/// Calls [onComplete] once the animation finishes (fully open, or fully
/// closed) so the caller can react — e.g. swap this out for the static
/// [CurtainClosedFrame] once a close finishes.
class CurtainOverlay extends StatefulWidget {
  const CurtainOverlay({
    super.key,
    required this.width,
    required this.height,
    this.durationMs = 1695,
    this.arcStrength = 0.16,
    this.topLead = 0.0,
    this.reverse = false,
    this.onComplete,
  });

  final double width;
  final double height;
  final double durationMs;
  final double arcStrength;
  final double topLead;
  final bool reverse;
  final VoidCallback? onComplete;

  @override
  State<CurtainOverlay> createState() => _CurtainOverlayState();
}

class _CurtainOverlayState extends State<CurtainOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _openController;

  @override
  void initState() {
    super.initState();
    _openController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs.round()),
    );
    final animation = widget.reverse
        ? _openController.reverse(from: 1)
        : _openController.forward(from: 0);
    animation.whenComplete(() => widget.onComplete?.call());
  }

  @override
  void dispose() {
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
        animation: _openController,
        builder: (context, _) {
          // `_openController.value` is literally "how open" the curtain
          // is, which is exactly what we want to feed the lead/lag
          // curves when OPENING (top curve reaches openness=1 fastest —
          // it leads). But naively reusing that same raw value while
          // reversed would flip which edge leads: reversing time alone
          // makes whichever curve reaches its target fastest also
          // finish CLOSING first, i.e. the bottom (which starts moving
          // late, so during reverse it's the first to already be at 0)
          // would appear to lead the close instead of chasing it — the
          // opposite of how a real curtain behaves (the top, pulled by
          // the rail, always initiates the motion in either direction;
          // the loose bottom always lags/catches up). So instead, `p`
          // below is "progress of the current motion" (0 → 1 regardless
          // of direction), and closing inverts the curve's OUTPUT
          // (`1 - curve(p)`) rather than reusing its input reversed —
          // that keeps the top leading and the bottom catching up both
          // ways.
          final p = widget.reverse
              ? 1 - _openController.value
              : _openController.value;
          final topT = widget.reverse
              ? 1 - _topCurve.transform(p)
              : _topCurve.transform(p);
          final bottomT = widget.reverse
              ? 1 - _bottomCurve.transform(p)
              : _bottomCurve.transform(p);
          // Only closing fades the texture — opening keeps it at full
          // strength throughout (see class doc).
          final textureOpacity = widget.reverse ? 1 - p : 1.0;
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

/// The curtain's resting closed frame — just the bare screenshot, full
/// bleed, no clipping, no fold texture, no animation (fully closed means
/// there's no seam to hide, so this is a single flat image). No texture
/// here on purpose: a closing [CurtainOverlay] fades its texture out to
/// exactly this look by the time it finishes, so swapping to this frame
/// afterward is seamless rather than popping texture back on. Shown
/// whenever the curtain is at rest closed: the splash's very first
/// frame, and again after a close finishes.
class CurtainClosedFrame extends StatelessWidget {
  const CurtainClosedFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const Image(
      image: AssetImage('assets/curtain_mock_screenshot.webp'),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
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
