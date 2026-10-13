import 'dart:math' as math;
import 'dart:typed_data';

import '../common/rng.dart';

/// Grid-based incompressible fluid ("stable fluids", Stam 1999) with
/// vorticity confinement, carrying an RGB dye field you can swirl around.
///
/// Coordinates are in grid cells; interior cells are `1..width` by
/// `1..height`, with a one-cell boundary ring around them.
class FluidSim {
  FluidSim(this.width, this.height, {int seed = 7})
    : _stride = width + 2,
      _rng = Rng(seed),
      pixels = Uint32List(width * height),
      u = Float32List((width + 2) * (height + 2)),
      v = Float32List((width + 2) * (height + 2)),
      r = Float32List((width + 2) * (height + 2)),
      g = Float32List((width + 2) * (height + 2)),
      b = Float32List((width + 2) * (height + 2)),
      _u0 = Float32List((width + 2) * (height + 2)),
      _v0 = Float32List((width + 2) * (height + 2)),
      _r0 = Float32List((width + 2) * (height + 2)),
      _g0 = Float32List((width + 2) * (height + 2)),
      _b0 = Float32List((width + 2) * (height + 2)),
      _p = Float32List((width + 2) * (height + 2)),
      _div = Float32List((width + 2) * (height + 2)),
      _curl = Float32List((width + 2) * (height + 2));

  final int width;
  final int height;
  final int _stride;
  final Rng _rng;

  /// Velocity components (cells per second) and dye channels.
  final Float32List u, v, r, g, b;
  final Float32List _u0, _v0, _r0, _g0, _b0, _p, _div, _curl;

  /// RGBA8888 image of the dye, refreshed by [render].
  final Uint32List pixels;

  /// Strength of the swirl-preserving vorticity confinement force.
  double vorticity = 18;

  /// Fraction of dye that survives each step.
  double dyeFade = 0.993;

  /// Fraction of velocity that survives each step.
  double velocityFade = 0.999;

  int pressureIterations = 20;

  int ix(int x, int y) => x + y * _stride;

  void clear() {
    for (final f in [u, v, r, g, b, _p]) {
      f.fillRange(0, f.length, 0);
    }
  }

  /// Total amount of dye in the field (sum over all channels).
  double totalDye() {
    var s = 0.0;
    for (var i = 0; i < r.length; i++) {
      s += r[i] + g[i] + b[i];
    }
    return s;
  }

  /// Largest absolute divergence over the interior.
  double maxDivergence() {
    var m = 0.0;
    for (var y = 1; y <= height; y++) {
      for (var x = 1; x <= width; x++) {
        final i = ix(x, y);
        final d = (0.5 * (u[i + 1] - u[i - 1] + v[i + _stride] - v[i - _stride])).abs();
        if (d > m) m = d;
      }
    }
    return m;
  }

  /// Adds a Gaussian blob of velocity ([dx], [dy] in cells/second) and dye
  /// centred at ([x], [y]) in interior grid coordinates.
  void splat(
    double x,
    double y,
    double dx,
    double dy,
    double cr,
    double cg,
    double cb, {
    double radius = 4,
  }) {
    final reach = (radius * 2.5).ceil();
    final cx = x + 1, cy = y + 1; // shift into padded coordinates
    final x0 = math.max(1, cx.floor() - reach), x1 = math.min(width, cx.floor() + reach);
    final y0 = math.max(1, cy.floor() - reach), y1 = math.min(height, cy.floor() + reach);
    final inv = 1 / (radius * radius);
    for (var j = y0; j <= y1; j++) {
      for (var i = x0; i <= x1; i++) {
        final ddx = i - cx, ddy = j - cy;
        final f = math.exp(-(ddx * ddx + ddy * ddy) * inv);
        if (f < 0.01) continue;
        final k = ix(i, j);
        u[k] += dx * f;
        v[k] += dy * f;
        r[k] += cr * f;
        g[k] += cg * f;
        b[k] += cb * f;
      }
    }
  }

  /// A burst of a few random colourful splats, used to greet new users.
  void randomSplats(int count) {
    for (var n = 0; n < count; n++) {
      final c = hsvToRgb(_rng.nextDouble(), 0.9, 1.0);
      final a = _rng.nextDouble() * math.pi * 2;
      final speed = 250 + _rng.nextDouble() * 250;
      splat(
        width * (0.15 + 0.7 * _rng.nextDouble()),
        height * (0.15 + 0.7 * _rng.nextDouble()),
        math.cos(a) * speed,
        math.sin(a) * speed,
        c[0] * 1.6,
        c[1] * 1.6,
        c[2] * 1.6,
        radius: width / 18,
      );
    }
  }

