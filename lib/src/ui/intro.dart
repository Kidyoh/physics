import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common/rng.dart';
import '../sand/sand_view.dart';
import 'backdrop.dart';

/// Opening animation: the app's name rains down out of sand grains, holds
/// for a beat, then crumbles into the live sand simulation underneath.
///
/// The grains sit on exactly the same grid as [SandView], so at the hand-off
/// ([onRelease]) the simulation picks them up in place and lets them fall.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key, required this.onRelease, required this.onDone});

  /// Receives the grain positions as fractions of the canvas size.
  final void Function(List<Offset> grains) onRelease;

  /// Called once the overlay has fully faded out.
  final VoidCallback onDone;

  static const String title = 'Tactile';
  static const String subtitle = 'PHYSICS YOU CAN TOUCH';

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

/// Moment (as a fraction of the timeline) when grains hand over to the sim.
const double _release = 0.78;

class _IntroOverlayState extends State<IntroOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  _Grains? _grains;
  Size _size = Size.zero;
  bool _building = false;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tick() {
    if (!_released && _c.value >= _release) {
      _released = true;
      final g = _grains;
      if (g != null) widget.onRelease(g.fractions());
    }
  }

  void _skip() {
    if (_c.value < _release - 0.05) {
      _c.animateTo(_release, duration: const Duration(milliseconds: 280)).whenComplete(() {
        if (mounted) _c.forward();
      });
    }
  }

  Future<void> _build(Size size) async {
    _building = true;
    final grains = await _Grains.build(size, DefaultTextStyle.of(context).style.fontFamily);
    if (!mounted) return;
    setState(() => _grains = grains);
    _c.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!_building && !size.isEmpty) {
          _size = size;
          _build(size);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // Everything fades out after the hand-off.
              final fade =
                  1 - Curves.easeIn.transform(((t - _release) / (1 - _release)).clamp(0, 1));
              final sub = Curves.easeOutCubic.transform(((t - 0.42) / 0.22).clamp(0, 1));
              final g = _grains;
              return Opacity(
                opacity: fade,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _IntroPainter(g, t, _released)),
                    if (g != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: g.titleBottom * _size.height + 18 + 10 * (1 - sub),
                        child: Opacity(
                          opacity: sub,
                          child: const Text(
                            IntroOverlay.subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 12.5,
                              letterSpacing: 4.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Grain targets for the title, on the [SandView] grid.
class _Grains {
  _Grains(
    this.cols,
    this.rows,
    this.x,
    this.y,
    this.startX,
    this.startY,
    this.delay,
    this.shade,
    this.titleBottom,
  );

  final int cols, rows;
  final Int16List x, y;
  final Float32List startX, startY, delay;
  final Uint8List shade;

  /// Bottom edge of the title as a fraction of the height.
  final double titleBottom;

  int get length => x.length;

  List<Offset> fractions() => [
    for (var i = 0; i < length; i++) Offset((x[i] + 0.5) / cols, (y[i] + 0.5) / rows),
  ];

  static Future<_Grains> build(Size size, String? fontFamily) async {
    final cols = SandView.columns;
    final rows = SandView.rowsFor(size);

    // Rasterise the title at grid resolution and keep the covered cells.
    final probe = TextPainter(
      text: TextSpan(
        text: IntroOverlay.title,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 100,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final fontSize = 100 * cols * 0.8 / probe.width;
    probe.dispose();
    final tp = TextPainter(
      text: TextSpan(
        text: IntroOverlay.title,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -fontSize * 0.02,
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = rows * 0.4 - tp.height / 2;
    final recorder = ui.PictureRecorder();
    tp.paint(Canvas(recorder), Offset((cols - tp.width) / 2, top));
    tp.dispose();
    final image = await recorder.endRecording().toImage(cols, rows);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();

    final xs = <int>[], ys = <int>[];
    var bottom = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        if (bytes.getUint8((j * cols + i) * 4 + 3) > 110) {
          xs.add(i);
          ys.add(j);
          bottom = math.max(bottom, j);
        }
      }
    }

    final rng = Rng(2024);
    final n = xs.length;
    final startX = Float32List(n), startY = Float32List(n), delay = Float32List(n);
    final shade = Uint8List(n);
    for (var k = 0; k < n; k++) {
      startX[k] = xs[k] + (rng.nextDouble() - 0.5) * 18;
      startY[k] = -4 - rng.nextDouble() * rows * 0.5;
      // A left-to-right wave with a little jitter; lower grains land first so
      // the letters build up like a pile.
      delay[k] = xs[k] / cols * 0.32 + (1 - ys[k] / rows) * 0.08 + rng.nextDouble() * 0.12;
      shade[k] = rng.nextInt(4);
    }
    return _Grains(
      cols,
      rows,
      Int16List.fromList(xs),
      Int16List.fromList(ys),
      startX,
      startY,
      delay,
      shade,
      (bottom + 1) / rows,
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.grains, this.t, this.released);

  final _Grains? grains;
  final double t;
  final bool released;

  static const _shades = [
    Color(0xFFD6A85C),
    Color(0xFFE6BC74),
    Color(0xFFF2CC86),
    Color(0xFFFFE0A6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size);
    final g = grains;
    // After the hand-off the live simulation draws the grains.
    if (g == null || released) return;

    final cell = size.width / g.cols;
    final cellH = size.height / g.rows;
    final fall = (t / 0.5).clamp(0.0, 1.0);
    final buckets = List.generate(4, (_) => Float32List(g.length * 2));
    final counts = List.filled(4, 0);
    for (var k = 0; k < g.length; k++) {
      final p = ((fall - g.delay[k]) / 0.48).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final e = Curves.easeOutQuart.transform(p);
      final gx = g.startX[k] + (g.x[k] - g.startX[k]) * e;
      final gy = g.startY[k] + (g.y[k] - g.startY[k]) * Curves.easeOutBack.transform(p);
      final b = g.shade[k];
      final list = buckets[b];
      list[counts[b]++] = (gx + 0.5) * cell;
      list[counts[b]++] = (gy + 0.5) * cellH;
    }

    // Warm bloom behind the letters once they have mostly landed.
    final glow = Curves.easeOut.transform(((t - 0.3) / 0.3).clamp(0, 1));
    for (var b = 0; b < 4; b++) {
      if (counts[b] == 0) continue;
      final pts = Float32List.sublistView(buckets[b], 0, counts[b]);
      if (glow > 0) {
        canvas.drawRawPoints(
          ui.PointMode.points,
          pts,
          Paint()
            ..color = _shades[b].withValues(alpha: 0.22 * glow)
            ..strokeWidth = cell * 2.4
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = _shades[b]
          ..strokeWidth = cell * 1.05
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.t != t || old.grains != grains || old.released != released;
}
