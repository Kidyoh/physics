/// Tiny xorshift32 generator. The simulations call it hundreds of thousands
/// of times per frame, so it avoids the overhead of `dart:math` [Random].
class Rng {
  Rng([int seed = 0x9E3779B9]) : _s = (seed & 0xFFFFFFFF) == 0 ? 1 : seed & 0xFFFFFFFF;

  int _s;

  /// Next raw 32-bit value.
  int next() {
    var s = _s;
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    _s = s;
    return s;
  }

  /// Uniform integer in `[0, max)`.
  int nextInt(int max) => next() % max;

  /// Uniform double in `[0, 1)`.
  double nextDouble() => next() / 4294967296.0;

  bool nextBool() => (next() & 1) == 0;

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;
}

/// Packs a colour into the RGBA8888 little-endian layout expected by
/// `ui.decodeImageFromPixels` when written through a `Uint32List`.
int rgba(int r, int g, int b, [int a = 255]) =>
    (a & 0xFF) << 24 | (b & 0xFF) << 16 | (g & 0xFF) << 8 | (r & 0xFF);
