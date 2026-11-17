import 'package:material_ui/material_ui.dart';

/// Shows an emoji, animated when Google's free Noto Animated Emoji has an
/// animation for it, otherwise as a normal (still) emoji.
///
/// The animation is downloaded once from fonts.gstatic.com (free, no key)
/// and cached in memory. Offline it simply shows the still emoji.
class AnimatedEmoji extends StatelessWidget {
  const AnimatedEmoji(
    this.emoji, {
    super.key,
    this.size = 28,
    this.animate = true,
  });

  final String emoji;
  final double size;
  final bool animate;

  /// Turned off in widget tests (no network there).
  static bool enabled = true;

  /// e.g. '❤️' -> '2764_fe0f', '👍' -> '1f44d'
  static String codeFor(String emoji) =>
      emoji.runes.map((r) => r.toRadixString(16)).join('_');

  static String urlFor(String emoji) =>
      'https://fonts.gstatic.com/s/e/notoemoji/latest/${codeFor(emoji)}/512.webp';

  @override
  Widget build(BuildContext context) {
    final still = Text(
      emoji,
      style: TextStyle(fontSize: size * 0.82, height: 1.1),
      textAlign: TextAlign.center,
    );
    if (!enabled || !animate) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: still),
      );
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox.square(
      dimension: size,
      child: Image.network(
        urlFor(emoji),
        width: size,
        height: size,
        cacheWidth: pixels,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        semanticLabel: emoji,
        frameBuilder: (context, child, frame, wasSync) =>
            frame == null ? Center(child: still) : child,
        errorBuilder: (context, error, stack) => Center(child: still),
      ),
    );
  }
}
