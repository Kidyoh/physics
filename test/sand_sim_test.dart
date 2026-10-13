import 'package:flutter_test/flutter_test.dart';
import 'package:tactile/src/sand/sand_sim.dart';

void main() {
  void run(SandSim sim, int steps) {
    for (var i = 0; i < steps; i++) {
      sim.step();
    }
  }

  test('sand falls to the floor', () {
    final sim = SandSim(20, 20)..set(10, 0, Mat.sand);
    run(sim, 40);
    expect(sim.typeAt(10, 19), Mat.sand);
    expect(sim.count(Mat.sand), 1);
  });

  test('walls hold sand up', () {
    final sim = SandSim(20, 20)..paintLine(0, 10.5, 20, 10.5, 0.6, Mat.wall);
    sim.set(10, 0, Mat.sand);
    run(sim, 40);
    expect(sim.typeAt(10, 10), Mat.wall);
    expect(sim.typeAt(10, 9), Mat.sand);
  });

  test('a poured column of sand piles up and keeps every grain', () {
    final sim = SandSim(40, 40);
    for (var y = 0; y < 20; y++) {
      sim.set(20, y, Mat.sand);
    }
    run(sim, 200);
    expect(sim.count(Mat.sand), 20);
    // It has spread sideways into a heap rather than standing as a column.
    var widest = 0;
    for (var x = 0; x < 40; x++) {
      if (sim.typeAt(x, 39) == Mat.sand) widest++;
    }
    expect(widest, greaterThan(2));
  });

  test('water levels out across the floor', () {
    final sim = SandSim(30, 20);
    for (var y = 0; y < 15; y++) {
      sim.set(15, y, Mat.water);
    }
    run(sim, 400);
    expect(sim.count(Mat.water), 15);
    var bottom = 0;
    for (var x = 0; x < 30; x++) {
      if (sim.typeAt(x, 19) == Mat.water) bottom++;
    }
    expect(bottom, 15);
  });

  test('sand sinks through water', () {
    final sim = SandSim(1, 10);
    for (var y = 5; y < 10; y++) {
      sim.set(0, y, Mat.water);
    }
    sim.set(0, 0, Mat.sand);
    run(sim, 200);
    expect(sim.typeAt(0, 9), Mat.sand);
    expect(sim.count(Mat.water), 5);
  });

  test('oil floats on top of water', () {
    final sim = SandSim(1, 10);
    for (var y = 0; y < 3; y++) {
      sim.set(0, y, Mat.water);
    }
    for (var y = 3; y < 6; y++) {
      sim.set(0, y, Mat.oil);
    }
    run(sim, 300);
    for (var y = 7; y < 10; y++) {
      expect(sim.typeAt(0, y), Mat.water, reason: 'row $y');
    }
    for (var y = 4; y < 7; y++) {
      expect(sim.typeAt(0, y), Mat.oil, reason: 'row $y');
    }
  });

  test('fire burns through plants', () {
    final sim = SandSim(20, 20);
    for (var y = 10; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        sim.set(x, y, Mat.plant);
      }
    }
    final before = sim.count(Mat.plant);
    sim.set(10, 9, Mat.fire);
    // Keep the flame fed so the test doesn't depend on a lucky first spark.
    for (var i = 0; i < 400; i++) {
      if (i < 60) sim.set(10, 9, Mat.fire);
      sim.step();
    }
    expect(sim.count(Mat.plant), lessThan(before));
  });

  test('fire and water make steam', () {
    final sim = SandSim(10, 10);
    for (var x = 0; x < 10; x++) {
      sim.set(x, 9, Mat.water);
    }
    var sawSteam = false;
    for (var i = 0; i < 60 && !sawSteam; i++) {
      for (var x = 0; x < 10; x++) {
        if (sim.typeAt(x, 8) == Mat.empty) sim.set(x, 8, Mat.fire);
      }
      sim.step();
      sawSteam = sim.count(Mat.steam) > 0;
    }
    expect(sawSteam, isTrue);
  });

  test('plants grow into water', () {
    final sim = SandSim(10, 10);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        sim.set(x, y, Mat.water);
      }
    }
    sim.set(5, 5, Mat.plant);
    run(sim, 300);
    expect(sim.count(Mat.plant), greaterThan(5));
  });

  test('smoke drifts away and disappears', () {
    final sim = SandSim(10, 20)..set(5, 19, Mat.smoke);
    run(sim, 300);
    expect(sim.count(Mat.smoke), 0);
  });

  test('painting a line fills cells along it, eraser clears them', () {
    final sim = SandSim(50, 50);
    sim.paintLine(5, 25, 45, 25, 2, Mat.wall);
    for (var x = 6; x < 45; x++) {
      expect(sim.typeAt(x, 25), Mat.wall, reason: 'x=$x');
    }
    sim.paintCircle(25, 25, 4, Mat.empty);
    expect(sim.typeAt(25, 25), Mat.empty);
  });

  test('render paints fire into the glow layer only', () {
    final sim = SandSim(4, 4)
      ..set(0, 0, Mat.fire)
      ..set(3, 3, Mat.sand)
      ..render();
    expect(sim.glowCells, 1);
    expect(sim.glow[0], isNot(0));
    expect(sim.glow[15], 0);
    expect(sim.pixels[5], SandSim.background);
  });
}
