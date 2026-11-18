import 'dart:async';

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
  Timer? _rest;

  /// With [AnimatedEmoji.onHover] the animation plays for a moment and then
  /// rests, even if the mouse stays on it (a mouse left resting on an emoji
  /// used to keep the whole window redrawing).
  static const Duration playFor = Duration(milliseconds: 3200);

  void _enter() {
    _rest?.cancel();
    _rest = Timer(playFor, () {
      if (mounted) setState(() => _hover = false);
    });
    setState(() => _hover = true);
  }

  void _exit() {
    _rest?.cancel();
    if (_hover) setState(() => _hover = false);
  }

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }

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
    final Widget content;
    if (!playing) {
      content = SizedBox.square(
        dimension: size,
        child: Center(child: still),
      );
    } else {
      final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
      // Its own layer, so each animation frame redraws only this emoji.
      content = RepaintBoundary(
        child: SizedBox.square(
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
        ),
      );
    }
    if (!widget.onHover || !AnimatedEmoji.enabled) return content;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: content,
    );
  }
}
