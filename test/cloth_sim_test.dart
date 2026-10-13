import 'package:flutter_test/flutter_test.dart';
import 'package:tactile/src/cloth/cloth_sim.dart';

ClothSim makeCloth() =>
    ClothSim(cols: 9, rows: 8, spacing: 10, originX: 0, originY: 0, floor: 1000);

void run(ClothSim sim, int steps) {
  for (var i = 0; i < steps; i++) {
    sim.step(1 / 60);
  }
}

void main() {
  test('pinned points hold while the rest hangs', () {
    final sim = makeCloth();
    run(sim, 120);
    expect(sim.x[0], 0);
    expect(sim.y[0], 0);
    final bottom = (sim.rows - 1) * sim.cols + 4;
    expect(sim.y[bottom], greaterThan(60));
    expect(sim.y[bottom], lessThan(200), reason: 'cloth should not stretch wildly');
    expect(sim.aliveCount, sim.alive.length, reason: 'gravity alone must not tear it');
  });

  test('cutting across the cloth drops the lower half to the floor', () {
    final sim = makeCloth();
    run(sim, 30);
    final y = sim.y[4 * sim.cols];
    expect(sim.cut(-20, y - 5, 200, y - 5), greaterThan(0));
    run(sim, 600);
    final bottom = (sim.rows - 1) * sim.cols + 4;
    expect(sim.y[bottom], closeTo(1000, 1));
  });

  test('grabbing drags a point and yanking hard tears the cloth', () {
    final sim = makeCloth();
    final k = (sim.rows - 1) * sim.cols + 4;
    expect(sim.grab(1, sim.x[k], sim.y[k]), isTrue);
    sim.drag(1, sim.x[k], 900);
    run(sim, 30);
    expect(sim.y[k], 900);
    expect(sim.aliveCount, lessThan(sim.alive.length));
    sim.release(1);
    expect(sim.isGrabbing(1), isFalse);
  });

  test('grab misses when nothing is close', () {
    final sim = makeCloth();
    expect(sim.grab(1, 500, 500), isFalse);
  });

  test('wind pushes the cloth sideways', () {
    final sim = makeCloth()..wind = true;
    final k = (sim.rows - 1) * sim.cols + 4;
    final x0 = sim.x[k];
    run(sim, 120);
    expect(sim.x[k], greaterThan(x0 + 5));
  });
}
