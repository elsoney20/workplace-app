import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// A slow, drifting pattern of gaming things (controllers, headsets,
/// consoles, trophies...) for the background of big screens.
///
/// Cheap by design: the icons are drawn once into a seamless tile that is
/// cached as a texture; every frame only *moves* that texture (no
/// redrawing). It moves while someone is using the app, rests after
/// [idleAfter] without mouse / keyboard activity (so an untouched app uses
/// no CPU), and stops while the window is in the background.
class GamingPattern extends StatefulWidget {
  const GamingPattern({super.key});

  /// Size of the repeating tile, in logical pixels.
  static const double tile = _PatternPainter.cell * _PatternPainter.cells;

  /// The drift pauses after this long without any input.
  static const Duration idleAfter = Duration(seconds: 12);

  @override
  State<GamingPattern> createState() => _GamingPatternState();
}

class _GamingPatternState extends State<GamingPattern>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<Offset> _shift = ValueNotifier(Offset.zero);
  Duration _last = Duration.zero;

  /// Seconds of drift so far (kept across pauses, so it never jumps).
  double _clock = 0;
  DateTime _lastInput = DateTime.now();
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _wake();
  }

  void _onPointer(PointerEvent e) => _wake();

  bool _onKey(KeyEvent e) {
    _wake();
    return false;
  }

  void _wake() {
    _lastInput = DateTime.now();
    if (FadeSlideIn.enabled && _foreground && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    if (DateTime.now().difference(_lastInput) > GamingPattern.idleAfter) {
      _ticker.stop();
      return;
    }
    final step = elapsed - _last;
    if (step < const Duration(milliseconds: 41)) return;
    _last = elapsed;
    _clock += step.inMicroseconds / 1e6;
    final t = _clock;
    const tile = GamingPattern.tile;
    // Pixel-snapped so the cached texture never needs re-filtering.
    _shift.value = Offset(
      ((t * 9) % tile).roundToDouble(),
      ((t * 6) % tile).roundToDouble(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _wake();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const tile = GamingPattern.tile;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth + tile;
          final h = box.maxHeight + tile;
          final pattern = RepaintBoundary(
            child: CustomPaint(
              size: Size(w, h),
              painter: _PatternPainter(dark: dark),
              isComplex: true,
              willChange: false,
            ),
          );
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -tile,
                top: -tile,
                width: w,
                height: h,
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _shift,
                  child: pattern,
                  builder: (context, shift, child) =>
                      Transform.translate(offset: shift, child: child),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Draws the icons once. The layout repeats every [cells] cells, so the
/// picture can slide by one tile and look identical (seamless loop).
class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.dark});

  final bool dark;

  static const double cell = 132;
  static const int cells = 6;

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

  TextPainter _glyph(int icon, int tint) {
    final base = dark ? Colors.white : const Color(0xFF14171C);
    final color = switch (tint) {
      0 => const Color(0xFF95AB52).withValues(alpha: dark ? .16 : .14),
      1 => const Color(0xFFF4B63D).withValues(alpha: .12),
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
          fontSize: 34,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cache = <(int, int), TextPainter>{};
    final rows = (size.height / cell).ceil() + 1;
    final cols = (size.width / cell).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        // Same values every `cells` rows / columns -> seamless tile.
        final rnd = math.Random(
          ((r % cells) * 73856093) ^ ((c % cells) * 19349663),
        );
        final icon = rnd.nextInt(_icons.length);
        final roll = rnd.nextInt(10);
        final tint = roll < 2 ? 0 : (roll < 3 ? 1 : (roll < 4 ? 2 : 3));
        final jx = rnd.nextDouble() * 50 - 25;
        final jy = rnd.nextDouble() * 50 - 25;
        final angle = rnd.nextDouble() * .9 - .45;
        final glyph = cache.putIfAbsent((icon, tint), () => _glyph(icon, tint));
        final x = c * cell + cell / 2 + jx + (r.isOdd ? cell / 2 : 0);
        final y = r * cell + cell / 2 + jy;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(angle);
        glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
        canvas.restore();
      }
    }
    for (final g in cache.values) {
      g.dispose();
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.dark != dark;
}
