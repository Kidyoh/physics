import 'dart:math' as math;
import 'dart:typed_data';

import '../common/rng.dart';

/// Material ids stored in [SandSim.type].
abstract final class Mat {
  static const int empty = 0;
  static const int wall = 1;
  static const int sand = 2;
  static const int water = 3;
  static const int oil = 4;
  static const int plant = 5;
  static const int fire = 6;
  static const int smoke = 7;
  static const int steam = 8;

  /// Invisible solid used for on-screen obstacles such as the floating tool
  /// bar: grains rest on it, but it is never drawn, painted over or erased.
  static const int ledge = 9;
  static const int count = 10;

  static bool isGas(int t) => t == fire || t == smoke || t == steam;
  static bool isLiquid(int t) => t == water || t == oil;
  static bool isFlammable(int t) => t == plant || t == oil;
}

/// Relative weights used to decide what sinks through what.
const List<int> _density = [0, 255, 10, 6, 5, 255, 1, 1, 1, 255];

/// How far a liquid can slide sideways in a single step.
const List<int> _dispersion = [0, 0, 0, 5, 3, 0, 0, 0, 0, 0];

/// Falling-sand cellular automaton: sand, water, oil, plant, fire, smoke,
/// steam and walls on a fixed grid, with simple reactions between them.
class SandSim {
  SandSim(this.width, this.height, {int seed = 1})
    : type = Uint8List(width * height),
      life = Uint8List(width * height),
      shade = Uint8List(width * height),
      _updated = Uint8List(width * height),
      pixels = Uint32List(width * height),
      glow = Uint32List(width * height),
      _rng = Rng(seed),
      _floor = height {
    _buildPalette();
  }

  final int width;
  final int height;

  /// Material of each cell, see [Mat].
  final Uint8List type;

  /// Remaining lifetime for fire, smoke and steam.
  final Uint8List life;

  /// Random per-cell value that gives each grain a slightly different colour.
  final Uint8List shade;

  final Uint8List _updated;

  /// RGBA8888 colour of every cell, refreshed by [render].
  final Uint32List pixels;

  /// Emissive layer (fire only); transparent elsewhere. Drawn blurred and
  /// additively on top of [pixels] to make flames glow.
  final Uint32List glow;

  final Rng _rng;
  int _frame = 0;

  /// Number of glowing cells after the last [render].
  int glowCells = 0;

  /// Colour of empty cells: fully transparent, so the view's backdrop
  /// gradient shows through.
  static const int background = 0;
  late final Uint32List _palette = Uint32List(Mat.count * 16);

  /// [_palette] brightened, for grains whose top is exposed to open air.
  late final Uint32List _litPalette = Uint32List(Mat.count * 16);
  late final Uint32List _firePalette = Uint32List(256);

  int _floor;

  /// First row that acts as solid ground. Rows from here down are never
  /// filled, so the view can hide them behind its tool dock.
  int get floorRow => _floor;
  set floorRow(int row) {
    final r = row.clamp(1, height);
    if (r < _floor) {
      type.fillRange(r * width, type.length, Mat.empty);
    }
    _floor = r;
  }

  int index(int x, int y) => y * width + x;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  int typeAt(int x, int y) => type[index(x, y)];

  /// Empties the canvas, keeping any ledge in place.
  void clear() {
    for (var i = 0; i < type.length; i++) {
      if (type[i] != Mat.ledge) type[i] = Mat.empty;
    }
    life.fillRange(0, life.length, 0);
  }

  /// Replaces the ledge with a capsule (stadium) spanning cells [x0]..[x1]
  /// by [y0]..[y1]. Pass an empty range to remove it.
  void setLedge(int x0, int y0, int x1, int y1) {
    for (var i = 0; i < type.length; i++) {
      if (type[i] == Mat.ledge) type[i] = Mat.empty;
    }
    if (x1 < x0 || y1 < y0) return;
    final r = (y1 - y0 + 1) / 2;
    final cy = (y0 + y1 + 1) / 2;
    final left = x0 + r, right = x1 + 1 - r;
    for (var y = math.max(0, y0); y <= math.min(height - 1, y1); y++) {
      for (var x = math.max(0, x0); x <= math.min(width - 1, x1); x++) {
        final px = x + 0.5, py = y + 0.5;
        final nx = px < left ? left : (px > right ? right : px);
        final dx = px - nx, dy = py - cy;
        if (dx * dx + dy * dy <= r * r) type[index(x, y)] = Mat.ledge;
      }
    }
  }

