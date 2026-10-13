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

const double _topBarHeight = 8 + 48;
const double _dockMargin = 12;
const EdgeInsets _dockPadding = EdgeInsets.fromLTRB(8, 12, 8, 6);

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
                        _canvas(
                          Mode.sand,
                          SandView(controller: _sand, floorInset: _dockInset(_SandPanel.height)),
                        ),
                        _canvas(Mode.fluid, FluidView(controller: _fluid)),
                        _canvas(
                          Mode.cloth,
                          ClothView(
                            controller: _cloth,
                            topInset: MediaQuery.paddingOf(context).top + _topBarHeight,
                            floorInset: _dockInset(_ClothPanel.height),
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

  /// Distance from the bottom of the screen to the top of the dock when it
  /// holds a panel of [panelHeight]. Every dock row has a fixed height, so
  /// this is exact.
  double _dockInset(double panelHeight) =>
      MediaQuery.paddingOf(context).bottom + _dockMargin + _dockPadding.vertical + panelHeight;

  Widget _canvas(Mode m, Widget view) => TickerMode(
    enabled: _mode == m,
    child: RepaintBoundary(child: view),
  );

  Widget _chromeLayer(Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Hint(controller: _active, text: _mode.hint, visible: _chrome),
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
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _ModeSwitcher(mode: _mode, accent: accent, onMode: _setMode),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Reveal(
            visible: _chrome,
            from: const Offset(0, 0.6),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, _dockMargin),
                child: Glass(
                  radius: 30,
                  glow: accent,
                  padding: _dockPadding,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: switch (_mode) {
                        Mode.sand => _SandPanel(
                          key: const ValueKey('sand'),
                          controller: _sand,
                          accent: accent,
                        ),
                        Mode.fluid => _FluidPanel(
                          key: const ValueKey('fluid'),
                          controller: _fluid,
                          accent: accent,
                        ),
                        Mode.cloth => _ClothPanel(
                          key: const ValueKey('cloth'),
                          controller: _cloth,
                          accent: accent,
                        ),
                      },
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

// -----------------------------------------------------------------------------
// Chrome
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
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 500),
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
          colors: [Color(0x00000000), Color(0x8C000000)],
          stops: [0.55, 1],
        ),
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.mode, required this.accent, required this.onMode});

  final Mode mode;
  final Color accent;
  final ValueChanged<Mode> onMode;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in Mode.values)
            _ModeSegment(mode: m, selected: m == mode, accent: accent, onTap: () => onMode(m)),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Mode mode;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 340);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOutCubic,
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: selected ? 15 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                  )
                : null,
            border: Border.all(
              color: selected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -5),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode.icon,
                size: 19,
                color: selected ? accent : Colors.white.withValues(alpha: 0.6),
              ),
              AnimatedSize(
                duration: _duration,
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          mode.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
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
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(4),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FpsBadge(fps: controller.fps),
            _RoundButton(
              tooltip: controller.paused ? 'Play' : 'Pause',
              onTap: () {
                HapticFeedback.selectionClick();
                controller.paused = !controller.paused;
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
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
          width: 40,
          height: 40,
          child: IconTheme(
            data: IconThemeData(size: 21, color: Colors.white.withValues(alpha: 0.92)),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Reset with a little full spin of its icon.
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
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

class _FpsBadge extends StatelessWidget {
  const _FpsBadge({required this.fps});

  final ValueListenable<int> fps;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: fps,
      builder: (context, value, _) {
        final good = value >= 55;
        final color = good ? const Color(0xFF6BEA8E) : const Color(0xFFFFB347);
        return Padding(
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
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
            alignment: const Alignment(0, 0.1),
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, 0.3),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Glass(
                    radius: 22,
                    padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
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
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
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
      child: Icon(Icons.swipe_right_rounded, size: 22, color: Colors.white.withValues(alpha: 0.85)),
    );
  }
}

// -----------------------------------------------------------------------------
// Tool docks
// -----------------------------------------------------------------------------

const double _orbRowHeight = 70;
const double _sliderHeight = 40;

class _ToolOrb extends StatelessWidget {
  const _ToolOrb({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.gradient,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Orb(
                color: color,
                selected: selected,
                gradient: gradient,
                child: icon == null
                    ? null
                    : Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.95)),
              ),
              const SizedBox(height: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: DefaultTextStyle.of(context).style.merge(
                  TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    letterSpacing: 0.2,
                    color: selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades the ends of a horizontal scroller so it reads as "more this way".
class _FadingEdges extends StatelessWidget {
  const _FadingEdges({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, 0.05, 0.95, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}

class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.leading,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.onChanged,
    required this.label,
  });

  final Widget leading;
  final double value, min, max;
  final Color accent;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _sliderHeight,
      child: Row(
        children: [
          SizedBox(width: 44, child: Center(child: leading)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                thumbColor: Colors.white,
                overlayColor: accent.withValues(alpha: 0.18),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 9,
                  elevation: 3,
                  pressedElevation: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                trackShape: const RoundedRectSliderTrackShape(),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                label: label,
                semanticFormatterCallback: (_) => label,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// A dot that grows with the brush size.
class _BrushDot extends StatelessWidget {
  const _BrushDot({required this.t, required this.color});

  /// Brush size normalised to 0..1.
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = 6 + 18 * t.clamp(0.0, 1.0);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.45)!, color],
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10)],
      ),
    );
  }
}

class _SandPanel extends StatelessWidget {
  const _SandPanel({super.key, required this.controller, required this.accent});

  static const double height = _orbRowHeight + _sliderHeight;

  final SandController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _orbRowHeight,
          child: _FadingEdges(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                for (final t in sandTools)
                  _ToolOrb(
                    label: t.label,
                    color: t.color,
                    icon: t.icon,
                    selected: controller.material == t.material,
                    onTap: () => controller.material = t.material,
                  ),
              ],
            ),
          ),
        ),
        _GlassSlider(
          leading: _BrushDot(t: (controller.brush - 1) / 11, color: accent),
          value: controller.brush,
          min: 1,
          max: 12,
          accent: accent,
          label: 'Brush size',
          onChanged: (v) => controller.brush = v,
        ),
      ],
    );
  }
}

