import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../domain/emoji_catalog.dart';
import 'animated_emoji.dart';
import 'emoji_grid.dart';

/// Result of the reaction picker.
sealed class ReactionChoice {
  const ReactionChoice();
}

class ReactionPicked extends ReactionChoice {
  const ReactionPicked(this.emoji);
  final String emoji;
}

class ReactionRemoved extends ReactionChoice {
  const ReactionRemoved();
}

/// A floating bar of animated reactions, shown above [anchor].
/// Returns null if closed without choosing.
Future<ReactionChoice?> showReactionPicker(
  BuildContext anchor, {
  String? current,
}) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  Offset position = Offset.zero;
  if (box != null && overlay != null) {
    position = box.localToGlobal(Offset.zero, ancestor: overlay);
  }
  final choice = await showGeneralDialog<Object>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) =>
        _ReactionBar(anchor: position, current: current),
    transitionBuilder: (context, animation, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
  if (choice == _more) {
    if (!anchor.mounted) return null;
    final emoji = await showEmojiGrid(anchor);
    return emoji == null ? null : ReactionPicked(emoji);
  }
  if (choice is String) {
    return choice == current ? const ReactionRemoved() : ReactionPicked(choice);
  }
  return null;
}

const Object _more = Object();

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.anchor, this.current});

  final Offset anchor;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    const width = 8 * 48.0 + 56;
    final left = (anchor.dx - 8).clamp(
      8.0,
      (size.width - width - 8).clamp(8.0, double.infinity),
    );
    final top = (anchor.dy - 72).clamp(8.0, size.height - 80);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(32),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in EmojiCatalog.quickReactions)
                    _ReactionButton(emoji: e, selected: e == current),
                  IconButton(
                    tooltip: l10n.moreEmojis,
                    icon: const Icon(Icons.add_reaction_outlined),
                    onPressed: () => Navigator.pop(context, _more),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatefulWidget {
  const _ReactionButton({required this.emoji, required this.selected});

  final String emoji;
  final bool selected;

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => Navigator.pop(context, widget.emoji),
        child: AnimatedScale(
          scale: _hover ? 1.35 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.selected ? scheme.primaryContainer : null,
            ),
            child: Center(child: AnimatedEmoji(widget.emoji, size: 36)),
          ),
        ),
      ),
    );
  }
}

/// "👍❤️😂 12" summary under a post or comment.
class ReactionSummary extends StatelessWidget {
  const ReactionSummary({
    super.key,
    required this.reactions,
    this.onTap,
    this.size = 20,
  });

  final Map<String, int> reactions;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final total = reactions.values.fold(0, (a, b) => a + b);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in reactions.keys.take(3))
              AnimatedEmoji(e, size: size, onHover: true),
            const SizedBox(width: 4),
            Text('$total', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
