import 'dart:math' as math;
import 'dart:typed_data';

/// Verlet-integrated cloth: a grid of point masses joined by distance
/// constraints that can be grabbed, flung, torn and cut.
///
/// Units are logical pixels and seconds.
class ClothSim {
  ClothSim({
    required this.cols,
    required this.rows,
    required this.spacing,
    required this.originX,
    required this.originY,
    required this.floor,
    this.pinEvery = 4,
  }) : x = Float32List(cols * rows),
       y = Float32List(cols * rows),
       px = Float32List(cols * rows),
       py = Float32List(cols * rows),
       pinned = Uint8List(cols * rows),
       _held = Uint8List(cols * rows),
       _heldX = Float32List(cols * rows),
       _heldY = Float32List(cols * rows) {
    final links = <int>[];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final k = j * cols + i;
        x[k] = px[k] = originX + i * spacing;
        y[k] = py[k] = originY + j * spacing;
        if (i < cols - 1) links.addAll([k, k + 1]);
        if (j < rows - 1) links.addAll([k, k + cols]);
      }
    }
    for (var i = 0; i < cols; i++) {
      if (i % pinEvery == 0 || i == cols - 1) pinned[i] = 1;
    }
    linkA = Int32List(links.length ~/ 2);
    linkB = Int32List(links.length ~/ 2);
    for (var c = 0; c < linkA.length; c++) {
      linkA[c] = links[c * 2];
      linkB[c] = links[c * 2 + 1];
    }
    alive = Uint8List(linkA.length)..fillRange(0, linkA.length, 1);
    _hIndex = Int32List(cols * rows)..fillRange(0, cols * rows, -1);
    _vIndex = Int32List(cols * rows)..fillRange(0, cols * rows, -1);
    for (var c = 0; c < linkA.length; c++) {
      if (linkB[c] == linkA[c] + 1) {
        _hIndex[linkA[c]] = c;
      } else {
        _vIndex[linkA[c]] = c;
      }
    }
  }

  final int cols;
  final int rows;
  final double spacing;
  final double originX;
  final double originY;

  /// The y coordinate of the ground.
  final double floor;
  final int pinEvery;

  final Float32List x, y, px, py;
  final Uint8List pinned;

  /// Constraint endpoints and whether each constraint is still intact.
  late final Int32List linkA, linkB;
  late final Uint8List alive;

  /// For point k: index of the constraint to its right / below, or -1.
  late final Int32List _hIndex, _vIndex;

  final Uint8List _held;
  final Float32List _heldX, _heldY;
  final Map<int, int> _grabs = {};

  double gravity = 1600;
  double damping = 0.992;
  int iterations = 8;

  /// Constraints stretched beyond this multiple of their rest length snap.
  double tearRatio = 3.2;

  bool wind = false;
  double _time = 0;

  int get pointCount => cols * rows;

  /// Number of constraints that are still intact.
  int get aliveCount {
    var n = 0;
    for (final a in alive) {
      n += a;
    }
    return n;
  }

  /// Index of the constraint to the right of point ([i], [j]), or -1.
  int hLink(int i, int j) => _hIndex[j * cols + i];

  /// Index of the constraint below point ([i], [j]), or -1.
  int vLink(int i, int j) => _vIndex[j * cols + i];

  // ---------------------------------------------------------------------------
  // Interaction
  // ---------------------------------------------------------------------------

  /// Grabs the point nearest to ([gx], [gy]) within [radius] for [pointer].
  /// Returns whether a point was caught.
  bool grab(int pointer, double gx, double gy, {double radius = 40}) {
    var best = -1;
    var bestD = radius * radius;
    for (var k = 0; k < pointCount; k++) {
      if (_held[k] != 0) continue;
      final dx = x[k] - gx, dy = y[k] - gy;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    if (best < 0) return false;
    _grabs[pointer] = best;
    _held[best] = 1;
    _heldX[best] = gx;
    _heldY[best] = gy;
    return true;
  }

  void drag(int pointer, double gx, double gy) {
    final k = _grabs[pointer];
    if (k == null) return;
    _heldX[k] = gx;
    _heldY[k] = gy;
  }

  void release(int pointer) {
    final k = _grabs.remove(pointer);
    if (k != null) _held[k] = 0;
  }

  bool isGrabbing(int pointer) => _grabs.containsKey(pointer);

  /// Severs every constraint whose midpoint lies within [radius] of the
  /// segment from ([ax], [ay]) to ([bx], [by]). Returns how many were cut.
  int cut(double ax, double ay, double bx, double by, {double radius = 10}) {
    final r2 = radius * radius;
    final sx = bx - ax, sy = by - ay;
    final len2 = sx * sx + sy * sy;
    var n = 0;
    for (var c = 0; c < alive.length; c++) {
      if (alive[c] == 0) continue;
      final mx = (x[linkA[c]] + x[linkB[c]]) * 0.5;
      final my = (y[linkA[c]] + y[linkB[c]]) * 0.5;
      var t = len2 == 0 ? 0.0 : ((mx - ax) * sx + (my - ay) * sy) / len2;
      t = t.clamp(0.0, 1.0);
      final dx = mx - (ax + sx * t), dy = my - (ay + sy * t);
      if (dx * dx + dy * dy <= r2) {
        alive[c] = 0;
        n++;
      }
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void step(double dt) {
    _time += dt;
    final dt2 = dt * dt;
    for (var k = 0; k < pointCount; k++) {
      if (_held[k] != 0) {
        // Keep the previous position so the cloth flies off when released.
        // Pinned points can be dragged too; they stay pinned where dropped.
        px[k] = pinned[k] != 0 ? _heldX[k] : x[k];
        py[k] = pinned[k] != 0 ? _heldY[k] : y[k];
        x[k] = _heldX[k];
        y[k] = _heldY[k];
        continue;
      }
      if (pinned[k] != 0) continue;
      var ax = 0.0;
      if (wind) {
        final gust = 0.6 + 0.4 * math.sin(_time * 1.7 + y[k] * 0.013);
        ax = 900 * gust * (0.7 + 0.3 * math.sin(_time * 5.3 + k * 0.37));
      }
      final vx = (x[k] - px[k]) * damping;
      final vy = (y[k] - py[k]) * damping;
      px[k] = x[k];
      py[k] = y[k];
      x[k] += vx + ax * dt2;
      y[k] += vy + gravity * dt2;
    }

    final rest = spacing;
    final tear = rest * tearRatio;
    for (var it = 0; it < iterations; it++) {
      for (var c = 0; c < alive.length; c++) {
        if (alive[c] == 0) continue;
        final a = linkA[c], b = linkB[c];
        final dx = x[b] - x[a], dy = y[b] - y[a];
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > tear) {
          alive[c] = 0;
          continue;
        }
        if (d == 0) continue;
        final fixedA = pinned[a] != 0 || _held[a] != 0;
        final fixedB = pinned[b] != 0 || _held[b] != 0;
        if (fixedA && fixedB) continue;
        final diff = (d - rest) / d;
        final wa = fixedA ? 0.0 : (fixedB ? 1.0 : 0.5);
        final wb = fixedB ? 0.0 : (fixedA ? 1.0 : 0.5);
        x[a] += dx * diff * wa;
        y[a] += dy * diff * wa;
        x[b] -= dx * diff * wb;
        y[b] -= dy * diff * wb;
      }
    }

    // Ground: stop and add a little friction.
    for (var k = 0; k < pointCount; k++) {
      if (pinned[k] != 0) continue;
      if (y[k] > floor) {
        y[k] = floor;
        px[k] = x[k] + (px[k] - x[k]) * 0.6;
        py[k] = floor;
      }
    }
  }
}
