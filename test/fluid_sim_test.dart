import 'package:flutter_test/flutter_test.dart';
import 'package:tactile/src/fluid/fluid_sim.dart';

void main() {
  const dt = 1 / 60;

  double centerOfMassX(FluidSim sim) {
    var sum = 0.0, weighted = 0.0;
    for (var y = 1; y <= sim.height; y++) {
      for (var x = 1; x <= sim.width; x++) {
        final d = sim.r[sim.ix(x, y)];
        sum += d;
        weighted += d * x;
      }
    }
    return weighted / sum;
  }

  test('dye is carried along with the flow', () {
    final sim = FluidSim(60, 60)..splat(20, 30, 300, 0, 1, 0, 0, radius: 4);
    final start = centerOfMassX(sim);
    for (var i = 0; i < 20; i++) {
      sim.step(dt);
    }
    expect(centerOfMassX(sim), greaterThan(start + 3));
  });

  test('pressure projection keeps the flow nearly incompressible', () {
    final sim = FluidSim(60, 60)
      ..splat(30, 30, 400, 0, 1, 1, 1, radius: 5)
      ..splat(30, 30, 0, -400, 1, 1, 1, radius: 5);
    final before = sim.maxDivergence();
    sim.project();
    // The collocated-grid projection is approximate (its Laplacian and
    // divergence stencils differ), so expect a large reduction, not zero.
    expect(sim.maxDivergence(), lessThan(before * 0.4));
    var maxSpeed = 0.0;
    for (var i = 0; i < sim.u.length; i++) {
      final s = sim.u[i].abs() + sim.v[i].abs();
      if (s > maxSpeed) maxSpeed = s;
    }
    expect(maxSpeed, greaterThan(1), reason: 'projection must not kill the flow');
  });

  test('stays finite under violent input', () {
    final sim = FluidSim(40, 80)..randomSplats(10);
    for (var i = 0; i < 120; i++) {
      sim.splat(20, 40, 5000, -5000, 2, 2, 2, radius: 6);
      sim.step(dt);
    }
    sim.render();
    expect(sim.totalDye().isFinite, isTrue);
    for (final v in sim.u) {
      expect(v.isFinite, isTrue);
    }
  });

  test('dye fades and clear empties the tank', () {
    final sim = FluidSim(30, 30)..splat(15, 15, 0, 0, 1, 1, 1);
    final before = sim.totalDye();
    for (var i = 0; i < 60; i++) {
      sim.step(dt);
    }
    expect(sim.totalDye(), lessThan(before));
    sim.clear();
    expect(sim.totalDye(), 0);
  });

  test('hsvToRgb covers the primaries', () {
    expect(hsvToRgb(0, 1, 1), [1, 0, 0]);
    expect(hsvToRgb(1 / 3, 1, 1)[1], closeTo(1, 1e-9));
    expect(hsvToRgb(2 / 3, 1, 1)[2], closeTo(1, 1e-9));
  });
}