  /// Number of cells currently holding material [t].
  int count(int t) {
    var n = 0;
    for (var i = 0; i < type.length; i++) {
      if (type[i] == t) n++;
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Painting
  // ---------------------------------------------------------------------------

  /// Sets a single cell, resetting its lifetime and shade.
  void set(int x, int y, int t) {
    if (!inBounds(x, y)) return;
    final i = index(x, y);
    type[i] = t;
    shade[i] = _rng.next() & 0xFF;
    life[i] = _initialLife(t);
  }

  /// Paints a filled disc of material [t]. Granular materials are sprinkled
  /// rather than filled solid, which looks far more natural.
  void paintCircle(double cx, double cy, double radius, int t) {
    final r2 = radius * radius;
    final x0 = (cx - radius).floor().clamp(0, width - 1);
    final x1 = (cx + radius).ceil().clamp(0, width - 1);
    final y0 = (cy - radius).floor().clamp(0, height - 1);
    final y1 = (cy + radius).ceil().clamp(0, _floor - 1);
    final p = _fillChance(t);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        if (dx * dx + dy * dy > r2) continue;
        final i = index(x, y);
        final current = type[i];
        if (current == Mat.ledge) continue;
        if (t == Mat.empty || t == Mat.wall) {
          if (current != t) set(x, y, t);
        } else if (current == Mat.empty && _rng.chance(p)) {
          set(x, y, t);
        } else if (t == Mat.fire && Mat.isFlammable(current)) {
          set(x, y, Mat.fire);
        }
      }
    }
  }

  /// Paints along the segment from ([x0], [y0]) to ([x1], [y1]) so fast
  /// strokes leave a continuous trail instead of dotted blobs.
  void paintLine(double x0, double y0, double x1, double y1, double radius, int t) {
    final dx = x1 - x0, dy = y1 - y0;
    final len = dx * dx + dy * dy;
    final step = (radius * 0.5).clamp(0.5, 4.0);
    final steps = len == 0 ? 0 : (math.sqrt(len) / step).ceil();
    for (var s = 0; s <= steps; s++) {
      final f = steps == 0 ? 0.0 : s / steps;
      paintCircle(x0 + dx * f, y0 + dy * f, radius, t);
    }
  }

  double _fillChance(int t) => switch (t) {
    Mat.sand => 0.35,
    Mat.water || Mat.oil => 0.5,
    Mat.fire => 0.55,
    Mat.smoke || Mat.steam => 0.3,
    Mat.plant => 0.85,
    _ => 1.0,
  };

  int _initialLife(int t) => switch (t) {
    Mat.fire => 30 + _rng.nextInt(50),
    Mat.smoke => 60 + _rng.nextInt(80),
    Mat.steam => 90 + _rng.nextInt(120),
    _ => 0,
  };

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void step() {
    _frame++;
    _updated.fillRange(0, _updated.length, 0);
    final leftToRight = _frame.isEven;
    for (var y = height - 1; y >= 0; y--) {
      for (var k = 0; k < width; k++) {
        final x = leftToRight ? k : width - 1 - k;
        final i = y * width + x;
        if (_updated[i] != 0) continue;
        switch (type[i]) {
          case Mat.sand:
            _powder(x, y, i);
          case Mat.water:
          case Mat.oil:
            _liquid(x, y, i);
          case Mat.plant:
            _plant(x, y, i);
          case Mat.fire:
            _fire(x, y, i);
          case Mat.smoke:
          case Mat.steam:
            _vapour(x, y, i);
        }
      }
    }
  }

  void _swap(int a, int b) {
    final t = type[a], l = life[a], s = shade[a];
    type[a] = type[b];
    life[a] = life[b];
    shade[a] = shade[b];
    type[b] = t;
    life[b] = l;
    shade[b] = s;
    _updated[a] = 1;
    _updated[b] = 1;
  }

  /// Whether a falling cell of type [src] may move into a cell of type [dst].
  bool _canSink(int src, int dst) =>
      dst == Mat.empty || ((Mat.isLiquid(dst) || Mat.isGas(dst)) && _density[dst] < _density[src]);

  /// Whether a liquid may slide sideways into [dst].
  bool _canSlide(int dst) => dst == Mat.empty || Mat.isGas(dst);

