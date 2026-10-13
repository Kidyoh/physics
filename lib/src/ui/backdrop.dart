import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Deep indigo-to-black backdrop with a soft glow near the top, shared by
/// the canvases and the intro so they blend into each other.
void paintBackdrop(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        const [Color(0xFF171430), Color(0xFF0B0A17), Color(0xFF050508)],
        const [0, 0.55, 1],
      ),
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.08),
        size.longestSide * 0.6,
        const [Color(0x553A2C7A), Color(0x00000000)],
      ),
  );
}
