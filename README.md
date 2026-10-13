# Tactile — physics you can touch

A Flutter sandbox for Android and iOS. Paint sand, water, fire, ink and cloth with
your fingers, at 60 fps.

| Mode  | What you do | Under the hood |
|-------|-------------|----------------|
| **Sand**  | Pour sand, water, oil, fire, plants, steam and walls. Erase anything. | Falling-sand cellular automaton (150 columns) with density-based sinking and reactions |
| **Fluid** | Swirl glowing ink with one finger or several. | Stable-fluids solver (Stam) with vorticity confinement, red-black Gauss-Seidel pressure solve |
| **Cloth** | Grab and fling a hanging banner, slice it with **Tear**, turn on **Wind**. | Verlet integration with distance constraints that snap when overstretched |

Reactions in sand mode:

- Sand sinks through water and oil; oil floats on water.
- Fire spreads through plants and oil, then turns to smoke.
- Fire and water make steam. Steam rises and sometimes condenses back into rain.
- Plants slowly grow into any water they touch.

Every mode supports multi-touch, pause, reset, and **Share**, which exports a PNG of
the canvas through the system share sheet. Fire and ink get an additive bloom pass.
Tool changes trigger light haptics.

### Look and feel

The interface follows Apple's iOS 26 *Liquid Glass* language:

- **Clear glass controls** float over a full-screen canvas. Each has a light blur, boosted
  saturation, a bright rim that catches the light from the top left, and a soft sheen.
  They share one backdrop pass (`BackdropGroup`) to stay cheap.
- **Lens bars:** the mode switcher and the tool bars slide a glass lens, with a small
  spring, behind the selected item. In sand mode the lens is tinted with the chosen
  material, and a small label pops up whenever you switch.
- **Fill sliders** like Control Center's sit on the screen edges for brush size and,
  in fluid mode, swirl.
- **The tool bar is a physical ledge:** sand piles on top of it and pours off its
  rounded ends.
- **Intro:** the word *Tactile* rains down out of sand grains, then crumbles onto the
  tool bar. Tap to skip.

## Run it

```sh
flutter pub get
flutter run --release   # use release mode to judge performance; debug builds are much slower
```

Requires Flutter 3.38+ (developed on 3.47). iOS 15+, Android minSdk from Flutter's default.

## Layout

```
lib/
  main.dart                  entry point (portrait, edge-to-edge)
  src/app.dart               shell: lens bars, fill sliders, tool label, hint, share
  src/ui/                    liquid glass, lens and orbs; shared backdrop; sand-title intro
  src/controllers.dart       per-mode settings shared by the toolbar and views
  src/common/                fixed-step loop, pixel-buffer → ui.Image upload, multi-touch input, RNG
  src/sand/                  SandSim (pure Dart) + SandView
  src/fluid/                 FluidSim (pure Dart) + FluidView
  src/cloth/                 ClothSim (pure Dart) + ClothView
test/                        unit tests for every simulation + widget smoke tests
```

The simulations are plain Dart with no Flutter dependency. They write RGBA pixels into a
`Uint32List`, and the view uploads that buffer as a `ui.Image` each frame. The cloth is
drawn directly with `drawVertices`.

## Performance

Each simulation runs at a fixed 60 Hz step whatever the display's refresh rate. The
small number in the top bar shows the achieved frame rate. AOT-compiled timings per frame
on a 2.8 GHz x86 core:

| Simulation | Grid | Time per frame |
|------------|------|----------------|
| Sand, busy screen | 150 × 325 | ~1.6 ms |
| Fluid | 110 × 238 | ~4 ms |
| Cloth | 34 × 30 points | ~0.4 ms |

## Tests

```sh
flutter analyze
flutter test
```
