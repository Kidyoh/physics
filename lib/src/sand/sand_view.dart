import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common/sim_loop.dart';
import '../common/touch_surface.dart';
import '../controllers.dart';
import 'sand_sim.dart';

/// Full-screen falling-sand canvas.
class SandView extends StatefulWidget {
  const SandView({super.key, required this.controller});

  final SandController controller;

  /// Grid columns; rows follow from the screen's aspect ratio.
  static const int columns = 150;

  @override
  State<SandView> createState() => _SandViewState();
}

class _SandViewState extends State<SandView> with SingleTickerProviderStateMixin {
  late final SimLoop _loop;
  final PixelImage _image = PixelImage();
  final PixelImage _glow = PixelImage();
  final Map<int, Offset> _strokes = {};
  SandSim? _sim;
  Size _size = Size.zero;
  int _seenReset = 0;

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
    _glow.dispose();
    super.dispose();
  }

  void _ensureSim(Size size) {
    if (size.isEmpty) return;
    if (_sim != null && size == _size) return;
    _size = size;
    final rows = (SandView.columns * size.height / size.width).round().clamp(40, 600);
    _sim = SandSim(SandView.columns, rows);
  }

  void _onFrame(int steps) {
    final sim = _sim;
    if (sim == null) return;
    final c = widget.controller;
    if (c.resetCount != _seenReset) {
      _seenReset = c.resetCount;
      sim.clear();
    }

    // Keep pouring while a finger is held still.
    for (final p in _strokes.values) {
      _paint(p, p);
    }

    if (!c.paused) {
      for (var i = 0; i < steps; i++) {
        sim.step();
      }
    }
    sim.render();
    _image.upload(sim.pixels, sim.width, sim.height);
    if (sim.glowCells > 0) {
      _glow.upload(sim.glow, sim.width, sim.height);
    } else {
      _glow.clearImage();
    }
  }

  Offset _toGrid(Offset p) {
    final sim = _sim!;
    return Offset(p.dx / _size.width * sim.width, p.dy / _size.height * sim.height);
  }

  void _paint(Offset from, Offset to) {
    final sim = _sim;
    if (sim == null) return;
    final a = _toGrid(from), b = _toGrid(to);
    sim.paintLine(a.dx, a.dy, b.dx, b.dy, widget.controller.brush, widget.controller.material);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureSim(constraints.biggest);
        return TouchSurface(
          onDown: (id, p) {
            widget.controller.markTouched();
            _strokes[id] = p;
            _paint(p, p);
          },
          onMove: (id, from, to) {
            _strokes[id] = to;
            _paint(from, to);
          },
          onUp: (id) => _strokes.remove(id),
          child: CustomPaint(size: constraints.biggest, painter: _SandPainter(_image, _glow)),
        );
      },
    );
  }
}

class _SandPainter extends CustomPainter {
  _SandPainter(this.image, this.glow) : super(repaint: Listenable.merge([image, glow]));

  final PixelImage image;
  final PixelImage glow;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawRect(dst, Paint()..color = const Color(0xFF0A0A10));
    final img = image.image;
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    // Crisp, chunky grains.
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.none);

    final g = glow.image;
    if (g == null) return;
    // Bloom: the fire layer drawn twice, blurred, with additive blending.
    for (final (sigma, alpha) in [(14.0, 0.9), (4.0, 0.55)]) {
      canvas.saveLayer(
        dst,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(255, 255, 255, alpha)
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
      );
      canvas.drawImageRect(g, src, dst, Paint()..filterQuality = FilterQuality.low);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SandPainter old) => old.image != image || old.glow != glow;
}
