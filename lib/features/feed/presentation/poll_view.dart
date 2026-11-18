import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../data/feed_repository.dart';
import '../domain/poll.dart';

/// A poll inside a post: tap a choice to vote, tap it again to take the
/// vote back. Results show as bars that grow into place.
class PollView extends ConsumerStatefulWidget {
  const PollView({super.key, required this.postId, required this.poll});

  final String postId;
  final Poll poll;

  @override
  ConsumerState<PollView> createState() => _PollViewState();
}

class _PollViewState extends ConsumerState<PollView> {
  late Poll _poll = widget.poll;
  bool _busy = false;

  @override
  void didUpdateWidget(PollView old) {
    super.didUpdateWidget(old);
    if (!_busy && old.poll != widget.poll) _poll = widget.poll;
  }

  Future<void> _vote(String optionId) async {
    if (_busy || _poll.closed) return;
    final before = _poll;
    final next = before.myOption == optionId ? null : optionId;
    setState(() {
      _busy = true;
      _poll = before.withMyVote(next);
    });
    try {
      await ref.read(feedRepositoryProvider).votePoll(widget.postId, next);
    } catch (_) {
      if (mounted) {
        setState(() => _poll = before);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorUnknown)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final poll = _poll;
    final voted = poll.myOption != null;
    final top = poll.options.fold(0, (m, o) => o.votes > m ? o.votes : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.poll_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  poll.question,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final o in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OptionBar(
                key: Key('pollOption-${o.id}'),
                label: o.label,
                votes: o.votes,
                share: poll.total == 0 ? 0 : o.votes / poll.total,
                mine: o.id == poll.myOption,
                leading: voted && o.votes == top && top > 0,
                showResults: voted || poll.closed,
                onTap: poll.closed ? null : () => _vote(o.id),
              ),
            ),
          Text(
            [
              l10n.pollVotes(poll.total),
              if (poll.closed) l10n.pollClosed,
              if (!voted && !poll.closed) l10n.pollTapToVote,
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionBar extends StatelessWidget {
  const _OptionBar({
    super.key,
    required this.label,
    required this.votes,
    required this.share,
    required this.mine,
    required this.leading,
    required this.showResults,
    required this.onTap,
  });

  final String label;
  final int votes;
  final double share;
  final bool mine;
  final bool leading;
  final bool showResults;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = mine
        ? scheme.primary.withValues(alpha: .32)
        : scheme.onSurface.withValues(alpha: leading ? .14 : .08);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine ? scheme.primary : scheme.outlineVariant,
              width: mine ? 1.6 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                // The result bar grows from the start edge.
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: showResults ? share : 0),
                    duration: const Duration(milliseconds: 520),
                    curve: kSmooth,
                    builder: (context, v, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: v.clamp(0.0, 1.0),
                      child: ColoredBox(color: fill),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: mine
                            ? Padding(
                                key: const ValueKey('mine'),
                                padding: const EdgeInsetsDirectional.only(
                                  end: 6,
                                ),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: mine || leading
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (showResults)
                        Text(
                          '${(share * 100).round()}%',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
