import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'checkerboard_painter.dart';
import 'droste_vortex_config.dart';
import 'droste_vortex_painter.dart';

class SpiralDebugScreen extends StatefulWidget {
  const SpiralDebugScreen({super.key});

  @override
  State<SpiralDebugScreen> createState() => _SpiralDebugScreenState();
}

class _SpiralDebugScreenState extends State<SpiralDebugScreen>
    with SingleTickerProviderStateMixin {
  DrosteVortexConfig _config = DrosteVortexConfig.initial;
  ui.Image? _image;
  bool _checkerboard = false;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _spinDeg = 0;
  bool _spinning = true;
  double _spinSpeedDegPerSec = 15;

  // "Dive": one full lap of [_diveFrac] 0→1 grows the whole picture by
  // exactly 1/nestScale while counter-rotating by exactly one rotation
  // step — since level n of the Droste stack is just the source image
  // scaled by nestScale^n around the SAME center, growing by that exact
  // ratio makes level n's content land pixel-for-pixel where level n-1's
  // content started. So the loop back to frac=0 has no visible pop.
  double _diveFrac = 0;
  bool _diving = true;
  double _diveSpeedPerSec = 0.25;

  // Press-and-hold boost: eases a 0→1 amount in/out (instead of snapping)
  // so the speed-up/slow-down itself feels like acceleration, then scales
  // the dive speed by up to [_boostMultiplier].
  static const double _boostMultiplier = 15.0;
  static const double _boostRampPerSec = 5.0;
  bool _boostHeld = false;
  double _boostAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (!_spinning && !_diving && !_boostHeld && _boostAmount == 0) return;
    setState(() {
      final rampDelta = dt * _boostRampPerSec;
      _boostAmount = _boostHeld
          ? math.min(1, _boostAmount + rampDelta)
          : math.max(0, _boostAmount - rampDelta);
      if (_spinning) {
        _spinDeg = (_spinDeg + dt * _spinSpeedDegPerSec) % 360;
      }
      if (_diving) {
        final boostFactor = 1 + _boostAmount * (_boostMultiplier - 1);
        _diveFrac = (_diveFrac + dt * _diveSpeedPerSec * boostFactor) % 1.0;
      }
    });
  }

  void _setBoosting(bool held) => setState(() => _boostHeld = held);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load('assets/vortex_spiral.png');
    final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _image = frame.image);
  }

  void _update(DrosteVortexConfig Function(DrosteVortexConfig) f) {
    setState(() => _config = f(_config));
  }

  void _reset() {
    setState(() {
      _config = DrosteVortexConfig.initial;
      _spinDeg = 0;
      _diveFrac = 0;
      _boostHeld = false;
      _boostAmount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    // Spin and dive are layered on top of the manual sliders (not replacing
    // them), so a hand-picked base config can still be animated.
    final n = _config.nestScale.clamp(0.01, 0.9);
    final diveZoom = math.pow(1 / n, _diveFrac).toDouble();
    final diveRotationDeg = -_config.rotationStepDeg * _diveFrac;

    final animatedConfig = _config.copyWith(
      baseScale: _config.baseScale * diveZoom,
      globalRotationDeg: _config.globalRotationDeg + _spinDeg + diveRotationDeg,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF16161C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E26),
        title: const Text('Droste vortex — playground'),
        actions: [
          IconButton(
            tooltip: 'Toggle checkerboard / vortex-glow background',
            icon: Icon(_checkerboard ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _checkerboard = !_checkerboard),
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          final canvasArea = Stack(
            fit: StackFit.expand,
            children: [
              _CanvasArea(
                image: image,
                config: animatedConfig,
                checkerboard: _checkerboard,
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: _BoostButton(
                  enabled: _diving,
                  boostAmount: _boostAmount,
                  onHeldChanged: _setBoosting,
                ),
              ),
            ],
          );
          final controls = _ControlsPanel(
            config: _config,
            onChanged: _update,
            spinning: _spinning,
            onSpinningChanged: (v) => setState(() => _spinning = v),
            spinSpeed: _spinSpeedDegPerSec,
            onSpinSpeedChanged: (v) => setState(() => _spinSpeedDegPerSec = v),
            diving: _diving,
            onDivingChanged: (v) => setState(() => _diving = v),
            diveSpeed: _diveSpeedPerSec,
            onDiveSpeedChanged: (v) => setState(() => _diveSpeedPerSec = v),
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: canvasArea),
                SizedBox(
                  width: 360,
                  child: Container(
                    color: const Color(0xFF1E1E26),
                    child: controls,
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 3, child: canvasArea),
              Expanded(
                flex: 2,
                child: Container(
                  color: const Color(0xFF1E1E26),
                  child: controls,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Press-and-hold control that ramps the dive speed up while held. Uses
/// [Listener] rather than a tap gesture so an arbitrarily long hold and a
/// release outside the widget's bounds are both handled reliably.
class _BoostButton extends StatelessWidget {
  const _BoostButton({
    required this.enabled,
    required this.boostAmount,
    required this.onHeldChanged,
  });

  final bool enabled;
  final double boostAmount;
  final ValueChanged<bool> onHeldChanged;

  @override
  Widget build(BuildContext context) {
    final glow = Color.lerp(
      const Color(0xFF3A2E66),
      const Color(0xFFB89CFF),
      boostAmount,
    )!;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Listener(
        onPointerDown: enabled ? (_) => onHeldChanged(true) : null,
        onPointerUp: enabled ? (_) => onHeldChanged(false) : null,
        onPointerCancel: enabled ? (_) => onHeldChanged(false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: glow, width: 2),
            boxShadow: boostAmount > 0
                ? [BoxShadow(color: glow.withValues(alpha: 0.6), blurRadius: 16 * boostAmount)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rocket_launch, color: glow),
              const SizedBox(width: 8),
              Text(
                'HOLD TO BOOST',
                style: TextStyle(
                  color: glow,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasArea extends StatelessWidget {
  const _CanvasArea({
    required this.image,
    required this.config,
    required this.checkerboard,
  });

  final ui.Image? image;
  final DrosteVortexConfig config;
  final bool checkerboard;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (checkerboard)
            const CustomPaint(painter: CheckerboardPainter(), size: Size.infinite)
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFEDE6FF),
                    Color(0xFF8C6FD9),
                    Color(0xFF2E2054),
                    Color(0xFF07050D),
                  ],
                  stops: [0.0, 0.22, 0.55, 1.0],
                ),
              ),
            ),
          if (image != null)
            CustomPaint(
              painter: DrosteVortexPainter(image: image!, config: config),
              size: Size.infinite,
            )
          else
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.config,
    required this.onChanged,
    required this.spinning,
    required this.onSpinningChanged,
    required this.spinSpeed,
    required this.onSpinSpeedChanged,
    required this.diving,
    required this.onDivingChanged,
    required this.diveSpeed,
    required this.onDiveSpeedChanged,
  });

  final DrosteVortexConfig config;
  final void Function(DrosteVortexConfig Function(DrosteVortexConfig)) onChanged;
  final bool spinning;
  final ValueChanged<bool> onSpinningChanged;
  final double spinSpeed;
  final ValueChanged<double> onSpinSpeedChanged;
  final bool diving;
  final ValueChanged<bool> onDivingChanged;
  final double diveSpeed;
  final ValueChanged<double> onDiveSpeedChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dive into vortex', style: TextStyle(color: Colors.white70)),
          subtitle: const Text(
              'grows toward 1/nestScale then loops — seamless because it\'s the same image',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: diving,
          onChanged: onDivingChanged,
        ),
        _SliderRow(
          label: 'Dive speed (loops/s)',
          value: diveSpeed,
          min: 0,
          max: 3,
          divisions: 300,
          valueLabel: '${diveSpeed.toStringAsFixed(2)}/s',
          onChanged: onDiveSpeedChanged,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('hold the ⏵ button over the canvas for a temporary 15× boost',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Animate spin', style: TextStyle(color: Colors.white70)),
          subtitle: const Text('continuously drives global rotation',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: spinning,
          onChanged: onSpinningChanged,
        ),
        _SliderRow(
          label: 'Spin speed (°/s)',
          value: spinSpeed,
          min: 0,
          max: 90,
          divisions: 180,
          valueLabel: '${spinSpeed.toStringAsFixed(1)}°/s',
          onChanged: onSpinSpeedChanged,
        ),
        const Divider(color: Colors.white24, height: 24),
        _SliderRow(
          label: 'Nest scale (per level)',
          value: config.nestScale,
          min: 0.05,
          max: 0.5,
          divisions: 450,
          valueLabel: '${(config.nestScale * 100).toStringAsFixed(1)}%',
          onChanged: (v) => onChanged((c) => c.copyWith(nestScale: v)),
        ),
        _SliderRow(
          label: 'Rotation per level (°)',
          value: config.rotationStepDeg,
          min: -30,
          max: 30,
          divisions: 300,
          valueLabel: '${config.rotationStepDeg.toStringAsFixed(1)}°',
          onChanged: (v) => onChanged((c) => c.copyWith(rotationStepDeg: v)),
        ),
        _SliderRow(
          label: 'Base scale',
          value: config.baseScale,
          min: 0.3,
          max: 3.0,
          divisions: 270,
          valueLabel: config.baseScale.toStringAsFixed(3),
          onChanged: (v) => onChanged((c) => c.copyWith(baseScale: v)),
        ),
        _SliderRow(
          label: 'Global rotation (°)',
          value: config.globalRotationDeg,
          min: 0,
          max: 360,
          divisions: 360,
          valueLabel: '${config.globalRotationDeg.toStringAsFixed(0)}°',
          onChanged: (v) => onChanged((c) => c.copyWith(globalRotationDeg: v)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
                onPressed: () => onChanged((_) => DrosteVortexConfig.initial),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Current config (copy/paste):',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        SelectableText(
          config.toDartLiteral(),
          style: const TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(valueLabel,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
