import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'cloth/cloth_view.dart';
import 'controllers.dart';
import 'fluid/fluid_view.dart';
import 'sand/sand_sim.dart';
import 'sand/sand_view.dart';
import 'ui/glass.dart';
import 'ui/intro.dart';

/// Screen margin around floating controls.
const double _edge = 14;

/// Height of a glass bar: 44pt items plus 4pt padding top and bottom.
const double _barHeight = 52;
const double _topBarHeight = 8 + _barHeight;

/// Springy curve for anything that slides: overshoots a touch, like a
/// liquid settling.
const Curve _liquid = Cubic(0.2, 1.25, 0.35, 1);

class TactileApp extends StatelessWidget {
  const TactileApp({super.key, this.showIntro = true});

  /// Whether to play the opening animation.
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tactile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8C7CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF050508),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xE61A1A24),
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      home: SandboxPage(showIntro: showIntro),
    );
  }
}

enum Mode {
  sand('Sand', Icons.grain_rounded, 'Drag to pour. Set plants or oil on fire.'),
  fluid('Fluid', Icons.water_drop_rounded, 'Swirl the ink. Try two fingers.'),
  cloth('Cloth', Icons.flag_rounded, 'Grab and fling it, or switch to Tear.');

  const Mode(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;
}

class SandboxPage extends StatefulWidget {
  const SandboxPage({super.key, this.showIntro = true});

  final bool showIntro;

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> with SingleTickerProviderStateMixin {
  final _captureKey = GlobalKey();
  final _shareKey = GlobalKey();
  final _sand = SandController();
  final _fluid = FluidController();
  final _cloth = ClothController();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );
  Mode _mode = Mode.sand;
  late bool _intro = widget.showIntro;
  late bool _chrome = !widget.showIntro;

  SimController get _active => switch (_mode) {
    Mode.sand => _sand,
    Mode.fluid => _fluid,
    Mode.cloth => _cloth,
  };

  @override
  void dispose() {
    _fade.dispose();
    _sand.dispose();
    _fluid.dispose();
    _cloth.dispose();
    super.dispose();
  }

  void _setMode(Mode m) {
    if (m == _mode) return;
    HapticFeedback.lightImpact();
    _fade
      ..value = 0.2
      ..forward();
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

  /// Accent colour for the chrome: follows the selected material, palette
  /// or tool.
  Color _accentFor() => switch (_mode) {
    Mode.sand => _sand.material == Mat.empty ? const Color(0xFFB9AEFF) : _sand.tool.color,
    Mode.fluid => _fluid.palette.swatch.first,
    Mode.cloth => _cloth.tool == ClothTool.grab ? const Color(0xFFB07CFF) : const Color(0xFFFF5F9E),
  };

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: BackdropGroup(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FadeTransition(
                    opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
                    child: IndexedStack(
                      index: _mode.index,
                      sizing: StackFit.expand,
                      children: [
                        // The canvas runs edge to edge; grains settle just
                        // above the home indicator and the controls float
                        // over them.
                        _canvas(
                          Mode.sand,
                          SandView(
                            controller: _sand,
                            floorInset: pad.bottom,
                            ledge: _chrome ? _sandBarRect(MediaQuery.sizeOf(context), pad) : null,
                          ),
                        ),
                        _canvas(Mode.fluid, FluidView(controller: _fluid)),
                        _canvas(
                          Mode.cloth,
                          ClothView(
                            controller: _cloth,
                            topInset: pad.top + _topBarHeight,
                            floorInset: pad.bottom + 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const IgnorePointer(child: RepaintBoundary(child: _Vignette())),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([_sand, _fluid, _cloth]),
              builder: (context, _) {
                final target = _accentFor();
                return TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: target),
                  duration: const Duration(milliseconds: 350),
                  builder: (context, accent, _) => _chromeLayer(accent ?? target),
                );
              },
            ),
            if (_intro)
              IntroOverlay(
                onRelease: (grains) {
                  _sand.seed(grains);
                  setState(() => _chrome = true);
                },
                onDone: () => setState(() => _intro = false),
              ),
          ],
        ),
      ),
    );
  }

  /// Where the sand tool bar sits on screen, so grains can pile on it. The
  /// bar has a fixed natural size and is only ever scaled down to fit.
  Rect _sandBarRect(Size screen, EdgeInsets pad) {
    final natural = Size(_SandBar.naturalWidth, _barHeight);
    final s = math.min(1.0, (screen.width - 2 * _edge) / natural.width);
    final w = natural.width * s, h = natural.height * s;
    final bottom = screen.height - pad.bottom - _edge;
    return Rect.fromLTWH((screen.width - w) / 2, bottom - h, w, h);
  }

