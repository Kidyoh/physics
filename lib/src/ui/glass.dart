import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Backdrop treatment for liquid glass: a light blur that keeps what's
/// behind recognisable, with boosted saturation so colours glow through.
final ui.ImageFilter _glassFilter = ui.ImageFilter.compose(
  outer: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.mirror),
  inner: ColorFilter.matrix(_saturate(1.9, 0.92)),
);

List<double> _saturate(double s, double b) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return [
    (sr + s) * b, sg * b, sb * b, 0, 0, //
    sr * b, (sg + s) * b, sb * b, 0, 0, //
    sr * b, sg * b, (sb + s) * b, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// iOS 26-style liquid glass: a clear, lightly blurred surface with a bright
/// rim that catches the light from the top left, a soft top sheen and a
/// floating shadow. [radius] defaults to a full capsule; [tint] washes the
/// glass with a colour (used for selected and "on" states).
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.tint,
  });

  final Widget child;

  /// Corner radius; `null` makes a capsule (or a circle for square content).
  final double? radius;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final ShapeBorder shape = radius == null
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius!));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          const BoxShadow(color: Color(0x47000000), blurRadius: 24, offset: Offset(0, 10)),
          if (tint != null)
            BoxShadow(color: tint!.withValues(alpha: 0.3), blurRadius: 22, spreadRadius: -4),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter.grouped(
          filter: _glassFilter,
          child: CustomPaint(
            painter: _GlassBodyPainter(shape, tint),
            foregroundPainter: _GlassRimPainter(shape),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Body: a faint dark base for legibility, optional tint, and a sheen that
/// fades out towards the middle.
class _GlassBodyPainter extends CustomPainter {
  _GlassBodyPainter(this.shape, this.tint);

  final ShapeBorder shape;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.drawPath(path, Paint()..color = const Color(0x2E0A0A14));
    if (tint != null) canvas.drawPath(path, Paint()..color = tint!.withValues(alpha: 0.32));
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33FFFFFF), Color(0x08FFFFFF), Color(0x00FFFFFF), Color(0x0FFFFFFF)],
          stops: [0, 0.42, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) => old.tint != tint || old.shape != shape;
}

/// Rim: bright on the top-left edge, nearly gone along the sides, and a
/// softer bounce light on the bottom-right.
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter(this.shape);

  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(0.6));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xC8FFFFFF), Color(0x24FFFFFF), Color(0x0AFFFFFF), Color(0x5CFFFFFF)],
          stops: [0, 0.3, 0.62, 1],
        ).createShader(rect),
    );
    // A thin inner line just inside the rim gives the glass its thickness.
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x12FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => old.shape != shape;
}

/// The lighter "lens" that slides behind the selected item of a glass bar.
class GlassLens extends StatelessWidget {
  const GlassLens({super.key, this.tint});

  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.28))),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              (tint ?? Colors.white).withValues(alpha: 0.32),
              Colors.white.withValues(alpha: 0.2),
            ),
            Color.alphaBlend(
              (tint ?? Colors.white).withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.06),
            ),
          ],
        ),
        shadows: [
          if (tint != null)
            BoxShadow(color: tint!.withValues(alpha: 0.45), blurRadius: 16, spreadRadius: -4),
        ],
      ),
    );
  }
}

/// Shrinks slightly while pressed, like a physical button.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child, this.scale = 0.92});

  final VoidCallback? onTap;
  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A glossy sphere used as a tool swatch.
class Orb extends StatelessWidget {
  const Orb({
    super.key,
    required this.color,
    required this.selected,
    this.size = 34,
    this.child,
    this.gradient,
    this.ring = true,
  });

  /// Whether selection is shown with a white ring and glow (otherwise only
  /// the size changes, for use on top of a [GlassLens]).
  final bool ring;

  final Color color;
  final bool selected;
  final double size;
  final Widget? child;

  /// Replaces the shaded fill (e.g. a palette sweep).
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.28).clamp(0, 1)).toColor();
    final dark = hsl.withLightness((hsl.lightness - 0.22).clamp(0, 1)).toColor();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected && ring ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: [
          if (selected && ring)
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: AnimatedScale(
        scale: selected ? (ring ? 1 : 1.08) : 0.86,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                gradient ??
                RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 0.95,
                  colors: [light, color, dark],
                  stops: const [0, 0.5, 1],
                ),
            boxShadow: const [
              BoxShadow(color: Color(0x73000000), blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Specular highlight.
              Positioned(
                left: size * 0.2,
                top: size * 0.12,
                child: Container(
                  width: size * 0.34,
                  height: size * 0.2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.7),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              ?child,
            ],
          ),
        ),
      ),
    );
  }
}
