import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Drives a simulation at a fixed 60 Hz step regardless of the display's
/// refresh rate, and measures the achieved frame rate.
class SimLoop {
  SimLoop(TickerProvider vsync, this.onFrame, {this.onFps}) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  static const double stepSeconds = 1 / 60;

  /// Called once per display frame with the number of fixed steps to run.
  final void Function(int steps) onFrame;

  /// Receives the measured frames per second roughly twice a second.
  final void Function(int fps)? onFps;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;
  int _frames = 0;
  double _fpsWindow = 0;

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.1 || dt < 0) dt = stepSeconds; // resumed after a pause

    _frames++;
    _fpsWindow += dt;
    if (_fpsWindow >= 0.5) {
      onFps?.call((_frames / _fpsWindow).round());
      _frames = 0;
      _fpsWindow = 0;
    }

    _acc += dt;
    var steps = 0;
    while (_acc >= stepSeconds * 0.98 && steps < 3) {
      _acc -= stepSeconds;
      steps++;
    }
    if (_acc > stepSeconds) _acc = 0; // too slow to catch up: drop time
    if (_acc < 0) _acc = 0;
    onFrame(steps);
  }

  void dispose() {
    _ticker.dispose();
  }
}

/// Turns an RGBA8888 pixel buffer into a [ui.Image] every frame, skipping
/// frames while a previous upload is still in flight.
class PixelImage extends ChangeNotifier {
  ui.Image? _image;
  bool _pending = false;
  bool _disposed = false;

  ui.Image? get image => _image;

  void upload(Uint32List pixels, int width, int height) {
    if (_pending || _disposed) return;
    _pending = true;
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) {
        _pending = false;
        if (_disposed) {
          img.dispose();
          return;
        }
        _image?.dispose();
        _image = img;
        notifyListeners();
      },
    );
  }

  /// Drops the current image (e.g. when an emissive layer goes dark).
  void clearImage() {
    if (_image == null) return;
    _image!.dispose();
    _image = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
