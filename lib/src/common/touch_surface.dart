import 'package:flutter/widgets.dart';

typedef PointerDownCallback = void Function(int pointer, Offset position);
typedef PointerMoveCallback = void Function(int pointer, Offset from, Offset to);
typedef PointerUpCallback = void Function(int pointer);

/// Raw multi-touch input: every finger is tracked independently, so you can
/// paint with several at once.
class TouchSurface extends StatefulWidget {
  const TouchSurface({
    super.key,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.child,
  });

  final PointerDownCallback onDown;
  final PointerMoveCallback onMove;
  final PointerUpCallback onUp;
  final Widget child;

  @override
  State<TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<TouchSurface> {
  final Map<int, Offset> _last = {};

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _last[e.pointer] = e.localPosition;
        widget.onDown(e.pointer, e.localPosition);
      },
      onPointerMove: (e) {
        final from = _last[e.pointer] ?? e.localPosition;
        _last[e.pointer] = e.localPosition;
        widget.onMove(e.pointer, from, e.localPosition);
      },
      onPointerUp: (e) {
        _last.remove(e.pointer);
        widget.onUp(e.pointer);
      },
      onPointerCancel: (e) {
        _last.remove(e.pointer);
        widget.onUp(e.pointer);
      },
      child: widget.child,
    );
  }
}
