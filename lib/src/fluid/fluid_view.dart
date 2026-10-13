import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common/rng.dart';
import '../common/sim_loop.dart';
import '../common/touch_surface.dart';
import '../controllers.dart';
import 'fluid_sim.dart';

/// Full-screen ink-in-water canvas.
class FluidView extends StatefulWidget {
  const FluidView({super.key, required this.controller});

  final FluidController controller;

  /// Grid columns; rows follow from the screen's aspect ratio.
  static const int columns = 110;

  @override
  State<FluidView> createState() => _FluidViewState();
}

class _FluidViewState extends State<FluidView> with SingleTickerProviderStateMixin {
  late final SimLoop _loop;
  final PixelImage _image = PixelImage();
  final Map<int, int> _fingerSeed = {};
  final Rng _rng = Rng(42);
  FluidSim? _sim;
  Size _size = Size.zero;
  double _time = 0;
  int _seenReset = 0;
  int _nextSeed = 0;

  @override
  void initState() {
    super.initState();
    _loop = SimLoop(this, _onFrame, onFps: (v) => widget.controller.fps.value = v);
    _seenReset = widget.controller.resetCount;
  }

  @override
  void dispose() {
    _loop.dispose();
    _image.dispose();
    super.dispose();
  }

  void _ensureSim(Size size) {
    if (size.isEmpty) return;
    if (_sim != null && size == _size) return;
    _size = size;
    final rows = (FluidView.columns * size.height / size.width).round().clamp(40, 400);
    // A splash of colour straight away: the first second should already be fun.
    _sim = FluidSim(FluidView.columns, rows)..randomSplats(6);
  }

  void _onFrame(int steps) {
    final sim = _sim;
    if (sim == null) return;
    final c = widget.controller;
    if (c.resetCount != _seenReset) {
      _seenReset = c.resetCount;
      sim.clear();
      sim.randomSplats(4);
    }
    sim.vorticity = c.swirl;
    if (!c.paused) {
      for (var i = 0; i < steps; i++) {
        sim.step(SimLoop.stepSeconds);
        _time += SimLoop.stepSeconds;
      }
    }
    sim.render();
    _image.upload(sim.pixels, sim.width, sim.height);
  }

  Offset _toGrid(Offset p) {
    final sim = _sim!;
    return Offset(p.dx / _size.width * sim.width, p.dy / _size.height * sim.height);
  }

  void _splat(int id, Offset from, Offset to, {bool burst = false}) {
    final sim = _sim;
    if (sim == null) return;
    final a = _toGrid(from), b = _toGrid(to);
    var dx = (b.dx - a.dx) * 140, dy = (b.dy - a.dy) * 140;
    if (burst) {
      final angle = _rng.nextDouble() * math.pi * 2;
      dx = math.cos(angle) * 120;
      dy = math.sin(angle) * 120;
    }
    // Cap the impulse so a flick can't blow the solver up.
    final speed = math.sqrt(dx * dx + dy * dy);
    const maxSpeed = 1400.0;
    if (speed > maxSpeed) {
      dx *= maxSpeed / speed;
      dy *= maxSpeed / speed;
    }
    final col = widget.controller.palette.colorAt(_time, _fingerSeed[id] ?? 0);
    const dye = 0.55;
    final radius = math.max(1.5, widget.controller.brush * sim.width);
    // Spread long strokes along the path so they stay smooth.
    final dist = (b - a).distance;
    final n = math.max(1, (dist / (radius * 0.6)).ceil()).clamp(1, 12);
    for (var i = 1; i <= n; i++) {
      final f = i / n;
      sim.splat(
        a.dx + (b.dx - a.dx) * f,
        a.dy + (b.dy - a.dy) * f,
        dx / n,
        dy / n,
        col[0] * dye,
        col[1] * dye,
        col[2] * dye,
        radius: radius,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureSim(constraints.biggest);
        return TouchSurface(
          onDown: (id, p) {
            widget.controller.markTouched();
            _fingerSeed[id] = _nextSeed++;
            _splat(id, p, p, burst: true);
          },
          onMove: (id, from, to) => _splat(id, from, to),
          onUp: (id) => _fingerSeed.remove(id),
          child: CustomPaint(size: constraints.biggest, painter: _FluidPainter(_image)),
        );
      },
    );
  }
}

class _FluidPainter extends CustomPainter {
  _FluidPainter(this.image) : super(repaint: image);

  final PixelImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawRect(dst, Paint()..color = const Color(0xFF06060A));
    final img = image.image;
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    // Smooth upscaling hides the grid.
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
    // Soft bloom.
    canvas.saveLayer(
      dst,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color.fromRGBO(255, 255, 255, 0.35)
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.decal),
    );
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.low);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FluidPainter old) => old.image != image;
}
