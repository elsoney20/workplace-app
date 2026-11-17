import 'package:material_ui/material_ui.dart';

/// Shows an emoji, animated when Google's free Noto Animated Emoji has an
/// animation for it, otherwise as a normal (still) emoji.
///
/// The animation is downloaded once from fonts.gstatic.com (free, no key)
/// and cached in memory. Offline it simply shows the still emoji.
///
/// With [onHover] it only plays while the mouse is over it. Use that for
/// emojis that stay on screen (feed, chats): many emojis animating forever
/// keep the whole window redrawing and made the app sluggish.
class AnimatedEmoji extends StatefulWidget {
  const AnimatedEmoji(
    this.emoji, {
    super.key,
    this.size = 28,
    this.animate = true,
    this.onHover = false,
  });

  final String emoji;
  final double size;
  final bool animate;
  final bool onHover;

  /// Turned off in widget tests (no network there).
  static bool enabled = true;

  /// e.g. '❤️' -> '2764_fe0f', '👍' -> '1f44d'
  static String codeFor(String emoji) =>
      emoji.runes.map((r) => r.toRadixString(16)).join('_');

  static String urlFor(String emoji) =>
      'https://fonts.gstatic.com/s/e/notoemoji/latest/${codeFor(emoji)}/512.webp';

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final emoji = widget.emoji;
    final size = widget.size;
    final still = Text(
      emoji,
      style: TextStyle(fontSize: size * 0.82, height: 1.1),
      textAlign: TextAlign.center,
    );
    final playing =
        AnimatedEmoji.enabled && widget.animate && (!widget.onHover || _hover);
    if (!playing) {
      final box = SizedBox.square(
        dimension: size,
        child: Center(child: still),
      );
      if (!widget.onHover || !AnimatedEmoji.enabled) return box;
      return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        child: box,
      );
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = SizedBox.square(
      dimension: size,
      child: Image.network(
        AnimatedEmoji.urlFor(emoji),
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
    // Its own layer, so each animation frame redraws only this emoji.
    final layer = RepaintBoundary(child: image);
    if (!widget.onHover) return layer;
    return MouseRegion(
      onExit: (_) => setState(() => _hover = false),
      child: layer,
    );
  }
}