  void _powder(int x, int y, int i) {
    if (y + 1 >= _floor) return;
    final below = i + width;
    final t = type[i];
    final b = type[below];
    if (_canSink(t, b) && (b == Mat.empty || _rng.chance(0.55))) {
      _swap(i, below);
      return;
    }
    final dir = _rng.nextBool() ? 1 : -1;
    for (var a = 0; a < 2; a++) {
      final d = a == 0 ? dir : -dir;
      final nx = x + d;
      if (nx < 0 || nx >= width) continue;
      final n = type[below + d];
      if (_canSink(t, n) && (n == Mat.empty || _rng.chance(0.4))) {
        _swap(i, below + d);
        return;
      }
    }
  }

  void _liquid(int x, int y, int i) {
    final t = type[i];
    if (y + 1 < _floor) {
      final below = i + width;
      if (_canSink(t, type[below])) {
        _swap(i, below);
        return;
      }
      final dir = _rng.nextBool() ? 1 : -1;
      for (var a = 0; a < 2; a++) {
        final d = a == 0 ? dir : -dir;
        final nx = x + d;
        if (nx < 0 || nx >= width) continue;
        if (_canSink(t, type[below + d])) {
          _swap(i, below + d);
          return;
        }
      }
    }
    final reach = _dispersion[t];
    final dir = _rng.nextBool() ? 1 : -1;
    for (var a = 0; a < 2; a++) {
      final d = a == 0 ? dir : -dir;
      var dist = 0;
      for (var k = 1; k <= reach; k++) {
        final nx = x + d * k;
        if (nx < 0 || nx >= width || !_canSlide(type[i + d * k])) break;
        dist = k;
      }
      if (dist > 0) {
        _swap(i, i + d * dist);
        return;
      }
    }
  }

  void _plant(int x, int y, int i) {
    // Grow into a random neighbouring water cell.
    if (!_rng.chance(0.08)) return;
    final nx = x + _rng.nextInt(3) - 1;
    final ny = y + _rng.nextInt(3) - 1;
    if (!inBounds(nx, ny)) return;
    final n = index(nx, ny);
    if (type[n] == Mat.water) {
      type[n] = Mat.plant;
      shade[n] = _rng.next() & 0xFF;
      _updated[n] = 1;
    }
  }

  void _fire(int x, int y, int i) {
    // React with the four direct neighbours.
    for (var k = 0; k < 4; k++) {
      final nx =
          x +
          (k == 0
              ? -1
              : k == 1
              ? 1
              : 0);
      final ny =
          y +
          (k == 2
              ? -1
              : k == 3
              ? 1
              : 0);
      if (!inBounds(nx, ny)) continue;
      final n = ny * width + nx;
      final nt = type[n];
      if (nt == Mat.water) {
        if (_rng.chance(0.35)) {
          _become(n, Mat.steam);
          _become(i, _rng.chance(0.5) ? Mat.steam : Mat.smoke);
          return;
        }
      } else if (nt == Mat.plant && _rng.chance(0.1)) {
        _become(n, Mat.fire);
        life[n] = 50 + _rng.nextInt(60);
      } else if (nt == Mat.oil && _rng.chance(0.25)) {
        _become(n, Mat.fire);
        life[n] = 70 + _rng.nextInt(80);
      }
    }

    final l = life[i];
    if (l <= 1) {
      if (_rng.chance(0.35)) {
        _become(i, Mat.smoke);
      } else {
        type[i] = Mat.empty;
      }
      return;
    }
    life[i] = l - 1 - (_rng.chance(0.3) ? 1 : 0);

    // Flicker upwards.
    if (y == 0 || !_rng.chance(0.55)) return;
    final nx = x + _rng.nextInt(3) - 1;
    if (nx < 0 || nx >= width) return;
    final up = i - width + (nx - x);
    if (type[up] == Mat.empty) _swap(i, up);
  }

  void _vapour(int x, int y, int i) {
    final l = life[i];
    if (l <= 1) {
      if (type[i] == Mat.steam && _rng.chance(0.3)) {
        _become(i, Mat.water);
      } else {
        type[i] = Mat.empty;
      }
      return;
    }
    life[i] = l - 1;
    if (_rng.chance(0.25)) return; // linger a little: wispier look

    if (y > 0) {
      final nx = x + _rng.nextInt(3) - 1;
      if (nx >= 0 && nx < width) {
        final up = i - width + (nx - x);
        final ut = type[up];
        // Rise through empty space, and bubble up through liquids.
        if (ut == Mat.empty || (Mat.isLiquid(ut) && _rng.chance(0.5))) {
          _swap(i, up);
          return;
        }
      }
    }
    final d = _rng.nextBool() ? 1 : -1;
    final nx = x + d;
    if (nx >= 0 && nx < width && type[i + d] == Mat.empty) _swap(i, i + d);
  }

