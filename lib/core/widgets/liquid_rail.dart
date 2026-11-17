import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// One button on the [LiquidRail].
class LiquidRailItem {
  const LiquidRailItem({
    this.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final Key? key;
  final IconData icon;
  final String label;

  /// The colour the liquid turns when this item is selected.
  final Color color;
  final VoidCallback onTap;
  final int badge;
}

/// A vertical icon rail where the selected item sits in a glowing blob of
/// "liquid". Picking another item makes the blob stretch, flow to it and
/// change colour, then wobble softly while it rests.
///
/// [top] items sit at the top, [bottom] items at the bottom; [selected]
/// counts through both lists (top first). `null` = nothing selected.
class LiquidRail extends StatefulWidget {
  const LiquidRail({
    super.key,
    required this.header,
    required this.top,
    required this.bottom,
    required this.selected,
    this.extra = const [],
  });

  final Widget header;
  final List<LiquidRailItem> top;
  final List<LiquidRailItem> bottom;

  /// Plain widgets shown above the bottom items (e.g. a language menu).
  final List<Widget> extra;
  final int? selected;

  static const double width = 80;
  static const double _item = 52;

  @override
  State<LiquidRail> createState() => _LiquidRailState();
}

class _LiquidRailState extends State<LiquidRail> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _slotKeys = _makeKeys();

  /// Centre (y) of each slot inside the rail, measured after layout.
  List<double> _centers = const [];
  int? _from;
  int? _to;

  int get _count => widget.top.length + widget.bottom.length;

  List<GlobalKey> _makeKeys() => List.generate(_count, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _to = widget.selected;
    _from = widget.selected;
    _move.value = 1;
    _wobbleFor(const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Timer? _calm;

  /// The blob wobbles while it moves and a little after, then rests (so an
  /// idle app doesn't redraw anything).
  void _wobbleFor(Duration d) {
    if (!FadeSlideIn.enabled) return;
    _calm?.cancel();
    if (!_wobble.isAnimating) unawaited(_wobble.repeat());
    _calm = Timer(d, () {
      if (mounted) _wobble.stop();
    });
  }

  @override
  void didUpdateWidget(LiquidRail old) {
    super.didUpdateWidget(old);
    if (old.top.length != widget.top.length ||
        old.bottom.length != widget.bottom.length) {
      _slotKeys = _makeKeys();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    if (old.selected != widget.selected) {
      _from = _to ?? widget.selected;
      _to = widget.selected;
      if (_from == null || _to == null || !FadeSlideIn.enabled) {
        _from = _to;
        _move.value = 1;
      } else {
        _move.forward(from: 0);
        _wobbleFor(const Duration(milliseconds: 2600));
      }
    }
  }

  void _measure() {
    if (!mounted) return;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return;
    final centers = <double>[];
    for (final k in _slotKeys) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: stack);
      centers.add(topLeft.dy + box.size.height / 2);
    }
    if (!_listEquals(centers, _centers)) setState(() => _centers = centers);
  }

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > .5) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _calm?.cancel();
    _move.dispose();
    _wobble.dispose();
    super.dispose();
  }

  LiquidRailItem _itemAt(int i) => i < widget.top.length
      ? widget.top[i]
      : widget.bottom[i - widget.top.length];

  Widget _slot(int index) {
    final item = _itemAt(index);
    final selected = index == widget.selected;
    return KeyedSubtree(
      key: _slotKeys[index],
      child: _RailIcon(item: item, selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final to = _to;
    final from = _from;
    final hasBlob =
        to != null &&
        from != null &&
        _centers.length == _count &&
        to < _count &&
        from < _count;

    return Container(
      width: LiquidRail.width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: .78),
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
          return false;
        },
        child: SizeChangedLayoutNotifier(
          child: Stack(
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              if (hasBlob)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _LiquidPainter(
                          move: _move,
                          wobble: _wobble,
                          fromY: _centers[from],
                          toY: _centers[to],
                          fromColor: _itemAt(from).color,
                          toColor: _itemAt(to).color,
                        ),
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  const SizedBox(height: 16),
                  widget.header,
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var i = 0; i < widget.top.length; i++) _slot(i),
                        ],
                      ),
                    ),
                  ),
                  ...widget.extra,
                  for (var i = 0; i < widget.bottom.length; i++)
                    _slot(widget.top.length + i),
                  const SizedBox(height: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.item, required this.selected});

  final LiquidRailItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = item.badge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: item.label,
        preferBelow: false,
        child: Pressable(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: item.key,
              customBorder: const CircleBorder(),
              onTap: item.onTap,
              child: SizedBox(
                width: LiquidRail._item,
                height: LiquidRail._item,
                child: Center(
                  child: PopOnChange(
                    trigger: badge,
                    child: Badge(
                      isLabelVisible: badge > 0,
                      label: Text(badge > 99 ? '99+' : '$badge'),
                      child: AnimatedScale(
                        scale: selected ? 1.12 : 1,
                        duration: const Duration(milliseconds: 420),
                        curve: kSpring,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(
                            end: selected
                                ? const Color(0xFF0B0D10)
                                : scheme.onSurfaceVariant,
                          ),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, color, _) =>
                              Icon(item.icon, color: color, size: 24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the blob. While moving, its front races ahead and its back
/// catches up later, so it stretches like a drop of liquid, then snaps
/// round again. At rest the outline breathes slowly.
class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.move,
    required this.wobble,
    required this.fromY,
    required this.toY,
    required this.fromColor,
    required this.toColor,
  }) : super(repaint: Listenable.merge([move, wobble]));

  final Animation<double> move;
  final Animation<double> wobble;
  final double fromY;
  final double toY;
  final Color fromColor;
  final Color toColor;

  static const Curve _head = Cubic(0.2, 0.9, 0.25, 1.15);
  static const Curve _tail = Cubic(0.65, 0, 0.25, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final t = move.value;
    final head = fromY + (toY - fromY) * _head.transform(t);
    final tail = fromY + (toY - fromY) * _tail.transform(t);
    final top = math.min(head, tail);
    final bottom = math.max(head, tail);
    final stretch = (bottom - top).clamp(0.0, 400.0);

    // Thinner while stretched, like a stream of liquid.
    final radius = 23 - math.min(stretch / 40, 7.0);
    final cx = size.width / 2;
    final phase = wobble.value * 2 * math.pi;
    final color = Color.lerp(fromColor, toColor, _tail.transform(t))!;

    final path = Path();
    const steps = 72;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final r =
          radius *
          (1 +
              .055 * math.sin(3 * a + phase) +
              .035 * math.sin(5 * a - phase * 2) +
              .02 * math.cos(2 * a + phase * 3));
      final s = math.sin(a);
      final y = (s >= 0 ? bottom : top) + r * s;
      final x = cx + r * math.cos(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Soft glow under the liquid.
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.45),
          radius: 1.1,
          colors: [
            Color.lerp(color, Colors.white, .45)!,
            color,
            Color.lerp(color, Colors.black, .18)!,
          ],
          stops: const [0, .55, 1],
        ).createShader(bounds),
    );
    // A small shine, like light on a drop of water.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - radius * .35, top - radius * .45),
        width: radius * .55,
        height: radius * .32,
      ),
      Paint()..color = Colors.white.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.fromY != fromY ||
      old.toY != toY ||
      old.fromColor != fromColor ||
      old.toColor != toColor;
}