  Widget _canvas(Mode m, Widget view) => TickerMode(
    enabled: _mode == m,
    child: RepaintBoundary(child: view),
  );

  Widget _chromeLayer(Color accent) {
    final pad = MediaQuery.paddingOf(context);
    // Edge sliders sit just above the bottom bar.
    final sliderBottom = pad.bottom + _edge + _barHeight + 20;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Hint(controller: _active, text: _mode.hint, visible: _chrome),

        // Top: mode bar on the left, actions on the right.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _Reveal(
            visible: _chrome,
            from: const Offset(0, -0.6),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_edge, 8, _edge, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _ModeBar(mode: _mode, accent: accent, onMode: _setMode),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Actions(controller: _active, shareKey: _shareKey, onShare: _share),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Edge sliders.
        Positioned(
          right: _edge,
          bottom: sliderBottom,
          child: _Reveal(visible: _chrome, from: const Offset(0.8, 0), child: _sliderFor(accent)),
        ),
        if (_mode == Mode.fluid)
          Positioned(
            left: _edge,
            bottom: sliderBottom,
            child: _Reveal(
              visible: _chrome,
              from: const Offset(-0.8, 0),
              child: _FillSlider(
                label: 'Swirl',
                icon: Icons.cyclone_rounded,
                value: _fluid.swirl,
                min: 0,
                max: 60,
                accent: accent,
                onChanged: (v) => _fluid.swirl = v,
              ),
            ),
          ),

        // Bottom: the tool bar, with a label that pops up on change.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Reveal(
            visible: _chrome,
            from: const Offset(0, 0.8),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_edge, 0, _edge, _edge),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolToast(text: _toolLabel(), color: accent),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: _liquid,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.9, end: 1.0).animate(anim),
                          child: child,
                        ),
                      ),
                      child: FittedBox(
                        key: ValueKey(_mode),
                        fit: BoxFit.scaleDown,
                        child: switch (_mode) {
                          Mode.sand => _SandBar(controller: _sand),
                          Mode.fluid => _FluidBar(controller: _fluid),
                          Mode.cloth => _ClothBar(controller: _cloth, accent: accent),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _toolLabel() => switch (_mode) {
    Mode.sand => _sand.tool.label,
    Mode.fluid => _fluid.palette.label,
    Mode.cloth => _cloth.tool == ClothTool.grab ? 'Grab' : 'Tear',
  };

  Widget _sliderFor(Color accent) => switch (_mode) {
    Mode.sand => _FillSlider(
      label: 'Brush size',
      icon: Icons.brush_rounded,
      value: _sand.brush,
      min: 1,
      max: 12,
      accent: accent,
      onChanged: (v) => _sand.brush = v,
    ),
    Mode.fluid => _FillSlider(
      label: 'Brush size',
      icon: Icons.brush_rounded,
      value: _fluid.brush,
      min: 0.015,
      max: 0.09,
      accent: accent,
      onChanged: (v) => _fluid.brush = v,
    ),
    Mode.cloth => const SizedBox.shrink(),
  };
}

// -----------------------------------------------------------------------------
// Building blocks
// -----------------------------------------------------------------------------

/// Slides and fades chrome in once the intro hands over.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.visible, required this.from, required this.child});

  final bool visible;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : from,
        duration: const Duration(milliseconds: 700),
        curve: _liquid,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 450),
          child: child,
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.15,
          colors: [Color(0x00000000), Color(0x80000000)],
          stops: [0.6, 1],
        ),
      ),
    );
  }
}

/// A glass capsule of equal-width items with a lens that slides, with a
/// little spring, behind the selected one.
class _LensBar extends StatelessWidget {
  const _LensBar({
    required this.count,
    required this.selected,
    required this.itemWidth,
    required this.labels,
    required this.onSelect,
    required this.itemBuilder,
    this.lensTint,
  });

  final int count;

  /// Index of the selected item, or -1 for none.
  final int selected;
  final double itemWidth;
  final List<String> labels;
  final ValueChanged<int> onSelect;
  final Widget Function(BuildContext context, int index, bool selected) itemBuilder;
  final Color? lensTint;