class _FluidPanel extends StatelessWidget {
  const _FluidPanel({super.key, required this.controller, required this.accent});

  final FluidController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _orbRowHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final p in FluidPalette.values)
                _ToolOrb(
                  label: p.label,
                  color: p.swatch.first,
                  gradient: SweepGradient(colors: [...p.swatch, p.swatch.first]),
                  selected: controller.palette == p,
                  onTap: () => controller.palette = p,
                ),
            ],
          ),
        ),
        _GlassSlider(
          leading: _BrushDot(t: (controller.brush - 0.015) / 0.075, color: accent),
          value: controller.brush,
          min: 0.015,
          max: 0.09,
          accent: accent,
          label: 'Brush size',
          onChanged: (v) => controller.brush = v,
        ),
        _GlassSlider(
          leading: Icon(Icons.cyclone_rounded, size: 20, color: accent),
          value: controller.swirl,
          min: 0,
          max: 60,
          accent: accent,
          label: 'Swirl',
          onChanged: (v) => controller.swirl = v,
        ),
      ],
    );
  }
}

class _ClothPanel extends StatelessWidget {
  const _ClothPanel({super.key, required this.controller, required this.accent});

  static const double height = 76;

  final ClothController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolOrb(
            label: 'Grab',
            color: const Color(0xFF7D5BD6),
            icon: Icons.pan_tool_rounded,
            selected: controller.tool == ClothTool.grab,
            onTap: () => controller.tool = ClothTool.grab,
          ),
          _ToolOrb(
            label: 'Tear',
            color: const Color(0xFFD9437F),
            icon: Icons.content_cut_rounded,
            selected: controller.tool == ClothTool.tear,
            onTap: () => controller.tool = ClothTool.tear,
          ),
          _ToolOrb(
            label: controller.wind ? 'Wind on' : 'Wind',
            color: const Color(0xFF2C9DB8),
            icon: Icons.air_rounded,
            selected: controller.wind,
            onTap: () => controller.wind = !controller.wind,
          ),
        ],
      ),
    );
  }
}