  void step(double dt) {
    _vorticityConfinement(dt);
    project();

    _u0.setAll(0, u);
    _v0.setAll(0, v);
    _advect(_u0, _v0, dt, velocityFade, u, _u0, v, _v0);
    _setBoundary(u, mirrorX: true);
    _setBoundary(v, mirrorY: true);

    _r0.setAll(0, r);
    _g0.setAll(0, g);
    _b0.setAll(0, b);
    _advect(u, v, dt, dyeFade, r, _r0, g, _g0, b, _b0);
    _setBoundary(r);
    _setBoundary(g);
    _setBoundary(b);
  }

  void _vorticityConfinement(double dt) {
    if (vorticity <= 0) return;
    final s = _stride, w = width, h = height;
    final u = this.u, v = this.v, curl = _curl;
    for (var y = 1; y <= h; y++) {
      var i = y * s + 1;
      for (var x = 1; x <= w; x++, i++) {
        curl[i] = 0.5 * ((v[i + 1] - v[i - 1]) - (u[i + s] - u[i - s]));
      }
    }
    final strength = vorticity * dt;
    for (var y = 2; y < h; y++) {
      var i = y * s + 2;
      for (var x = 2; x < w; x++, i++) {
        // Gradient of |curl| points towards the vortex centre.
        final nx = 0.5 * (curl[i + 1].abs() - curl[i - 1].abs());
        final ny = 0.5 * (curl[i + s].abs() - curl[i - s].abs());
        final len = math.sqrt(nx * nx + ny * ny) + 1e-5;
        final f = curl[i] * strength / len;
        // f = N x w  ->  (Ny * w, -Nx * w)
        u[i] += ny * f;
        v[i] -= nx * f;
      }
    }
  }

  /// Removes the divergent part of the velocity field (pressure solve).
  void project() {
    final s = _stride, w = width, h = height;
    final u = this.u, v = this.v, p = _p, div = _div;
    for (var y = 1; y <= h; y++) {
      var i = y * s + 1;
      for (var x = 1; x <= w; x++, i++) {
        div[i] = -0.5 * (u[i + 1] - u[i - 1] + v[i + s] - v[i - s]);
        p[i] *= 0.8; // warm start from the previous frame's pressure
      }
    }
    _setBoundary(div);
    _setBoundary(p);
    // Red-black Gauss-Seidel: cells of one colour only read cells of the
    // other, so each sweep has no serial dependency and pipelines well.
    for (var k = 0; k < pressureIterations; k++) {
      for (var colour = 0; colour < 2; colour++) {
        for (var y = 1; y <= h; y++) {
          final x0 = 1 + ((y + 1 + colour) & 1);
          for (var i = y * s + x0, end = y * s + w; i <= end; i += 2) {
            p[i] = (div[i] + p[i - 1] + p[i + 1] + p[i - s] + p[i + s]) * 0.25;
          }
        }
      }
      _setBoundary(p);
    }
    for (var y = 1; y <= h; y++) {
      var i = y * s + 1;
      for (var x = 1; x <= w; x++, i++) {
        u[i] -= 0.5 * (p[i + 1] - p[i - 1]);
        v[i] -= 0.5 * (p[i + s] - p[i - s]);
      }
    }
    _setBoundary(u, mirrorX: true);
    _setBoundary(v, mirrorY: true);
  }

  /// Semi-Lagrangian advection along the velocity field ([vu], [vv]):
  /// each `dstN` receives `srcN` traced back one step. Up to three fields
  /// share one backtrace.
  void _advect(
    Float32List vu,
    Float32List vv,
    double dt,
    double fade,
    Float32List dst0,
    Float32List src0,
    Float32List dst1,
    Float32List src1, [
    Float32List? dst2,
    Float32List? src2,
  ]) {
    final s = _stride, w = width, h = height;
    final maxX = w + 0.5, maxY = h + 0.5;
    for (var y = 1; y <= h; y++) {
      var i = y * s + 1;
      for (var x = 1; x <= w; x++, i++) {
        var px = x - dt * vu[i];
        var py = y - dt * vv[i];
        if (px < 0.5) px = 0.5;
        if (px > maxX) px = maxX;
        if (py < 0.5) py = 0.5;
        if (py > maxY) py = maxY;
        final x0 = px.toInt(), y0 = py.toInt(); // px, py > 0 so this floors
        final sx = px - x0, sy = py - y0;
        // Bilinear weights.
        final w11 = sx * sy, w10 = sx - w11, w01 = sy - w11, w00 = 1 - sx - w01;
        final k = x0 + y0 * s, kr = k + 1, kd = k + s, kdr = kd + 1;
        dst0[i] = (src0[k] * w00 + src0[kr] * w10 + src0[kd] * w01 + src0[kdr] * w11) * fade;
        dst1[i] = (src1[k] * w00 + src1[kr] * w10 + src1[kd] * w01 + src1[kdr] * w11) * fade;
        if (dst2 != null) {
          dst2[i] = (src2![k] * w00 + src2[kr] * w10 + src2[kd] * w01 + src2[kdr] * w11) * fade;
        }
      }
    }
  }

