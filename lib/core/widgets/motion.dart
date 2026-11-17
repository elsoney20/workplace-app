import 'package:material_ui/material_ui.dart';

import 'gaming_pattern.dart';

/// Smooth "Apple-like" easing used everywhere.
const Curve kSmooth = Cubic(0.16, 1, 0.3, 1);

/// Springy overshoot for small playful things (likes, badges).
const Curve kSpring = Cubic(0.34, 1.56, 0.64, 1);

/// Fades and slides its child up a little when it first appears.
/// [index] staggers a list so cards arrive one after another.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  /// Turned off in widget tests so frames settle immediately.
  static bool enabled = true;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: kSmooth);

  @override
  void initState() {
    super.initState();
    if (!FadeSlideIn.enabled) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 60 * widget.index.clamp(0, 6));
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Lifts its child slightly when the mouse is over it (desktop feel).
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.lift = 2});

  final Widget child;
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: kSmooth,
        offset: Offset(0, _hover ? -widget.lift / 100 : 0),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

/// Pops (scales up then back) every time [trigger] changes, e.g. on a like.
class PopOnChange extends StatefulWidget {
  const PopOnChange({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.4), weight: 35),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.4,
        end: 1,
      ).chain(CurveTween(curve: kSpring)),
      weight: 65,
    ),
  ]).animate(_c);

  @override
  void didUpdateWidget(PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && FadeSlideIn.enabled) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// Shrinks a little while pressed, like a physical button.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The soft green / gold glow behind the app, like games2egypt.com.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.pattern = false});

  final Widget child;

  /// Adds the drifting gaming-icons pattern behind [child].
  final bool pattern;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dir = Directionality.of(context);

    Widget glow(AlignmentDirectional center, double radius, Color color) =>
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: center.resolve(dir),
                radius: radius,
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Stack(
        children: [
          // The glow never changes: its own layer, so it is drawn once and
          // not again on every frame of the content above it.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Stack(
                  children: [
                    glow(
                      const AlignmentDirectional(0.9, -1.1),
                      1.1,
                      const Color(
                        0xFF95AB52,
                      ).withValues(alpha: dark ? .16 : .14),
                    ),
                    glow(
                      const AlignmentDirectional(-0.9, -1.05),
                      0.9,
                      const Color(
                        0xFFF4B63D,
                      ).withValues(alpha: dark ? .09 : .10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pattern)
            const Positioned.fill(child: IgnorePointer(child: GamingPattern())),
          Positioned.fill(child: RepaintBoundary(child: child)),
        ],
      ),
    );
  }
}
