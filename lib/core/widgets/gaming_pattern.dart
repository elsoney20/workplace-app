import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// A slow, drifting pattern of gaming things (controllers, headsets,
/// consoles, trophies...) for the background of big screens.
///
/// Cheap by design: the icons are drawn once into a seamless tile image;
/// every frame only repeats that image with a slightly moved offset. It moves while someone is using the app, rests after
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
  /// Driven by the screen refresh (a ticker), so every refresh moves the
  /// pattern by the same tiny, sub-pixel step: that is what makes it
  /// glide instead of hop. Each frame only draws one textured rectangle.
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<Offset> _shift = ValueNotifier(Offset.zero);
  Duration _last = Duration.zero;

  /// Seconds of drift so far (kept across pauses, so it never jumps).
  double _clock = 0;
  DateTime _lastInput = DateTime.now();
  bool _foreground = true;

  ui.Image? _tileImage;
  double _tileDpr = 0;
  bool _tileDark = false;

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

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    if (DateTime.now().difference(_lastInput) > GamingPattern.idleAfter) {
      _stop();
      return;
    }
    final step = elapsed - _last;
    _last = elapsed;
    _clock += step.inMicroseconds / 1e6;
    final t = _clock;
    const tile = GamingPattern.tile;
    // Not rounded: the texture is sampled smoothly between pixels.
    _shift.value = Offset((t * 9) % tile, (t * 6) % tile);
  }

  /// Draws one seamless tile into a picture once (per theme and screen
  /// density); every frame then just repeats it with a moving offset.
  ui.Image _tileFor(double dpr, bool dark) {
    final cached = _tileImage;
    if (cached != null && _tileDpr == dpr && _tileDark == dark) return cached;
    cached?.dispose();
    const tile = GamingPattern.tile;
    final px = (tile * dpr).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(px / tile)
      ..clipRect(const Rect.fromLTWH(0, 0, tile, tile));
    _PatternPainter(dark: dark).paintTile(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    _tileImage = image;
    _tileDpr = dpr;
    _tileDark = dark;
    return image;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _wake();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _shift.dispose();
    _tileImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = _tileFor(dpr, dark);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DriftPainter(image: image, dpr: dpr, shift: _shift),
      ),
    );
  }
}

/// Fills the area with the repeated tile, shifted by [shift]; bilinear
/// sampling makes sub-pixel offsets look smooth.
class _DriftPainter extends CustomPainter {
  _DriftPainter({required this.image, required this.dpr, required this.shift})
    : super(repaint: shift);

  final ui.Image image;
  final double dpr;
  final ValueNotifier<Offset> shift;

  @override
  void paint(Canvas canvas, Size size) {
    final s = shift.value;
    final scale = GamingPattern.tile / image.width;
    final matrix = Matrix4.identity()
      ..translateByDouble(s.dx, s.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.low
        ..shader = ImageShader(
          image,
          TileMode.repeated,
          TileMode.repeated,
          matrix.storage,
          filterQuality: FilterQuality.low,
        ),
    );
  }

  @override
  bool shouldRepaint(_DriftPainter old) => old.image != image || old.dpr != dpr;
}

/// Draws the icons once. The layout repeats every [cells] cells, so the
/// picture can slide by one tile and look identical (seamless loop).
class _PatternPainter {
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

  /// Paints one tile (cells x cells), including the parts of icons from
  /// neighbouring tiles that reach into it, so the edges line up.
  void paintTile(Canvas canvas) {
    final cache = <(int, int), TextPainter>{};
    for (var r = -1; r <= cells; r++) {
      for (var c = -1; c <= cells; c++) {
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
}