  /// Copies interior edge values into the boundary ring; with [mirrorX] or
  /// [mirrorY] the normal component is negated so walls are solid.
  void _setBoundary(Float32List f, {bool mirrorX = false, bool mirrorY = false}) {
    final w = width, h = height;
    for (var y = 1; y <= h; y++) {
      f[ix(0, y)] = mirrorX ? -f[ix(1, y)] : f[ix(1, y)];
      f[ix(w + 1, y)] = mirrorX ? -f[ix(w, y)] : f[ix(w, y)];
    }
    for (var x = 1; x <= w; x++) {
      f[ix(x, 0)] = mirrorY ? -f[ix(x, 1)] : f[ix(x, 1)];
      f[ix(x, h + 1)] = mirrorY ? -f[ix(x, h)] : f[ix(x, h)];
    }
    f[ix(0, 0)] = 0.5 * (f[ix(1, 0)] + f[ix(0, 1)]);
    f[ix(0, h + 1)] = 0.5 * (f[ix(1, h + 1)] + f[ix(0, h)]);
    f[ix(w + 1, 0)] = 0.5 * (f[ix(w, 0)] + f[ix(w + 1, 1)]);
    f[ix(w + 1, h + 1)] = 0.5 * (f[ix(w, h + 1)] + f[ix(w + 1, h)]);
  }

  /// Writes the dye into [pixels], with a little fake lighting taken from the
  /// dye gradient so the ink looks glossy rather than flat.
  void render() {
    final s = _stride, w = width, h = height;
    final r = this.r, g = this.g, b = this.b, out = pixels;
    var o = 0;
    for (var y = 1; y <= h; y++) {
      var i = y * s + 1;
      for (var x = 1; x <= w; x++, i++) {
        final cr = r[i], cg = g[i], cb = b[i];
        final lum = cr + cg + cb;
        var k = 1.0;
        if (lum > 0.02) {
          final gx = (r[i + 1] + g[i + 1] + b[i + 1]) - (r[i - 1] + g[i - 1] + b[i - 1]);
          final gy = (r[i + s] + g[i + s] + b[i + s]) - (r[i - s] + g[i - s] + b[i - s]);
          // Light from the top-left.
          k = 1.0 + (-gx - gy) * 0.35;
          if (k < 0.55) k = 0.55;
          if (k > 1.5) k = 1.5;
        }
        out[o++] =
            0xFF000000 |
            (_tone(cb * k) + 10) << 16 |
            (_tone(cg * k) + 6) << 8 |
            (_tone(cr * k) + 6);
      }
    }
  }

  /// Soft tone curve so heavy dye saturates gracefully instead of clipping.
  static int _tone(double c) {
    if (c <= 0) return 0;
    final k = (c * _toneScale).toInt();
    return k >= _toneSize ? 245 : _toneTable[k];
  }

  static const int _toneSize = 1024;
  static const double _toneScale = 256; // table covers dye values 0..4
  static final Uint8List _toneTable = Uint8List.fromList([
    for (var k = 0; k < _toneSize; k++) ((1 - math.exp(-k / _toneScale * 1.6)) * 245).round(),
  ]);
}

/// HSV (all components 0..1) to linear RGB triple in 0..1.
List<double> hsvToRgb(double h, double s, double v) {
  h = (h % 1.0) * 6;
  final i = h.floor();
  final f = h - i;
  final p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  return switch (i % 6) {
    0 => [v, t, p],
    1 => [q, v, p],
    2 => [p, v, t],
    3 => [p, q, v],
    4 => [t, p, v],
    _ => [v, p, q],
  };
}
