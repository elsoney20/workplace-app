import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';

import 'motion.dart';

/// A slow, drifting pattern of gaming things (controllers, headsets,
/// consoles, trophies...) for the background of big screens.
///
/// It is drawn at about 30 frames a second, and stops while the app
/// window is in the background, so it costs very little.
class GamingPattern extends StatefulWidget {
  const GamingPattern({super.key});

  @override
  State<GamingPattern> createState() => _GamingPatternState();
}

class _GamingPatternState extends State<GamingPattern>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _time = ValueNotifier(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (FadeSlideIn.enabled) _ticker.start();
  }

  void _tick(Duration elapsed) {
    // ~30 fps is plenty for something this slow.
    if (elapsed - _last < const Duration(milliseconds: 33)) return;
    _last = elapsed;
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!FadeSlideIn.enabled) return;
    final active = state == AppLifecycleState.resumed;
    if (active && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PatternPainter(time: _time, dark: dark),
        size: Size.infinite,
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.time, required this.dark})
    : super(repaint: time);

  final ValueListenable<double> time;
  final bool dark;

  static const List<IconData> _icons = [
    Icons.sports_esports,
    Icons.headset_mic,
    Icons.videogame_asset,
    Icons.gamepad,
    Icons.emoji_events,
    Icons.mouse,
    Icons.keyboard,
    Icons.tv,
    Icons.sports_soccer,
    Icons.bolt,
  ];

  static const double _cell = 132;

  /// Glyphs are laid out once and reused every frame.
  static final Map<(int, int, bool), TextPainter> _cache = {};

  TextPainter _glyph(int icon, int tint, double size) {
    return _cache.putIfAbsent((icon, tint, dark), () {
      final base = dark ? Colors.white : const Color(0xFF14171C);
      final color = switch (tint) {
        0 => const Color(0xFF95AB52).withValues(alpha: dark ? .16 : .14),
        1 => const Color(0xFFF4B63D).withValues(alpha: dark ? .12 : .12),
        2 => const Color(0xFF3D7BFF).withValues(alpha: dark ? .12 : .10),
        _ => base.withValues(alpha: dark ? .055 : .05),
      };
      final data = _icons[icon];
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(data.codePoint),
          style: TextStyle(
            fontFamily: data.fontFamily,
            package: data.fontPackage,
            fontSize: size,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    // The whole field drifts diagonally and wraps around.
    final dx = (t * 9) % _cell;
    final dy = (t * 6) % _cell;
    final cols = (size.width / _cell).ceil() + 2;
    final rows = (size.height / _cell).ceil() + 2;

    for (var r = -1; r < rows; r++) {
      for (var c = -1; c < cols; c++) {
        // Stable pseudo-random values per cell (no flicker between frames).
        final seed = (r * 73856093) ^ (c * 19349663);
        final rnd = math.Random(seed);
        final icon = rnd.nextInt(_icons.length);
        final roll = rnd.nextInt(10);
        final tint = roll < 2 ? 0 : (roll < 3 ? 1 : (roll < 4 ? 2 : 3));
        final jitterX = rnd.nextDouble() * 50 - 25;
        final jitterY = rnd.nextDouble() * 50 - 25;
        final speed = .4 + rnd.nextDouble() * .5;
        final phase = rnd.nextDouble() * 2 * math.pi;
        final baseAngle = rnd.nextDouble() * .8 - .4;

        final glyph = _glyph(icon, tint, 34);
        final x = c * _cell + dx + jitterX + (r.isOdd ? _cell / 2 : 0);
        final y = r * _cell + dy + jitterY + 6 * math.sin(t * speed + phase);
        final angle = baseAngle + .18 * math.sin(t * speed * .7 + phase);

        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(angle);
        glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.dark != dark;
}
