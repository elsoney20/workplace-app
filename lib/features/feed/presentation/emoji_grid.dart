import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../domain/emoji_catalog.dart';
import 'animated_emoji.dart';

String emojiCategoryLabel(AppLocalizations l10n, String key) => switch (key) {
  'smileys' => l10n.emojiSmileys,
  'gestures' => l10n.emojiGestures,
  'hearts' => l10n.emojiHearts,
  'celebration' => l10n.emojiCelebration,
  'work' => l10n.emojiWork,
  'people' => l10n.emojiPeople,
  'nature' => l10n.emojiNature,
  _ => l10n.emojiFlags,
};

/// Opens a dialog with all emojis in tabs; returns the chosen one.
Future<String?> showEmojiGrid(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const Dialog(
      child: SizedBox(width: 420, height: 460, child: _EmojiGrid()),
    ),
  );
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = EmojiCatalog.categories.entries.toList();
    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final c in categories)
                Tab(
                  icon: Text(
                    c.value.first,
                    style: const TextStyle(fontSize: 20),
                  ),
                  text: emojiCategoryLabel(l10n, c.key),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in categories)
                  GridView.extent(
                    maxCrossAxisExtent: 48,
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final e in c.value)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.pop(context, e),
                          child: Center(
                            // Still emojis here: a whole grid of animations
                            // would download a lot of data.
                            child: AnimatedEmoji(e, size: 32, animate: false),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