  static const double _itemHeight = _barHeight - 8;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: itemWidth * count,
        height: _itemHeight,
        child: Stack(
          children: [
            if (selected >= 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 460),
                curve: _liquid,
                left: selected * itemWidth,
                top: 0,
                width: itemWidth,
                height: _itemHeight,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: lensTint),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, tint, _) => GlassLens(tint: tint),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                    width: itemWidth,
                    height: _itemHeight,
                    child: Semantics(
                      button: true,
                      selected: i == selected,
                      label: labels[i],
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: Center(child: itemBuilder(context, i, i == selected)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon over a small label, tab-bar style.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label, required this.selected});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = selected ? Colors.white : Colors.white.withValues(alpha: 0.7);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: c),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          style: DefaultTextStyle.of(context).style.merge(
            TextStyle(
              fontSize: 10.5,
              height: 1.1,
              letterSpacing: 0.1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.mode, required this.accent, required this.onMode});

  final Mode mode;
  final Color accent;
  final ValueChanged<Mode> onMode;

  @override
  Widget build(BuildContext context) {
    return _LensBar(
      count: Mode.values.length,
      selected: mode.index,
      itemWidth: 64,
      labels: [for (final m in Mode.values) '${m.label} mode'],
      lensTint: accent.withValues(alpha: 0.55),
      onSelect: (i) => onMode(Mode.values[i]),
      itemBuilder: (context, i, selected) =>
          _IconLabel(icon: Mode.values[i].icon, label: Mode.values[i].label, selected: selected),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller, required this.shareKey, required this.onShare});

  final SimController controller;
  final GlobalKey shareKey;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        LiquidGlass(
          padding: const EdgeInsets.all(4),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoundButton(
                  tooltip: controller.paused ? 'Play' : 'Pause',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.paused = !controller.paused;
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      controller.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      key: ValueKey(controller.paused),
                    ),
                  ),
                ),
                _ResetButton(controller: controller),
                _RoundButton(
                  key: shareKey,
                  tooltip: 'Share',
                  onTap: onShare,
                  child: const Icon(Icons.ios_share_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _FpsLabel(fps: controller.fps),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.85,
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconTheme(
            data: const IconThemeData(size: 21, color: Colors.white),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Reset with a full spin of its icon.
class _ResetButton extends StatefulWidget {
  const _ResetButton({required this.controller});

  final SimController controller;

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  double _turns = 0;

  @override
  Widget build(BuildContext context) {
    return _RoundButton(
      tooltip: 'Reset',
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() => _turns -= 1);
        widget.controller.reset();
      },
      child: AnimatedRotation(
        turns: _turns,
        duration: const Duration(milliseconds: 600),
        curve: _liquid,
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

class _FpsLabel extends StatelessWidget {
  const _FpsLabel({required this.fps});

  final ValueListenable<int> fps;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: fps,
      builder: (context, value, _) {
        final color = value >= 55 ? const Color(0xFF6BEA8E) : const Color(0xFFFFB347);
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 5)],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$value fps',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Colors.white.withValues(alpha: 0.6),
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Control Center-style vertical slider: the glass capsule fills from the
/// bottom with the accent colour. Drag anywhere on it.
class _FillSlider extends StatefulWidget {
  const _FillSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final double value, min, max;
  final Color accent;
  final ValueChanged<double> onChanged;

  static const double width = 48, height = 150;

  @override
  State<_FillSlider> createState() => _FillSliderState();
}

class _FillSliderState extends State<_FillSlider> {
  int _lastTick = -1;
  bool _active = false;

  double get _t => ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _setFromLocal(Offset local) {
    final t = (1 - local.dy / _FillSlider.height).clamp(0.0, 1.0);
    final tick = (t * 10).round();
    if (tick != _lastTick) {
      _lastTick = tick;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(widget.min + (widget.max - widget.min) * t);
  }

  void _nudge(double dir) {
    final step = (widget.max - widget.min) / 10;
    widget.onChanged((widget.value + step * dir).clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    String pct(double v) => '${(v.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      slider: true,
      label: widget.label,
      value: pct(t),
      increasedValue: pct(t + 0.1),
      decreasedValue: pct(t - 0.1),
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _setFromLocal(d.localPosition),
        onVerticalDragStart: (d) {
          setState(() => _active = true);
          _setFromLocal(d.localPosition);
        },
        onVerticalDragUpdate: (d) => _setFromLocal(d.localPosition),
        onVerticalDragEnd: (_) => setState(() => _active = false),
        onVerticalDragCancel: () => setState(() => _active = false),
        child: AnimatedScale(
          scale: _active ? 1.06 : 1,
          duration: const Duration(milliseconds: 220),
          curve: _liquid,
          child: LiquidGlass(
            child: SizedBox(
              width: _FillSlider.width,
              height: _FillSlider.height,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    height: _FillSlider.height * t,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(widget.accent, Colors.white, 0.25)!.withValues(alpha: 0.9),
                          widget.accent.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: Colors.white,
                      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
                    ),
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

/// A small glass label that pops up above the tool bar whenever the tool
/// changes, then fades away.
class _ToolToast extends StatefulWidget {
  const _ToolToast({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  State<_ToolToast> createState() => _ToolToastState();
}

class _ToolToastState extends State<_ToolToast> {
  bool _show = false;
  Timer? _timer;

  @override
  void didUpdateWidget(_ToolToast old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _show = true;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _show = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedScale(
          scale: _show ? 1 : 0.85,
          duration: const Duration(milliseconds: 380),
          curve: _liquid,
          child: LiquidGlass(
            padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: widget.color, blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass capsule with a nudging finger, shown until the first touch.
class _Hint extends StatelessWidget {
  const _Hint({required this.controller, required this.text, required this.visible});

  final SimController controller;
  final String text;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final show = visible && !controller.touched;
          return Align(
            alignment: const Alignment(0, 0.05),
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, 0.3),
              duration: const Duration(milliseconds: 600),
              curve: _liquid,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: LiquidGlass(
                    padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Nudge(active: show),
                        const SizedBox(width: 10),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              text,
                              key: ValueKey(text),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Nudge extends StatefulWidget {
  const _Nudge({required this.active});

  final bool active;

  @override
  State<_Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<_Nudge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Nudge old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Swipe right, then glide back.
        final t = _c.value;
        final dx = t < 0.6 ? Curves.easeInOut.transform(t / 0.6) * 8 : 8 * (1 - (t - 0.6) / 0.4);
        return Transform.translate(offset: Offset(dx - 4, 0), child: child);
      },
      child: const Icon(Icons.swipe_right_rounded, size: 22, color: Colors.white),
    );
  }
}

// -----------------------------------------------------------------------------
// Tool bars
// -----------------------------------------------------------------------------

class _SandBar extends StatelessWidget {
  const _SandBar({required this.controller});

  static const double _itemWidth = 42;

  /// Width of the bar including its 4pt padding on each side.
  static final double naturalWidth = sandTools.length * _itemWidth + 8;

  final SandController controller;

  @override
  Widget build(BuildContext context) {
    final selected = sandTools.indexWhere((t) => t.material == controller.material);
    return _LensBar(
      count: sandTools.length,
      selected: selected,
      itemWidth: _itemWidth,
      labels: [for (final t in sandTools) t.label],
      lensTint: controller.material == Mat.empty ? null : sandTools[selected].color,
      onSelect: (i) => controller.material = sandTools[i].material,
      itemBuilder: (context, i, isSelected) {
        final t = sandTools[i];
        return Orb(
          color: t.color,
          selected: isSelected,
          ring: false,
          size: 24,
          child: t.icon == null ? null : Icon(t.icon, size: 13, color: Colors.white),
        );
      },
    );
  }
}

class _FluidBar extends StatelessWidget {
  const _FluidBar({required this.controller});

  final FluidController controller;

  @override
  Widget build(BuildContext context) {
    const palettes = FluidPalette.values;
    return _LensBar(
      count: palettes.length,
      selected: controller.palette.index,
      itemWidth: 52,
      labels: [for (final p in palettes) p.label],
      lensTint: controller.palette.swatch.first,
      onSelect: (i) => controller.palette = palettes[i],
      itemBuilder: (context, i, isSelected) {
        final p = palettes[i];
        return Orb(
          color: p.swatch.first,
          gradient: SweepGradient(colors: [...p.swatch, p.swatch.first]),
          selected: isSelected,
          ring: false,
          size: 26,
        );
      },
    );
  }
}

class _ClothBar extends StatelessWidget {
  const _ClothBar({required this.controller, required this.accent});

  final ClothController controller;
  final Color accent;

  static const _tools = [
    (ClothTool.grab, 'Grab', Icons.pan_tool_rounded),
    (ClothTool.tear, 'Tear', Icons.content_cut_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LensBar(
          count: _tools.length,
          selected: controller.tool.index,
          itemWidth: 70,
          labels: [for (final t in _tools) t.$2],
          lensTint: accent,
          onSelect: (i) => controller.tool = _tools[i].$1,
          itemBuilder: (context, i, isSelected) =>
              _IconLabel(icon: _tools[i].$3, label: _tools[i].$2, selected: isSelected),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          toggled: controller.wind,
          label: 'Wind',
          excludeSemantics: true,
          child: Pressable(
            onTap: () {
              HapticFeedback.selectionClick();
              controller.wind = !controller.wind;
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: LiquidGlass(
                key: ValueKey(controller.wind),
                tint: controller.wind ? const Color(0xFF2CB8D8) : null,
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 70,
                  height: _barHeight - 8,
                  child: Center(
                    child: _IconLabel(
                      icon: Icons.air_rounded,
                      label: controller.wind ? 'Wind on' : 'Wind',
                      selected: controller.wind,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
