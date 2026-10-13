import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'cloth/cloth_view.dart';
import 'controllers.dart';
import 'fluid/fluid_view.dart';
import 'sand/sand_view.dart';

class TactileApp extends StatelessWidget {
  const TactileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tactile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A1A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07070B),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
      ),
      home: const SandboxPage(),
    );
  }
}

enum Mode {
  sand('Sand', Icons.grain, 'Drag to pour. Try fire on plants or oil.'),
  fluid('Fluid', Icons.waves, 'Swirl the ink with your fingers.'),
  cloth('Cloth', Icons.curtains, 'Grab and fling it. Switch to Tear to slice.');

  const Mode(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;
}

class SandboxPage extends StatefulWidget {
  const SandboxPage({super.key});

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> {
  final _captureKey = GlobalKey();
  final _shareKey = GlobalKey();
  final _sand = SandController();
  final _fluid = FluidController();
  final _cloth = ClothController();
  Mode _mode = Mode.sand;

  SimController get _active => switch (_mode) {
    Mode.sand => _sand,
    Mode.fluid => _fluid,
    Mode.cloth => _cloth,
  };

  @override
  void dispose() {
    _sand.dispose();
    _fluid.dispose();
    _cloth.dispose();
    super.dispose();
  }

  void _setMode(Mode m) {
    if (m == _mode) return;
    HapticFeedback.lightImpact();
    setState(() => _mode = m);
  }

  Future<void> _share() async {
    HapticFeedback.mediumImpact();
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null || !mounted) return;
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png')],
        fileNameOverrides: ['tactile-${_mode.name}.png'],
        text: 'Made in Tactile',
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _captureKey,
            child: IndexedStack(
              index: _mode.index,
              sizing: StackFit.expand,
              children: [
                TickerMode(
                  enabled: _mode == Mode.sand,
                  child: SandView(controller: _sand),
                ),
                TickerMode(
                  enabled: _mode == Mode.fluid,
                  child: FluidView(controller: _fluid),
                ),
                TickerMode(
                  enabled: _mode == Mode.cloth,
                  child: ClothView(controller: _cloth),
                ),
              ],
            ),
          ),
          _Hint(controller: _active, text: _mode.hint),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _TopBar(
                  mode: _mode,
                  controller: _active,
                  shareKey: _shareKey,
                  onMode: _setMode,
                  onShare: _share,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: switch (_mode) {
                    Mode.sand => _SandPanel(key: const ValueKey('sand'), controller: _sand),
                    Mode.fluid => _FluidPanel(key: const ValueKey('fluid'), controller: _fluid),
                    Mode.cloth => _ClothPanel(key: const ValueKey('cloth'), controller: _cloth),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chrome
// -----------------------------------------------------------------------------

const _panelColor = Color(0xD9121218);
const _panelBorder = Color(0x22FFFFFF);

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(10)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _panelBorder),
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.controller,
    required this.shareKey,
    required this.onMode,
    required this.onShare,
  });

  final Mode mode;
  final SimController controller;
  final GlobalKey shareKey;
  final ValueChanged<Mode> onMode;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _Panel(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in Mode.values)
                    _ModeButton(mode: m, selected: m == mode, onTap: () => onMode(m)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Panel(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: controller.fps,
                  builder: (context, fps, _) => Padding(
                    padding: const EdgeInsets.only(left: 8, right: 2),
                    child: Text(
                      '$fps',
                      style: TextStyle(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: fps >= 55 ? const Color(0xFF6BE38B) : const Color(0xFFFFB347),
                      ),
                    ),
                  ),
                ),
                _IconAction(
                  icon: controller.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  tooltip: controller.paused ? 'Play' : 'Pause',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.paused = !controller.paused;
                  },
                ),
                _IconAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reset',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    controller.reset();
                  },
                ),
                _IconAction(
                  key: shareKey,
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Share',
                  onTap: onShare,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.selected, required this.onTap});

  final Mode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, size: 18, color: selected ? accent : Colors.white70),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                mode.label,
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      onPressed: onTap,
    );
  }
}

/// Fades out the first time the user touches the canvas.
class _Hint extends StatelessWidget {
  const _Hint({required this.controller, required this.text});

  final SimController controller;
  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AnimatedOpacity(
          opacity: controller.touched ? 0 : 1,
          duration: const Duration(milliseconds: 600),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app_rounded, size: 40, color: Colors.white54),
                  const SizedBox(height: 10),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(icon, size: 18, color: Colors.white60),
        ),
        Expanded(
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Mode panels
// -----------------------------------------------------------------------------

class _SandPanel extends StatelessWidget {
  const _SandPanel({super.key, required this.controller});

  final SandController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in sandTools)
                    _Swatch(
                      label: t.label,
                      selected: controller.material == t.material,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.material = t.material;
                      },
                      decoration: BoxDecoration(
                        color: t.color,
                        shape: BoxShape.circle,
                        boxShadow: t.label == 'Fire'
                            ? [BoxShadow(color: t.color.withValues(alpha: 0.7), blurRadius: 10)]
                            : null,
                      ),
                      child: t.label == 'Erase'
                          ? const Icon(
                              Icons.cleaning_services_rounded,
                              size: 16,
                              color: Colors.white70,
                            )
                          : null,
                    ),
                ],
              ),
            ),
            _LabeledSlider(
              icon: Icons.brush_rounded,
              value: controller.brush,
              min: 1,
              max: 12,
              onChanged: (v) => controller.brush = v,
            ),
          ],
        ),
      ),
    );
  }
}

class _FluidPanel extends StatelessWidget {
  const _FluidPanel({super.key, required this.controller});

  final FluidController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final p in FluidPalette.values)
                    _Swatch(
                      label: p.label,
                      selected: controller.palette == p,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.palette = p;
                      },
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [...p.swatch, p.swatch.first]),
                      ),
                    ),
                ],
              ),
            ),
            _LabeledSlider(
              icon: Icons.brush_rounded,
              value: controller.brush,
              min: 0.015,
              max: 0.09,
              onChanged: (v) => controller.brush = v,
            ),
            _LabeledSlider(
              icon: Icons.cyclone_rounded,
              value: controller.swirl,
              min: 0,
              max: 60,
              onChanged: (v) => controller.swirl = v,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClothPanel extends StatelessWidget {
  const _ClothPanel({super.key, required this.controller});

  final ClothController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Swatch(
                label: 'Grab',
                selected: controller.tool == ClothTool.grab,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.tool = ClothTool.grab;
                },
                decoration: const BoxDecoration(color: Color(0xFF3A3550), shape: BoxShape.circle),
                child: const Icon(Icons.pan_tool_rounded, size: 15, color: Colors.white),
              ),
              _Swatch(
                label: 'Tear',
                selected: controller.tool == ClothTool.tear,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.tool = ClothTool.tear;
                },
                decoration: const BoxDecoration(color: Color(0xFF5A2440), shape: BoxShape.circle),
                child: const Icon(Icons.content_cut_rounded, size: 15, color: Colors.white),
              ),
              _Swatch(
                label: controller.wind ? 'Wind on' : 'Wind',
                selected: controller.wind,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.wind = !controller.wind;
                },
                decoration: const BoxDecoration(color: Color(0xFF1F4256), shape: BoxShape.circle),
                child: const Icon(Icons.air_rounded, size: 16, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round, labelled, selectable tool button.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.decoration,
    this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final BoxDecoration decoration;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
              ),
              child: AnimatedScale(
                scale: selected ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: decoration,
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: selected ? Colors.white : Colors.white60,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
