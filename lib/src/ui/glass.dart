import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Backdrop treatment shared by every glass panel: boost the saturation of
/// what's behind, dim it slightly for legibility, then blur.
final ui.ImageFilter _glassFilter = ui.ImageFilter.compose(
  outer: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
  inner: ColorFilter.matrix(_saturateAndDim(1.7, 0.62)),
);

List<double> _saturateAndDim(double s, double b) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return [
    (sr + s) * b, sg * b, sb * b, 0, 0, //
    sr * b, (sg + s) * b, sb * b, 0, 0, //
    sr * b, sg * b, (sb + s) * b, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// A frosted-glass panel: blurred, colour-boosted backdrop, a faint sheen,
/// a light-catching edge and a soft drop shadow. An optional [glow] tints the
/// edge and shadow with an accent colour.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.glow,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          const BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14)),
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: 0.22), blurRadius: 26, spreadRadius: -6),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter.grouped(
          filter: _glassFilter,
          child: CustomPaint(
            foregroundPainter: _GlassEdgePainter(radius, glow),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x26FFFFFF), Color(0x0AFFFFFF), Color(0x14FFFFFF)],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassEdgePainter extends CustomPainter {
  _GlassEdgePainter(this.radius, this.glow);

  final double radius;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius - 0.5));
    final tint = glow ?? Colors.white;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.06),
            tint.withValues(alpha: glow == null ? 0.14 : 0.45),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) => old.radius != radius || old.glow != glow;
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
  });

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
          color: selected ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0.86,
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
