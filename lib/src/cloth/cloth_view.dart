import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/sim_loop.dart';
import '../common/touch_surface.dart';
import '../controllers.dart';
import '../ui/backdrop.dart';
import 'cloth_sim.dart';

/// A hanging sheet of cloth you can grab, fling, and tear.
class ClothView extends StatefulWidget {
  const ClothView({super.key, required this.controller, this.topInset = 0, this.floorInset = 0});

  final ClothController controller;

  /// Space at the top kept clear for the toolbar; the cloth hangs below it.
  final double topInset;

  /// Height at the bottom that acts as the ground (the tool dock).
  final double floorInset;

  @override
  State<ClothView> createState() => _ClothViewState();
}

class _ClothViewState extends State<ClothView> with SingleTickerProviderStateMixin {
  late final SimLoop _loop;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  ClothSim? _sim;
  Size _size = Size.zero;
  int _seenReset = 0;
  int _lastHaptic = 0;

  @override
  void initState() {
    super.initState();
    _loop = SimLoop(this, _onFrame, onFps: (v) => widget.controller.fps.value = v);
    _seenReset = widget.controller.resetCount;
  }

  @override
  void dispose() {
    _loop.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _ensureSim(Size size, {bool force = false}) {
    if (size.isEmpty) return;
    if (!force && _sim != null && size == _size) return;
    _size = size;
    const cols = 34;
    final width = math.min(size.width * 0.86, 560.0);
    final spacing = width / (cols - 1);
    final top = math.max(size.height * 0.1, widget.topInset + 28);
    final floor = size.height - widget.floorInset - 4;
    final rows = (((floor - top) * 0.62) / spacing).floor().clamp(10, 70);
    _sim = ClothSim(
      cols: cols,
      rows: rows,
      spacing: spacing,
      originX: (size.width - width) / 2,
      originY: top,
      floor: floor,
    );
  }

  @override
  void didUpdateWidget(ClothView old) {
    super.didUpdateWidget(old);
    if (old.topInset != widget.topInset || old.floorInset != widget.floorInset) {
      _ensureSim(_size, force: true);
    }
  }

  void _onFrame(int steps) {
    final sim = _sim;
    if (sim == null) return;
    final c = widget.controller;
    if (c.resetCount != _seenReset) {
      _seenReset = c.resetCount;
      _ensureSim(_size, force: true);
    }
    final s = _sim!;
    s.wind = c.wind;
    if (!c.paused) {
      for (var i = 0; i < steps; i++) {
        s.step(SimLoop.stepSeconds);
      }
    }
    _frame.value++;
  }

  void _down(int id, Offset p) {
    widget.controller.markTouched();
    final sim = _sim;
    if (sim == null) return;
    if (widget.controller.tool == ClothTool.grab) {
      sim.grab(id, p.dx, p.dy, radius: math.max(36, sim.spacing * 2));
    } else {
      _cut(p, p);
    }
  }

  void _move(int id, Offset from, Offset to) {
    final sim = _sim;
    if (sim == null) return;
    if (sim.isGrabbing(id)) {
      sim.drag(id, to.dx, to.dy);
    } else if (widget.controller.tool == ClothTool.tear) {
      _cut(from, to);
    }
  }

  void _cut(Offset from, Offset to) {
    final sim = _sim!;
    final n = sim.cut(from.dx, from.dy, to.dx, to.dy, radius: math.max(8, sim.spacing * 0.6));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (n > 0 && now - _lastHaptic > 60) {
      _lastHaptic = now;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureSim(constraints.biggest);
        return TouchSurface(
          onDown: _down,
          onMove: _move,
          onUp: (id) => _sim?.release(id),
          child: CustomPaint(size: constraints.biggest, painter: _ClothPainter(() => _sim, _frame)),
        );
      },
    );
  }
}

class _ClothPainter extends CustomPainter {
  _ClothPainter(this.sim, Listenable frame) : super(repaint: frame);

  final ClothSim? Function() sim;

  @override
  void paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size);
    final s = sim();
    if (s == null) return;
    _drawSheet(canvas, s);
    _drawThreads(canvas, s);
    _drawPins(canvas, s);
  }

  void _drawSheet(Canvas canvas, ClothSim s) {
    final cols = s.cols, rows = s.rows;
    final quads = (cols - 1) * (rows - 1);
    final pos = Float32List(quads * 12);
    final colors = Int32List(quads * 6);
    final restArea = s.spacing * s.spacing;
    var v = 0;
    for (var j = 0; j < rows - 1; j++) {
      for (var i = 0; i < cols - 1; i++) {
        final top = s.hLink(i, j), bottom = s.hLink(i, j + 1);
        final left = s.vLink(i, j), right = s.vLink(i + 1, j);
        if (s.alive[top] == 0 ||
            s.alive[bottom] == 0 ||
            s.alive[left] == 0 ||
            s.alive[right] == 0) {
          continue;
        }
        final a = j * cols + i, b = a + 1, c = a + cols, d = c + 1;
        // Shade by how squashed the quad is: folds read as darker creases.
        final area =
            0.5 *
            ((s.x[b] - s.x[c]) * (s.y[d] - s.y[a]) - (s.x[d] - s.x[a]) * (s.y[b] - s.y[c])).abs();
        final light = (area / restArea).clamp(0.25, 1.15);
        final color = _fabric(i / (cols - 1), j / (rows - 1), light);
        for (final k in [a, b, c, b, d, c]) {
          pos[v * 2] = s.x[k];
          pos[v * 2 + 1] = s.y[k];
          colors[v] = color;
          v++;
        }
      }
    }
    if (v == 0) return;
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(pos, 0, v * 2),
      colors: Int32List.sublistView(colors, 0, v),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  /// A silky magenta-to-violet banner with faint stripes.
  int _fabric(double u, double v, double light) {
    final stripe = ((u * 12).floor().isEven) ? 1.0 : 0.88;
    final r = (230 - 120 * v) * light * stripe;
    final g = (60 + 40 * u) * light * stripe;
    final b = (140 + 100 * v) * light * stripe;
    return 0xFF000000 |
        (r.round().clamp(0, 255) << 16) |
        (g.round().clamp(0, 255) << 8) |
        b.round().clamp(0, 255);
  }

  void _drawThreads(Canvas canvas, ClothSim s) {
    final pts = Float32List(s.aliveCount * 4);
    var n = 0;
    for (var c = 0; c < s.alive.length; c++) {
      if (s.alive[c] == 0) continue;
      pts[n++] = s.x[s.linkA[c]];
      pts[n++] = s.y[s.linkA[c]];
      pts[n++] = s.x[s.linkB[c]];
      pts[n++] = s.y[s.linkB[c]];
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      pts,
      Paint()
        ..color = const Color(0x55FFD6F0)
        ..strokeWidth = 1,
    );
  }

  void _drawPins(Canvas canvas, ClothSim s) {
    // Little brass pins with a highlight.
    final halo = Paint()..color = const Color(0x40FFE3B0);
    final head = Paint()..color = const Color(0xFFE8C27A);
    final shine = Paint()..color = const Color(0xFFFFF6E0);
    for (var k = 0; k < s.pointCount; k++) {
      if (s.pinned[k] == 0) continue;
      final c = Offset(s.x[k], s.y[k]);
      canvas.drawCircle(c, 6, halo);
      canvas.drawCircle(c, 3.6, head);
      canvas.drawCircle(c.translate(-1, -1), 1.2, shine);
    }
  }

  @override
  bool shouldRepaint(_ClothPainter old) => false;
}
