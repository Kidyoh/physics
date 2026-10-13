import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'fluid/fluid_sim.dart';
import 'sand/sand_sim.dart';

/// State shared between a simulation view and the toolbar that drives it.
abstract class SimController extends ChangeNotifier {
  bool _paused = false;
  bool get paused => _paused;
  set paused(bool value) {
    if (value == _paused) return;
    _paused = value;
    notifyListeners();
  }

  /// Whether the user has touched this mode yet (hides the hint).
  bool _touched = false;
  bool get touched => _touched;
  void markTouched() {
    if (_touched) return;
    _touched = true;
    notifyListeners();
  }

  /// Measured frame rate of this mode's render loop.
  final ValueNotifier<int> fps = ValueNotifier(0);

  int _resetCount = 0;

  /// Increments whenever [reset] is called; views watch it to rebuild state.
  int get resetCount => _resetCount;

  void reset() {
    _resetCount++;
    notifyListeners();
  }

  @override
  void dispose() {
    fps.dispose();
    super.dispose();
  }
}

/// A material the user can paint in sand mode.
class SandTool {
  const SandTool(this.material, this.label, this.color);
  final int material;
  final String label;
  final Color color;
}

const sandTools = <SandTool>[
  SandTool(Mat.sand, 'Sand', Color(0xFFF0C27E)),
  SandTool(Mat.water, 'Water', Color(0xFF3A8CFF)),
  SandTool(Mat.fire, 'Fire', Color(0xFFFF7A1A)),
  SandTool(Mat.oil, 'Oil', Color(0xFF7A5230)),
  SandTool(Mat.plant, 'Plant', Color(0xFF3CC45A)),
  SandTool(Mat.steam, 'Steam', Color(0xFFC0CCDD)),
  SandTool(Mat.wall, 'Wall', Color(0xFF7D8293)),
  SandTool(Mat.empty, 'Erase', Color(0xFF2A2A34)),
];

class SandController extends SimController {
  int _material = Mat.sand;
  int get material => _material;
  set material(int value) {
    _material = value;
    notifyListeners();
  }

  /// Brush radius in grid cells.
  double _brush = 3;
  double get brush => _brush;
  set brush(double value) {
    _brush = value;
    notifyListeners();
  }
}

/// Colour schemes for the fluid dye.
enum FluidPalette {
  rainbow('Rainbow', [Color(0xFFFF3D7F), Color(0xFFFFD23D), Color(0xFF3DFFB4), Color(0xFF3D8BFF)]),
  ember('Ember', [Color(0xFFFF3B1F), Color(0xFFFF9A1F), Color(0xFFFFE07A)]),
  ocean('Ocean', [Color(0xFF0B5CFF), Color(0xFF19D3FF), Color(0xFF7DFFE8)]),
  neon('Neon', [Color(0xFFFF2BD6), Color(0xFF8A2BFF), Color(0xFF2BF0FF)]);

  const FluidPalette(this.label, this.swatch);
  final String label;
  final List<Color> swatch;

  /// Dye colour (0..1 RGB) for a moment in time [t] in seconds and a
  /// per-finger offset [seed].
  List<double> colorAt(double t, int seed) {
    switch (this) {
      case FluidPalette.rainbow:
        return hsvToRgb(t * 0.12 + seed * 0.27, 0.85, 1.0);
      case FluidPalette.ember:
        return hsvToRgb(0.02 + 0.08 * (0.5 + 0.5 * _wave(t * 0.7 + seed)), 0.95, 1.0);
      case FluidPalette.ocean:
        return hsvToRgb(0.5 + 0.12 * (0.5 + 0.5 * _wave(t * 0.5 + seed)), 0.85, 1.0);
      case FluidPalette.neon:
        return hsvToRgb(0.78 + 0.25 * (0.5 + 0.5 * _wave(t * 0.6 + seed)), 0.85, 1.0);
    }
  }

  static double _wave(double x) {
    // Cheap triangle-ish wave in -1..1.
    final f = x - x.floorToDouble();
    return f < 0.5 ? f * 4 - 1 : 3 - f * 4;
  }
}

class FluidController extends SimController {
  FluidPalette _palette = FluidPalette.rainbow;
  FluidPalette get palette => _palette;
  set palette(FluidPalette value) {
    _palette = value;
    notifyListeners();
  }

  /// Brush radius as a fraction of the grid width.
  double _brush = 0.035;
  double get brush => _brush;
  set brush(double value) {
    _brush = value;
    notifyListeners();
  }

  /// Swirliness (vorticity confinement strength).
  double _swirl = 18;
  double get swirl => _swirl;
  set swirl(double value) {
    _swirl = value;
    notifyListeners();
  }
}

enum ClothTool { grab, tear }

class ClothController extends SimController {
  ClothTool _tool = ClothTool.grab;
  ClothTool get tool => _tool;
  set tool(ClothTool value) {
    _tool = value;
    notifyListeners();
  }

  bool _wind = false;
  bool get wind => _wind;
  set wind(bool value) {
    _wind = value;
    notifyListeners();
  }
}