  void _become(int i, int t) {
    type[i] = t;
    life[i] = _initialLife(t);
    _updated[i] = 1;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  void _buildPalette() {
    void ramp(int t, List<int> a, List<int> b) {
      for (var s = 0; s < 16; s++) {
        final f = s / 15;
        _palette[t * 16 + s] = rgba(
          (a[0] + (b[0] - a[0]) * f).round(),
          (a[1] + (b[1] - a[1]) * f).round(),
          (a[2] + (b[2] - a[2]) * f).round(),
        );
      }
    }

    for (var s = 0; s < 16; s++) {
      _palette[s] = background;
    }
    void lit() {
      for (var k = 0; k < _palette.length; k++) {
        final c = _palette[k];
        int up(int v) => (v + (255 - v) * 0.22).round();
        _litPalette[k] = c == background
            ? background
            : rgba(up(c & 0xFF), up((c >> 8) & 0xFF), up((c >> 16) & 0xFF));
      }
    }

    ramp(Mat.wall, [92, 96, 110], [122, 126, 140]);
    ramp(Mat.sand, [214, 168, 92], [246, 210, 138]);
    ramp(Mat.water, [36, 112, 230], [64, 150, 255]);
    ramp(Mat.oil, [70, 46, 26], [104, 70, 36]);
    ramp(Mat.plant, [34, 150, 64], [92, 206, 86]);
    ramp(Mat.smoke, [52, 52, 60], [76, 76, 86]);
    ramp(Mat.steam, [150, 165, 185], [200, 212, 228]);
    ramp(Mat.fire, [255, 120, 20], [255, 200, 60]);
    lit();

    // Fire colour by remaining life: embers are deep red, fresh flames are
    // nearly white-hot.
    const stops = [
      [0.00, 90, 10, 5],
      [0.25, 200, 40, 10],
      [0.55, 255, 120, 20],
      [0.80, 255, 205, 70],
      [1.00, 255, 250, 210],
    ];
    for (var l = 0; l < 256; l++) {
      final f = (l / 90).clamp(0.0, 1.0);
      var k = 0;
      while (k < stops.length - 2 && f > stops[k + 1][0]) {
        k++;
      }
      final a = stops[k], b = stops[k + 1];
      final u = ((f - a[0]) / (b[0] - a[0])).clamp(0.0, 1.0);
      _firePalette[l] = rgba(
        (a[1] + (b[1] - a[1]) * u).round(),
        (a[2] + (b[2] - a[2]) * u).round(),
        (a[3] + (b[3] - a[3]) * u).round(),
      );
    }
  }

  /// Writes the current state into [pixels] and [glow].
  void render() {
    final waterShimmer = (_frame >> 3) & 15;
    final w = width;
    var glowing = 0;
    for (var i = 0; i < type.length; i++) {
      final t = type[i];
      if (t == Mat.empty || t == Mat.ledge) {
        pixels[i] = background;
        glow[i] = 0;
        continue;
      }
      if (t == Mat.fire) {
        final c = _firePalette[(life[i] + (shade[i] & 15)).clamp(0, 255)];
        pixels[i] = c;
        glow[i] = c;
        glowing++;
        continue;
      }
      glow[i] = 0;
      var s = shade[i] & 15;
      if (t == Mat.water) s = (s + waterShimmer) & 15;
      if (t == Mat.smoke || t == Mat.steam) {
        // Translucent, fading out as the vapour dissipates.
        final a = (life[i] * 3).clamp(0, 255) * (t == Mat.steam ? 0.8 : 0.9);
        pixels[i] = _withAlpha(_palette[t * 16 + s], a.round());
        continue;
      }
      // Grains with open air above catch the light, so piles and water
      // surfaces read as lit from above.
      final above = i >= w ? type[i - w] : Mat.empty;
      final exposed = above == Mat.empty || Mat.isGas(above);
      pixels[i] = (exposed ? _litPalette : _palette)[t * 16 + s];
    }
    glowCells = glowing;
  }

  /// Premultiplies an opaque colour by alpha [a] (0..255).
  static int _withAlpha(int c, int a) {
    final f = a / 255.0;
    return rgba(
      ((c & 0xFF) * f).round(),
      (((c >> 8) & 0xFF) * f).round(),
      (((c >> 16) & 0xFF) * f).round(),
      a,
    );
  }
}
