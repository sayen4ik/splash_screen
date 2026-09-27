import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;

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

  // The phone-frame preview size: iPhone 13/14/15 logical points (390x844),
  // one of the most common phone viewport sizes — chosen so this demo shows
  // a developer an accurate, device-shaped preview rather than whatever
  // random size the browser window happens to be.
  static const _phoneWidth = 390.0;
  static const _phoneHeight = 844.0;

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

  // Uploaded replacements for the logo and the 3 cloud sprite slots — set
  // via the "Assets" panel on the right, letting a developer preview their
  // own art without editing code. `null` at an index means "use the
  // bundled default" (from `assets/logo.png` / `_cloudAssetPaths`). Bytes
  // are kept alongside the decoded `ui.Image` because the logo is drawn as
  // an `Image.memory` widget (needs bytes) while cloud sprites are drawn by
  // `CloudSpiralPainter` on a raw `Canvas` (needs a decoded `ui.Image`).
  Uint8List? _customLogoBytes;
  final List<Uint8List?> _customCloudBytes = List<Uint8List?>.filled(3, null);
  final List<ui.Image?> _customCloudImages = List<ui.Image?>.filled(3, null);

  // "Share params" box at the bottom of the panel: a plain-text (JSON)
  // dump of every slider value (never the uploaded images — those aren't
  // meant to travel through a chat message). One person hits "Copy", pastes
  // the text to someone else, who pastes it in here and hits "Apply" to
  // pull those exact slider positions onto their own screen.
  late final TextEditingController _configController;
  String? _configApplyError;

  // Background: a plain 2-stop gradient (top color -> bottom color) behind
  // everything — always fully opaque, no opacity knob needed. Foreground:
  // the tint overlay drawn on top of the whole scene, also top color ->
  // bottom color, but each end has its own live opacity (0-100%) instead
  // of the old fixed 0%/40% fade — so both the hue *and* how strong the
  // fade is at each end are tunable.
  Color _bgTopColor = const Color(0xFF07020D);
  Color _bgBottomColor = const Color(0xFFC9C3D9);
  Color _fgTopColor = const Color(0xFFE6BAFF);
  Color _fgBottomColor = const Color(0xFFE6BAFF);
  double _fgTopOpacity = 0.0;
  double _fgBottomOpacity = 40.0;

  /// Where the foreground gradient's *top* stop sits, as a 0..1 fraction
  /// of the screen from the top — the bottom stop always stays pinned at
  /// the very bottom (1.0), only this one moves. Raising it slides the
  /// whole top-to-bottom transition down toward the bottom, so the FG Top
  /// color holds solid over more of the upper screen before the blend
  /// into FG Bottom starts. 0.0 = old behavior (transition spans the
  /// full screen top-to-bottom).
  double _fgTopStop = 0.0;
  late final TextEditingController _bgTopHexController;
  late final TextEditingController _bgBottomHexController;
  late final TextEditingController _fgTopHexController;
  late final TextEditingController _fgBottomHexController;

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
  double _speedMultiplier = 0.0303;

  /// Live size knob for the *outer* (far/near-camera) clouds — the ones
  /// that have traveled furthest from the logo tip, i.e. how big puffs get
  /// once they've scaled all the way out. Shown in the UI as "Scale Out".
  double _sizeMultiplier = 1.41;

  /// Live size knob for the clouds right at the logo tip (spawn size), i.e.
  /// how big puffs are the moment they scale in from the logo. Shown in the
  /// UI as "Scale In". Together with `_sizeMultiplier` ("Scale Out") this
  /// sets how much clouds grow over their trip out — a bigger gap between
  /// the two reads as puffs visibly ballooning outward as they travel.
  double _startSizeMultiplier = 0.19;

  /// Where (0..1, along life-progress `p`) a puff sits exactly halfway
  /// between Scale In and Scale Out in size. 0.5 = old plain-linear growth.
  /// Push toward 0 to have puffs balloon up to full size quickly right
  /// after spawning and hold it the rest of the way out; push toward 1 to
  /// stay small for most of the trip and only balloon up near the edge.
  /// Shown in the UI as "Scale Midpoint".
  double _sizeMidpoint = 0.5;

  /// Base number of puffs `_particleSpacing` scales the density from
  /// (overrides [CloudSpiralConfig.particleCount] live).
  double _particleCount = 86;

  /// Live knob for how far apart consecutive puffs sit along the spiral
  /// (1.0 = evenly fills the whole loop, as before).
  double _particleSpacing = 0.91;

  /// Live ellipse-squash knob (1.0 = perfect circle, less = flatter oval),
  /// for the tilted-tunnel "distort" look.
  double _squashFactor = 0.7235;

  /// Live tilt angle (degrees) of the squash axis.
  double _tiltAngleDeg = -39.0;

  /// Live multiplier on the spiral's turn count.
  double _turnsMultiplier = 2.76;

  /// Live multiplier on how far out the spiral reaches (1.0 = the canvas'
  /// own corner distance, so it fills a tall portrait screen edge to edge).
  double _reachMultiplier = 2.55;

  /// Live multiplier on [CloudSpiralConfig.spawnRadius] — how far out the
  /// very first turn sits. Raising this pushes puffs off the logo (the
  /// r(p) curve's outer end is unaffected — see [CloudSpiralPainter]),
  /// useful when the innermost turn is landing on top of the logo instead
  /// of wrapping around it. Shown in the UI as "Inner Radius".
  double _innerRadiusMultiplier = 1.72;

  /// Live power curve on a puff's real-time pacing based on where it is
  /// along its own life. 1.0 = uniform (old behavior). Above 1.0, puffs
  /// near the logo move slowly and accelerate as they travel outward —
  /// "closer/outer puffs move faster, ones near the logo move slower".
  /// Shown in the UI as "Depth Speed".
  double _depthSpeedPower = 1.0;

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

  /// Pixel offset (from the phone-frame canvas' own center) of where the
  /// spiral's spawn point sits — the logo itself always stays dead center;
  /// only the spiral's own center moves, so this is for cases where the
  /// spiral should wind out from a point near the logo rather than exactly
  /// through it. Applied *before* the zoom/rotation transform above, so it
  /// scales/rotates along with everything else rather than fighting it.
  /// Shown in the UI as "Spawn X"/"Spawn Y".
  double _spawnOffsetX = 1.0;
  double _spawnOffsetY = 10.0;

  /// Cloud sprite variants to pick from — add more paths here (and to
  /// pubspec.yaml's assets list) to have particles randomly (but stably,
  /// see [CloudSpiralPainter]) mix between several cloud shapes instead of
  /// stamping the same one everywhere.
  static const _cloudAssetPaths = [
    'assets/cloud_blob_16.webp',
    'assets/cloud_blob_17.webp',
    'assets/cloud_blob_18.webp',
  ];

  @override
  void initState() {
    super.initState();
    _loadImages();
    _ticker = createTicker(_onTick)..start();
    _configController = TextEditingController(text: _encodeConfig());
    _bgTopHexController = TextEditingController(
      text: _colorToHex(_bgTopColor),
    );
    _bgBottomHexController = TextEditingController(
      text: _colorToHex(_bgBottomColor),
    );
    _fgTopHexController = TextEditingController(
      text: _colorToHex(_fgTopColor),
    );
    _fgBottomHexController = TextEditingController(
      text: _colorToHex(_fgBottomColor),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _configController.dispose();
    _bgTopHexController.dispose();
    _bgBottomHexController.dispose();
    _fgTopHexController.dispose();
    _fgBottomHexController.dispose();
    super.dispose();
  }

  /// Parses a 6-digit hex string (with or without a leading `#`) into an
  /// opaque [Color]; `null` if it isn't one, so callers can leave a bad
  /// hex box untouched instead of crashing on it.
  static Color? _parseHex(String input) {
    final cleaned = input.trim().replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  static String _colorToHex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _applyBgTopHex() {
    final parsed = _parseHex(_bgTopHexController.text);
    if (parsed == null) return;
    setState(() => _bgTopColor = parsed);
  }

  void _applyBgBottomHex() {
    final parsed = _parseHex(_bgBottomHexController.text);
    if (parsed == null) return;
    setState(() => _bgBottomColor = parsed);
  }

  void _applyFgTopHex() {
    final parsed = _parseHex(_fgTopHexController.text);
    if (parsed == null) return;
    setState(() => _fgTopColor = parsed);
  }

  void _applyFgBottomHex() {
    final parsed = _parseHex(_fgBottomHexController.text);
    if (parsed == null) return;
    setState(() => _fgBottomColor = parsed);
  }

  /// Every slider's current value, keyed by the same short names the
  /// "Apply" side reads back — deliberately excludes the uploaded logo/
  /// cloud images (those don't belong in a pasted chat message).
  Map<String, Object> _paramsMap() => {
    'speed': _speedMultiplier,
    'scaleOut': _sizeMultiplier,
    'scaleIn': _startSizeMultiplier,
    'scaleMid': _sizeMidpoint,
    'count': _particleCount.round(),
    'spacing': _particleSpacing,
    'squash': _squashFactor,
    'tilt': _tiltAngleDeg,
    'turns': _turnsMultiplier,
    'reach': _reachMultiplier,
    'innerRadius': _innerRadiusMultiplier,
    'depthSpeed': _depthSpeedPower,
    'zoom': _globalZoom,
    'fill': _fillAmount,
    'rotate': _rotationDeg,
    'spawnX': _spawnOffsetX,
    'spawnY': _spawnOffsetY,
    'bgTop': _colorToHex(_bgTopColor),
    'bgBottom': _colorToHex(_bgBottomColor),
    'fgTop': _colorToHex(_fgTopColor),
    'fgBottom': _colorToHex(_fgBottomColor),
    'fgTopOpacity': _fgTopOpacity,
    'fgBottomOpacity': _fgBottomOpacity,
    'fgTopStop': _fgTopStop,
  };

  String _encodeConfig() =>
      const JsonEncoder.withIndent('  ').convert(_paramsMap());

  void _copyConfig() {
    final text = _encodeConfig();
    setState(() {
      _configController.text = text;
      _configApplyError = null;
    });
    Clipboard.setData(ClipboardData(text: text));
  }

  /// Parses whatever's currently typed/pasted into the config box and
  /// pushes each recognized field onto its slider, clamped into that
  /// slider's own min/max — a `Slider` throws if handed a value outside
  /// its range, and a value from someone else's session (or a hand-typed
  /// one) is never guaranteed to already fit. Unrecognized keys are
  /// ignored; a value that isn't a number for a known key is skipped
  /// rather than failing the whole import.
  void _applyConfig() {
    try {
      final decoded = jsonDecode(_configController.text);
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object');
      }
      double? asDouble(String key) => switch (decoded[key]) {
        final num n => n.toDouble(),
        _ => null,
      };
      Color? asColor(String key) => switch (decoded[key]) {
        final String s => _parseHex(s),
        _ => null,
      };
      setState(() {
        if (asDouble('speed') case final v?) {
          _speedMultiplier = v.clamp(0.01, 0.1);
        }
        if (asDouble('scaleOut') case final v?) {
          _sizeMultiplier = v.clamp(0.3, 6.0);
        }
        if (asDouble('scaleIn') case final v?) {
          _startSizeMultiplier = v.clamp(0.1, 4.0);
        }
        if (asDouble('scaleMid') case final v?) {
          _sizeMidpoint = v.clamp(0.05, 0.95);
        }
        if (asDouble('count') case final v?) {
          _particleCount = v.clamp(10, 200);
        }
        if (asDouble('spacing') case final v?) {
          _particleSpacing = v.clamp(0.3, 3.0);
        }
        if (asDouble('squash') case final v?) {
          _squashFactor = v.clamp(0.3, 1.0);
        }
        if (asDouble('tilt') case final v?) {
          _tiltAngleDeg = v.clamp(-60, 60);
        }
        if (asDouble('turns') case final v?) {
          _turnsMultiplier = v.clamp(0.5, 6.0);
        }
        if (asDouble('reach') case final v?) {
          _reachMultiplier = v.clamp(0.5, 6.0);
        }
        if (asDouble('innerRadius') case final v?) {
          _innerRadiusMultiplier = v.clamp(0.5, 10.0);
        }
        if (asDouble('depthSpeed') case final v?) {
          _depthSpeedPower = v.clamp(0.3, 4.0);
        }
        if (asDouble('zoom') case final v?) {
          _globalZoom = v.clamp(0.3, 5.0);
        }
        if (asDouble('fill') case final v?) {
          _fillAmount = v.clamp(0, 100);
        }
        if (asDouble('rotate') case final v?) {
          _rotationDeg = v.clamp(-180, 180);
        }
        if (asDouble('spawnX') case final v?) {
          _spawnOffsetX = v.clamp(-200, 200);
        }
        if (asDouble('spawnY') case final v?) {
          _spawnOffsetY = v.clamp(-200, 200);
        }
        if (asColor('bgTop') case final c?) {
          _bgTopColor = c;
          _bgTopHexController.text = _colorToHex(c);
        }
        if (asColor('bgBottom') case final c?) {
          _bgBottomColor = c;
          _bgBottomHexController.text = _colorToHex(c);
        }
        if (asColor('fgTop') case final c?) {
          _fgTopColor = c;
          _fgTopHexController.text = _colorToHex(c);
        }
        if (asColor('fgBottom') case final c?) {
          _fgBottomColor = c;
          _fgBottomHexController.text = _colorToHex(c);
        }
        if (asDouble('fgTopOpacity') case final v?) {
          _fgTopOpacity = v.clamp(0, 100);
        }
        if (asDouble('fgBottomOpacity') case final v?) {
          _fgBottomOpacity = v.clamp(0, 100);
        }
        if (asDouble('fgTopStop') case final v?) {
          _fgTopStop = v.clamp(0.0, 0.95);
        }
        _configApplyError = null;
      });
    } catch (_) {
      setState(() => _configApplyError = 'Couldn\'t read that — check it\'s valid JSON.');
    }
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

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List?> _pickImageBytes() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    return files.single.readAsBytes();
  }

  Future<void> _pickLogo() async {
    final bytes = await _pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() => _customLogoBytes = bytes);
  }

  void _resetLogo() => setState(() => _customLogoBytes = null);

  Future<void> _pickCloud(int index) async {
    final bytes = await _pickImageBytes();
    if (bytes == null) return;
    final image = await _decodeBytes(bytes);
    if (!mounted) return;
    setState(() {
      _customCloudBytes[index] = bytes;
      _customCloudImages[index] = image;
    });
  }

  void _resetCloud(int index) => setState(() {
    _customCloudBytes[index] = null;
    _customCloudImages[index] = null;
  });

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

    // The splash itself is rendered at a fixed phone-sized canvas (not the
    // browser window) so what's shown on the left is an accurate preview of
    // how it'll actually look on a phone screen — this is a dev-facing demo
    // meant to be shown to the person implementing it, not just a live-tune
    // canvas. Everything below (gradient, starfield, spiral, logo, tint) is
    // unchanged from before; only the outer wrapping changed.
    final splashContent = Opacity(
      opacity: sceneOpacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_bgTopColor, _bgBottomColor],
                    ),
                  ),
                ),
                // Static starfield: fixed in place, centered, never moves
                // or animates — sits above the background gradient but
                // below the spiral/logo, and is unaffected by the zoom and
                // rotation transforms applied to those below.
                const Positioned.fill(
                  child: Image(
                    image: AssetImage('assets/stars_bg.png'),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
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
                              images: [
                                for (var i = 0; i < _cloudImages!.length; i++)
                                  _customCloudImages[i] ?? _cloudImages![i],
                              ],
                              config: _config,
                              timeSeconds: _spiralTimeSec,
                              sizeMultiplier: _sizeMultiplier,
                              startSizeMultiplier: _startSizeMultiplier,
                              sizeMidpoint: _sizeMidpoint,
                              particleSpacing: _particleSpacing,
                              squashFactor: _squashFactor,
                              tiltAngleRad: _tiltAngleDeg * math.pi / 180,
                              turnsMultiplier: _turnsMultiplier,
                              reachMultiplier: _reachMultiplier,
                              innerRadiusMultiplier: _innerRadiusMultiplier,
                              depthSpeedPower: _depthSpeedPower,
                              fillAmount: effectiveFill,
                              spawnOffset: Offset(
                                _spawnOffsetX,
                                _spawnOffsetY,
                              ),
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
                                child: _customLogoBytes != null
                                    ? Image.memory(
                                        _customLogoBytes!,
                                        fit: BoxFit.contain,
                                      )
                                    : Image.asset('assets/logo.png'),
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
          // Cosmetic tint over the whole splash, top color -> bottom color,
          // each with its own live opacity. Sits above the scene (clouds/
          // logo), as part of the phone-frame content itself — not debug
          // UI, so it stays inside `splashContent`.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _fgTopColor.withValues(alpha: _fgTopOpacity / 100),
                    _fgBottomColor.withValues(alpha: _fgBottomOpacity / 100),
                  ],
                  stops: [_fgTopStop, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Dev-facing layout: the splash renders inside a fixed phone-sized,
    // rounded frame on the left — exactly `_phoneWidth`x`_phoneHeight`,
    // scaled to fit via FittedBox but never stretched off its 9:19.5
    // aspect ratio — so what's shown is a faithful preview of the phone
    // screen to hand to a developer, not the debug canvas. All live-tuning
    // controls (sliders, state, triggers) live in the panel on the right,
    // entirely outside the phone frame, so they never show up "in" the
    // splash itself.
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
                            child: splashContent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${_phoneWidth.toStringAsFixed(0)} × '
                    '${_phoneHeight.toStringAsFixed(0)} — iPhone 13/14/15 '
                    'logical size (most common phone viewport)',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 360,
            color: const Color(0xFF14101C),
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live tuning controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _StateBadge(state: _state),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const Text(
                          'Colors',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ColorPickerRow(
                          label: 'BG Top',
                          description:
                              'Колір верхньої частини базового градієнта '
                              'сцени',
                          color: _bgTopColor,
                          controller: _bgTopHexController,
                          onSubmitted: _applyBgTopHex,
                        ),
                        const SizedBox(height: 8),
                        _ColorPickerRow(
                          label: 'BG Bottom',
                          description:
                              'Колір нижньої частини базового градієнта '
                              'сцени',
                          color: _bgBottomColor,
                          controller: _bgBottomHexController,
                          onSubmitted: _applyBgBottomHex,
                        ),
                        const SizedBox(height: 8),
                        _ColorPickerRow(
                          label: 'FG Top',
                          description:
                              'Колір верхньої частини тонування зверху '
                              'сцени',
                          color: _fgTopColor,
                          controller: _fgTopHexController,
                          onSubmitted: _applyFgTopHex,
                          opacity: _fgTopOpacity,
                          onOpacityChanged: (v) =>
                              setState(() => _fgTopOpacity = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'FG Top Pos',
                          value: _fgTopStop * 100,
                          min: 0,
                          max: 95,
                          unit: '%',
                          description:
                              'Позиція верхньої точки градієнта форграунду '
                              '(0% — верх екрана; більше — зсуває ближче '
                              'до низу). Нижня точка завжди в самому низу',
                          onChanged: (v) =>
                              setState(() => _fgTopStop = v / 100),
                        ),
                        const SizedBox(height: 8),
                        _ColorPickerRow(
                          label: 'FG Bottom',
                          description:
                              'Колір нижньої частини тонування зверху '
                              'сцени',
                          color: _fgBottomColor,
                          controller: _fgBottomHexController,
                          onSubmitted: _applyFgBottomHex,
                          opacity: _fgBottomOpacity,
                          onOpacityChanged: (v) =>
                              setState(() => _fgBottomOpacity = v),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Assets',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _AssetPickerRow(
                          label: 'Logo',
                          preview: _customLogoBytes != null
                              ? Image.memory(
                                  _customLogoBytes!,
                                  fit: BoxFit.contain,
                                )
                              : Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.contain,
                                ),
                          onPick: _pickLogo,
                          onReset: _customLogoBytes != null
                              ? _resetLogo
                              : null,
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _cloudAssetPaths.length; i++) ...[
                          _AssetPickerRow(
                            label: 'Cloud ${i + 1}',
                            preview: _customCloudBytes[i] != null
                                ? Image.memory(
                                    _customCloudBytes[i]!,
                                    fit: BoxFit.contain,
                                  )
                                : Image.asset(
                                    _cloudAssetPaths[i],
                                    fit: BoxFit.contain,
                                  ),
                            onPick: () => _pickCloud(i),
                            onReset: _customCloudBytes[i] != null
                                ? () => _resetCloud(i)
                                : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Speed',
                          value: _speedMultiplier,
                          min: 0.01,
                          max: 0.1,
                          description:
                              'Швидкість руху хмар по спіралі в стані LOOPING',
                          onChanged: (v) =>
                              setState(() => _speedMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Scale Out',
                          value: _sizeMultiplier,
                          min: 0.3,
                          max: 6.0,
                          description:
                              'Розмір хмаринок на зовнішньому краю спіралі '
                              '(найдальші від лого)',
                          onChanged: (v) =>
                              setState(() => _sizeMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Scale In',
                          value: _startSizeMultiplier,
                          min: 0.1,
                          max: 4.0,
                          description:
                              'Розмір хмаринок біля кінчика логотипу '
                              '(точка появи)',
                          onChanged: (v) =>
                              setState(() => _startSizeMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Scale Mid',
                          value: _sizeMidpoint,
                          min: 0.05,
                          max: 0.95,
                          description:
                              'Точка (0–1) шляху, де хмаринка має рівно '
                              'середній розмір між Scale In і Scale Out',
                          onChanged: (v) =>
                              setState(() => _sizeMidpoint = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Count',
                          value: _particleCount,
                          min: 10,
                          max: 200,
                          unit: '',
                          description: 'Базова кількість хмаринок у спіралі',
                          onChanged: (v) =>
                              setState(() => _particleCount = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Spacing',
                          value: _particleSpacing,
                          min: 0.3,
                          max: 3.0,
                          description:
                              'Відстань між сусідніми хмаринками вздовж '
                              'спіралі (більше — рідше)',
                          onChanged: (v) =>
                              setState(() => _particleSpacing = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Squash',
                          value: _squashFactor,
                          min: 0.3,
                          max: 1.0,
                          description:
                              'Стиснення еліпса спіралі (1.0 — коло, менше '
                              '— сплощений овал)',
                          onChanged: (v) =>
                              setState(() => _squashFactor = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Tilt',
                          value: _tiltAngleDeg,
                          min: -60,
                          max: 60,
                          unit: '°',
                          description: 'Кут нахилу осі стиснення (Squash)',
                          onChanged: (v) =>
                              setState(() => _tiltAngleDeg = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Turns',
                          value: _turnsMultiplier,
                          min: 0.5,
                          max: 6.0,
                          description: 'Кількість витків спіралі',
                          onChanged: (v) =>
                              setState(() => _turnsMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Reach',
                          value: _reachMultiplier,
                          min: 0.5,
                          max: 6.0,
                          description:
                              'Наскільки далеко спіраль тягнеться від '
                              'центру до краю екрана',
                          onChanged: (v) =>
                              setState(() => _reachMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Inner R',
                          value: _innerRadiusMultiplier,
                          min: 0.5,
                          max: 10.0,
                          description:
                              'Радіус першого витка (де хмаринки з\'являються)'
                              ' — більше, щоб огортав лого, а не налазив на '
                              'нього',
                          onChanged: (v) =>
                              setState(() => _innerRadiusMultiplier = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Depth Spd',
                          value: _depthSpeedPower,
                          min: 0.3,
                          max: 4.0,
                          description:
                              'Хмари ближче до центру рухаються повільніше, '
                              'далі — швидше (1.0 — без ефекту)',
                          onChanged: (v) =>
                              setState(() => _depthSpeedPower = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Zoom',
                          value: _globalZoom,
                          min: 0.3,
                          max: 5.0,
                          description:
                              'Загальний масштаб усієї композиції '
                              '(спіраль + лого разом)',
                          onChanged: (v) => setState(() => _globalZoom = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Fill',
                          value: _fillAmount,
                          min: 0,
                          max: 100,
                          unit: '%',
                          description:
                              'Який % спіралі заповнений хмарами від лого '
                              'назовні (Intro: 0→100%)',
                          onChanged: (v) => setState(() => _fillAmount = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Rotate',
                          value: _rotationDeg,
                          min: -180,
                          max: 180,
                          unit: '°',
                          description:
                              'Загальний поворот композиції '
                              '(спіраль + лого разом)',
                          onChanged: (v) => setState(() => _rotationDeg = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Spawn X',
                          value: _spawnOffsetX,
                          min: -200,
                          max: 200,
                          unit: 'px',
                          description:
                              'Зсув точки спавну хмар по горизонталі '
                              '(логотип не рухається)',
                          onChanged: (v) =>
                              setState(() => _spawnOffsetX = v),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Spawn Y',
                          value: _spawnOffsetY,
                          min: -200,
                          max: 200,
                          unit: 'px',
                          description:
                              'Зсув точки спавну хмар по вертикалі '
                              '(логотип не рухається)',
                          onChanged: (v) =>
                              setState(() => _spawnOffsetY = v),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Share params',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Copy this and send it to someone else, or paste '
                          'theirs in and hit Apply to match their sliders.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _configController,
                          maxLines: 6,
                          minLines: 4,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(10),
                          ),
                        ),
                        if (_configApplyError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _configApplyError!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _copyConfig,
                              child: const Text('Copy current'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _applyConfig,
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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

/// One row in the "Assets" panel: a thumbnail of the current image (bundled
/// default, or an uploaded replacement), a label, an upload button, and —
/// only once something's been uploaded — a reset button to go back to the
/// bundled default.
/// One row in the "Colors" section: a live swatch of the current color, a
/// hex text box to type/paste a new one into, and a short Ukrainian
/// description of what this color drives. Submitting the hex box (Enter,
/// or tapping away) calls [onSubmitted], which is expected to parse it and
/// update the color — an invalid hex is simply ignored, leaving the last
/// good color in place rather than crashing.
class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.label,
    required this.description,
    required this.color,
    required this.controller,
    required this.onSubmitted,
    this.opacity,
    this.onOpacityChanged,
  });

  final String label;
  final String description;
  final Color color;
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  /// When non-null (alongside [onOpacityChanged]), an extra 0–100% slider
  /// is shown under the hex row — used for the foreground tint, whose
  /// opacity at each end is itself live, unlike the always-opaque
  /// background.
  final double? opacity;
  final ValueChanged<double>? onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSubmitted(),
                  onTapOutside: (_) => onSubmitted(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '#',
                    prefixStyle: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              description,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          if (opacity != null && onOpacityChanged != null)
            Row(
              children: [
                const SizedBox(
                  width: 76 + 28 + 8,
                  child: Text(
                    'Opacity',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
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
                      value: opacity!,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${opacity!.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AssetPickerRow extends StatelessWidget {
  const _AssetPickerRow({
    required this.label,
    required this.preview,
    required this.onPick,
    this.onReset,
  });

  final String label;
  final Widget preview;
  final VoidCallback onPick;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 36,
              height: 36,
              color: Colors.white10,
              child: preview,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.upload, size: 18, color: Colors.white70),
            tooltip: 'Upload image',
            onPressed: onPick,
          ),
          if (onReset != null)
            IconButton(
              icon: const Icon(
                Icons.replay,
                size: 18,
                color: Colors.white38,
              ),
              tooltip: 'Reset to default',
              onPressed: onReset,
            ),
        ],
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
    this.description,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;

  /// Short Ukrainian one-liner explaining what this slider changes, shown
  /// under the row — a plain-language hint for anyone tuning the splash
  /// who isn't reading the Dart source's own doc comments.
  final String? description;

  bool get _isWholeNumberUnit =>
      unit == '°' || unit == '%' || unit == 'px' || unit.isEmpty;

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
                width: 64,
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
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
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
